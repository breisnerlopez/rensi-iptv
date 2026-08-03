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

/// String tolerante: cualquier valor no-String del wire (incluido null) → ''.
/// Réplica local del helper homónimo de `cast_protocol.dart` (privado a esa
/// library, no importable de aquí): un campo opcional del LOAD viene de un
/// PEER emparejado, y un tipo inesperado (p.ej. un número) NUNCA debe lanzar
/// — a diferencia de `(msg['x'] as String?) ?? ''`, que sólo tolera null y
/// SÍ lanza un TypeError ante cualquier otro tipo no-String.
String _wireString(dynamic v) => v is String ? v : '';

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

  /// Posición (ms) desde la que reanudar la reproducción en la TV. 0 → desde el
  /// principio (LOAD sin `pos`, o build vieja del móvil). El host lo pasa al
  /// PlayerWidget como resume inicial.
  final int startPositionMs;

  /// Metadatos TMDb OPCIONALES que el móvil resolvió y envió con el LOAD
  /// (sinopsis + reparto para el panel de pausa). Null cuando el móvil no envió
  /// nada (build vieja, sin clave TMDb o sin coincidencia): la TV cae al
  /// comportamiento actual (TmdbEnrichment/solo-título).
  final CastMeta? meta;

  /// Feature H — el móvil pide que la TV PERSISTA las credenciales de este LOAD
  /// (cifradas, indexadas por [providerId]) para reproducción standalone. False
  /// salvo que el móvil tenga permiso maestro + consentimiento explícito para
  /// este (TV, proveedor) y el contenido sea VOD/serie Xtream. Compat. hacia
  /// atrás: un LOAD sin `standalone` decodifica a false (no persiste nada).
  final bool standalone;

  /// Id de la playlist del móvil (opaco, NO derivado de las credenciales) con el
  /// que indexar las credenciales persistidas cuando [standalone] es true. Vacío
  /// cuando no aplica.
  final String providerId;

  /// Feature H (fase 5) — id ESTABLE del móvil que envió este LOAD. La TV
  /// particiona su historial de casting por-dispositivo (`__cast__:<deviceId>`)
  /// y sincroniza el progreso de vuelta SOLO a este móvil. Vacío cuando el móvil
  /// no lo envió (build vieja) → la TV cae al `__cast__` plano. Clave de
  /// PARTICIÓN, no control de seguridad: el emparejamiento ya gatea quién conecta.
  final String deviceId;

  /// Feature H (mejora) — seriesId del episodio (VOD/serie Xtream). Vacío salvo
  /// que el móvil castee un episodio de serie. La TV lo persiste en la fila de
  /// historial `__cast__` (vía seriesStream) para poder resolver la lista
  /// COMPLETA de episodios y AUTO-AVANZAR sola por la serie al reanudar en
  /// standalone. Compat. hacia atrás: ausente → la TV reanuda sólo ese episodio.
  final String seriesId;

  CastLoadRequest({
    required this.channelId,
    required this.contentType,
    required this.url,
    required this.username,
    required this.password,
    required this.title,
    this.ext = '',
    this.meta,
    this.startPositionMs = 0,
    this.standalone = false,
    this.providerId = '',
    this.deviceId = '',
    this.seriesId = '',
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

/// Feature H (fase 5) — evento de historySync entregado a la UI de la TV. Lleva
/// el socket ORIGEN y su [deviceId] (el del LOAD autenticado de ESE socket) para
/// que la respuesta se ate al socket correcto y se mezcle en su partición, sin
/// depender del `_activeWs` global (spoofeable/mutable por un LOAD concurrente).
typedef HistorySyncEvent = (
  WebSocket socket,
  String deviceId,
  List<HistorySyncItem> items,
);

class TvReceiverService {
  TvReceiverService({
    required this.deviceName,
    String? pin,
    this.tls,
    this.tvId = '',
    this.knownTokens = const [],
    this.onIssueToken,
    this.pinMaxAttempts = 5,
    this.pinAttemptWindow = const Duration(minutes: 15),
    this.pinLockoutBase = const Duration(seconds: 30),
    this.pinLockoutMax = const Duration(minutes: 15),
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

  /// AC2 — anti-fuerza-bruta del PIN CROSS-SOCKET. Nº de intentos de proof
  /// fallidos (por peer, dentro de [pinAttemptWindow]) que dispara un bloqueo.
  /// El límite por-socket (3, ver [_handleSocket]) NO frena la fuerza bruta:
  /// el atacante reabre un socket y el contador local se reinicia. Este límite
  /// vive en la INSTANCIA del servicio y se indexa por IP remota, así que
  /// sobrevive a la reconexión.
  final int pinMaxAttempts;

  /// Ventana deslizante sobre la que se cuentan los fallos hacia [pinMaxAttempts].
  final Duration pinAttemptWindow;

  /// Enfriamiento base tras superar [pinMaxAttempts]. Crece exponencialmente por
  /// cada bloqueo consecutivo del mismo peer (backoff), tope [pinLockoutMax].
  final Duration pinLockoutBase;

  /// Tope del enfriamiento por backoff exponencial.
  final Duration pinLockoutMax;

  /// Estado del guardia anti-fuerza-bruta por peer (IP remota). Vive en la
  /// instancia (no por-socket) para que reconectar no reinicie el contador.
  final Map<String, _PinAttemptGuard> _pinGuards = {};

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
  final _historyController = StreamController<HistorySyncEvent>.broadcast();

  /// LOADs recibidos (tras emparejar). La UI de la TV se suscribe para reproducir.
  Stream<CastLoadRequest> get onLoad => _loadController.stream;

  /// Comandos de control remoto (mensaje completo: `c` + campos como `id`).
  Stream<Map<String, dynamic>> get onCommand => _commandController.stream;

  /// Feature H (fase 5) — deltas de "continuar viendo" que un móvil EMPAREJADO
  /// envía. El evento lleva TAMBIÉN el socket ORIGEN y el deviceId establecido
  /// por el LOAD de ESE socket (no un deviceId del payload, que sería
  /// spoofeable). El host mezcla en `__cast__:<deviceId>` y RESPONDE con los
  /// suyos vía [sendMessageTo] al MISMO socket — nunca al `_activeWs` "activo"
  /// (que un LOAD de otro móvil pudo reasignar mientras el merge estaba en
  /// vuelo). Solo emite tras emparejar (ver [_handleSocket]).
  Stream<HistorySyncEvent> get onHistorySync => _historyController.stream;

  /// Envía un mensaje al móvil que CONTROLA la reproducción (state/tracks/ended…).
  /// Va al `_activeWs` (el dueño actual, reasignado en cada LOAD/command). NO
  /// usar para responder a un historySync: esa respuesta debe atarse al socket
  /// ORIGEN (ver [sendMessageTo]), porque un LOAD concurrente de otro móvil pudo
  /// mover `_activeWs` mientras se procesaba el sync → fuga cruzada.
  void sendMessage(String type, Map<String, dynamic> body) {
    _activeWs?.add(encodeMsg(type, body));
  }

  /// Envía un mensaje a UN socket concreto (no al `_activeWs` global). Es lo que
  /// hace la respuesta de historySync socket-bound: la contestación al lote de
  /// un móvil vuelve EXACTAMENTE por su propio socket, aunque entretanto otro
  /// móvil haya tomado el control (reasignando `_activeWs`). Si [socket] ya se
  /// cerró (el móvil se desconectó o fue `superseded`), `add` lanza y aquí se
  /// traga: la respuesta va a su dueño o a NADIE, jamás a otro socket.
  void sendMessageTo(WebSocket socket, String type, Map<String, dynamic> body) {
    try {
      socket.add(encodeMsg(type, body));
    } catch (_) {/* socket cerrado: no-op (nunca al socket equivocado) */}
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
    _historyController.close();
  }

  Future<void> _handleHttpRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    // Peer (IP remota) para el guardia anti-fuerza-bruta cross-socket (AC2).
    // Se resuelve ANTES del upgrade (connectionInfo sigue disponible aquí).
    final peer = req.connectionInfo?.remoteAddress.address ?? 'unknown';
    final ws = await WebSocketTransformer.upgrade(req);
    _handleSocket(ws, peer);
  }

  /// Latido de la conexión de control (mismo motivo/valor que el emisor móvil,
  /// ver [PhoneSenderService]). dart:io envía un ping cada [_kPingInterval] y
  /// cierra el socket si no llega el pong: mantiene vivo el canal ocioso a
  /// través de NAT/power-save y limpia un socket medio-abierto (su `onDone`
  /// suelta `_controllingWs`/`_activeWs`). Frames transparentes al protocolo.
  static const _kPingInterval = Duration(seconds: 12);

  void _handleSocket(WebSocket ws, [String peer = 'unknown']) {
    // Latido: mantiene vivo el socket ocioso durante la reproducción (el móvil
    // no manda nada por el canal) y detecta el medio-abierto (ver arriba).
    ws.pingInterval = _kPingInterval;
    if (!_connectController.isClosed) _connectController.add(null);
    // Estado de emparejamiento POR conexión.
    final salt = randomBytes(16);
    final nonce = randomBytes(16);
    SecretKey? sessionKey;
    var paired = false;
    var attempts = 0;
    // Feature H (fase 5) — deviceId ESTABLECIDO por el LOAD de ESTE socket. Vive
    // en el estado por-conexión (esta clausura), así que es intrínsecamente
    // socket-bound y NO spoofeable: un historySync solo puede mezclarse/
    // responderse bajo la partición del deviceId que ESTE socket autenticó en su
    // LOAD, nunca uno embebido en el payload del sync. Vacío hasta el 1er LOAD →
    // `__cast__` plano (compat. hacia atrás). Se descarta con la clausura al
    // cerrarse el socket (nada que limpiar en un mapa global).
    var loadDeviceId = '';

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
            // AC2 — guardia anti-fuerza-bruta CROSS-SOCKET: si este peer está
            // bloqueado (superó [pinMaxAttempts] en la ventana), se rechaza el
            // proof ANTES de derivar clave alguna (sin gastar crypto ni filtrar
            // timing) y se cierra el socket. Reconectar no ayuda: el estado vive
            // en la instancia indexado por IP.
            if (_peerLockedOut(peer)) {
              ws.add(encodeMsg(MsgType.error, {'e': 'locked_out'}));
              await ws.close();
              return;
            }
            attempts++;
            final proofB64 = msg['proof'] as String;
            // 1) Intento con el PIN → si acierta, emparejado y se EMITE un token
            //    de confianza (para no volver a pedir PIN durante 7 días).
            final pinKey = await CastCrypto.deriveSessionKey(pin, salt);
            if (await CastCrypto.verifyProof(pinKey, nonce, proofB64, _certfp)) {
              paired = true;
              sessionKey = pinKey;
              _clearPinGuard(peer); // emparejamiento OK → se olvidan los fallos
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
              if (paired) {
                // Reanudó con un token de confianza vigente → limpia el guardia.
                _clearPinGuard(peer);
              } else {
                // Fallo real (ni PIN ni token): cuenta hacia el bloqueo
                // cross-socket por peer. Si ESTE fallo dispara el bloqueo, se
                // avisa y se cierra ya; si no, sigue el corte por-socket a los 3.
                final lockedNow = _registerPinFailure(peer);
                if (lockedNow) {
                  ws.add(encodeMsg(MsgType.error, {'e': 'locked_out'}));
                  await ws.close();
                } else if (attempts >= 3) {
                  ws.add(encodeMsg(MsgType.error, {'e': 'too_many_attempts'}));
                  await ws.close();
                }
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
              // Resume: tolerante a tipos del wire (un `pos` no-numérico → 0),
              // nunca aborta el LOAD.
              startPositionMs: (msg['pos'] as num?)?.toInt() ?? 0,
              // Feature H — persistencia standalone. Tolerante a tipos del wire:
              // `standalone` no-bool → false; `pid` no-String → ''. Un LOAD sin
              // estos campos (móvil viejo / no autorizado) no persiste nada.
              standalone: msg['standalone'] == true,
              providerId: (msg['pid'] as String?) ?? '',
              // Feature H (fase 5) — id del móvil para particionar el historial de
              // casting. Tolerante a tipos del wire (`did` no-String → ''); un
              // LOAD sin él (móvil viejo) cae al `__cast__` plano.
              deviceId: loadDeviceId = (msg['did'] as String?) ?? '',
              // Feature H (mejora) — seriesId para el auto-avance standalone de
              // series. Tolerante a tipos del wire (`sid` no-String → ''); un
              // LOAD sin él (móvil viejo / no es serie) → la TV reanuda sólo el
              // episodio, sin encadenar. `_wireString` (no `as String?`): un
              // `sid` NO-null y NO-String (p.ej. un número de un peer) haría
              // lanzar el cast `as String?` — un TypeError que abortaría el
              // LOAD entero, justo lo que esta tolerancia promete evitar.
              seriesId: _wireString(msg['sid']),
            ));
            ws.add(encodeMsg(MsgType.state, {'status': 'loading', 'id': msg['id']}));
            break;

          case MsgType.command:
            if (!paired) return;
            _activeWs = ws;
            _commandController.add(msg);
            break;

          case MsgType.historySync:
            // Feature H (fase 5) — SOLO sobre el canal emparejado. El móvil nos
            // manda sus deltas; el host los mezcla en la partición de ESTE socket
            // y responde por ESTE MISMO socket. Se emite el evento con el socket
            // ORIGEN y su `loadDeviceId` (el del LOAD autenticado de esta
            // conexión) — NO se toca `_activeWs`: si otro móvil hace un LOAD
            // mientras el merge está en vuelo, su reasignación de `_activeWs` NO
            // debe desviar esta respuesta (era la fuga cruzada entre
            // dispositivos). Parseo DEFENSIVO (capado, tolerante).
            if (!paired) return;
            _historyController.add((ws, loadDeviceId, parseHistorySyncItems(msg)));
            break;
        }
      } catch (e) {
        ws.add(encodeMsg(MsgType.error, {'e': e.toString()}));
      }
    }, onDone: () => _releaseSocket(ws), onError: (_) => _releaseSocket(ws));
  }

  /// Un socket de control se cerró — BACK/stop del móvil, o el [pingInterval]
  /// mató un medio-abierto (NAT/Wi-Fi power-save). Suelta las referencias
  /// globales que apuntaban a ÉL para no dejar `_controllingWs`/`_activeWs`
  /// colgando de un socket muerto. Sin esto, tras una caída silenciosa del
  /// controlador un 2º móvil que tomara el control mandaría `superseded` al
  /// socket MUERTO del 1º (tragado por el try/catch de [_handleSocket]) en vez de
  /// a su socket vivo, y el 1º nunca se enteraría de que perdió el control. Solo
  /// limpia si la referencia sigue siendo ESTE socket: un LOAD posterior de otra
  /// conexión (toma de control) ya pudo reasignar `_controllingWs`/`_activeWs`, y
  /// el cierre diferido del socket cedido (`superseded`) no debe borrar al nuevo
  /// dueño.
  void _releaseSocket(WebSocket ws) {
    if (identical(_controllingWs, ws)) _controllingWs = null;
    if (identical(_activeWs, ws)) _activeWs = null;
  }

  static String _genPin() {
    // 6 dígitos con bytes CSPRNG (no Random()).
    final b = randomBytes(4);
    final n = (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]) & 0x7fffffff;
    return (n % 1000000).toString().padLeft(6, '0');
  }

  /// True si [peer] está en enfriamiento por bloqueo (AC2). Un enfriamiento ya
  /// vencido se limpia aquí (perezosamente) — pero se conserva el contador de
  /// rondas de bloqueo, para que el backoff siga creciendo si el mismo peer
  /// reincide enseguida.
  bool _peerLockedOut(String peer) {
    final g = _pinGuards[peer];
    final until = g?.lockedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    g!.lockedUntil = null;
    g.failsInWindow = 0;
    g.windowStart = null;
    return false;
  }

  /// Registra un intento de PIN fallido para [peer]. Devuelve true si ESTE
  /// fallo alcanzó [pinMaxAttempts] dentro de [pinAttemptWindow] y disparó un
  /// bloqueo. El enfriamiento crece por backoff exponencial (base
  /// [pinLockoutBase], tope [pinLockoutMax]) por cada ronda consecutiva.
  bool _registerPinFailure(String peer) {
    final now = DateTime.now();
    final g = _pinGuards.putIfAbsent(peer, _PinAttemptGuard.new);
    if (g.windowStart == null ||
        now.difference(g.windowStart!) > pinAttemptWindow) {
      g.windowStart = now;
      g.failsInWindow = 0;
    }
    g.failsInWindow++;
    if (g.failsInWindow >= pinMaxAttempts) {
      g.lockoutRounds++;
      final shift = (g.lockoutRounds - 1).clamp(0, 20);
      final backoff = pinLockoutBase * (1 << shift);
      g.lockedUntil =
          now.add(backoff > pinLockoutMax ? pinLockoutMax : backoff);
      g.failsInWindow = 0;
      g.windowStart = null;
      return true;
    }
    return false;
  }

  /// Olvida los fallos de [peer] tras un emparejamiento válido (PIN o token).
  void _clearPinGuard(String peer) => _pinGuards.remove(peer);
}

/// Estado por peer del guardia anti-fuerza-bruta del PIN (AC2). Vive en la
/// instancia del [TvReceiverService], indexado por IP remota, para que el
/// límite sea CROSS-SOCKET: reconectar no reinicia el contador.
class _PinAttemptGuard {
  /// Fallos acumulados dentro de la ventana actual.
  int failsInWindow = 0;

  /// Inicio de la ventana deslizante en curso (null = sin ventana activa).
  DateTime? windowStart;

  /// Cuántas veces consecutivas este peer ha sido bloqueado (para el backoff).
  int lockoutRounds = 0;

  /// Instante hasta el que el peer está bloqueado (null = no bloqueado).
  DateTime? lockedUntil;
}
