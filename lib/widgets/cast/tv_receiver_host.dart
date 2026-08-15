// Integra el RECEPTOR de casting en la app cuando corre en Android TV: la misma
// app instalada (que además navega IPTV con normalidad) escucha en la LAN y,
// cuando un móvil emparejado envía un canal, lo reproduce a pantalla completa
// con el PlayerWidget/media_kit. En móvil/tablet este host es transparente.
//
// No usa Cast Connect → funciona con la app instalada por sideload.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:uuid/uuid.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/m3u_item.dart';
import '../../models/playlist_content_model.dart';
import '../../models/playlist_model.dart';
import '../../models/series.dart';
import '../../redesign/rensi_widgets.dart';
import '../../services/app_state.dart';
import '../../services/cast/cast_protocol.dart';
import '../../services/cast/cast_tls.dart';
import '../../services/cast/tv_receiver_service.dart';
import '../../services/cast/tv_standalone_creds_service.dart';
import '../../services/event_bus.dart';
import '../../services/player_state.dart';
import '../../services/watch_history_service.dart';
import '../../utils/app_themes.dart';
import '../../utils/responsive_helper.dart';
import '../player_widget.dart';

const _castPlaylistId = '__cast__';

/// Feature H (fase 5) — playlist sintética del historial de casting PARTICIONADA
/// por dispositivo: `__cast__:<deviceId>`. Así la TV escribe el progreso de un
/// título bajo la partición del móvil que lo casteó y le sincroniza SOLO a él (el
/// rail combina todas las particiones para reanudar en standalone, pero el sync
/// del avance es per-dispositivo). Fallback a `__cast__` plano cuando [deviceId]
/// es vacío (móvil viejo / LOAD sin `did`) → compat. hacia atrás. NO es un
/// control de seguridad (el emparejamiento ya gatea quién conecta): es una clave
/// de partición.
String castHistoryPlaylistId(String deviceId) =>
    deviceId.isEmpty ? _castPlaylistId : '$_castPlaylistId:$deviceId';

/// Feature H (fase 5) — núcleo TESTEABLE de la sincronización de historial en la
/// TV. Mezcla [items] (los deltas que envió el móvil con id [deviceId]) en SU
/// partición `__cast__:<deviceId>` y DEVUELVE los deltas de ESA MISMA partición
/// para responder — per-dispositivo: la respuesta a un móvil NUNCA incluye filas
/// de otro. Función de nivel superior (no método del State) a propósito: permite
/// probar el merge+reply REALES contra una BD sin montar el widget. Best-effort:
/// el llamador la envuelve en try/catch; aquí no se atrapa para que el test vea
/// cualquier fallo real de la orquestación de BD.
Future<({int written, List<HistorySyncItem> reply})> mergeAndReplyHistorySync(
  WatchHistoryService svc,
  String deviceId,
  List<HistorySyncItem> items,
) async {
  final pid = castHistoryPlaylistId(deviceId);
  final written = items.isEmpty ? 0 : await svc.mergeHistorySync(pid, items);
  final reply = await svc.historySyncDeltas(pid);
  return (written: written, reply: reply);
}

/// Feature H — persiste EN LA TV, cifradas en reposo, las credenciales de un LOAD
/// standalone autorizado (indexadas por su `providerId`/pid opaco), para que la
/// TV pueda reproducir sin el móvil (replay de fase 4). Las credenciales ya
/// llegaron descifradas en [req] (el servicio las abrió con la clave de sesión).
///
/// Guarda SOLO cuando el móvil pidió `standalone` (lo que el móvil gatea por
/// permiso maestro + consentimiento explícito) Y el contenido es VOD/serie con
/// las 3 credenciales presentes — defensa en profundidad contra un LOAD de
/// archivo local (creds vacías) o de vivo. En cualquier otro caso es no-op, así
/// que un LOAD normal nunca deja credenciales en la TV.
///
/// Función de nivel superior (no método del State) a propósito: encapsula la
/// decisión de persistir y la hace testeable sin montar el widget.
/// Feature H — decide si el auto-wipe de credenciales standalone debe correr al
/// arrancar el receptor. SOLO cuando la lectura de tokens fue EXITOSA
/// ([tokensLoadedOk]) y quedó vacía ([tokensEmpty]) — nadie de confianza. Un
/// fallo de lectura (keystore bloqueado, IO) deja [tokensLoadedOk] false y NUNCA
/// debe disparar un borrado destructivo (un falso-vacío borraría las creds de un
/// usuario con dispositivos de confianza). Función pura y testeable.
bool shouldWipeStandaloneOnBoot({
  required bool tokensLoadedOk,
  required bool tokensEmpty,
}) =>
    tokensLoadedOk && tokensEmpty;

Future<void> maybePersistStandaloneCreds(CastLoadRequest req) async {
  if (!(req.standalone &&
      req.providerId.isNotEmpty &&
      (req.contentType == 'vod' || req.contentType == 'series') &&
      req.url.isNotEmpty &&
      req.username.isNotEmpty &&
      req.password.isNotEmpty)) {
    return;
  }
  await TvStandaloneCredsService.save(
    req.providerId,
    url: req.url,
    user: req.username,
    pass: req.password,
  );
}

