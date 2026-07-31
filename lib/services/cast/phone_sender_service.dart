// Sender de segunda pantalla que corre en el móvil (arquitectura D).
//
// Descubre la TV por mDNS (bonsoir), abre el WebSocket de control, se empareja
// por PIN y envía el LOAD (con credenciales cifradas) y comandos de control.
// El móvil NO reproduce: sólo controla.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'cast_protocol.dart';

/// Un Android TV descubierto en la LAN.
class CastDevice {
  final String name;
  final String host;
  final int port;

  /// La TV sirve wss:// (nuestra app siempre lo hace). En pruebas por loopback
  /// se usa ws:// (secure=false).
  final bool secure;
  CastDevice(
      {required this.name,
      required this.host,
      required this.port,
      this.secure = true});
}

class PhoneSenderService {
  WebSocket? _ws;
  StreamSubscription? _sub;

  // Estado del reto de emparejamiento recibido de la TV.
  List<int>? _salt;
  List<int>? _nonce;
  List<int>? _certfp; // fingerprint del cert que la TV firma en el reto
  Uint8List? _capturedFp; // fingerprint del cert TLS realmente presentado (wss)
  SecretKey? _sessionKey;
  Completer<bool>? _pairResult; // recreado por cada intento (PIN o token)
  final _challengeReady = Completer<void>();

  /// Id estable de la TV (llega en el reto). Para recordar la confianza.
  String? tvId;

  /// Token de larga duración que la TV emite al emparejar con PIN (para
  /// persistirlo y reutilizarlo sin PIN durante 7 días).
  String? issuedToken;

  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onState => _stateController.stream;

  final _tracksController = StreamController<Map<String, dynamic>>.broadcast();

  /// Pistas de audio/subtítulo que reporta la TV (respuesta a getTracks).
  Stream<Map<String, dynamic>> get onTracks => _tracksController.stream;

  /// Se invoca si el socket se cierra (para que el controlador reconecte).
  void Function()? onDisconnected;

  /// Se invoca cuando la TV avisa que la reproducción se detuvo/cerró en su
  /// lado (mensaje `ended`), para que el móvil pase a idle en vez de intentar
  /// reconectar contra una TV que ya no reproduce nada.
  void Function()? onEnded;

  /// Se invoca cuando la TV avisa que el título terminó de reproducirse (fin de
  /// archivo, mensaje `completed`), para que el móvil pueda auto-avanzar al
  /// siguiente episodio de la cola. Distinto de [onEnded] (BACK/stop → idle):
  /// aquí la sesión SIGUE viva y el móvil decide si reenvía un LOAD.
  void Function()? onCompleted;

  /// Se invoca cuando la TV avisa que OTRO dispositivo tomó el control
  /// (mensaje `superseded`): esta sesión quedó cedida. El móvil debe pasar a
  /// idle EN SILENCIO (sin error, sin reconectar) — el cierre de socket que
  /// llega justo después NO debe tratarse como caída.
  void Function()? onSuperseded;

  /// true tras recibir `superseded`: el `onDone` posterior del socket no debe
  /// disparar [onDisconnected] (evita que el móvil pelee por recuperar la TV).
  bool _superseded = false;

