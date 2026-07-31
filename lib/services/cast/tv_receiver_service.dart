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

  /// Metadatos TMDb OPCIONALES que el móvil resolvió y envió con el LOAD
  /// (sinopsis + reparto para el panel de pausa). Null cuando el móvil no envió
  /// nada (build vieja, sin clave TMDb o sin coincidencia): la TV cae al
  /// comportamiento actual (TmdbEnrichment/solo-título).
  final CastMeta? meta;

  CastLoadRequest({
    required this.channelId,
    required this.contentType,
    required this.url,
    required this.username,
    required this.password,
    required this.title,
    this.ext = '',
    this.meta,
  });

  /// URL de stream Xtream (misma forma que lib/utils/build_media_url.dart).
  String get mediaUrl {
    final suffix = ext.isNotEmpty ? '.$ext' : '';
    switch (contentType) {
      case 'file':
        // Archivo local servido por el móvil en la LAN: la URL ya es el media
        // completo (http://<ip>:<port>/f), no se arma URL Xtream.
        return url;
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
  TvReceiverService({
    required this.deviceName,
    String? pin,
    this.tls,
    this.tvId = '',
    this.knownTokens = const [],
    this.onIssueToken,
  })  : pin = pin ?? _genPin(),
        // Conjunto VIVO de tokens que esta sesión honra sin PIN: parte de los
        // persistidos y CRECE al emitir uno nuevo (ver pairProof). Sin esto, un
        // móvil emparejado por PIN durante ESTE arranque de la TV volvería a
        // pedir PIN en su siguiente conexión (el token recién emitido no estaba
        // en la lista fija cargada al arrancar), rompiendo la confianza de 7 días.
        _liveTokens = [...knownTokens];

  final String deviceName;

  /// PIN de 6 dígitos que la UI de la TV muestra al usuario.
  final String pin;

  /// Id estable de esta TV (para que el móvil recuerde la confianza por-TV).
  final String tvId;

  /// Tokens de confianza vigentes (dispositivos ya emparejados en los últimos
  /// 7 días). Un móvil con uno de estos empareja sin PIN.
  final List<String> knownTokens;

  /// Se invoca al emitir un token nuevo (emparejamiento con PIN) para que la
  /// capa de UI lo persista.
  final void Function(String token)? onIssueToken;

  /// Tokens que ESTA sesión acepta sin PIN: los persistidos + los emitidos en
  /// este arranque. Se consulta al validar un `resume` (ver [_handleSocket]).
  final List<String> _liveTokens;

  /// Cert TLS para servir wss:// con cert-pinning. Si es null, sirve ws:// plano
  /// (útil en pruebas por loopback; el fingerprint atado al proof queda vacío).
  final CastTls? tls;

  List<int> get _certfp => tls?.fingerprint ?? const [];

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  WebSocket? _activeWs; // socket emparejado en curso (para responder a la app)
  // Socket que CONTROLA la reproducción (el del último LOAD válido). Modelo
  // last-load-wins: cuando OTRO socket toma el control, al anterior se le manda
  // `superseded` y se le cierra → soporte multi-dispositivo (toma de control).
  WebSocket? _controllingWs;

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
      'tvId': tvId,
      'certfp': base64.encode(_certfp),
    }));

    ws.listen((data) async {
      try {
        final msg = decodeMsg(data as String);
        switch (msg['t']) {
          case MsgType.pairProof:
            attempts++;
            final proofB64 = msg['proof'] as String;
            // 1) Intento con el PIN → si acierta, emparejado y se EMITE un token
            //    de confianza (para no volver a pedir PIN durante 7 días).
            final pinKey = await CastCrypto.deriveSessionKey(pin, salt);
            if (await CastCrypto.verifyProof(pinKey, nonce, proofB64, _certfp)) {
              paired = true;
              sessionKey = pinKey;
              final token = base64.encode(randomBytes(32));
              // Persistir (para próximos arranques) Y honrarlo YA en esta sesión:
              // así una reconexión posterior del mismo móvil reanuda sin PIN.
              onIssueToken?.call(token);
              _liveTokens.add(token);
              _activeWs = ws;
              ws.add(encodeMsg(MsgType.pairResult, {'ok': true, 'token': token}));
            } else {
              // 2) Intento con los tokens de confianza vigentes (sin PIN):
              //    los persistidos MÁS los emitidos en este arranque. Se itera
              //    sobre una COPIA: hay `await` en el cuerpo y otro socket puede
              //    hacer `_liveTokens.add` en paralelo → sin la copia saltaría
              //    ConcurrentModificationError (pairing espurio fallido).
              for (final t in [..._liveTokens]) {
                final tk = await CastCrypto.deriveSessionKey(t, salt);
                if (await CastCrypto.verifyProof(tk, nonce, proofB64, _certfp)) {
                  paired = true;
                  sessionKey = tk;
                  _activeWs = ws;
                  break;
                }
              }
              ws.add(encodeMsg(MsgType.pairResult, {'ok': paired}));
              if (!paired && attempts >= 3) {
                ws.add(encodeMsg(MsgType.error, {'e': 'too_many_attempts'}));
                await ws.close();
              }
            }
            break;

          case MsgType.load:
            if (!paired || sessionKey == null) {
              ws.add(encodeMsg(MsgType.error, {'e': 'not_paired'}));
              return;
            }
            // Toma de control multi-dispositivo (last-load-wins): si OTRO socket
            // controlaba, este LOAD se lo arrebata. Avisar al anterior con
            // `superseded` ANTES de cerrarlo, para que su móvil vaya a idle en
            // silencio (no lo trata como caída → no dispara reconexión). Un
            // pequeño respiro deja salir el frame antes del cierre.
            final prev = _controllingWs;
            if (prev != null && !identical(prev, ws)) {
              try {
                prev.add(encodeMsg(MsgType.superseded, const {}));
              } catch (_) {/* socket ya cerrado */}
              Future<void>.delayed(const Duration(milliseconds: 150), () {
                prev.close().catchError((_) {});
              });
            }
            _controllingWs = ws;
            _activeWs = ws; // el control (state/tracks) va al dueño actual
            // Credenciales cifradas con la clave de sesión (nunca en claro).
            final creds =
                await CastCrypto.decryptJson(sessionKey!, msg['creds'] as Map<String, dynamic>);
            // Metadatos TMDb opcionales (público, sin cifrar). Se parsea en su
            // PROPIO try/catch: un `meta` malformado (tipos inválidos de un peer)
            // NUNCA debe abortar el LOAD — sin meta ese mismo LOAD sí reproduce.
            // Ante cualquier fallo → meta null y el LOAD sigue normal. (Defensa en
            // profundidad: CastMeta.fromJson ya es tolerante de por sí.)
            CastMeta? meta;
            final rawMeta = msg['meta'];
            if (rawMeta is Map<String, dynamic>) {
              try {
                meta = CastMeta.fromJson(rawMeta);
              } catch (_) {
                meta = null;
              }
            }
            _loadController.add(CastLoadRequest(
              channelId: msg['id'] as String,
              contentType: (msg['ct'] as String?) ?? 'live',
              url: creds['url'] as String,
              username: creds['user'] as String,
              password: creds['pass'] as String,
              title: (msg['title'] as String?) ?? '',
              ext: (msg['ext'] as String?) ?? '',
              meta: meta,
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