/// Live state of the LAN receiver, surfaced to the idle TV home so a silent
/// mDNS failure stops being invisible (see `TvReceiverHost._start`).
enum ReceiverStatus {
  /// Server up, advertising via mDNS — a phone on the same Wi-Fi can find it.
  discoverable,

  /// A phone is mid-handshake; the PIN overlay is showing.
  pairing,

  /// Either the server never started, or it started WITHOUT mDNS advertising
  /// (the `advertise: false` fallback) — either way a phone cannot discover
  /// this TV automatically.
  error,
}

/// Exposes [TvReceiverHost]'s [ReceiverStatus] (+ whether a `_start()` attempt
/// is currently in flight) and a retry hook to descendants — chiefly
/// `TvReceiverHome`'s status pill — without the host needing to know that its
/// `child` even IS that widget.
///
/// The notifier carries a `(ReceiverStatus, bool starting)` record rather than
/// two separate notifiers: `starting` has to be exposed reactively too (so the
/// pill can hide Retry for the duration of an attempt — see `_start`), and an
/// `InheritedNotifier` only tracks ONE `Listenable`. Piggybacking both values
/// on it, the same way `_loadNotifier` already piggybacks a sequence counter
/// on the cast-player's `ValueNotifier` a few lines down, keeps this a single
/// dependency instead of two independently-timed rebuild sources.
///
/// `InheritedNotifier` so a descendant's `dependOnInheritedWidgetOfExactType`
/// rebuilds on every status change, not just when this widget is replaced.
class TvReceiverStatusScope
    extends InheritedNotifier<ValueNotifier<(ReceiverStatus, bool)>> {
  const TvReceiverStatusScope({
    super.key,
    required ValueNotifier<(ReceiverStatus, bool)> status,
    required this.deviceName,
    required this.onRetry,
    required super.child,
  }) : super(notifier: status);

  final String deviceName;
  final VoidCallback onRetry;

  static TvReceiverStatusScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvReceiverStatusScope>();

  ReceiverStatus get status => notifier!.value.$1;

  /// True while a `_start()`/Retry attempt is in flight. The pill uses this to
  /// hide the Retry action instead of leaving it tappable during an attempt
  /// that is already running (see `_TvReceiverHostState._start`).
  bool get starting => notifier!.value.$2;
}

class TvReceiverHost extends StatefulWidget {
  const TvReceiverHost({super.key, required this.child, this.deviceName = 'Rensi TV'});
  final Widget child;
  final String deviceName;

  @override
  State<TvReceiverHost> createState() => _TvReceiverHostState();
}

class _TvReceiverHostState extends State<TvReceiverHost> {
  TvReceiverService? _service;
  StreamSubscription<void>? _connectSub;
  StreamSubscription<CastLoadRequest>? _loadSub;
  StreamSubscription<Map<String, dynamic>>? _commandSub;
  StreamSubscription<HistorySyncEvent>? _historySub;
  bool _pinVisible = false;
  bool _playing = false;

  // Estado del receptor para el pill de conexión del home (ver
  // ReceiverStatus). Arranca en `(error, false)`: hasta que `_start` termine
  // no hay forma de descubrir esta TV, y eso es justo lo que antes se perdía
  // en silencio.
  final ValueNotifier<(ReceiverStatus, bool)> _status =
      ValueNotifier((ReceiverStatus.error, false));
  bool _advertised = false;

  // Guardia de re-entrancia de `_start()`: sin esto, un segundo tap de Retry
  // (D-pad) mientras el primer intento sigue en sus `await` (cert TLS,
  // _loadTvId, service.start) lanzaba una SEGUNDA `TvReceiverService`/
  // `HttpServer` — dos servidores anunciándose por mDNS a la vez, y el que
  // escribe último en `_service`/`_connectSub` deja al otro huérfano (sin
  // parar su server ni cancelar sus subs, sin referencia para `dispose()`).
  bool _starting = false;

  /// Recuperación de un emparejamiento abandonado: si un móvil conecta y
  /// nunca completa el LOAD (se cierra la app, cambia de red…), sin esto el
  /// pill se queda en "Pairing…" para siempre — no hay señal de desconexión
  /// en `TvReceiverService` (solo onClientConnected/onLoad/onCommand; añadir
  /// un onDisconnect es un cambio de protocolo fuera del alcance de este
  /// archivo). Un timeout es la única recuperación posible sin tocar el
  /// servicio: si el PIN sigue visible pasado este plazo, se oculta y el
  /// estado vuelve a discoverable/error.
  static const _pinTimeout = Duration(seconds: 60);
  Timer? _pinTimeoutTimer;

  // Reenvío de posición TV→móvil (para "continuar viendo" en el teléfono).
  StreamSubscription<Map<String, dynamic>>? _positionSub;
  DateTime? _lastStateSent; // throttle: como mucho 1 envío cada ~5s
  int _lastPos = 0;
  int _lastDur = 0;
  String _currentChannelId = '';
  // FIX-2: estado play/pausa REAL del PlayerWidget de la TV (por el evento
  // 'cast_player_playing'), reenviado al móvil en `_sendState` como campo
  // autoritativo. Default true: al arrancar el LOAD la TV reproduce.
  StreamSubscription<bool>? _playingSub;
  bool _lastPlaying = true;