  /// Descubre TVs anunciando [kCastServiceType] durante [timeout].
  Future<List<CastDevice>> discover(
      {Duration timeout = const Duration(seconds: 4)}) async {
    final discovery = BonsoirDiscovery(type: kCastServiceType);
    await discovery.ready;
    final found = <String, CastDevice>{};
    final sub = discovery.eventStream!.listen((event) async {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        await event.service!.resolve(discovery.serviceResolver);
      } else if (event.type ==
          BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final s = event.service!;
        final host = (s.toJson()['service.host'] ?? s.toJson()['host']) as String?;
        final port = s.port;
        if (host != null) {
          found[s.name] = CastDevice(name: s.name, host: host, port: port);
        }
      }
    });
    await discovery.start();
    await Future<void>.delayed(timeout);
    await sub.cancel();
    await discovery.stop();
    return found.values.toList();
  }

  /// Abre el WebSocket con la TV y espera el reto de emparejamiento.
  /// Con [secure] usa wss:// y captura el cert presentado para pinearlo (el
  /// pinning se cierra en pair(), atado al PIN).
  Future<void> connect(String host, int port, {bool secure = false}) async {
    if (secure) {
      final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (cert, h, p) {
          // TOFU: aceptamos el cert y validamos por el proof atado al PIN.
          _capturedFp = Uint8List.fromList(crypto.sha256.convert(cert.der).bytes);
          return true;
        };
      _ws = await WebSocket.connect('wss://$host:$port', customClient: client);
    } else {
      _ws = await WebSocket.connect('ws://$host:$port');
    }
    _sub = _ws!.listen(_onMessage, onDone: () {
      if (_pairResult?.isCompleted == false) _pairResult!.complete(false);
      // Tras `superseded` el cierre es esperado (nos cedieron el control): NO
      // notificar caída, o el controlador intentaría reconectar contra la TV.
      if (_superseded) return;
      onDisconnected?.call();
    });
    await _challengeReady.future
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw TimeoutException('sin reto de emparejamiento de la TV');
    });
  }

  /// Prueba el PIN. Devuelve true si la TV lo acepta.
  /// Empareja con el PIN (primera vez con esa TV).
  Future<bool> pair(String pin) => _pairWithSecret(pin);

  /// Reanuda la confianza SIN PIN usando un token guardado (cumple el rol de
  /// "secreto" en el mismo emparejamiento). Devuelve false si la TV ya no lo
  /// reconoce (venció o reinstaló) → el controlador cae al PIN.
  Future<bool> resume(String token) => _pairWithSecret(token);

  Future<bool> _pairWithSecret(String secret) async {
    if (_salt == null || _nonce == null) {
      throw StateError('connect() debe completarse antes de emparejar');
    }
    final certfp = _certfp ?? const <int>[];
    // Anti-MITM: si vamos por wss, el cert TLS presentado debe coincidir con el
    // fingerprint que la TV firmó en el reto; si no, hay un intermediario.
    if (_capturedFp != null && !CastCrypto.bytesEqual(_capturedFp!, certfp)) {
      return false;
    }
    final result = _pairResult = Completer<bool>();
    _sessionKey = await CastCrypto.deriveSessionKey(secret, _salt!);
    final proof = await CastCrypto.proof(_sessionKey!, _nonce!, certfp);
    _ws!.add(encodeMsg(MsgType.pairProof, {'proof': proof}));
    return result.future
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
  }

  /// Envía un LOAD: la TV reproducirá el contenido. Las credenciales viajan
  /// cifradas con la clave de sesión (AES-GCM).
  Future<void> sendLoad({
    required String channelId,
    String contentType = 'live',
    required String url,
    required String username,
    required String password,
    String title = '',
    String ext = '',
    CastMeta? meta,
  }) async {
    if (_sessionKey == null) throw StateError('no emparejado');
    final creds = await CastCrypto.encryptJson(_sessionKey!, {
      'url': url,
      'user': username,
      'pass': password,
    });
    _ws!.add(encodeMsg(MsgType.load, {
      'id': channelId,
      'ct': contentType,
      'title': title,
      'ext': ext,
      'creds': creds,
      // Metadatos TMDb OPCIONALES (sinopsis/reparto para el panel de pausa de la
      // TV). Público, sin cifrar. Se omite si no hay nada útil que enviar → un
      // LOAD idéntico al de siempre (compat. hacia atrás).
      if (meta != null && !meta.isEmpty) 'meta': meta.toJson(),
    }));
  }

  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) {
    _ws?.add(encodeMsg(MsgType.command, {'c': cmd, ...extra}));
  }

  void _onMessage(dynamic data) {
    final msg = decodeMsg(data as String);
    switch (msg['t']) {
      case MsgType.pairChallenge:
        _salt = base64.decode(msg['salt'] as String);
        _nonce = base64.decode(msg['nonce'] as String);
        tvId = msg['tvId'] as String?;
        final fp = msg['certfp'] as String?;
        _certfp = (fp != null && fp.isNotEmpty) ? base64.decode(fp) : const [];
        if (!_challengeReady.isCompleted) _challengeReady.complete();
        break;
      case MsgType.pairResult:
        final tk = msg['token'] as String?;
        if (tk != null && tk.isNotEmpty) issuedToken = tk;
        if (_pairResult?.isCompleted == false) {
          _pairResult!.complete(msg['ok'] == true);
        }
        break;
      case MsgType.state:
        _stateController.add(msg);
        break;
      case MsgType.tracks:
        _tracksController.add(msg);
        break;
      case MsgType.ended:
        onEnded?.call();
        break;
      case MsgType.completed:
        onCompleted?.call();
        break;
      case MsgType.superseded:
        _superseded = true;
        onSuperseded?.call();
        break;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _ws?.close();
    await _stateController.close();
    await _tracksController.close();
  }
}
