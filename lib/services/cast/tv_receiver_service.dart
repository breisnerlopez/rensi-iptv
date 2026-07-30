// Receptor de segunda pantalla que corre en el Android TV (arquitectura D).
//
// - Levanta un servidor WebSocket (dart:io) en un puerto efímero de la LAN.
// - Anuncia el servicio por mDNS/DNS-SD con bonsoir para que el móvil lo
//   descubra.
// - Empareja por PIN (ver CastCrypto) y sólo tras emparejar acepta un LOAD.
// - Al recibir un LOAD, descifra las credenciales y emite un CastLoadRequest
//   que la UI de la TV usa para reproducir con el PlayerWidget/media_kit.
//
// No usa Cast Connect: por eso funciona con la app instalada por sideload
// (sin depender de Google Play). Ver CASTING_ARCHITECTURE.md (opción D).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';

import 'cast_protocol.dart';
import 'cast_tls.dart';

/// Petición de reproducción que llega desde el móvil (credenciales ya
/// descifradas). El receptor construye la URL igual que el móvil.
class CastLoadRequest {
  final String channelId;
  final String contentType; // 'live' | 'vod' | 'series'
  final String url;
  final String username;
  final String password;
  final String title;

  /// container_extension (mp4/mkv/…) para VOD/series. Vacío en vivo.
  final String ext;

  CastLoadRequest({
    required this.channelId,
    required this.contentType,
    required this.url,
    required this.username,
    required this.password,
    required this.title,
    this.ext = '',
  });

  /// URL de stream Xtream (misma forma que lib/utils/build_media_url.dart).
  String get mediaUrl {
    final suffix = ext.isNotEmpty ? '.$ext' : '';
    switch (contentType) {
      case 'vod':
        return '$url/movie/$username/$password/$channelId$suffix';
      case 'series':
        return '$url/series/$username/$password/$channelId$suffix';
      default:
        return '$url/$username/$password/$channelId';
    }
  }
}

class TvReceiverService {
  TvReceiverService({required this.deviceName, String? pin, this.tls})
      : pin = pin ?? _genPin();

  final String deviceName;

  /// PIN de 6 dígitos que la UI de la TV muestra al usuario.
  final String pin;

  /// Cert TLS para servir wss:// con cert-pinning. Si es null, sirve ws:// plano
  /// (útil en pruebas por loopback; el fingerprint atado al proof queda vacío).
  final CastTls? tls;

  List<int> get _certfp => tls?.fingerprint ?? const [];

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  WebSocket? _activeWs; // socket emparejado en curso (para responder a la app)

  final _loadController = StreamController<CastLoadRequest>.broadcast();
  final _commandController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectController = StreamController<void>.broadcast();

  /// LOADs recibidos (tras emparejar). La UI de la TV se suscribe para reproducir.
  Stream<CastLoadRequest> get onLoad => _loadController.stream;

  /// Comandos de control remoto (mensaje completo: `c` + campos como `id`).
  Stream<Map<String, dynamic>> get onCommand => _commandController.stream;

  /// Envía un mensaje a la app emparejada (p. ej. la lista de pistas).
  void sendMessage(String type, Map<String, dynamic> body) {
    _activeWs?.add(encodeMsg(type, body));
  }

  /// Se emite cuando un móvil abre el canal (para mostrar el PIN en la TV).
  Stream<void> get onClientConnected => _connectController.stream;

  int get port => _server?.port ?? 0;

  /// Arranca el servidor y el anuncio mDNS. Devuelve el puerto ligado.
  /// [advertise] false = solo servidor (útil en pruebas por loopback).
  Future<int> start({bool advertise = true}) async {
    if (tls != null) {
      final ctx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(tls!.certPem.codeUnits)
        ..usePrivateKeyBytes(tls!.keyPem.codeUnits);
      _server =
          await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, ctx, shared: true);
    } else {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }
    _server!.listen(_handleHttpRequest);
    if (advertise) {
      _broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: deviceName,
          type: kCastServiceType,
          port: _server!.port,
          attributes: {'device': deviceName, 'tls': tls != null ? '1' : '0'},
        ),
      );
      await _broadcast!.ready;
      await _broadcast!.start();
    }
    return _server!.port;
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    await _server?.close(force: true);
    _broadcast = null;
    _server = null;
  }

  void dispose() {
    _loadController.close();
    _commandController.close();
    _connectController.close();
  }

  Future<void> _handleHttpRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    _handleSocket(ws);
  }

  void _handleSocket(WebSocket ws) {
    if (!_connectController.isClosed) _connectController.add(null);
    // Estado de emparejamiento POR conexión.
    final salt = randomBytes(16);
    final nonce = randomBytes(16);
    SecretKey? sessionKey;
    var paired = false;
    var attempts = 0;

    // Reto de emparejamiento en cuanto conecta.
    ws.add(encodeMsg(MsgType.pairChallenge, {
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'device': deviceName,
      'certfp': base64.encode(_certfp),
    }));

    ws.listen((data) async {
      try {
        final msg = decodeMsg(data as String);
        switch (msg['t']) {
          case MsgType.pairProof:
            attempts++;
            sessionKey = await CastCrypto.deriveSessionKey(pin, salt);
            paired = await CastCrypto.verifyProof(
                sessionKey!, nonce, msg['proof'] as String, _certfp);
            ws.add(encodeMsg(MsgType.pairResult, {'ok': paired}));
            if (paired) _activeWs = ws;
            if (!paired && attempts >= 3) {
              ws.add(encodeMsg(MsgType.error, {'e': 'too_many_attempts'}));
              await ws.close();
            }
            break;

          case MsgType.load:
            if (!paired || sessionKey == null) {
              ws.add(encodeMsg(MsgType.error, {'e': 'not_paired'}));
              return;
            }
            // Credenciales cifradas con la clave de sesión (nunca en claro).
            final creds =
                await CastCrypto.decryptJson(sessionKey!, msg['creds'] as Map<String, dynamic>);
            _loadController.add(CastLoadRequest(
              channelId: msg['id'] as String,
              contentType: (msg['ct'] as String?) ?? 'live',
              url: creds['url'] as String,
              username: creds['user'] as String,
              password: creds['pass'] as String,
              title: (msg['title'] as String?) ?? '',
              ext: (msg['ext'] as String?) ?? '',
            ));
            ws.add(encodeMsg(MsgType.state, {'status': 'loading', 'id': msg['id']}));
            break;

          case MsgType.command:
            if (!paired) return;
            _activeWs = ws;
            _commandController.add(msg);
            break;
        }
      } catch (e) {
        ws.add(encodeMsg(MsgType.error, {'e': e.toString()}));
      }
    });
  }

  static String _genPin() {
    // 6 dígitos con bytes CSPRNG (no Random()).
    final b = randomBytes(4);
    final n = (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]) & 0x7fffffff;
    return (n % 1000000).toString().padLeft(6, '0');
  }
}