  // Reenvío de volumen TV→móvil (eco para que el slider del móvil refleje el
  // volumen real de la TV). Coalescido/throttled (~250ms tras el ÚLTIMO
  // evento): mientras el móvil arrastra su slider, `_player.setVolume` puede
  // emitir por frame (vía media_kit) — reenviar cada tick inundaría la LAN y
  // forzaría un `notifyListeners` en el móvil por cada uno (rebuild del
  // mini-control decenas de veces/seg). El Timer se reinicia en cada evento y
  // solo dispara el envío cuando el volumen deja de cambiar por ese lapso;
  // sigue reflejando cualquier cambio (agrupado), no lo pierde.
  StreamSubscription<double>? _volumeSub;
  Timer? _volumeThrottle;
  double _lastVolume = 100; // default sensato si aún no llegó ningún evento
  static const _volumeThrottleDelay = Duration(milliseconds: 250);

  // QA fix — auto-push de pistas TV→móvil. El móvil pedía las pistas con
  // `getTracks` (petición/respuesta), pero cuando ese `get` corría en la ventana
  // en que el player de la TV aún NO había resuelto sus pistas (media_kit las
  // emite un instante DESPUÉS del open), la TV respondía con una lista vacía o
  // rancia y el sheet del móvil se quedaba sin audios/subtítulos. Solución: en
  // vez de depender solo del pull, la TV EMPUJA la lista de pistas cada vez que
  // el player emite 'player_tracks' (la lista cambió), con el mismo payload que
  // el caso `getTracks`. Así el móvil recibe las pistas en cuanto existen.
  StreamSubscription<Tracks>? _tracksSub;

  // Fin-de-título → móvil (para auto-avance de series). El PlayerWidget de la TV
  // emite 'cast_player_completed' al acabar un VOD/serie; lo reenviamos como
  // MsgType.completed. Distinto de MsgType.ended (BACK/stop cierra la ruta).
  StreamSubscription<String>? _completedSub;
  bool _completedSent = false;

  // Reemplazo de reproducción EN EL MISMO SITIO: un re-LOAD (zapping, auto-avance
  // o reenvío) NO empuja otra ruta de player encima (eso apilaba reproductores y
  // dejaba uno viejo "Preparando…" detrás al hacer BACK). En su lugar se cambia
  // el contenido del player ya montado a través de este notifier.
  // El valor lleva un contador monótono de LOAD además del request: la key del
  // PlayerWidget se deriva del contador (no de identityHashCode, que podría
  // colisionar entre dos requests y NO reinicializar el player en el swap).
  ValueNotifier<(int, CastLoadRequest)>? _loadNotifier;
  int _loadSeq = 0;
  bool _castRouteOpen = false;

  @override
  void initState() {
    super.initState();
    if (ResponsiveHelper.isTelevisionDevice) {
      _start();
    }
  }

