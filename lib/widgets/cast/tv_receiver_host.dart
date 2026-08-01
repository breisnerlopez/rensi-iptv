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
import '../../redesign/rensi_widgets.dart';
import '../../services/app_state.dart';
import '../../services/cast/cast_protocol.dart';
import '../../services/cast/cast_tls.dart';
import '../../services/cast/tv_receiver_service.dart';
import '../../services/event_bus.dart';
import '../../services/player_state.dart';
import '../../utils/app_themes.dart';
import '../../utils/responsive_helper.dart';
import '../player_widget.dart';

const _castPlaylistId = '__cast__';

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
        await oldService.stop();
        oldService.dispose();
        _service = null;
      }

      final tls = await _loadOrCreateCert();
      String tvId = '';
      List<String> tokens = const [];
      try {
        tvId = await _loadTvId();
        tokens = await _loadTokens();
      } catch (_) {/* sin confianza persistida; se pedirá PIN */}
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
        _service?.sendMessage('tracks', {
          'audio': _serializeTracks(
              PlayerState.audios, PlayerState.selectedAudio.id),
          'sub': _serializeTracks(
              PlayerState.subtitles, PlayerState.selectedSubtitle.id),
        });
        break;
      case CmdType.selectAudio:
        final id = msg['id'] as String? ?? '';
        final t = PlayerState.audios.firstWhere((x) => x.id == id,
            orElse: () => AudioTrack.auto());
        EventBus().emit('audio_track_changed', t);
        break;
      case CmdType.selectSubtitle:
        final id = msg['id'] as String? ?? '';
        final t = id.isEmpty || id == 'no'
            ? SubtitleTrack.no()
            : PlayerState.subtitles.firstWhere((x) => x.id == id,
                orElse: () => SubtitleTrack.no());
        EventBus().emit('subtitle_track_changed', t);
        break;
      case CmdType.setVolume:
        final v = (msg['v'] as num?)?.toDouble();
        if (v != null) EventBus().emit('cast_set_volume', v.clamp(0, 100));
        break;
    }
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
      id: _castPlaylistId,
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
  }

  /// Corta el reenvío de posición; si [sendFinal], manda una última posición
  /// (para que un título casi terminado quede bien registrado en el móvil).
  void _stopPositionForwarding({bool sendFinal = false}) {
    _positionSub?.cancel();
    _positionSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _volumeSub?.cancel();
    _volumeSub = null;
    _volumeThrottle?.cancel();
    _volumeThrottle = null;
    if (sendFinal && _lastPos > 0) {
      _sendState(_lastPos, _lastDur);
    }
  }

  void _sendState(int pos, int dur) {
    _service?.sendMessage(MsgType.state, {
      'status': 'playing',
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
    _positionSub?.cancel();
    _completedSub?.cancel();
    _volumeSub?.cancel();
    _volumeThrottle?.cancel();
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
    m3uItem: M3uItem(
      id: req.channelId,
      playlistId: _castPlaylistId,
      url: req.mediaUrl,
      contentType: ctype,
      name: req.title,
    ),
  );
}
