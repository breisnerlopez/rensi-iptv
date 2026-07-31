import 'dart:async';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/channel_number_buffer.dart';
import 'package:rensi_iptv/services/download_service.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/pip_service.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/channel_order.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/widgets/channel_number_overlay.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_info_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_next_episode_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_settings_widget.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/utils/pre_buffer_monitor.dart';
import 'package:rensi_iptv/widgets/cast/cast_flow.dart';
import 'package:rensi_iptv/widgets/cast/pause_info_panel.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/utils/subtitle_configuration.dart';
import 'package:rensi_iptv/widgets/video_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/content_type.dart';
import '../../services/player_state.dart';
import '../../services/service_locator.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';
import '../../utils/audio_handler.dart';
import '../utils/player_error_handler.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

class PlayerWidget extends StatefulWidget {
  final ContentItem contentItem;
  final double? aspectRatio;
  final bool showControls;
  final bool showInfo;
  final VoidCallback? onFullscreen;
  final List<ContentItem>? queue;

  const PlayerWidget({
    super.key,
    required this.contentItem,
    this.aspectRatio,
    this.showControls = true,
    this.showInfo = false,
    this.onFullscreen,
    this.queue,
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with WidgetsBindingObserver {
  late StreamSubscription videoTrackSubscription;
  late StreamSubscription audioTrackSubscription;
  late StreamSubscription subtitleTrackSubscription;
  StreamSubscription? _externalSubUriSubscription;
  StreamSubscription? _externalSubDataSubscription;
  StreamSubscription? _playbackSpeedSubscription;
  StreamSubscription? _castPlayPauseSubscription;
  Duration? _seekPos;
  Duration? _seekDur;
  Timer? _seekHideTimer;
  // Seek acumulado + acelerado (mando de TV). Pulsaciones consecutivas en la
  // misma dirección crecen el paso (15s → 1min → 3min → 5min) y ACUMULAN sobre
  // un objetivo pendiente; el seek real se hace UNA sola vez ~350ms tras la
  // última pulsación (patrón de _changeChannel) para no re-bufferizar en cada
  // paso, y se reanuda con play() para no quedar en el spinner de carga.
  Duration? _pendingSeekTarget;
  Timer? _seekCommitTimer;
  Timer? _seekGraceTimer;
  int _seekStreak = 0;
  bool _seekForward = true;
  bool _seekWasPlaying = true;
  bool _seekInProgress = false; // ventana de gracia del re-buffer tras el seek
  DateTime? _lastSeekPressAt;
  // Rich pause panel (TV only): while paused, show title + synopsis + cast.
  bool _showPausePanel = false;
  // Nullable (not `late`): they're assigned inside the async _initializePlayer,
  // so a fast BACK before init finishes must not crash dispose().
  StreamSubscription? contentItemIndexChangedSubscription;
  StreamSubscription? _connectivitySubscription;

  late Player _player;
  VideoController? _videoController;
  late WatchHistoryService watchHistoryService;
  final MyAudioHandler _audioHandler = getIt<MyAudioHandler>();
  final AppDatabase _database = getIt<AppDatabase>();
  List<ContentItem>? _queue;
  late ContentItem contentItem;
  final PlayerErrorHandler _errorHandler = PlayerErrorHandler();

  // Feature A — self-heal a stale container extension. Providers re-encode
  // titles (e.g. mkv→mp4); the cached extension then resolves to an HTML error
  // page and libmpv reports "failed to recognize file format". Try alternate
  // extensions, capped, and persist the winner so the cost is paid once.
  final Set<String> _triedExtensions = {};
  int _extHealAttempts = 0;
  static const int _maxExtHealAttempts = 2;
  String? _pendingHealExtension; // the extension a trial is currently testing
  String? _healContentId; // id whose heal state _tried/_attempts belong to

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  bool _wasDisconnected = false;
  bool _isFirstCheck = true;
  int _currentItemIndex = 0;
  bool _showChannelList = false;
  // Stream IDs of favourited channels, so the player's channel list can show
  // favourites first. Refreshed each time the list is opened.
  Set<String> _favoriteChannelIds = {};
  // ID (not raw index) of the channel we were on before the current one, for a
  // quick "last channel" recall. Tracked by identity so a queue/category change
  // can't make it resolve to the wrong channel.
  String? _previousChannelId;
  Timer? _watchHistoryTimer;
  Duration? _pendingWatchDuration;
  Duration? _pendingTotalDuration;
  final FocusNode _remoteFocusNode = FocusNode(debugLabel: 'PlayerRemote');
  // Focus target for the "Siguiente episodio" button inside the TV pause panel.
  // The panel normally keeps focus on [_remoteFocusNode] (so OK resumes); D-pad
  // DOWN hands focus here to reveal the ring, and UP/BACK returns it.
  final FocusNode _nextEpisodeFocusNode =
      FocusNode(debugLabel: 'PlayerNextEpisode');
  // OK/center long-press → open player options (audio/subtitles). Short press
  // stays play/pause. This is the universal remote route to those panels.
  Timer? _okHoldTimer;
  bool _okHoldFired = false;
  bool _okDownStarted = false;
  // Transient TV hint teaching the long-press-OK gesture (shown a few times).
  bool _showOkHint = false;
  Timer? _okHintTimer;
  StreamSubscription<int?>? _pipWidthSubscription;
  StreamSubscription<int?>? _pipHeightSubscription;
  int? _lastVideoWidth;
  int? _lastVideoHeight;
  StreamSubscription<void>? _sleepTimerSubscription;
  final ChannelNumberBuffer _channelBuffer = ChannelNumberBuffer();
  StreamSubscription<int>? _channelBufferSubscription;
  // Overlay toggle subscriptions — previously leaked (never cancelled).
  StreamSubscription<bool>? _toggleChannelListSub;
  StreamSubscription<bool>? _toggleVideoInfoSub;
  StreamSubscription<bool>? _toggleVideoSettingsSub;
  // Keep the screen awake while playing.
  StreamSubscription<bool>? _playingSubscription;
  // Live-stream stall watchdog.
  StreamSubscription<bool>? _bufferingSubscription;
  Timer? _stallTimer;
  // Guard against disposing the native player twice (lifecycle + dispose()).
  bool _playerDisposed = false;
  // Debounce channel surfing (holding channel up/down) so we reopen the stream
  // once the user stops, not on every key repeat.
  int? _pendingChannelIndex;
  Timer? _channelDebounceTimer;

  // --- Casting (segunda pantalla) ---
  CastSenderController? _cast;
  bool _wasCasting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // El provider de casting solo existe en la app real; en tests aislados que
    // montan el player sin él, no hacemos nada.
    try {
      final cast = context.read<CastSenderController>();
      if (!identical(cast, _cast)) {
        _cast?.removeListener(_onCastChanged);
        _cast = cast..addListener(_onCastChanged);
      }
    } catch (_) {/* sin CastSenderController en el árbol */}
  }

  /// Handoff de conexión: al empezar a castear se libera el stream local (evita
  /// dos conexiones simultáneas contra el proveedor); al terminar, se reabre.
  void _onCastChanged() {
    final now = _cast?.isCasting ?? false;
    if (now == _wasCasting || !mounted) return;
    _wasCasting = now;
    if (now) {
      // Handoff: liberar el stream local (evita dos conexiones al proveedor y
      // que el audio suene en el móvil). El CIERRE de la pantalla lo hace
      // _onGateSendToTv DESPUÉS de que el modal de casting se cierre — si se
      // hiciera aquí (con el modal aún encima) el maybePop cerraría el modal en
      // vez del reproductor, dejando el player montado.
      _player.stop();
    }
    // Importante: al TERMINAR el cast NO se reabre la reproducción local. Antes
    // se hacía `_reopenCurrent()`, lo que provocaba que al detener en la TV el
    // móvil empezara a reproducir solo (audio fantasma). Parar es parar; si el
    // usuario quiere ver en el móvil, vuelve a abrir el contenido.
  }

  static String _castType(ContentType t) => switch (t) {
        ContentType.vod => 'vod',
        ContentType.series => 'series',
        ContentType.liveStream => 'live',
      };

  CastMedia get _castMedia => CastMedia(
        channelId: widget.contentItem.id,
        contentType: _castType(widget.contentItem.contentType),
        title: widget.contentItem.name,
        ext: widget.contentItem.containerExtension ?? '',
        imagePath: widget.contentItem.imagePath,
        playlistId: AppState.currentPlaylist?.id ?? '',
        seriesId: widget.contentItem.seriesStream?.seriesId,
        // Misma clave de historial que _saveWatchHistory (Xtream: id; M3U:
        // m3uItem.id) para no duplicar "continuar viendo".
        historyId: isXtreamCode
            ? widget.contentItem.id
            : widget.contentItem.m3uItem?.id ?? widget.contentItem.id,
      );

  /// Catálogo actual mapeado a CastMedia (para el zapping desde el móvil).
  List<CastMedia>? get _castQueue {
    final q = _queue;
    if (q == null || q.length <= 1) return null;
    return [
      for (final it in q)
        CastMedia(
          channelId: it.id,
          contentType: _castType(it.contentType),
          title: it.name,
          ext: it.containerExtension ?? '',
          imagePath: it.imagePath,
          playlistId: AppState.currentPlaylist?.id ?? '',
          seriesId: it.seriesStream?.seriesId,
          historyId: isXtreamCode ? it.id : it.m3uItem?.id ?? it.id,
        )
    ];
  }

  int get _castIndex {
    final q = _queue;
    if (q == null) return 0;
    final i = q.indexWhere((it) => it.id == widget.contentItem.id);
    return i < 0 ? 0 : i;
  }

  // --- Gate de casting pre-reproducción (solo móvil) ---
  // Antes de cargar el stream en el teléfono, ofrece enviarlo a la TV para NO
  // gastar datos. "Reproducir ahora" o la cuenta atrás siguen a reproducción
  // local. En la TV (receptora) o si ya se está casteando, no aparece.
  Completer<bool>? _castGate;
  bool _castGateActive = false;
  // El usuario pulsó "Enviar a la TV": desde ese momento y mientras el flujo de
  // cast (descubrir/emparejar) sigue en curso, el gate NO debe resolver JAMÁS a
  // reproducción local — ni por la cuenta atrás ni por una carrera del timer.
  // Solo un cancel EXPLÍCITO del modal de cast (startCastFlow retorna sin
  // castear) permite volver a local, y para entonces este flag ya se limpió.
  bool _castCommitted = false;
  Timer? _castGateTimer;
  int _castGateSecs = 8;

  // --- Pre-buffer inteligente (conexiones lentas) ---
  // Abre el stream, PAUSA el video (el demuxer sigue llenando el caché) y
  // reproduce al alcanzar colchón suficiente (o al forzar). Muestra velocidad,
  // buffer y estado (cargando/listo/lento/sin datos). Solo se activa en el open
  // inicial; el zapping/reconexión no pasan por aquí.
  Timer? _preBufferTimer;
  PreBufferMonitor? _preBuffer;
  bool _preBuffering = false;
  final Stopwatch _preBufferClock = Stopwatch();

  // Watchdog de la carga inicial: cuenta el tiempo en "Preparando…" para poder
  // avisar (y ofrecer Reintentar) si la apertura del stream se cuelga sin lanzar
  // error — el caso reportado en algunas cajas de TV.
  Timer? _loadTicker;
  final Stopwatch _loadClock = Stopwatch();
  bool _autoRetried = false; // un solo auto-reintento del primer arranque
  // Fase de la carga (audio/open/ready), para diagnosticar dónde se cuelga.
  String _loadStage = '';

  void _startPreBuffer() {
    final isLive = widget.contentItem.contentType == ContentType.liveStream;
    final tv = ResponsiveHelper.isTelevisionDevice;
    _preBuffer = PreBufferMonitor(targetSecs: isLive ? 4 : 15);
    _preBuffering = true;
    if (tv) {
      // En la TV (receptor de casting) NO retener el vídeo: algunas cajas no
      // llenan/reportan la caché con el vídeo en pausa antes del primer frame,
      // así que retener dejaba las métricas en 0 y el arranque colgado (el
      // usuario veía un círculo eterno). Reproducir y SOLO monitorear: el panel
      // muestra velocidad/buffer reales mientras carga y se oculta al estabilizar.
      _player.play();
    } else {
      _player.pause(); // móvil: retener el vídeo; el caché sigue llenándose
    }
    _preBufferClock
      ..reset()
      ..start();
    if (mounted) setState(() {});
    _preBufferTimer?.cancel();
    _preBufferTimer =
        Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (!mounted || !_preBuffering) {
        t.cancel();
        return;
      }
      double buf = 0, spd = 0;
      final pf = _player.platform;
      if (pf is NativePlayer) {
        try {
          buf = double.tryParse(
                  await pf.getProperty('demuxer-cache-duration')) ??
              0;
          spd = double.tryParse(await pf.getProperty('cache-speed')) ?? 0;
        } catch (_) {}
      }
      _preBuffer!.add(PreBufferSample(buf, spd, _preBufferClock.elapsed));
      if (mounted) setState(() {});
      final elapsed = _preBufferClock.elapsed;
      final tv = ResponsiveHelper.isTelevisionDevice;
      // Piso (solo TV): mostrar "preparando" al menos 1.5s tras enviar el
      // contenido; con buena conexión el colchón se llena en 1-2 ticks y no se
      // llegaba a ver el estado. En el móvil se inicia en cuanto hay colchón.
      final minShown = !tv || elapsed >= const Duration(milliseconds: 1500);
      // TECHO de seguridad: NUNCA retener el vídeo indefinidamente. En algunos
      // backends (p. ej. cajas de TV) la caché no reporta duración con el vídeo
      // en pausa, o un live pausado no la llena, así que 'isReady' no llegaría
      // nunca y el vídeo quedaría retenido → "círculo de carga infinito" al
      // castear. Pasado el máximo, reproducir igual (mejor un arranque sin
      // colchón que un cuelgue eterno).
      final maxWaited = elapsed >= const Duration(seconds: 8);
      // Sin datos (stalled): no tiene sentido seguir reteniendo — soltar y dejar
      // que el player normal (buffering/stall-watchdog/error) tome el control.
      final stalled = _preBuffer!.phase == BufferPhase.stalled;
      if ((_preBuffer!.isReady && minShown) || stalled || maxWaited) {
        _finishPreBuffer(); // arranca: colchón listo, o sin datos, o techo agotado
      }
    });
  }