  Future<CastTls?> _loadOrCreateCert() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    try {
      final cert = await storage.read(key: 'cast.tls.cert');
      final key = await storage.read(key: 'cast.tls.key');
      if (cert != null && key != null) {
        return CastTls.fromStorage({'cert': cert, 'key': key});
      }
      final tls = CastTls.generate(); // costoso: solo la 1ª vez
      await storage.write(key: 'cast.tls.cert', value: tls.certPem);
      await storage.write(key: 'cast.tls.key', value: tls.keyPem);
      return tls;
    } catch (_) {
      return null; // si falla, se sirve ws:// (degradado)
    }
  }

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _trustTtlMs = 7 * 24 * 60 * 60 * 1000; // 7 días
  List<Map<String, dynamic>> _tokenEntries = [];

  /// Id estable de esta TV (uuid persistido).
  Future<String> _loadTvId() async {
    var id = await _store.read(key: 'cast.tv.id');
    if (id == null) {
      id = const Uuid().v4();
      await _store.write(key: 'cast.tv.id', value: id);
    }
    return id;
  }

  /// Tokens de confianza vigentes (poda los de más de 7 días).
  Future<List<String>> _loadTokens() async {
    final raw = await _store.read(key: 'cast.tv.tokens');
    final now = DateTime.now().millisecondsSinceEpoch;
    _tokenEntries = raw != null
        ? (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .where((e) => now - (e['iat'] as int) < _trustTtlMs)
            .toList()
        : [];
    return _tokenEntries.map((e) => e['t'] as String).toList();
  }

  /// Feature H — borra TODAS las credenciales standalone persistidas (índice +
  /// secure storage). Se invoca cuando la TV se queda sin dispositivos de
  /// confianza (auto-wipe al desemparejar). Nunca lanza: un fallo de borrado no
  /// debe impedir arrancar el receptor.
  Future<void> _wipeAllStandaloneCreds() async {
    try {
      for (final pid in await TvStandaloneCredsService.listProviderIds()) {
        await TvStandaloneCredsService.delete(pid);
      }
    } catch (_) {/* mejor esfuerzo: no romper el arranque del receptor */}
  }

  /// Pushes a new `(status, starting)` pair, preserving whatever `_starting`
  /// currently is. Centralising this (instead of writing `_status.value =`
  /// at each call site) is what makes the `starting` half of the record
  /// trustworthy — every status change re-stamps it, so it can never go
  /// stale relative to the status itself.
  void _setStatus(ReceiverStatus s) {
    if (!mounted) return;
    _status.value = (s, _starting);
  }

  /// Status to fall back to once pairing/playing is no longer in progress —
  /// whatever `_start` last determined about mDNS advertising.
  ReceiverStatus get _idleStatus =>
      _advertised ? ReceiverStatus.discoverable : ReceiverStatus.error;

  /// Starts (or, from the status pill's Retry, RE-starts) the receiver.
  ///
  /// Re-entrant-SAFE, not just re-entrant: a second call while one is already
  /// running (a double D-pad "select" on Retry, or Retry firing while the
  /// very first `initState` call is still mid-`await`) returns immediately
  /// instead of racing it. Without the `_starting` guard, both calls would
  /// reach the "tear down `_service`" branch, each holding its own snapshot
  /// of the OLD service, then each start a NEW `TvReceiverService` — leaving
  /// two servers advertising over mDNS simultaneously, with whichever call
  /// finishes last overwriting `_service`/`_connectSub`/etc. and orphaning
  /// the other (its server never stopped, its subs never cancelled, and no
  /// reference left anywhere to `dispose()` it later).
  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    _setStatus(ReceiverStatus.error);
    try {
      final oldService = _service;
      if (oldService != null) {
        await _connectSub?.cancel();
        await _loadSub?.cancel();
        await _commandSub?.cancel();
        await _historySub?.cancel();
        await oldService.stop();
        oldService.dispose();
        _service = null;
      }

      final tls = await _loadOrCreateCert();
      String tvId = '';
      List<String> tokens = const [];
      // Solo true tras una lectura EXITOSA de tokens. CRÍTICO para el auto-wipe:
      // un fallo transitorio de secure-storage (keystore aún bloqueado, IO) deja
      // el catch con `tokens = const []` — un falso-vacío que NO debe disparar el
      // borrado destructivo de las credenciales de un usuario con dispositivos de
      // confianza (ver shouldWipeStandaloneOnBoot).
      var tokensLoadedOk = false;
      try {
        tvId = await _loadTvId();
        tokens = await _loadTokens();
        tokensLoadedOk = true;
      } catch (_) {/* sin confianza persistida; se pedirá PIN */}
      // Feature H — auto-wipe al desemparejar: la confianza de la TV es puramente
      // por token con TTL de 7 días (_loadTokens poda los vencidos); no hay UI de
      // "olvidar". Cuando NO queda ningún dispositivo de confianza (todos los
      // tokens vencieron / se desemparejó) —y la lectura fue GENUINA, no un
      // fallo—, cualquier credencial standalone guardada quedó huérfana: ningún
      // móvil puede volver a autorizarla sin re-emparejar. Se borran TODAS
      // (índice + secure storage). No-op inofensivo en una TV recién estrenada.
      if (shouldWipeStandaloneOnBoot(
          tokensLoadedOk: tokensLoadedOk, tokensEmpty: tokens.isEmpty)) {
        unawaited(_wipeAllStandaloneCreds());
      }
      final service = TvReceiverService(
        deviceName: widget.deviceName,
        tls: tls,
        tvId: tvId,
        knownTokens: tokens,
        onIssueToken: (token) {
          // Recordar el dispositivo emparejado 7 días (sin UI de gestión).
          _tokenEntries
              .add({'t': token, 'iat': DateTime.now().millisecondsSinceEpoch});
          _store.write(key: 'cast.tv.tokens', value: jsonEncode(_tokenEntries));
        },
      );
      // `advertised` tracks WHICH branch succeeded: the `advertise: false`
      // fallback still serves loopback connections, but a phone on the LAN
      // has no way to find it via mDNS, so it is surfaced as `error` just
      // like a total failure — that silent fallback was exactly the bug this
      // status pill exists to expose.
      var advertised = true;
      try {
        await service.start();
      } catch (_) {
        advertised = false;
        try {
          await service.start(advertise: false);
        } catch (_) {
          return; // sin red utilizable; la app sigue funcionando normal
        }
      }
      _service = service;
      _advertised = advertised;
      _setStatus(advertised ? ReceiverStatus.discoverable : ReceiverStatus.error);
      // Mostrar el PIN cuando un móvil intenta conectar; ocultarlo al reproducir.
      _connectSub = service.onClientConnected.listen((_) {
        if (!mounted) return;
        if (!_playing) {
          setState(() => _pinVisible = true);
          _setStatus(ReceiverStatus.pairing);
          _armPinTimeout();
        } else {
          // Un móvil (re)conecta MIENTRAS ya reproducimos: casi seguro un sender
          // que perdió su socket (se backgroundeó) y se está reenganchando. Eco
          // INMEDIATO del estado actual para que confirme que la sesión sigue
          // viva y resincronice posición/volumen SIN re-LOAD (que reiniciaría la
          // reproducción). Se resetea el throttle para que el próximo tick
          // periódico tampoco quede suprimido.
          _lastStateSent = null;
          _sendState(_lastPos, _lastDur);
        }
      });
      _loadSub = service.onLoad.listen(_play);
      _commandSub = service.onCommand.listen(_handleCommand);
      _historySub = service.onHistorySync.listen(_onHistorySync);
    } finally {
      _starting = false;
      // Re-stamp so `starting` flips back to false in the UI even on a path
      // that didn't otherwise touch the status (the "no usable network"
      // early return above never calls `_setStatus` on its own).
      if (mounted) _status.value = (_status.value.$1, false);
    }
  }

  /// Arms (restarting if already armed) the abandoned-pairing recovery: if
  /// the PIN is still showing `_pinTimeout` after a phone connects — no LOAD
  /// ever arrived, e.g. it closed the app or left the network mid-handshake —
  /// hide it and fall back to the idle status. See the `_pinTimeoutTimer`
  /// field doc for why a timeout (not an onDisconnect signal) is what's
  /// available here.
  void _armPinTimeout() {
    _pinTimeoutTimer?.cancel();
    _pinTimeoutTimer = Timer(_pinTimeout, () {
      if (!mounted || !_pinVisible || _playing) return;
      setState(() => _pinVisible = false);
      _setStatus(_idleStatus);
    });
  }

  void _cancelPinTimeout() {
    _pinTimeoutTimer?.cancel();
    _pinTimeoutTimer = null;
  }

  /// Aplica en la TV los comandos que envía el móvil (control remoto).
  void _handleCommand(Map<String, dynamic> msg) {
    switch (msg['c']) {
      case CmdType.playPause:
        EventBus().emit('cast_play_pause', true);
        break;
      case CmdType.stop:
        if (_playing) {
          _stopPositionForwarding(sendFinal: true);
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        break;
      case CmdType.getTracks:
        _sendTracks();
        break;
      case CmdType.selectAudio:
        final id = msg['id'] as String? ?? '';
        final t = PlayerState.audios.firstWhere((x) => x.id == id,
            orElse: () => AudioTrack.auto());
        EventBus().emit('audio_track_changed', t);
        // RETADOR (reflejo de selección): 'player_tracks' solo dispara cuando
        // cambia la LISTA de pistas, no cuando se selecciona una. El player
        // consume 'audio_track_changed' de forma síncrona y actualiza
        // PlayerState.selectedAudio; en el siguiente turno del event loop ya está
        // fijado, así que re-empujamos las pistas para que el móvil vea el nuevo
        // flag `sel`.
        scheduleMicrotask(_sendTracks);
        break;
      case CmdType.selectSubtitle:
        final id = msg['id'] as String? ?? '';
        final t = id.isEmpty || id == 'no'
            ? SubtitleTrack.no()
            : PlayerState.subtitles.firstWhere((x) => x.id == id,
                orElse: () => SubtitleTrack.no());
        EventBus().emit('subtitle_track_changed', t);
        // Ver RETADOR arriba: re-empujar tras aplicar la selección de subtítulo.
        scheduleMicrotask(_sendTracks);
        break;
      case CmdType.setVolume:
        final v = (msg['v'] as num?)?.toDouble();
        if (v != null) EventBus().emit('cast_set_volume', v.clamp(0, 100));
        break;
      case CmdType.seek:
        // Seek móvil→TV (VOD/serie): el móvil manda la posición absoluta en ms. El
        // PlayerWidget (receptor) la aplica y EXCLUYE vivo en su listener (un seek
        // en vivo lanza "--force-seekable=yes").
        final ms = (msg['ms'] as num?)?.toInt();
        if (ms != null) EventBus().emit('cast_seek', ms);
        break;
      case CmdType.wipeStandalone:
        // Feature H — el móvil revocó el consentimiento de un proveedor: borrar
        // sus credenciales standalone guardadas en ESTA TV (creds + índice).
        final pid = msg['pid'] as String?;
        if (pid != null && pid.isNotEmpty) {
          unawaited(TvStandaloneCredsService.delete(pid));
        }
        break;
    }
  }

  /// Envía al móvil la lista ACTUAL de pistas (audio/subtítulo) con el flag `sel`
  /// del seleccionado. Mismo payload que el caso `getTracks`; se usa tanto por el
  /// auto-push (cuando cambia la lista) como tras aplicar un selectAudio/Subtitle.
  void _sendTracks() {
    _service?.sendMessage('tracks', {
      'audio':
          _serializeTracks(PlayerState.audios, PlayerState.selectedAudio.id),
      'sub': _serializeTracks(
          PlayerState.subtitles, PlayerState.selectedSubtitle.id),
    });
  }

  List<Map<String, dynamic>> _serializeTracks(List<dynamic> tracks, String selId) {
    return [
      for (final t in tracks)
        {
          'id': t.id as String,
          'label': (t.title ?? t.language ?? t.id) as String,
          'sel': t.id == selId,
        }
    ];
  }

  Future<void> _play(CastLoadRequest req) async {
    if (!mounted) return;
    // Un LOAD real llegó: la sesión de pairing (si había una PIN pendiente)
    // se completó, así que el timeout de abandono ya no aplica.
    _cancelPinTimeout();
    // Feature H — persistencia standalone gateada por consentimiento: el móvil
    // solo marca `standalone` cuando el usuario dio permiso maestro + explícito.
    // Las credenciales ya llegan DESCIFRADAS en el req (el servicio las abrió con
    // la clave de sesión); aquí se guardan cifradas en reposo. Ver la función.
    unawaited(maybePersistStandaloneCreds(req));
    setState(() {
      _pinVisible = false;
      _playing = true;
    });
    // (Re)empezar a reenviar posición/fin-de-título al móvil. Se llama en CADA
    // LOAD (incluido el re-LOAD de auto-avance/zapping) para reengancharse al
    // nuevo contenido.
    _completedSent = false;
    _startPositionForwarding(req.channelId);

    // Re-LOAD sobre una sesión ya abierta (zapping en vivo, auto-avance de serie
    // o reenvío): cambiar el contenido del player YA montado en vez de empujar
    // otra ruta encima. Así no se apilan reproductores (causa de "vuelve al
    // contador Preparando… al hacer BACK") ni se envía `ended` (la sesión sigue).
    if (_castRouteOpen && _loadNotifier != null) {
      _loadNotifier!.value = (++_loadSeq, req);
      return;
    }

    // Primer LOAD de la sesión: reproducir la URL EXACTA que envió el móvil (con
    // SUS credenciales), no la del proveedor local. El ContentItem se arma en
    // contexto M3U (ContentItem.url = m3uItem.url) bajo la playlist sintética
    // '__cast__', y se restaura la playlist del usuario al cerrar.
    final saved = AppState.currentPlaylist;
    AppState.currentPlaylist = Playlist(
      // Feature H (fase 5) — la fila de historial que escribe el PlayerWidget
      // (bajo AppState.currentPlaylist.id) queda PARTICIONADA por dispositivo:
      // `__cast__:<deviceId>` (o `__cast__` plano si el móvil no envió `did`), de
      // modo que el sync per-dispositivo sepa a quién pertenece el progreso.
      id: castHistoryPlaylistId(req.deviceId),
      name: 'Cast',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    final notifier =
        _loadNotifier = ValueNotifier<(int, CastLoadRequest)>((++_loadSeq, req));
    _castRouteOpen = true;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _CastPlayerScreen(loadNotifier: notifier),
      ),
    );
    // Al CERRAR la ruta del player (BACK en la TV o stop del móvil), enviar una
    // última posición, avisar al móvil que la TV DEJÓ de reproducir (para que
    // salga de "casting" y no entre en bucle de reconexión), cortar el reenvío,
    // y restaurar la playlist del usuario.
    _castRouteOpen = false;
    _loadNotifier = null;
    notifier.dispose();
    _stopPositionForwarding(sendFinal: true);
    _service?.sendMessage(MsgType.ended, const {});
    AppState.currentPlaylist = saved;
    // El home reducido de la TV lee el historial una sola vez; avisarle de que
    // acaba de reproducirse algo (guardado bajo '__cast__') para que lo recargue
    // y el contenido casteado aparezca en su rail de "historial".
    EventBus().emit('tv_history_changed', null);
    if (mounted) {
      setState(() => _playing = false);
      _setStatus(_idleStatus);
    }
  }

  /// Suscribe el reenvío de posición mientras un cast está en curso. El player
  /// (que corre aquí, en la TV) emite 'cast_player_position'; lo mandamos al
  /// móvil como MsgType.state throttled a como mucho 1 vez cada ~5s.
  void _startPositionForwarding(String channelId) {
    _currentChannelId = channelId;
    _lastStateSent = null;
    _lastPos = 0;
    _lastDur = 0;
    _lastPlaying = true; // FIX-2: un LOAD nuevo arranca reproduciendo
    // Fin-de-título: el player de la TV emite 'cast_player_completed' al acabar
    // un VOD/serie. Reenviarlo UNA vez por episodio (el guard evita duplicados
    // si el stream 'completed' de media_kit reemite) para que el móvil decida el
    // auto-avance. No se envía en vivo (ese caso reabre en el propio player).
    _completedSub?.cancel();
    _completedSub =
        EventBus().on<String>('cast_player_completed').listen((_) {
      if (!_playing || _completedSent) return;
      _completedSent = true;
      _service?.sendMessage(MsgType.completed, {'id': _currentChannelId});
    });
    // Auto-push de pistas: cuando el player de la TV resuelve/cambia su lista de
    // pistas (media_kit emite 'player_tracks'), empujarlas al móvil. Evita la
    // carrera del pull `getTracks` que llegaba antes de que existieran las pistas
    // y devolvía una lista vacía/rancia (ver [_tracksSub]).
    _tracksSub?.cancel();
    _tracksSub = EventBus().on<Tracks>('player_tracks').listen((_) {
      if (!_playing) return;
      _sendTracks();
    });
    _positionSub?.cancel();
    _positionSub =
        EventBus().on<Map<String, dynamic>>('cast_player_position').listen((e) {
      final pos = (e['pos'] as num?)?.toInt() ?? 0;
      final dur = (e['dur'] as num?)?.toInt() ?? 0;
      // Simetría con el receptor en el móvil: sin duración fiable no hay nada
      // que registrar en "continuar viendo" (evita mandar dur:0 en vivo).
      if (pos <= 0 || dur <= 0) return;
      _lastPos = pos;
      _lastDur = dur;
      final now = DateTime.now();
      final last = _lastStateSent;
      if (last != null && now.difference(last) < const Duration(seconds: 5)) {
        return;
      }
      _lastStateSent = now;
      _sendState(pos, dur);
    });
    // Volumen: el PlayerWidget de la TV emite 'cast_player_volume' en cada
    // cambio (incluida la restauración inicial de UserPreferences). NO espera
    // el throttle de posición de 5s (un cambio de volumen debe sentirse
    // responsivo), pero SÍ se coalesce a como mucho 1 envío cada ~250ms tras
    // el último tick (ver el doc de [_volumeThrottle]).
    _volumeSub?.cancel();
    _volumeSub = EventBus().on<double>('cast_player_volume').listen((v) {
      _lastVolume = v;
      _volumeThrottle?.cancel();
      _volumeThrottle = Timer(_volumeThrottleDelay, () {
        _sendState(_lastPos, _lastDur);
      });
    });
    // FIX-2: play/pausa real de la TV → envío INMEDIATO en la transición (bypass
    // del gate pos<=0||dur<=0 y del throttle de 5s, que solo viven en el path de
    // posición), para que el móvil no muestre el icono equivocado ~5s.
    _playingSub?.cancel();
    _playingSub = EventBus().on<bool>('cast_player_playing').listen((playing) {
      if (playing == _lastPlaying) return; // solo en cambios reales
      _lastPlaying = playing;
      _lastStateSent = DateTime.now();
      _sendState(_lastPos, _lastDur);
    });
  }

  /// Corta el reenvío de posición; si [sendFinal], manda una última posición
  /// (para que un título casi terminado quede bien registrado en el móvil).
  void _stopPositionForwarding({bool sendFinal = false}) {
    _positionSub?.cancel();
    _positionSub = null;
    _tracksSub?.cancel();
    _tracksSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _volumeSub?.cancel();
    _volumeSub = null;
    _volumeThrottle?.cancel();
    _volumeThrottle = null;
    _playingSub?.cancel();
    _playingSub = null;
    if (sendFinal && _lastPos > 0) {
      _sendState(_lastPos, _lastDur);
    }
  }

  /// Feature H (fase 5) — un móvil emparejado envió sus deltas de "continuar
  /// viendo". El evento trae el socket ORIGEN y el deviceId establecido por el
  /// LOAD de ESE socket (socket-bound, no spoofeable). MEZCLAMOS en la partición
  /// de ese deviceId (`__cast__:<deviceId>`) y RESPONDEMOS con los de ESA MISMA
  /// partición POR ESE MISMO SOCKET (`sendMessageTo`), no por el `_activeWs`
  /// global: si otro móvil hizo un LOAD (toma de control) mientras este merge
  /// —hasta 200 items × varias queries Drift— estaba en vuelo, `_activeWs` ya
  /// apunta a ESE otro socket, y responder por él le filtraría el historial de
  /// este móvil. Atando socket+deviceId al evento, la respuesta va a su dueño o,
  /// si ya se desconectó/`superseded`, a NADIE (no-op) — nunca a otro. Una sola
  /// respuesta por lote (el móvil no responde a la nuestra → sin ping-pong).
  /// Best-effort: un fallo de BD no rompe nada.
  Future<void> _onHistorySync(HistorySyncEvent event) async {
    final (socket, deviceId, items) = event;
    try {
      final r =
          await mergeAndReplyHistorySync(WatchHistoryService(), deviceId, items);
      // El home reducido de la TV lee el historial una vez; avisar si cambió
      // para que el rail de "vistos" refleje el progreso recibido del móvil.
      if (r.written > 0) EventBus().emit('tv_history_changed', null);
      _service?.sendMessageTo(
          socket, MsgType.historySync, encodeHistorySyncBody(r.reply));
    } catch (_) {/* un sync de historial nunca debe romper el receptor */}
  }

  void _sendState(int pos, int dur) {
    _service?.sendMessage(MsgType.state, {
      // 'status' se mantiene por compat con emisores viejos (leían 'playing'
      // hardcodeado). FIX-2: 'playing' es el campo AUTORITATIVO nuevo con el
      // estado real; un emisor viejo lo ignora, uno nuevo deja de inferir.
      'status': 'playing',
      'playing': _lastPlaying,
      'pos': pos,
      'dur': dur,
      'id': _currentChannelId,
      'vol': _lastVolume,
    });
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _loadSub?.cancel();
    _commandSub?.cancel();
    _historySub?.cancel();
    _positionSub?.cancel();
    _tracksSub?.cancel();
    _completedSub?.cancel();
    _volumeSub?.cancel();
    _volumeThrottle?.cancel();
    _playingSub?.cancel();
    _pinTimeoutTimer?.cancel();
    _loadNotifier?.dispose();
    _service?.stop();
    _service?.dispose();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TvReceiverStatusScope(
          status: _status,
          deviceName: widget.deviceName,
          onRetry: _start,
          child: widget.child,
        ),
        if (_pinVisible && _service != null) _pinOverlay(context),
      ],
    );
  }

  Widget _pinOverlay(BuildContext context) {
    final loc = context.loc;
    final r = rensi(context);
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        // Warm ramp instead of flat black87, same intent as the home behind
        // it: a translucent wash of the theme's own background, not an
        // unrelated near-black.
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cast, color: r.accent, size: 56),
            const SizedBox(height: 20),
            Text(loc.cast_enter_pin,
                style: TextStyle(
                    color: r.text2,
                    fontSize: AppThemes.tenFoot(context, AppThemes.bodySize))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: r.accent, width: 2),
              ),
              child: Text(
                _service!.pin,
                style: TextStyle(
                    color: r.accent,
                    fontSize: AppThemes.tenFoot(context, 60),
                    letterSpacing: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                _cancelPinTimeout();
                setState(() => _pinVisible = false);
                _setStatus(_idleStatus);
              },
              child: Text(MaterialLocalizations.of(context).okButtonLabel,
                  style: TextStyle(
                      color: r.text3,
                      fontSize: AppThemes.tenFoot(context, AppThemes.bodySmallSize))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ruta ÚNICA del player receptor durante una sesión de casting. En vez de
/// empujar una ruta nueva por cada LOAD, esta pantalla observa un notifier y
/// reconstruye el [PlayerWidget] con una key nueva cuando llega otro contenido
/// (zapping / auto-avance de serie). Así el BACK siempre vuelve al home de la TV
/// (no a un player viejo apilado) y no hay doble audio.
class _CastPlayerScreen extends StatelessWidget {
  const _CastPlayerScreen({required this.loadNotifier});

  final ValueNotifier<(int, CastLoadRequest)> loadNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<(int, CastLoadRequest)>(
      valueListenable: loadNotifier,
      builder: (context, value, _) {
        final (seq, req) = value;
        final item = _castItemFor(req);
        return Scaffold(
          backgroundColor: Colors.black,
          // Key por el contador monótono del LOAD: cada re-LOAD tiene un seq
          // distinto, así el player se reinicializa por completo con el nuevo
          // contenido (sin riesgo de colisión de identityHashCode).
          body: PlayerWidget(
            key: ValueKey('cast-$seq'),
            contentItem: item,
            queue: [item],
            // Ficha TMDb (sinopsis + reparto) que envió el móvil con el LOAD; el
            // panel de pausa la pinta sin llamar a TMDb (la TV no tiene clave).
            castMeta: req.meta,
            // Resume: reanudar donde el móvil lo dejó (0 → desde el principio).
            // La TV no tiene el historial local del móvil, así que sin esto un
            // título a medias arrancaría siempre en 0.
            startPositionMs: req.startPositionMs,
            // Feature H — cuando el LOAD es standalone, el `pid` del proveedor se
            // guarda en la fila de historial `__cast__` (junto al container
            // extension del ContentItem) para el replay standalone de fase 4. En
            // un LOAD normal es null → la fila queda con ambas columnas null,
            // exactamente como antes.
            standaloneProviderId: req.standalone && req.providerId.isNotEmpty
                ? req.providerId
                : null,
          ),
        );
      },
    );
  }
}

/// Reconstruye un [ContentItem] reproducible desde un LOAD del móvil. Se arma en
/// contexto M3U para que ContentItem.url resuelva a la URL EXACTA que envió el
/// móvil (con sus credenciales), no una URL Xtream del proveedor local.
ContentItem _castItemFor(CastLoadRequest req) {
  final ctype = switch (req.contentType) {
    'vod' => ContentType.vod,
    'series' => ContentType.series,
    // Archivo local (descarga offline) enviado por LAN: tratarlo como VOD para
    // que el player ofrezca barra de progreso/seek.
    'file' => ContentType.vod,
    _ => ContentType.liveStream,
  };
  // Póster: URL reconstruida por CastMeta contra el host FIJO de TMDb
  // (image.tmdb.org) a partir del fragmento que envió el móvil — nunca una URL
  // controlada por el emisor. Se usa como imagePath para que la fila de historial
  // (__cast__, escrita por PlayerWidget._saveWatchHistory) guarde una URL pública
  // ALCANZABLE → la miniatura del carrusel "vistos" muestra el póster. Sin
  // fragmento (contenido no-TMDb / archivo local) → '' y se mantiene el degradado.
  final poster = req.meta?.posterUrl ?? '';
  return ContentItem(
    req.channelId,
    req.title.isEmpty ? 'Cast' : req.title,
    poster,
    ctype,
    // Feature H — se conserva el container extension del LOAD para que, cuando el
    // cast sea standalone, la fila de historial `__cast__` lo persista (necesario
    // para reconstruir la URL Xtream en el replay de fase 4). No afecta la URL de
    // reproducción (contexto M3U → usa m3uItem.url).
    containerExtension: req.ext.isNotEmpty ? req.ext : null,
    // Feature H (mejora) — cuando el LOAD trae seriesId (episodio de serie), se
    // adjunta un seriesStream para que PlayerWidget._saveWatchHistory persista
    // WatchHistory.seriesId en la fila `__cast__`. Con ese seriesId, un replay
    // standalone posterior puede resolver la lista COMPLETA de episodios y
    // auto-avanzar sola por la serie. Sin seriesId (VOD/archivo/vivo) → null,
    // exactamente como antes (la columna queda null).
    seriesStream: req.seriesId.isNotEmpty
        ? SeriesStream(
            playlistId: _castPlaylistId,
            seriesId: req.seriesId,
            name: req.title,
          )
        : null,
    m3uItem: M3uItem(
      id: req.channelId,
      playlistId: _castPlaylistId,
      url: req.mediaUrl,
      contentType: ctype,
      name: req.title,
    ),
  );
}