  /// Reproduce: automático al alcanzar la meta de caché, o forzado por el usuario.
  void _finishPreBuffer() {
    _preBufferTimer?.cancel();
    _preBufferClock.stop();
    if (!_preBuffering) return;
    _preBuffering = false;
    _player.play();
    if (mounted) setState(() {});
  }

  /// Indicador de carga inicial (mientras se abre el stream, antes de que el
  /// pre-buffer tome métricas): "Preparando…" en vez de un círculo mudo, para
  /// que en la TV el usuario sepa que está conectando y no vea solo una rueda.
  Widget _buildLoadingIndicator(BuildContext context) {
    // Null-safe: durante la carga el árbol puede no tener aún los delegados de
    // localización (p. ej. en tests) → fallback.
    final loc = AppLocalizations.of(context);
    final secs = _loadClock.elapsed.inSeconds;
    // Umbral: si sigue "Preparando…" pasado un tiempo, probablemente la TV no
    // logra abrir el stream (cuelgue silencioso, sin error) → avisar + Reintentar.
    final tooLong = secs >= 12;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFD2603A)),
            const SizedBox(height: 18),
            Text(
              '${loc?.prebuffer_preparing ?? 'Preparando…'}'
              '${secs > 0 ? '  ·  ${secs}s' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: AppThemes.tenFoot(context, 16),
              ),
            ),
            if (tooLong) ...[
              const SizedBox(height: 14),
              Text(
                'Está tardando más de lo normal. Puede que la TV no esté '
                'logrando abrir el stream.'
                '${_loadStage.isNotEmpty ? '  (fase: $_loadStage)' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: AppThemes.tenFoot(context, 13),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                autofocus: ResponsiveHelper.isTelevisionDevice,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD2603A),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                onPressed: _retryPlayback,
                icon: const Icon(Icons.refresh),
                label: Text(
                  loc?.cast_retry ?? 'Reintentar',
                  style: TextStyle(fontSize: AppThemes.tenFoot(context, 14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreBuffer(BuildContext context) {
    if (!_preBuffering || _preBuffer == null) return const SizedBox.shrink();
    final loc = context.loc;
    final m = _preBuffer!;
    final speedMbps = m.speedBps / (1024 * 1024);
    final (String status, Color color, IconData icon) = switch (m.phase) {
      BufferPhase.ready => (loc.prebuffer_ready, Colors.greenAccent, Icons.check_circle),
      BufferPhase.slow => (loc.prebuffer_slow, Colors.orangeAccent, Icons.warning_amber),
      BufferPhase.stalled => (loc.prebuffer_stalled, Colors.redAccent, Icons.wifi_off),
      _ => (loc.prebuffer_preparing, Colors.white70, Icons.downloading),
    };
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 46),
              const SizedBox(height: 14),
              Text(status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: AppThemes.tenFoot(context, 18),
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text('${speedMbps.toStringAsFixed(2)} MB/s',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: AppThemes.tenFoot(context, 15))),
              const SizedBox(height: 8),
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: m.progress,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    color: const Color(0xFFD2603A),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('${m.bufferedSecs.toStringAsFixed(0)} s / ${m.targetSecs.toStringAsFixed(0)} s',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: AppThemes.tenFoot(context, 13))),
              const SizedBox(height: 22),
              SizedBox(
                width: 260,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD2603A),
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: _finishPreBuffer, // "Reproducir ahora"
                  child: Text(loc.prebuffer_play_now),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _needsCastGate() {
    if (ResponsiveHelper.isTelevisionDevice || !mounted) return false;
    try {
      // Leer el provider directamente (no depender del orden de
      // didChangeDependencies respecto a la init asíncrona).
      final cast = context.read<CastSenderController>();
      _cast ??= cast;
      return !cast.isCasting;
    } catch (_) {
      return false; // sin provider de casting (p. ej. tests aislados del player)
    }
  }

  /// Devuelve el controlador SI ya se está casteando (política "casting manda"):
  /// abrir un título mientras se castea NO debe reproducirlo en el móvil, sino
  /// reenviarlo a la TV. null en la TV receptora, sin provider, o si no castea.
  CastSenderController? _castingController() {
    if (ResponsiveHelper.isTelevisionDevice || !mounted) return null;
    try {
      final cast = context.read<CastSenderController>();
      _cast ??= cast;
      return cast.isCasting ? cast : null;
    } catch (_) {
      return null;
    }
  }

  /// Coexistencia móvil↔TV: reenvía el título que se iba a abrir localmente a la
  /// TV (re-LOAD sobre la sesión viva, sin re-emparejar) y vuelve a la
  /// navegación. Evita la doble reproducción y deja el mini-control reflejando
  /// el nuevo contenido. Las descargas OFFLINE (url no http) van por el camino
  /// de archivo local (servidas por la LAN).
  Future<void> _recastToTv(CastSenderController cast) async {
    final url = contentItem.url;
    final isLocalFile = !url.startsWith('http');
    bool ok;
    try {
      ok = isLocalFile
          ? await cast.castNextLocalFile(
              filePath: url,
              contentId: contentItem.id,
              title: contentItem.name,
              ext: contentItem.containerExtension ?? '',
              imagePath: contentItem.imagePath,
            )
          : await cast.castNext(_castMedia, queue: _castQueue, index: _castIndex);
    } catch (_) {
      // El recast nunca debe propagar a _initializePlayer: eso dejaría el player
      // colgado antes del stop/pop (ni local ni TV). Se trata como fallo.
      ok = false;
    }
    if (!mounted) return;
    // Pase lo que pase, NO abrir el player local (política "casting manda"):
    // parar el (aún sin abrir) player y volver a la navegación. El mini-control
    // sigue reflejando lo que la TV reproduce. Si el recast falló (sesión
    // reconectándose), avisar — sin dejar el player atascado.
    _player.stop();
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).maybePop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(ok ? context.loc.cast_sent_to_tv : context.loc.cast_send_failed),
      ),
    );
  }

  void _startCastGateCountdown() {
    _castGateSecs = 8;
    _castGateTimer?.cancel();
    _castGateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      // Una vez comprometido a la TV, la cuenta atrás queda MUERTA: ni decrementa
      // ni puede disparar reproducción local (cubre la carrera en la que este
      // callback ya estaba encolado cuando el usuario pulsó "Enviar a la TV").
      if (_castCommitted) return t.cancel();
      setState(() => _castGateSecs--);
      if (_castGateSecs <= 0) _resolveCastGate(true);
    });
  }

  void _resolveCastGate(bool playLocal) {
    // Blindaje de la política "casting manda": si el usuario ya comprometió el
    // envío a la TV, NUNCA resolvemos a reproducción local mientras el flujo de
    // cast sigue vivo. El único camino legítimo a local tras comprometer es el
    // cancel explícito del modal, que limpia _castCommitted ANTES de llamar aquí.
    if (playLocal && _castCommitted) return;
    _castGateTimer?.cancel();
    _castGateActive = false;
    if (_castGate?.isCompleted == false) _castGate!.complete(playLocal);
    if (mounted) setState(() {});
  }

  Future<void> _onGateSendToTv() async {
    // Comprometer el envío a la TV: mata la cuenta atrás y bloquea cualquier
    // resolución a reproducción local mientras se descubre/empareja.
    _castCommitted = true;
    _castGateTimer?.cancel();
    // Matar el watchdog de carga: su auto-reintento a los 8s reabriría el stream
    // LOCAL (doble reproducción móvil+TV) mientras el usuario lee el PIN / elige
    // la TV (el gate mantiene isLoading=true todo el rato, así que el disparo es
    // casi seguro si el flujo tarda >8s). _reopenCurrent además queda blindado.
    _loadTicker?.cancel();
    _loadClock.stop();
    if (mounted) setState(() => _castGateActive = false);
    var casting = false;
    try {
      await startCastFlow(context, _castMedia, queue: _castQueue, index: _castIndex);
      if (mounted) casting = _cast?.isCasting ?? false;
    } catch (_) {
      // El flujo de cast lanzó. Derivar de isCasting (no forzar false): si la
      // sesión de TV YA quedó viva antes del throw, forzar local abriría el
      // stream en el móvil con la TV reproduciendo (doble-play) — el open
      // inicial no pasa por el blindaje de _reopenCurrent.
      casting = _cast?.isCasting ?? false;
    } finally {
      // Pase lo que pase (incluido que startCastFlow lance), limpiar el
      // compromiso: si no, _resolveCastGate(true) quedaría bloqueado PARA
      // SIEMPRE y el player colgado en "Preparando…". Se limpia ANTES de
      // resolver para que la rama de cancelado sí pueda caer a local.
      if (mounted) _castCommitted = false;
    }
    if (!mounted) return;
    // No abrir el stream local (si casteó) o abrirlo (si canceló/falló).
    _resolveCastGate(!casting);
    if (casting) {
      // El modal de casting ya se cerró (startCastFlow retornó), así que ahora
      // el reproductor ES la ruta superior: cerrarlo devuelve al usuario a la
      // navegación mientras la TV reproduce (el control vive en el mini-control).
      _player.stop();
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildCastGate(BuildContext context) {
    if (!_castGateActive) return const SizedBox.shrink();
    final loc = context.loc;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cast, color: Color(0xFFD2603A), size: 52),
              const SizedBox(height: 20),
              Text(loc.cast_gate_prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 28),
              SizedBox(
                width: 280,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD2603A),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _onGateSendToTv,
                  icon: const Icon(Icons.cast),
                  label: Text(loc.cast_to_tv),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => _resolveCastGate(true),
                  child: Text('${loc.cast_gate_play_now}  ·  ${_castGateSecs}s'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    contentItem = widget.contentItem;
    _queue = widget.queue;

    // --- INSERTION 1: INITIAL CONTENT SET ---
    PlayerState.currentContent = widget.contentItem;
    PlayerState.queue = _queue;
    PlayerState.currentIndex = 0;
    // ----------------------------------------

    PlayerState.title = widget.contentItem.name;
    // Bigger packet buffer smooths out network jitter on TV boxes.
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    _tuneForPerformance();
    watchHistoryService = WatchHistoryService();

    super.initState();
    videoTrackSubscription = EventBus()
        .on<VideoTrack>('video_track_changed')
        .listen((VideoTrack data) async {
          _player.setVideoTrack(data);
          await UserPreferences.setVideoTrack(data.id);
        });

    audioTrackSubscription = EventBus()
        .on<AudioTrack>('audio_track_changed')
        .listen((AudioTrack data) async {
          _player.setAudioTrack(data);
          await UserPreferences.setAudioTrack(data.language ?? 'null');
        });

    subtitleTrackSubscription = EventBus()
        .on<SubtitleTrack>('subtitle_track_changed')
        .listen((SubtitleTrack data) async {
          _player.setSubtitleTrack(data);
          await UserPreferences.setSubtitleTrack(data.language ?? 'null');
        });

    // Cast: cuando este player es el receptor en la TV, el móvil envía
    // play/pausa por el canal de control y aquí se aplica.
    _castPlayPauseSubscription =
        EventBus().on<bool>('cast_play_pause').listen((_) {
      _settleSeekForManualToggle(); // la pausa remota gana a un seek local pendiente
      _player.playOrPause();
      // The phone toggled play/pause: reveal the info bar so the TV viewer sees
      // the title + progress react to the remote press.
      _revealInfoBar();
    });

    // External subtitle from a URL (.srt/.ass/.vtt).
    _externalSubUriSubscription = EventBus()
        .on<String>('load_external_subtitle_uri')
        .listen((uri) {
          if (uri.trim().isEmpty) return;
          _player.setSubtitleTrack(SubtitleTrack.uri(uri.trim()));
        });

    // External subtitle from raw file contents.
    _externalSubDataSubscription = EventBus()
        .on<String>('load_external_subtitle_data')
        .listen((data) {
          if (data.isEmpty) return;
          _player.setSubtitleTrack(SubtitleTrack.data(data));
        });

    // Persist + apply playback speed changes.
    _playbackSpeedSubscription = EventBus()
        .on<double>('playback_speed_changed')
        .listen((rate) async {
          await _player.setRate(rate);
          await UserPreferences.setPlaybackSpeed(rate);
        });

    // Set only after all synchronous init succeeded: if the Player constructor
    // (or anything above) threw, the State never mounts and dispose never runs,
    // so leaving this false keeps the background refresh from being wedged off
    // for the rest of the session. dispose() always clears it.
    PlayerState.isPlayerActive = true;

    _castGate = Completer<bool>();
    _initializePlayer();
  }

  @override
  void dispose() {
    PlayerState.isPlayerActive = false;
    // Cancel timer and save watch history one last time before disposing
    _watchHistoryTimer?.cancel();
    _stallTimer?.cancel();
    _channelDebounceTimer?.cancel();
    _okHoldTimer?.cancel();
    _okHintTimer?.cancel();
    if (_pendingWatchDuration != null) {
      // Use unawaited to save without blocking dispose. ignoreMounted lets the
      // final position flush even though the State is already unmounted here.
      _saveWatchHistory(ignoreMounted: true).catchError((e) {
        // Ignore errors during dispose
      });
    }

    unawaited(WakelockPlus.disable());
    _disposePlayer();
    _audioHandler.setPlayer(null);
    _audioHandler.stop();
    videoTrackSubscription.cancel();
    audioTrackSubscription.cancel();
    subtitleTrackSubscription.cancel();
    _externalSubUriSubscription?.cancel();
    _externalSubDataSubscription?.cancel();
    _playbackSpeedSubscription?.cancel();
    _castPlayPauseSubscription?.cancel();
    _seekHideTimer?.cancel();
    _seekCommitTimer?.cancel();
    _seekGraceTimer?.cancel();
    contentItemIndexChangedSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _errorHandler.reset();
    _cast?.removeListener(_onCastChanged);
    _castGateTimer?.cancel();
    _preBufferTimer?.cancel();
    _loadTicker?.cancel();
    _remoteFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    _pipWidthSubscription?.cancel();
    _pipHeightSubscription?.cancel();
    PipService.instance.isInPip.removeListener(_onPipModeChanged);
    // Best-effort: disarm auto-PiP when leaving the player so other screens
    // don't trigger it accidentally.
    unawaited(PipService.instance.setAutoEnter(false));
    _sleepTimerSubscription?.cancel();
    // Cancel any pending sleep timer so it doesn't fire while a different
    // screen is active.
    SleepTimerService.instance.cancel();
    _channelBufferSubscription?.cancel();
    _channelBuffer.dispose();
    _toggleChannelListSub?.cancel();
    _toggleVideoInfoSub?.cancel();
    _toggleVideoSettingsSub?.cancel();
    // Tear down any root-overlay player panel that's still open, so its static
    // OverlayEntry isn't left pointing at a now-defunct Overlay (which would
    // make the settings/info panel permanently un-openable). The widgets' own
    // static listeners handle the actual removal; our own listeners above are
    // already cancelled, and they no-op while unmounted anyway.
    EventBus().emit('toggle_video_info', false);
    EventBus().emit('toggle_video_settings', false);
    EventBus().emit('toggle_channel_list', false);
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    super.dispose();
  }

  /// Dispose the native player exactly once (lifecycle `detached` and the
  /// widget's own dispose() can both fire).
  Future<void> _disposePlayer() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    // Cubre el camino AppLifecycleState.detached (no pasa por State.dispose):
    // un seek diferido no debe dispararse sobre un player ya liberado.
    _seekCommitTimer?.cancel();
    _seekGraceTimer?.cancel();
    await _player.dispose();
  }

  void _jumpToChannel(int oneBasedIndex) {
    // A direct numeric jump overrides any in-flight channel-surf debounce.
    _channelDebounceTimer?.cancel();
    _pendingChannelIndex = null;
    if (_queue == null || _queue!.isEmpty) return;
    // Channels are 1-indexed in the UI but 0-indexed in the queue.
    final clamped = oneBasedIndex.clamp(1, _queue!.length);
    final newIndex = clamped - 1;
    if (newIndex == _currentItemIndex) return;
    EventBus().emit('player_content_item_index_changed', newIndex);
  }

  /// True when the queue has an episode after the current one to skip to.
  /// Never for live (a bare Media with no queue advance), never without a
  /// queue, and never on the last item. Single source of truth shared with the
  /// mobile [VideoNextEpisodeWidget] so both agree on when to show the control.
  bool get _hasNextEpisode => hasNextEpisode(
        contentType: contentItem.contentType,
        queue: _queue,
        currentIndex: _currentItemIndex,
      );

  /// Jump to the next queue item without waiting for the current one's credits.
  ///
  /// Advances through the EXACT same path the in-app episode picker uses: it
  /// emits `player_content_item_index_changed`, which the existing subscription
  /// turns into `_player.jump(index)` for non-live content (see the listener in
  /// initState). That jump drives media_kit's `stream.playlist` — the very same
  /// listener the end-of-file auto-advance fires — so `_currentItemIndex`,
  /// `contentItem`, `PlayerState` and the history save all update through one
  /// consistent code path, and the casting guard on that subscription is
  /// honoured too. No-op when there is no next episode.
  void _skipToNextEpisode() {
    if (!_hasNextEpisode) return;
    // El seek acumulado (si lo hay) se descarta centralizadamente en la
    // suscripción a 'player_content_item_index_changed' (rama no-live), que cubre
    // este salto y el resto de emisores.
    EventBus()
        .emit('player_content_item_index_changed', _currentItemIndex + 1);
  }

  /// Maps a [LogicalKeyboardKey] to its 0-9 digit value, including the
  /// number row (`digit0`-`digit9`) and numeric keypad (`numpad0`-`numpad9`).
  /// Returns null for any other key.
  int? _digitForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) return 0;
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) return 1;
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) return 2;
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) return 3;
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) return 4;
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) return 5;
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) return 6;
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) return 7;
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) return 8;
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) return 9;
    return null;
  }

  void _onPipModeChanged() {
    if (!mounted) return;
    // When entering PiP, force-hide overlays. Triggers a rebuild that
    // re-evaluates the conditional widgets in _buildPlayerContent.
    setState(() {
      if (PipService.instance.isInPip.value) {
        _showChannelList = false;
        PlayerState.showChannelList = false;
        PlayerState.showVideoInfo = false;
        PlayerState.showVideoSettings = false;
      }
    });
  }

  Future<void> _saveWatchHistory({bool ignoreMounted = false}) async {
    // In dispose the State is already unmounted, so allow an explicit
    // ignoreMounted to still flush the final position.
    if (_pendingWatchDuration == null || (!mounted && !ignoreMounted)) return;

    try {
      await watchHistoryService.saveWatchHistory(
        WatchHistory(
          playlistId: AppState.currentPlaylist!.id,
          contentType: contentItem.contentType,
          streamId: isXtreamCode
              ? contentItem.id
              : contentItem.m3uItem?.id ?? contentItem.id,
          lastWatched: DateTime.now(),
          title: contentItem.name,
          imagePath: contentItem.imagePath,
          totalDuration: _pendingTotalDuration,
          watchDuration: _pendingWatchDuration,
          seriesId: contentItem.seriesStream?.seriesId,
        ),
      );
      // Borrar-al-ver: si este contenido es una descarga offline y se alcanzó
      // el umbral de "visto" (política conservadora: requiere duración fiable),
      // liberar el archivo. No-op si no hay descarga con este contentId.
      final watched = _pendingWatchDuration;
      final total = _pendingTotalDuration;
      if (watched != null && total != null) {
        await DownloadService.instance
            .markWatchedAndMaybeDelete(contentItem.id, watched, total);
      }
      _pendingWatchDuration = null;
      _pendingTotalDuration = null;
      // Avisar que el historial cambió → "Continuar viendo" se refresca en cuanto
      // ves algo, sin depender de cambiar de pestaña.
      EventBus().emit('history_changed', null);
    } catch (e) {
      // Silently handle database errors to prevent crashes
      // The next save attempt will retry
      debugPrint('Error saving watch history: ${scrubCredentials(e)}');
    }
  }

  /// Reopen the current content. Live streams restart from the live edge;
  /// VOD/series resume from the last known position. Used by reconnect,
  /// error retry and the stall watchdog.
  Future<void> _reopenCurrent() async {
    if (_playerDisposed || contentItem.url.isEmpty) return;
    // Coexistencia con casting (política "casting manda"): mientras se castea, o
    // el usuario ya se comprometió a enviar a la TV, NUNCA reabrir el stream
    // local. Cierra TODOS los caminos de reopen a la vez (watchdog de carga,
    // handler de conectividad, watchdog de stall, error-handler, ext-heal) →
    // ninguno puede provocar doble reproducción móvil+TV. En la TV receptora
    // _castingController() es null y _castCommitted false, así que su reopen de
    // stall en vivo queda intacto.
    if (_castCommitted || _castingController() != null) return;
    // Live streams are not seekable: passing start:Duration.zero makes libmpv
    // attempt a seek-to-0 on reopen, which fires the non-fatal
    // "Cannot seek … --force-seekable=yes" error (triggered by the 15s stall
    // watchdog). Omit start entirely for live; VOD/series keep their resume.
    // VOD/series: reanudar desde la posición REAL del player (no
    // _pendingWatchDuration, que se pone a null tras cada guardado de historial
    // → reabría en 0 y "reiniciaba desde el principio"). Live no lleva start.
    final livePos = _player.state.position;
    final Duration? start = contentItem.contentType == ContentType.liveStream
        ? null
        : (livePos > Duration.zero
            ? livePos
            : (_pendingWatchDuration ?? Duration.zero));
    // Preserve a multi-item VOD queue: reopening a bare Media would collapse the
    // native Playlist to a single item and break jump/next for the rest of the
    // session. The current item's url is read live (it may have been healed).
    if (_queue != null &&
        _queue!.length > 1 &&
        contentItem.contentType != ContentType.liveStream) {
      final medias = [
        for (var i = 0; i < _queue!.length; i++)
          Media(i == _currentItemIndex ? contentItem.url : _queue![i].url,
              start: i == _currentItemIndex ? start : Duration.zero),
      ];
      await _player.open(Playlist(medias, index: _currentItemIndex),
          play: true);
    } else {
      await _player.open(Media(contentItem.url, start: start), play: true);
    }
  }

  /// If a VOD failed because its cached container extension is stale, reopen
  /// with the next candidate extension. Returns true if a retry was started, so
  /// the normal error handler stands down. Silent and capped
  /// ([_maxExtHealAttempts]); after that the friendly error screen shows.
  Future<bool> _tryHealExtension(String error) async {
    if (_playerDisposed || !mounted) return false;
    if (contentItem.contentType != ContentType.vod || !isXtreamCode) {
      return false;
    }
    // "failed to recognize file format" is what a wrong extension (HTML body)
    // yields; a genuine network failure says "Failed to open" and belongs to
    // the retry/backoff path, not here.
    final e = error.toLowerCase();
    if (!(e.contains('recognize') || e.contains('format'))) return false;
    if (_extHealAttempts >= _maxExtHealAttempts) return false;

    final current = _urlExtension(contentItem.url);
    if (current != null) _triedExtensions.add(current);
    String? next;
    for (final cand in kVodExtensionCandidates) {
      if (!_triedExtensions.contains(cand)) {
        next = cand;
        break;
      }
    }
    if (next == null) return false;

    _triedExtensions.add(next);
    _extHealAttempts++;
    _pendingHealExtension = next;
    final healed = swapUrlExtension(contentItem.url, next);
    contentItem.url = healed;
    // Mirror onto the queue slot: the playlist listener reassigns `contentItem`
    // from `_queue[index]` on every reopen, so the queue entry must carry the
    // healed url too or the fix would be lost on the next reopen.
    if (_queue != null &&
        _currentItemIndex >= 0 &&
        _currentItemIndex < _queue!.length) {
      _queue![_currentItemIndex].url = healed;
    }
    debugPrint('EXT-HEAL -> retrying with .$next (attempt $_extHealAttempts)');
    _errorHandler.reset();
    await _reopenCurrent();
    return true;
  }

  static String? _urlExtension(String url) {
    final q = url.indexOf('?');
    final base = q >= 0 ? url.substring(0, q) : url;
    final dot = base.lastIndexOf('.');
    final slash = base.lastIndexOf('/');
    return dot > slash ? base.substring(dot + 1).toLowerCase() : null;
  }

  void _resetHealStateIfContentChanged() {
    final id = contentItem.id.toString();
    if (id != _healContentId) {
      _healContentId = id;
      _triedExtensions.clear();
      _extHealAttempts = 0;
      _pendingHealExtension = null;
    }
  }

  /// User-triggered retry from the error screen.
  void _retryPlayback() {
    _errorHandler.reset();
    // Reiniciar el watchdog de carga para el nuevo intento.
    _loadClock
      ..reset()
      ..start();
    _loadTicker?.cancel();
    _loadTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !isLoading) {
        t.cancel();
        return;
      }
      setState(() {});
    });
    if (mounted) {
      setState(() {
        hasError = false;
        isLoading = true;
      });
    }
    _reopenCurrent().whenComplete(() {
      _loadTicker?.cancel();
      _loadClock.stop();
      if (mounted) setState(() => isLoading = false);
    });
  }

  /// Build the VideoController per the user's decoder preference.
  /// - 'auto' (default): GPU render + auto-safe HW decode (mediacodec-copy). Most
  ///   compatible; the copy-back can drop frames on weak boxes.
  /// - 'hw_direct': zero-copy decode straight to a native Surface (smoothest on
  ///   Amlogic TV boxes). EXPERIMENTAL — can green/black-screen on some decoders;
  ///   the user can switch back in Settings if a stream fails.
  /// - 'software': no HW decode (last resort for odd codecs).
  VideoController _createVideoController(String mode) {
    switch (mode) {
      case 'hw_direct':
        return VideoController(
          _player,
          configuration: const VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            androidAttachSurfaceAfterVideoParameters: false,
          ),
        );
      case 'software':
        return VideoController(
          _player,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: false,
          ),
        );
      default:
        return VideoController(_player);
    }
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;

    // Arranca el watchdog de carga: refresca el indicador cada segundo mientras
    // dure "Preparando…", para mostrar el tiempo transcurrido y, pasado un
    // umbral, ofrecer Reintentar si la apertura se cuelga.
    _autoRetried = false;
    _loadClock
      ..reset()
      ..start();
    _loadTicker?.cancel();
    _loadTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !isLoading) {
        t.cancel();
        return;
      }
      // Auto-reintento UNA vez: si el PRIMER intento sigue en "Preparando…" tras
      // 8s (típico en algunas cajas de TV donde el primer arranque se atasca), se
      // reintenta solo — como el usuario tenía que pulsar Reintentar a mano, que
      // sí funciona. Luego, si vuelve a colgarse, aparece el botón manual a los 12s.
      if (!_autoRetried && _loadClock.elapsed >= const Duration(seconds: 8)) {
        _autoRetried = true;
        t.cancel();
        _retryPlayback();
        return;
      }
      setState(() {});
    });

    // Cada await de la preparación va con timeout: en algunas cajas de TV uno
    // de estos se colgaba en el PRIMER intento (sin lanzar error) y dejaba el
    // arranque en "Preparando…" para siempre; el reintento funcionaba porque se
    // los salta. Con timeout, si uno tarda, se usa un valor por defecto y el
    // arranque continúa igual (auto-recuperación del primer intento).
    PlayerState.subtitleConfiguration = await getSubtitleConfiguration()
        .timeout(const Duration(seconds: 6),
            onTimeout: () => const SubtitleViewConfiguration());

    PlayerState.backgroundPlay = await UserPreferences.getBackgroundPlay()
        .timeout(const Duration(seconds: 4), onTimeout: () => true);
    _audioHandler.setPlayer(_player);
    final decoderMode = await UserPreferences.getVideoDecoder()
        .timeout(const Duration(seconds: 4), onTimeout: () => 'auto');
    _videoController = _createVideoController(decoderMode);

    // Coexistencia móvil↔TV — política "el casting manda": si YA se está
    // casteando, NO reproducir aquí (evita doble reproducción y controles
    // desincronizados). Reenviar el título a la TV reutilizando la sesión y
    // volver a la navegación; el mini-control refleja el nuevo título.
    final castingNow = _castingController();
    if (castingNow != null) {
      // Matar el watchdog de carga antes del await del recast: si no, su
      // auto-reintento a 8s reabriría el stream LOCAL mientras se reenvía a la TV.
      _loadTicker?.cancel();
      _loadClock.stop();
      await _recastToTv(castingNow);
      return;
    }

    // Gate de casting (solo móvil): ofrecer enviar a la TV ANTES de cargar el
    // stream aquí (para no gastar datos). Si se elige enviar, no abrimos local.
    if (_needsCastGate()) {
      _castGateActive = true;
      if (mounted) setState(() {});
      _startCastGateCountdown();
      if (!await _castGate!.future) return;
    }

    // Picture-in-Picture: arm auto-enter on user-leave-hint and keep the
    // native side in sync with the video aspect ratio.
    unawaited(_setupPip());
    PipService.instance.isInPip.addListener(_onPipModeChanged);

    // Sleep timer: pause playback when the countdown reaches zero.
    _sleepTimerSubscription =
        SleepTimerService.instance.onFire.listen((_) {
      if (_player.state.playing) _player.pause();
    });

    // Channel-number entry (TV remote): jump to channel queue[N-1] on commit.
    _channelBufferSubscription = _channelBuffer.onCommit.listen(_jumpToChannel);

    var watchHistory = await watchHistoryService
        .getWatchHistory(
          AppState.currentPlaylist!.id,
          isXtreamCode
              ? contentItem.id
              : contentItem.m3uItem?.id ?? contentItem.id,
        )
        .timeout(const Duration(seconds: 4), onTimeout: () => null);

    List<MediaItem> mediaItems = [];
    var currentItemIndex = 0;

    if (_queue != null) {
      for (int i = 0; i < _queue!.length; i++) {
        final item = _queue![i];
        final itemWatchHistory = await watchHistoryService
            .getWatchHistory(
              AppState.currentPlaylist!.id,
              isXtreamCode ? item.id : item.m3uItem?.id ?? item.id,
            )
            .timeout(const Duration(seconds: 4), onTimeout: () => null);

        mediaItems.add(
          MediaItem(
            id: item.id.toString(),
            title: item.name,
            artist: _getContentTypeDisplayName(),
            album: AppState.currentPlaylist?.name ?? '',
            artUri: item.imagePath.isNotEmpty
                ? Uri.tryParse(item.imagePath)
                : null,
            playable: true,
            extras: {
              'url': item.url,
              'startPosition':
                  itemWatchHistory?.watchDuration?.inMilliseconds ?? 0,
            },
          ),
        );

        if (item.id == contentItem.id) {
          currentItemIndex = i;
          _currentItemIndex = i;

          if (contentItem.contentType == ContentType.liveStream) {
            currentItemIndex = 0;
            _currentItemIndex = 0;
            contentItem = item;

            mediaItems.add(
              MediaItem(
                id: item.id.toString(),
                title: item.name,
                artist: _getContentTypeDisplayName(),
                album: AppState.currentPlaylist?.name ?? '',
                artUri: item.imagePath.isNotEmpty
                    ? Uri.tryParse(item.imagePath)
                    : null,
                playable: true,
                extras: {'url': item.url, 'startPosition': 0},
              ),
            );

            EventBus().emit('player_content_item', item);
            EventBus().emit('player_content_item_index', i);
          }
        }
      }

      _loadStage = 'audio';
      await _audioHandler
          .setQueue(mediaItems, initialIndex: currentItemIndex)
          .timeout(const Duration(seconds: 8), onTimeout: () {});

      _loadStage = 'open';
      if (contentItem.contentType != ContentType.liveStream) {
        var playlist = mediaItems.map((mediaItem) {
          final url = mediaItem.extras!['url'] as String;
          final startMs = mediaItem.extras!['startPosition'] as int;
          return Media(url, start: Duration(milliseconds: startMs));
        }).toList();

        await _player.open(
          Playlist(playlist, index: currentItemIndex),
          play: true,
        );
      } else {
        await _player.open(Media(contentItem.url));
      }
      _loadStage = 'ready';
    } else {
      final mediaItem = MediaItem(
        id: contentItem.id.toString(),
        title: contentItem.name,
        artist: _getContentTypeDisplayName(),
        artUri: contentItem.imagePath.isNotEmpty
            ? Uri.tryParse(contentItem.imagePath)
            : null,
        extras: {
          'url': contentItem.url,
          'startPosition': watchHistory?.watchDuration?.inMilliseconds ?? 0,
        },
      );

      // if (contentItem.contentType == ContentType.liveStream) {
      //   liveStreamContentItem = contentItem;
      // }

      _loadStage = 'audio';
      await _audioHandler
          .setQueue([mediaItem]).timeout(const Duration(seconds: 8),
              onTimeout: () {});

      _loadStage = 'open';
      await _player.open(
        Playlist([
          Media(
            contentItem.url,
            start: watchHistory?.watchDuration ?? Duration(),
          ),
        ]),
        play: true,
      );
      _loadStage = 'ready';
    }

    // Pre-buffer: pausa el video y llena caché; muestra velocidad/buffer/estado
    // y reproduce al haber colchón suficiente (o al forzar). Cubre además el
    // caso de cargas infinitas / errores de conexión con estado visible.
    _startPreBuffer();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      bool hasConnection = results.any(
        (connectivity) =>
            connectivity == ConnectivityResult.mobile ||
            connectivity == ConnectivityResult.wifi ||
            connectivity == ConnectivityResult.ethernet,
      );

      if (_isFirstCheck) {
        // Connectivity is auxiliary (reconnect UX). Some platforms — observed on
        // the Android TV emulator image — can make checkConnectivity() throw a
        // plugin cast error; that must never abort player init, so on failure we
        // assume connected and carry on.
        try {
          final currentConnectivity = await Connectivity().checkConnectivity();
          hasConnection = currentConnectivity.any(
            (connectivity) =>
                connectivity == ConnectivityResult.mobile ||
                connectivity == ConnectivityResult.wifi ||
                connectivity == ConnectivityResult.ethernet,
          );
        } catch (e) {
          debugPrint('checkConnectivity failed, assuming online: $e');
          hasConnection = true;
        }
        _isFirstCheck = false;
      }

      if (hasConnection) {
        if (_wasDisconnected && contentItem.url.isNotEmpty) {
          try {
            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Online", style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.green,
              ),
            );

            // Reabrir SOLO si la reproducción se rompió de verdad (parada o
            // atascada en buffering): un blip breve de red que no cortó el
            // stream no debe forzar un reopen (rebuffer/reinicio sin motivo).
            if (!_player.state.playing || _player.state.buffering) {
              // Live vuelve al borde; VOD/series reanudan en su posición real.
              await _reopenCurrent();
            }
          } catch (e) {
            debugPrint('Error reopening media after reconnect: ${scrubCredentials(e)}');
          }
        }
        _wasDisconnected = false;
      } else {
        _wasDisconnected = true;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "No Connection",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    _player.stream.tracks.listen((event) async {
      if (!mounted) return;

      PlayerState.videos = event.video;
      PlayerState.audios = event.audio;
      PlayerState.subtitles = event.subtitle;

      EventBus().emit('player_tracks', event);

      await _player.setVideoTrack(
        VideoTrack(await UserPreferences.getVideoTrack(), null, null),
      );

      var selectedAudioLanguage = await UserPreferences.getAudioTrack();
      var possibleAudioTrack = event.audio.firstWhere(
        (x) => _langMatches(x.language, x.title, selectedAudioLanguage),
        orElse: AudioTrack.auto,
      );

      await _player.setAudioTrack(possibleAudioTrack);

      var selectedSubtitleLanguage = await UserPreferences.getSubtitleTrack();
      final SubtitleTrack possibleSubtitleLanguage;
      if (selectedSubtitleLanguage == 'off') {
        // Preferred: subtitles off by default.
        possibleSubtitleLanguage = SubtitleTrack.no();
      } else {
        possibleSubtitleLanguage = event.subtitle.firstWhere(
          (x) => _langMatches(x.language, x.title, selectedSubtitleLanguage),
          orElse: SubtitleTrack.auto,
        );
      }

      await _player.setSubtitleTrack(possibleSubtitleLanguage);

      // Apply the remembered playback speed.
      final rate = await UserPreferences.getPlaybackSpeed();
      if (rate > 0) await _player.setRate(rate);
    });

    _player.stream.track.listen((event) async {
      if (!mounted) return;

      PlayerState.selectedVideo = _player.state.track.video;
      PlayerState.selectedAudio = _player.state.track.audio;
      PlayerState.selectedSubtitle = _player.state.track.subtitle;

      // Track değişikliğini bildir
      EventBus().emit('player_track_changed', null);

      var volume = await UserPreferences.getVolume();
      await _player.setVolume(volume);
    });

    _player.stream.volume.listen((event) async {
      await UserPreferences.setVolume(event);
    });

    _player.stream.position.listen((position) {
      // Keep the resume position fresh, but never index past the current
      // playlist length (guards against RangeError during open/reset).
      final medias = _player.state.playlist.medias;
      if (currentItemIndex >= 0 && currentItemIndex < medias.length) {
        medias[currentItemIndex] = Media(contentItem.url, start: position);
      }

      // Debounce: Save watch history every 5 seconds instead of on every position update
      _pendingWatchDuration = position;
      _pendingTotalDuration = _player.state.duration;

      // Puente de casting: solo la TV receptora reenvía su posición al móvil
      // para alimentar "continuar viendo". Emitir solo en TV evita trabajo por
      // tick en el móvil, donde nadie consume el evento.
      if (ResponsiveHelper.isTelevisionDevice) {
        EventBus().emit('cast_player_position', {
          'pos': position.inMilliseconds,
          'dur': _player.state.duration.inMilliseconds,
        });
      }

      _watchHistoryTimer?.cancel();
      _watchHistoryTimer = Timer(const Duration(seconds: 5), () {
        _saveWatchHistory();
      });
    });

    // Keep the screen on while actually playing; release it on pause/stop so
    // we don't hold the wakelock in the background.
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
        // Resuming hides the rich pause panel.
        if (_showPausePanel && mounted) {
          // If the D-pad ring was on the "Siguiente episodio" button, its node
          // is about to unmount — hand focus back to the player node first so
          // key handling never lands on a stale/scope node.
          if (_nextEpisodeFocusNode.hasFocus) {
            _remoteFocusNode.requestFocus();
          }
          setState(() => _showPausePanel = false);
        }
        // A heal that reached "playing" is confirmed good: persist the winning
        // extension so future plays of this title skip the retry entirely.
        final healed = _pendingHealExtension;
        if (healed != null && isXtreamCode) {
          _pendingHealExtension = null;
          final pid = AppState.currentPlaylist?.id;
          if (pid != null) {
            unawaited(_database.updateVodStreamContainerExtension(
                contentItem.id.toString(), pid, healed));
          }
        }
      } else {
        WakelockPlus.disable();
        // Paused on the TV (cast receiver): reveal the rich info panel (title +
        // synopsis + cast). Gated to the TV, and only once the stream is really
        // up (not during load/pre-buffer/error) so it never covers the loading
        // flow. Degrades to just the title when TMDb is unconfigured/no match.
        if (ResponsiveHelper.isTelevisionDevice &&
            mounted &&
            !isLoading &&
            !_preBuffering &&
            !hasError &&
            // No durante un seek: el 'playing=false' es el re-buffer transitorio
            // del salto (o la acumulación en curso), no una pausa del usuario.
            !_seekInProgress &&
            _pendingSeekTarget == null &&
            // No al FINAL del archivo: al completar un episodio, 'playing' pasa a
            // false justo antes del swap al siguiente → el panel parpadearía.
            !_player.state.completed &&
            !_showPausePanel) {
          setState(() => _showPausePanel = true);
        }
      }
    });

    // Live-stream stall watchdog: a frozen live source (server stops sending,
    // infinite buffering) emits no error and never completes, so nothing else
    // recovers it. If we stay buffering for 15s on a live stream, reopen it.
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      _stallTimer?.cancel();
      if (buffering &&
          contentItem.contentType == ContentType.liveStream &&
          contentItem.url.isNotEmpty) {
        _stallTimer = Timer(const Duration(seconds: 15), () {
          if (!mounted || _playerDisposed) return;
          if (_player.state.buffering) {
            _reopenCurrent();
          }
        });
      }
    });

    _player.stream.error.listen((error) async {
      debugPrint('PLAYER ERROR -> ${scrubCredentials(error)}');
      // Try to self-heal a stale container extension before surfacing anything.
      if (await _tryHealExtension(error)) return;
      _errorHandler.handleError(
        error,
        () async {
          // Retry: reopen current content (VOD/series resume from position).
          await _reopenCurrent();
        },
        (message) {
          // Retries exhausted / non-recoverable: show a real error screen with
          // a Retry button instead of a transient SnackBar over a black frame.
          if (!mounted) return;
          setState(() {
            hasError = true;
            // Belt-and-braces: PlayerErrorHandler already scrubs, but this
            // string goes straight to a full-screen Text().
            errorMessage = scrubCredentials(message);
          });
        },
        isLive: contentItem.contentType == ContentType.liveStream,
      );
    });

    _player.stream.playlist.listen((playlist) {
      if (!mounted) return;

      if (contentItem.contentType == ContentType.liveStream) {
        return;
      }

      // Cambió el episodio (salto manual O auto-avance nativo de EOF): invalidar
      // cualquier seek acumulado, cuya posición era del episodio anterior.
      _cancelPendingSeek();

      _currentItemIndex = playlist.index;
      currentItemIndex = _currentItemIndex;
      contentItem = _queue?[playlist.index] ?? widget.contentItem;
      // Fresh item → fresh extension-heal budget (no-op on a heal reopen, which
      // keeps the same id).
      _resetHealStateIfContentChanged();

      // --- INSERTION 2: QUEUE CHANGE SETTER ---
      PlayerState.currentContent = contentItem;
      PlayerState.currentIndex = _currentItemIndex;
      // ----------------------------------------

      PlayerState.title = contentItem.name;
      EventBus().emit('player_content_item', contentItem);
      EventBus().emit('player_content_item_index', playlist.index);

      // Kanal listesi açıksa güncelle
      if (_showChannelList && mounted) {
        setState(() {});
      }
    });

    _player.stream.completed.listen((completed) async {
      if (contentItem.contentType == ContentType.liveStream) {
        await _player.open(Media(contentItem.url));
        return;
      }
      // Fin de un VOD/serie EN LA TV (receptor de casting): avisar para que el
      // móvil auto-avance al siguiente episodio de la cola. Solo la TV reenvía
      // (el móvil no consume este evento). El host de casting lo traduce a
      // MsgType.completed; si no hay siguiente, la TV se queda en el fin.
      if (completed && ResponsiveHelper.isTelevisionDevice) {
        EventBus().emit('cast_player_completed', contentItem.id.toString());
      }
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) async {
          // Casting activo: el zap lo gobierna el CastSenderController (manda el
          // comando a la TV). NO revivir el reproductor local aquí — abriría un
          // stream con audio en el móvil mientras la TV reproduce (doble-play).
          if (_castCommitted || _castingController() != null) return;
          if (contentItem.contentType == ContentType.liveStream) {
            // Queue'yu PlayerState'ten al (kategori değiştiğinde güncellenmiş olabilir)
            final updatedQueue = PlayerState.queue ?? _queue;
            if (updatedQueue == null || index >= updatedQueue.length) return;

            final item = updatedQueue[index];
            // Capture the channel we're leaving (by ID, before reassignment) for
            // "last channel" recall — robust to the queue changing underneath.
            final leavingId = contentItem.id.toString();
            _previousChannelId = recallIdAfterSwitch(
                _previousChannelId, leavingId, item.id.toString());
            contentItem = item;
            _queue = updatedQueue; // Queue'yu güncelle

            // --- INSERTION 3: EXTERNAL CHANGE SETTER ---
            PlayerState.currentContent = contentItem;
            PlayerState.currentIndex = index;
            PlayerState.title = item.name;
            _currentItemIndex = index;
            // -------------------------------------------

            await _player.open(Playlist([Media(item.url)]), play: true);
            EventBus().emit('player_content_item', item);
            EventBus().emit('player_content_item_index', index);
            _errorHandler.reset();

            // Kanal listesi açıksa güncelle
            if (_showChannelList && mounted) {
              setState(() {});
            }
          } else {
            // Cambiar de título (serie/VOD) invalida cualquier seek acumulado:
            // su posición pertenece al episodio anterior. Centralizado aquí para
            // cubrir TODOS los emisores del evento (botón siguiente, selector de
            // episodios, salto por número), no solo uno.
            _cancelPendingSeek();
            _player.jump(index);
          }
        });

    // Kanal listesi göster/gizle event'i (stored so it can be cancelled).
    _toggleChannelListSub =
        EventBus().on<bool>('toggle_channel_list').listen((bool show) {
      if (mounted) {
        setState(() {
          _showChannelList = show;
          PlayerState.showChannelList = show;
        });
        if (show) _loadFavoriteChannels(); // refresh favourites-first ordering
      }
    });

    // Video bilgisi göster/gizle event'i
    _toggleVideoInfoSub =
        EventBus().on<bool>('toggle_video_info').listen((bool show) {
      if (mounted) {
        setState(() {
          PlayerState.showVideoInfo = show;
        });
      }
    });

    // Video ayarları göster/gizle event'i
    _toggleVideoSettingsSub =
        EventBus().on<bool>('toggle_video_settings').listen((bool show) {
      if (mounted) {
        setState(() {
          PlayerState.showVideoSettings = show;
        });
      }
    });

    _loadTicker?.cancel();
    _loadClock.stop();
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
    unawaited(_maybeShowOkHint());
  }

  /// On TV, briefly teach the long-press-OK gesture (the route to audio /
  /// subtitles) the first few times the player is opened, then stop nagging.
  Future<void> _maybeShowOkHint() async {
    if (!mounted || !ResponsiveHelper.isDesktopOrTV(context)) return;
    final shown = await UserPreferences.getOkHintShownCount();
    if (shown >= 4) return;
    await UserPreferences.setOkHintShownCount(shown + 1);
    if (!mounted) return;
    setState(() => _showOkHint = true);
    _okHintTimer?.cancel();
    _okHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showOkHint = false);
    });
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        await _disposePlayer();
        _audioHandler.setPlayer(null);
        await _audioHandler.stop();
        break;
      default:
        break;
    }
  }

  // Tolerant language match so a saved preference like "spa" picks up tracks
  // labelled spa / es / spanish / castellano / latino, etc.
  static const Map<String, List<String>> _langSynonyms = {
    'spa': ['spa', 'es', 'esp', 'spanish', 'castellano', 'español', 'lat', 'latino'],
    'eng': ['eng', 'en', 'english', 'ingles', 'inglés'],
    'por': ['por', 'pt', 'portugu'],
    'fra': ['fra', 'fre', 'fr', 'french', 'franc'],
    'ita': ['ita', 'it', 'italian'],
    'deu': ['deu', 'ger', 'de', 'german', 'aleman'],
  };

  bool _langMatches(String? lang, String? title, String pref) {
    if (pref == 'auto' || pref.isEmpty) return false;
    final hay = '${lang ?? ''} ${title ?? ''}'.toLowerCase();
    final syns = _langSynonyms[pref] ?? [pref.toLowerCase()];
    return syns.any((s) => hay.contains(s));
  }

  /// Tune libmpv (via media_kit) for smooth IPTV playback on low-power Android
  /// TV boxes (e.g. Amlogic Mi Box). NOTE: `hwdec` is intentionally NOT set here
  /// — the AndroidVideoController fixes it to `auto-safe` AFTER this runs, so a
  /// value here would be overwritten. HW decode is already active via that path.
  Future<void> _tuneForPerformance() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final isLive =
          widget.contentItem.contentType == ContentType.liveStream;
      try {
        await platform.setProperty('cache', 'yes');
        // Root cause of the stutter on TV boxes: media_kit defaults to caching
        // to DISK; on slow eMMC/flash that causes periodic I/O stalls. Cache in
        // RAM instead.
        await platform.setProperty('cache-on-disk', 'no');
        // Más bytes de buffer para absorber señal débil (el readahead grande de
        // abajo necesita headroom de bytes o topa antes de llenar los segundos).
        await platform.setProperty('demuxer-max-bytes', '128MiB');
        await platform.setProperty('demuxer-max-back-bytes', '32MiB');
        // Colchón de lectura anticipada. Más alto = más resistente a cortes de
        // señal. En vivo se subió (era 5s) para señal débil, a costa de un poco
        // más de latencia al cambiar de canal.
        await platform.setProperty(
            'demuxer-readahead-secs', isLive ? '15' : '20');
        // Don't freeze on brief IPTV network hiccups.
        await platform.setProperty('cache-pause', 'no');
        // AUTO-RECONEXIÓN de red (ffmpeg): si el stream HTTP se corta un instante
        // (señal débil), reconecta solo en vez de quedarse entrecortado o parar
        // (evita además el reopen que reinicia). Clave para conexiones malas.
        await platform.setProperty(
            'demuxer-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
                'reconnect_delay_max=5');
      } catch (_) {
        // Best-effort; defaults are fine if a property is unsupported.
      }
    }
  }

  void _showSeekFeedback(Duration pos, Duration dur,
      {Duration hold = const Duration(milliseconds: 1500)}) {
    _seekHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _seekPos = pos;
        _seekDur = dur;
      });
    }
    _seekHideTimer = Timer(hold, () {
      if (mounted) setState(() => _seekPos = null);
    });
  }

  /// Avance/retroceso ACELERADO en la TV (solo VOD). Cada pulsación consecutiva
  /// en la misma dirección crece el paso (15s → 1min → 3min → 5min) y ACUMULA
  /// sobre un objetivo pendiente que se muestra en la barra; el seek real ocurre
  /// UNA vez ~350ms tras la última pulsación. Ventajas: (1) para contenido largo
  /// se recorre rápido manteniendo pulsado mientras se ve el tiempo proyectado;
  /// (2) no hay un re-buffer por cada paso (antes cada pulsación hacía un seek);
  /// (3) al comprometer se reanuda con play() — algunas cajas de TV dejan el
  /// stream buffering-sin-reanudar tras un seek (parecía pausado con spinner y
  /// exigía un OK). Cambiar de dirección o una pausa larga reinicia la racha al
  /// paso fino.
  void _seekBy(bool forward) {
    final dur = _player.state.duration;
    if (dur <= Duration.zero) return; // sin duración fiable (no es VOD)
    final now = DateTime.now();
    final gap =
        _lastSeekPressAt == null ? null : now.difference(_lastSeekPressAt!);
    _lastSeekPressAt = now;
    if (_pendingSeekTarget == null ||
        _seekForward != forward ||
        (gap != null && gap > const Duration(milliseconds: 900))) {
      _seekStreak = 0;
      _seekForward = forward;
      _seekWasPlaying = _player.state.playing || _seekInProgress;
      _pendingSeekTarget = _player.state.position;
    }
    _seekStreak++;
    final step = _seekStepFor(_seekStreak);
    var target = _pendingSeekTarget! + (forward ? step : -step);
    // Tope 1s antes del final: evita seek EXACTO a EOF (que carreraría con el
    // evento `completed`/auto-avance de serie) y deja algo que reproducir.
    final cap =
        dur > const Duration(seconds: 1) ? dur - const Duration(seconds: 1) : dur;
    if (target > cap) target = cap;
    if (target < Duration.zero) target = Duration.zero;
    _pendingSeekTarget = target;
    _showSeekFeedback(target, dur); // la barra muestra el objetivo proyectado
    _seekCommitTimer?.cancel();
    _seekCommitTimer =
        Timer(const Duration(milliseconds: 350), _commitPendingSeek);
  }

  /// Paso incremental por racha: arranca fino (15s) y escala a minutos.
  Duration _seekStepFor(int streak) {
    if (streak <= 2) return const Duration(seconds: 15);
    if (streak <= 4) return const Duration(minutes: 1);
    if (streak <= 6) return const Duration(minutes: 3);
    return const Duration(minutes: 5);
  }

  void _commitPendingSeek() => _commitSeek(resume: _seekWasPlaying);

  /// Ejecuta el seek acumulado una sola vez. [resume]=true reanuda con play()
  /// (arregla el "buffering sin reanudar" de algunas cajas de TV tras un seek);
  /// se pasa false cuando el usuario tomó control explícito de la pausa alrededor
  /// del seek, para NO revertir su pausa.
  void _commitSeek({required bool resume}) {
    final target = _pendingSeekTarget;
    _seekCommitTimer?.cancel();
    _seekCommitTimer = null;
    _pendingSeekTarget = null;
    _seekStreak = 0;
    if (target == null) return;
    // El timer pudo sobrevivir a un dispose (p.ej. AppLifecycleState.detached):
    // no tocar un player liberado.
    if (!mounted || _playerDisposed) return;
    _player.seek(target);
    if (resume) {
      _player.play();
      // Gracia: ignorar el 'playing=false' del re-buffer para no levantar el
      // panel de pausa mientras el stream se recompone.
      _seekInProgress = true;
      _seekGraceTimer?.cancel();
      _seekGraceTimer = Timer(const Duration(milliseconds: 1200), () {
        _seekInProgress = false;
      });
    } else {
      _seekInProgress = false;
      _seekGraceTimer?.cancel();
    }
  }

  /// El usuario pulsa play/pausa alrededor de un seek: cerrar el seek pendiente
  /// SIN reanudar y soltar la supresión del panel de pausa, para que su toggle
  /// mande sobre la reanudación automática del commit.
  void _settleSeekForManualToggle() {
    if (_pendingSeekTarget == null && !_seekInProgress) return;
    _seekWasPlaying = false;
    _seekGraceTimer?.cancel();
    _seekInProgress = false;
    if (_pendingSeekTarget != null) _commitSeek(resume: false);
  }

  /// Descarta un seek acumulado SIN ejecutarlo ni tocar el player. Para cuando la
  /// posición pendiente deja de tener sentido (p.ej. al saltar de episodio).
  void _cancelPendingSeek() {
    _seekCommitTimer?.cancel();
    _seekCommitTimer = null;
    _seekGraceTimer?.cancel();
    _pendingSeekTarget = null;
    _seekStreak = 0;
    _seekInProgress = false;
    if (mounted) setState(() => _seekPos = null); // oculta la barra del objetivo
  }

  /// Short OK during playback. First press reveals the playback info bar (the
  /// TITLE, and for seekable content the progress + current/total time) without
  /// pausing — so the viewer can see WHAT is playing and how far in. Pressing OK
  /// again while the bar is showing toggles play/pause. Live has no duration, so
  /// the bar shows just the title; a second OK still toggles.
  void _handleOkTap() {
    // OK alrededor de un seek: cerrar el seek pendiente y que ESTE OK gobierne
    // play/pausa (la reanudación automática del commit no debe revertirlo). Deja
    // el estado estable para que un 'playing=false' de pausa levante el panel.
    if (_pendingSeekTarget != null || _seekInProgress) {
      _settleSeekForManualToggle();
      _player.playOrPause();
      _revealInfoBar(hold: const Duration(seconds: 4));
      return;
    }
    // Paused (rich panel up, or otherwise not playing): OK resumes directly —
    // don't force a second press.
    if (_showPausePanel || !_player.state.playing) {
      _player.playOrPause();
      return;
    }
    // Playing: first OK reveals the info bar (title + progress), second pauses.
    if (_seekPos == null) {
      _revealInfoBar(hold: const Duration(seconds: 4));
      return;
    }
    _player.playOrPause();
  }

  /// Reveal the transient playback info bar (title + progress/time), reusing the
  /// seek-feedback surface so pause/play and OK share one overlay. Works for
  /// live too (dur == 0 → the bar shows title only).
  void _revealInfoBar({Duration hold = const Duration(seconds: 3)}) {
    _showSeekFeedback(_player.state.position, _player.state.duration, hold: hold);
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _buildSeekOverlay() {
    final pos = _seekPos, dur = _seekDur;
    // The rich pause panel already carries the title + progress, so suppress the
    // thin bar underneath it to avoid a double display.
    if (pos == null || _showPausePanel) {
      return const SizedBox.shrink();
    }
    final hasDur = dur != null && dur.inMilliseconds > 0;
    final title = PlayerState.currentContent?.name ?? contentItem.name;
    final progress =
        hasDur ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 40,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TITLE — the whole point of the info bar: what is playing.
              if (title.isNotEmpty)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppThemes.tenFoot(context, 15),
                  ),
                ),
              if (hasDur) ...[
                if (title.isNotEmpty) const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_fmtDur(pos),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: AppThemes.tenFoot(context, 12))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Color(0xFFC75F41)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_fmtDur(dur),
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: AppThemes.tenFoot(context, 12))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setupPip() async {
    // PiP is a phone feature. On Android TV / large screens the system PiP
    // transition can hang the device, so never arm auto-PiP there.
    if (!mounted) return;
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      await PipService.instance.setAutoEnter(false);
      return;
    }
    final pip = PipService.instance;
    if (!await pip.isAvailable()) return;
    if (!mounted) return;

    final autoPip = await UserPreferences.getAutoPipOnHome();
    await pip.setAutoEnter(autoPip);

    _pipWidthSubscription = _player.stream.width.listen((w) {
      if (w == null || w <= 0) return;
      _lastVideoWidth = w;
      _pushAspect();
    });
    _pipHeightSubscription = _player.stream.height.listen((h) {
      if (h == null || h <= 0) return;
      _lastVideoHeight = h;
      _pushAspect();
    });
  }

  void _pushAspect() {
    final w = _lastVideoWidth, h = _lastVideoHeight;
    if (w == null || h == null) return;
    PipService.instance.updateAspectRatio(width: w, height: h);
  }

  void _changeChannel(int direction) {
    if (_queue == null || _queue!.length <= 1) return;

    // Coalesce rapid presses: advance a pending index immediately but only
    // reopen the stream ~350ms after the user stops, instead of reopening on
    // every key repeat (which caused flicker/reconnect storms).
    final base = _pendingChannelIndex ?? _currentItemIndex;
    final newIndex = base + direction;
    if (newIndex < 0 || newIndex >= _queue!.length) return;
    _pendingChannelIndex = newIndex;

    _channelDebounceTimer?.cancel();
    _channelDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      final target = _pendingChannelIndex;
      _pendingChannelIndex = null;
      if (target != null) {
        EventBus().emit('player_content_item_index_changed', target);
      }
    });
  }

  // Android TV / D-pad / keyboard handler. Returns handled when the key is
  // consumed so it does not propagate to media_kit's own bindings.
  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isOkKey = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final anyOverlayOpen = _showChannelList ||
        PlayerState.showVideoSettings ||
        PlayerState.showVideoInfo;

    // TV pause panel: while the focus ring sits on the "Siguiente episodio"
    // button, OK skips to the next episode instead of resuming. Consume every
    // phase (down/repeat/up) so the generic OK handler below never also fires,
    // and act on the up so a single press equals one skip.
    if (isOkKey &&
        _showPausePanel &&
        _hasNextEpisode &&
        _nextEpisodeFocusNode.hasFocus &&
        !anyOverlayOpen &&
        !_channelBuffer.isActive) {
      if (event is KeyUpEvent) _skipToNextEpisode();
      return KeyEventResult.handled;
    }

    // OK/center: SHORT press = reveal the progress/time info bar first, then
    // pause on a second press (see _handleOkTap); LONG press (≈450ms) = open the
    // player options panel (audio/subtitles). On a basic Android TV remote this is the
    // only route to audio/subtitle selection for LIVE and queued content, where
    // the Menu key is already taken by the channel list. Skipped while an overlay
    // is open (OK acts on it) or while typing a channel number (OK commits it).
    if (isOkKey && !anyOverlayOpen && !_channelBuffer.isActive) {
      if (event is KeyDownEvent) {
        _okHoldFired = false;
        _okDownStarted = true;
        _okHoldTimer?.cancel();
        _okHoldTimer = Timer(const Duration(milliseconds: 450), () {
          // Don't pop settings mid channel-number entry, or once unmounted.
          if (!mounted || _channelBuffer.isActive) {
            _okDownStarted = false;
            return;
          }
          _okHoldFired = true;
          _okDownStarted = false; // the press is consumed by the long-press
          EventBus().emit('toggle_video_settings', true);
        });
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        // Only a press that actually started here becomes a short-press toggle
        // (guards against an OK-up that follows a channel-number commit, etc.).
        if (!_okDownStarted) return KeyEventResult.ignored;
        _okDownStarted = false;
        final wasHold = _okHoldFired;
        _okHoldFired = false;
        _okHoldTimer?.cancel();
        _okHoldTimer = null;
        if (!wasHold) _handleOkTap();
        return KeyEventResult.handled;
      }
      // KeyRepeatEvent while holding OK: swallow so it neither pauses nor drives
      // the video behind; the timer decides when the long-press fires.
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hasQueue = _queue != null && _queue!.length > 1;
    // Channel up/down (D-pad up/down) only makes sense for live TV. For
    // VOD/series it must not jump to another title — those use up/down for
    // the controls instead.
    final isLive =
        PlayerState.currentContent?.contentType == ContentType.liveStream;

    // TV pause panel next-episode ring: DOWN moves the focus ring onto the
    // "Siguiente episodio" button (revealing its highlight); UP or BACK returns
    // the ring to the player so OK resumes as usual. Only while the panel is up
    // and a next episode exists — otherwise these keys fall through unchanged
    // (DOWN is a no-op on non-live, BACK still exits).
    if (_showPausePanel && _hasNextEpisode) {
      if (!_nextEpisodeFocusNode.hasFocus &&
          key == LogicalKeyboardKey.arrowDown) {
        _nextEpisodeFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_nextEpisodeFocusNode.hasFocus &&
          key == LogicalKeyboardKey.arrowUp) {
        _remoteFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_nextEpisodeFocusNode.hasFocus &&
          (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.browserBack)) {
        // BACK con el foco en el botón: devolver el ring al player pero NO
        // consumir, para que BACK salga del reproductor en UNA sola pulsación
        // (como antes de existir el botón), no en dos.
        _remoteFocusNode.requestFocus();
        return KeyEventResult.ignored;
      }
    }

    // Channel-number entry: digit keys accumulate, Enter commits, Backspace
    // deletes. Only meaningful when there's a queue to jump within.
    if (hasQueue) {
      final digit = _digitForKey(key);
      if (digit != null) {
        // Starting a channel-number entry preempts any pending OK long-press
        // (e.g. OK held, then a digit typed) so settings can't pop mid-entry.
        _okHoldTimer?.cancel();
        _okHoldTimer = null;
        _okHoldFired = false;
        _okDownStarted = false;
        _channelBuffer.appendDigit(digit);
        return KeyEventResult.handled;
      }
      if (_channelBuffer.isActive) {
        if (key == LogicalKeyboardKey.backspace) {
          _channelBuffer.backspace();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.select) {
          _channelBuffer.commit();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.browserBack) {
          _channelBuffer.clear();
          return KeyEventResult.handled;
        }
      }
    }

    // Toggle channel list (Menu / Info / "M")
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.info ||
        key == LogicalKeyboardKey.keyM) {
      if (hasQueue) {
        // Live / queued content: Menu shows the channel (or episode) list. The
        // audio/subtitle panel is reached by long-pressing OK (handled above),
        // which works on any remote regardless of a Menu button.
        EventBus().emit('toggle_channel_list', !_showChannelList);
        return KeyEventResult.handled;
      }
      // Single-item VOD has no channel list → Menu opens settings directly, so
      // it's never a dead key.
      EventBus().emit('toggle_video_settings', !PlayerState.showVideoSettings);
      return KeyEventResult.handled;
    }

    // Audio / subtitle settings panel. On a remote-only TV this is the ONLY
    // way to reach audio-track / subtitle selection: the gear button lives in
    // media_kit's touch control bar, which never mounts without a tap. Bound
    // to the dedicated media keys (real remotes) and to "A" (test/keyboards).
    if (key == LogicalKeyboardKey.mediaAudioTrack ||
        key == LogicalKeyboardKey.keyA) {
      EventBus().emit('toggle_video_settings', !PlayerState.showVideoSettings);
      return KeyEventResult.handled;
    }

    // Stream info panel ("I", or the dedicated info hardware key on VOD where
    // it isn't already the channel-list toggle).
    if (key == LogicalKeyboardKey.keyI) {
      EventBus().emit('toggle_video_info', !PlayerState.showVideoInfo);
      return KeyEventResult.handled;
    }

    // Any overlay open (channel list / settings / info): let arrow keys and OK
    // traverse the overlay itself instead of driving the video behind it, and
    // let BACK close the overlay.
    if (_showChannelList ||
        PlayerState.showVideoSettings ||
        PlayerState.showVideoInfo) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        _closePlayerOverlays();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Play / pause — dedicated media keys are always instant (OK/center is
    // handled above so it can distinguish short-press from long-press).
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _settleSeekForManualToggle(); // la pausa explícita gana al seek pendiente
      _player.playOrPause();
      // Dedicated play/pause keys reveal the info bar (title + progress) too.
      _revealInfoBar();
      return KeyEventResult.handled;
    }

    // Channel up/down — live only (dedicated channel keys, or D-pad up/down
    // on a live stream). On VOD/series, D-pad up/down falls through to the
    // controls instead of switching titles.
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.channelDown ||
        (isLive &&
            (key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.pageUp ||
                key == LogicalKeyboardKey.arrowDown ||
                key == LogicalKeyboardKey.pageDown))) {
      if (hasQueue) {
        final up = key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.channelUp ||
            key == LogicalKeyboardKey.pageUp;
        _changeChannel(up ? 1 : -1);
      }
      return KeyEventResult.handled;
    }

    // Seek ACELERADO (solo VOD; live ignora el seek). Ver _seekBy: acumula +
    // escala el paso y comprometa un único seek al soltar.
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaStepForward) {
      if (!isLive) _seekBy(true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaStepBackward) {
      if (!isLive) _seekBy(false);
      return KeyEventResult.handled;
    }

    // Mute / volume keys are handled by the system; let them through.
    return KeyEventResult.ignored;
  }

  Future<void> _loadFavoriteChannels() async {
    try {
      final favs = await FavoritesRepository().getLiveStreamFavorites();
      if (!mounted) return;
      setState(() {
        _favoriteChannelIds = favs.map((f) => f.streamId).toSet();
      });
    } catch (_) {
      // Non-fatal: without favourites the list just shows in queue order.
    }
  }

  Widget _buildChannelListOverlay(BuildContext context) {
    // Use the SAME queue the tap handler jumps into (PlayerState.queue ?? _queue),
    // so the reordered rows' queueIndex maps to the right channel.
    final items = PlayerState.queue ?? _queue!;
    final currentContent = PlayerState.currentContent;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    // Favourites first (display order only — zapping still follows the queue).
    final ordered = orderFavoritesFirst(items, _favoriteChannelIds);

    // Selected row = the current channel's position in the (reordered) list.
    // Resolve the current channel by identity first (robust to reordering);
    // fall back to the live-tracked index only when it's in range, so a
    // momentary queue desync can't autofocus the wrong channel.
    var currentQueueIndex = currentContent != null
        ? items.indexWhere((item) => item.id == currentContent.id)
        : -1;
    if (currentQueueIndex == -1 &&
        _currentItemIndex >= 0 &&
        _currentItemIndex < items.length) {
      currentQueueIndex = _currentItemIndex;
    }
    final di = ordered.indexWhere((o) => o.queueIndex == currentQueueIndex);
    final selectedIndex = di != -1 ? di : 0;

    // "Last channel" resolved by IDENTITY against the CURRENT queue, so a queue
    // change can't point it at the wrong channel — it just hides if absent.
    final prevIdx = _previousChannelId != null
        ? items.indexWhere((i) => i.id.toString() == _previousChannelId)
        : -1;

    String overlayTitle = context.loc.select_channel;
    if (currentContent?.contentType == ContentType.vod) {
      overlayTitle = context.loc.movies;
    } else if (currentContent?.contentType == ContentType.series) {
      overlayTitle = context.loc.episodes;
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showChannelList = false;
          });
        },
        child: Container(
          color: Colors.black.withOpacity(0.3),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {}, // Panel içine tıklanınca kapanmasın
              child: Container(
                width: panelWidth,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[800]!,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              overlayTitle,
                              style: const TextStyle(
                                fontSize: AppThemes.bodySize,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '${selectedIndex + 1} / ${items.length}',
                            style: TextStyle(
                              fontSize: AppThemes.tenFoot(context, 12),
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _showChannelList = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    // "Last channel" quick-recall (reachable on any remote via
                    // this list, no dedicated key needed).
                    if (prevIdx != -1 && prevIdx != currentQueueIndex)
                      _buildLastChannelRow(
                        context,
                        items[prevIdx],
                        prevIdx,
                      ),
                    // Channel list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: ordered.length,
                        itemBuilder: (context, index) {
                          final row = ordered[index];
                          final isSelected = index == selectedIndex;

                          // Pass the REAL queue index so a tap jumps to the
                          // right channel even though the list is reordered.
                          return _buildChannelListItem(
                            context,
                            row.item,
                            row.queueIndex,
                            isSelected,
                            row.isFavorite,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLastChannelRow(
      BuildContext context, ContentItem item, int queueIndex) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () =>
            EventBus().emit('player_content_item_index_changed', queueIndex),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.loc.last_channel,
                        style: TextStyle(
                            fontSize: AppThemes.tenFoot(context, 11), color: Colors.white54)),
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppThemes.tenFoot(context, 13),
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Icon(Icons.replay, color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelListItem(
    BuildContext context,
    ContentItem item,
    int queueIndex,
    bool isSelected,
    bool isFavorite,
  ) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
      autofocus: isSelected,
      onTap: () {
        // queueIndex is the REAL playlist position (the list may be reordered).
        EventBus().emit('player_content_item_index_changed', queueIndex);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.grey[800]!, width: 1),
        ),
        child: Row(
          children: [
            // Thumbnail
            if (item.imagePath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  item.imagePath,
                  width: 50,
                  height: 35,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 50,
                      height: 35,
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image,
                        color: Colors.grey,
                        size: 20,
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                width: 50,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.video_library,
                  color: Colors.grey,
                  size: 20,
                ),
              ),
            const SizedBox(width: 10),
            // Title and info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: AppThemes.tenFoot(context, 13),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getContentTypeIcon(item.contentType),
                        size: 11,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _getContentTypeDisplayNameForItem(item.contentType),
                          style: TextStyle(
                            fontSize: AppThemes.tenFoot(context, 11),
                            color: Colors.grey[500],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isFavorite) ...[
              const Icon(Icons.star, color: Color(0xFFF2C14E), size: 16),
              const SizedBox(width: 6),
            ],
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
      ),
    );
  }

  IconData _getContentTypeIcon(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return Icons.live_tv;
      case ContentType.vod:
        return Icons.movie;
      case ContentType.series:
        return Icons.tv;
    }
  }

  String _getContentTypeDisplayNameForItem(ContentType contentType) {
    // Null-safe: this can run during async init / for OS media metadata, before
    // (or without) a Localizations ancestor — never crash the player over a label.
    final loc = AppLocalizations.of(context);
    switch (contentType) {
      case ContentType.liveStream:
        return loc?.live_stream_content_type ?? 'Live';
      case ContentType.vod:
        return loc?.movie_content_type ?? 'Movie';
      case ContentType.series:
        return loc?.series_content_type ?? 'Series';
    }
  }

  String _getContentTypeDisplayName() {
    final loc = AppLocalizations.of(context);
    switch (widget.contentItem.contentType) {
      case ContentType.liveStream:
        return loc?.live_stream_content_type ?? 'Live';
      case ContentType.vod:
        return loc?.movie_content_type ?? 'Movie';
      case ContentType.series:
        return loc?.series_content_type ?? 'Series';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.shortestSide >= 600;
    final isLandscape = screenSize.width > screenSize.height;

    // Series ve LiveStream için tam ekran modu
    final isSeries = widget.contentItem.contentType == ContentType.series;
    final isLiveStream =
        widget.contentItem.contentType == ContentType.liveStream;
    final isVod = widget.contentItem.contentType == ContentType.vod;
    final isFullScreen = isSeries || isLiveStream || isVod;

    double calculateAspectRatio() {
      if (widget.aspectRatio != null) return widget.aspectRatio!;

      if (isTablet) {
        return isLandscape ? 21 / 9 : 16 / 9;
      }
      return 16 / 9;
    }

    double? calculateMaxHeight() {
      if (isTablet) {
        if (isLandscape) {
          return screenSize.height * 0.6;
        } else {
          return screenSize.height * 0.4;
        }
      }
      return null;
    }

    Widget playerWidget;

    if (isFullScreen) {
      // Series ve LiveStream için tam ekran
      playerWidget = SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            isLoading ? _buildLoadingIndicator(context) : _buildPlayerContent(),
            // Gate de casting por encima (también durante la carga), para poder
            // enviar a la TV sin esperar a que cargue el stream.
            _buildCastGate(context),
            // Pre-buffer: velocidad/buffer/estado (por encima de la carga).
            _buildPreBuffer(context),
          ],
        ),
      );
    } else {
      // Diğer içerikler için aspect ratio kullan
      playerWidget = AspectRatio(
        aspectRatio: calculateAspectRatio(),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            isLoading ? _buildLoadingIndicator(context) : _buildPlayerContent(),
            // Gate de casting por encima (también durante la carga), para poder
            // enviar a la TV sin esperar a que cargue el stream.
            _buildCastGate(context),
            // Pre-buffer: velocidad/buffer/estado (por encima de la carga).
            _buildPreBuffer(context),
          ],
        ),
      );

      if (isTablet) {
        final maxHeight = calculateMaxHeight();
        if (maxHeight != null) {
          playerWidget = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: playerWidget,
          );
        }
      }
    }

    return PopScope(
      // While any overlay is open, Back closes it instead of leaving the player
      // — otherwise a root Overlay panel could be orphaned over the next screen.
      canPop: !_anyOverlayOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closePlayerOverlays();
      },
      child: Container(
        color: Colors.black,
        child: isFullScreen ? playerWidget : Column(children: [playerWidget]),
      ),
    );
  }

  bool get _anyOverlayOpen =>
      _showChannelList ||
      PlayerState.showChannelList ||
      PlayerState.showVideoInfo ||
      PlayerState.showVideoSettings;

  /// Close every player overlay (internal Stack panels + the button widgets'
  /// own root OverlayEntries via the EventBus toggles).
  void _closePlayerOverlays() {
    if (mounted) {
      setState(() {
        _showChannelList = false;
        PlayerState.showChannelList = false;
        PlayerState.showVideoInfo = false;
        PlayerState.showVideoSettings = false;
      });
    }
    EventBus().emit('toggle_channel_list', false);
    EventBus().emit('toggle_video_info', false);
    EventBus().emit('toggle_video_settings', false);
  }

  Widget _buildPlayerContent() {
    if (hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            // Friendly, localized headline. The raw string is a libmpv
            // diagnostic ("Cannot seek in this stream", "Failed to open http://…")
            // — English, developer-facing and sometimes a leaked path/flag, so it
            // must never be the primary message a customer reads.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.loc.playback_failed,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: AppThemes.tenFoot(context, 14),
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            // The scrubbed technical detail stays available (support, power
            // users) but dimmed and small, below the headline.
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  errorMessage,
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: AppThemes.tenFoot(context, 10)),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Focusable so the D-pad can reach it on Android TV.
            ElevatedButton.icon(
              autofocus: true,
              onPressed: _retryPlayback,
              icon: const Icon(Icons.refresh),
              label: Text(context.loc.try_again),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    return Focus(
      focusNode: _remoteFocusNode,
      autofocus: true,
      onKeyEvent: _handleRemoteKey,
      child: GestureDetector(
      onVerticalDragEnd: (details) {
        if (_queue == null || _queue!.length <= 1) return;

        // Yukarı swipe - sonraki kanal
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -500) {
          _changeChannel(1);
        }
        // Aşağı swipe - önceki kanal
        else if (details.primaryVelocity != null &&
            details.primaryVelocity! > 500) {
          _changeChannel(-1);
        }
      },
      child: Stack(
        children: [
          getVideo(
            context,
            _videoController!,
            PlayerState.subtitleConfiguration,
          ),

          if (widget.onFullscreen != null &&
              (Theme.of(context).platform == TargetPlatform.macOS ||
                  Theme.of(context).platform == TargetPlatform.windows ||
                  Theme.of(context).platform == TargetPlatform.linux))
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: widget.onFullscreen,
                icon: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 24,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),

          // Kanal listesi overlay - normal mod için
          if (_showChannelList && _queue != null && _queue!.length > 1)
            _buildChannelListOverlay(context),

          // TV remote reachability: the settings (audio/subtitle) and stream-info
          // panels normally live inside media_kit's touch control bar, which only
          // mounts on a tap — so on a remote-only Android TV they'd never register
          // their open/close listeners and the D-pad keys above would do nothing.
          // Mount them off-screen so those listeners are always live; the panels
          // themselves open into the root overlay.
          ExcludeFocus(
            child: Offstage(
              offstage: true,
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [VideoInfoWidget(), VideoSettingsWidget()],
                ),
              ),
            ),
          ),

          // Channel-number entry overlay (TV remote).
          ChannelNumberOverlay(buffer: _channelBuffer.buffer),

          // Rich pause panel (TV): title + synopsis + cast while paused. Not
          // wrapped in ExcludeFocus because it now hosts the focusable
          // "Siguiente episodio" button — but that button never autofocuses, so
          // the player keeps the D-pad by default and OK still reaches
          // _handleRemoteKey to resume; the ring only moves here on D-pad DOWN.
          // (The cast rail's InkWells are disabled in this panel — no onActorTap
          // — so nothing else can steal focus.) Hidden while another overlay
          // (channel list / settings / info) is open.
          if (_showPausePanel &&
              !_anyOverlayOpen &&
              contentItem.contentType != ContentType.liveStream)
            PauseInfoPanel(
              title: contentItem.name,
              contentType: contentItem.contentType,
              position: _player.state.position,
              duration: _player.state.duration,
              hasNext: _hasNextEpisode,
              onNext: _skipToNextEpisode,
              nextFocusNode: _nextEpisodeFocusNode,
            ),

          // Transient seek progress bar (D-pad ±10s feedback).
          _buildSeekOverlay(),

          // Transient TV hint: "Hold OK for audio & subtitles".
          _buildOkHintOverlay(context),

        ],
      ),
      ),
    );
  }

  Widget _buildOkHintOverlay(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 28,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _showOkHint ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.radio_button_checked,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    context.loc.hold_ok_for_options,
                    style: TextStyle(
                        color: Colors.white,
                        // Same reason as movie_screen's poster title: a raw
                        // labelSize stayed at 14 on TV while the error message
                        // above it went 12 -> 16, leaving the remote hint
                        // smaller than the body it belongs to.
                        fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
