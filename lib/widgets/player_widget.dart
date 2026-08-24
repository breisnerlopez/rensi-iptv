import 'dart:async';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/channel_number_buffer.dart';
import 'package:rensi_iptv/services/download_service.dart';
import 'package:rensi_iptv/services/dvr_service.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/pip_service.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/channel_order.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/utils/resume_position.dart';
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
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/tmdb_cast_resolver.dart';
import 'package:rensi_iptv/utils/pre_buffer_monitor.dart';
import 'package:rensi_iptv/services/app_navigator.dart';
import 'package:rensi_iptv/widgets/cast/cast_flow.dart';
import 'package:rensi_iptv/widgets/cast/cast_mini_controller.dart';
import 'package:rensi_iptv/widgets/cast/pause_info_panel.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/utils/subtitle_configuration.dart';
import 'package:rensi_iptv/utils/connectivity_helper.dart';
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
import 'package:rensi_iptv/models/series_response.dart';
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

  /// Metadatos TMDb (sinopsis + reparto) que el MÓVIL resolvió y envió con el
  /// LOAD de casting. Solo lo rellena el host receptor de la TV
  /// (tv_receiver_host) con lo que llegó en el LOAD; el panel de pausa los
  /// muestra en vez de llamar a TMDb (la TV no tiene clave). Null en la
  /// reproducción normal → comportamiento de siempre.
  final CastMeta? castMeta;

  /// Posición (ms) desde la que reanudar, cuando la conoce QUIEN monta el player
  /// pero NO está en el historial local — hoy solo el receptor de casting en la
  /// TV (le llega en el LOAD del móvil; la TV no tiene el "continuar viendo" del
  /// teléfono). Es AUTORITATIVO: se usa TAL CUAL como ancla de resume del ítem
  /// actual, sin compararlo con el historial local de la TV. Null → resume normal
  /// (solo historial). Ver _resumeMsFor.
  final int? startPositionMs;

  /// Feature H — providerId (id de playlist Xtream del móvil) para guardar en la
  /// fila de historial cuando este player es el receptor de un cast STANDALONE.
  /// Solo lo rellena tv_receiver_host con el `pid` del LOAD; junto al
  /// `containerExtension` del ContentItem alimenta las columnas homónimas de la
  /// fila `__cast__` que necesita el replay standalone (fase 4). Null en toda
  /// reproducción no-standalone → la fila conserva ambas columnas en null, igual
  /// que siempre.
  final String? standaloneProviderId;

  const PlayerWidget({
    super.key,
    required this.contentItem,
    this.aspectRatio,
    this.showControls = true,
    this.showInfo = false,
    this.onFullscreen,
    this.queue,
    this.castMeta,
    this.startPositionMs,
    this.standaloneProviderId,
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
  StreamSubscription? _castSetVolumeSubscription;
  StreamSubscription? _castSeekSubscription;
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
  int _seekStreak = 0; // nivel de escalado del paso (0..._maxSeekLevel)
  // Escalado del paso de seek THROTTLEADO POR TIEMPO: un KeyRepeat rápido no debe
  // disparar la racha a su tope en unas pocas décimas (antes cada evento subía el
  // paso → mantener la flecha saltaba a 5min y se pasaba del final). Se sube como
  // mucho un nivel cada ~750ms de mantener pulsado.
  DateTime? _lastSeekEscalationAt;
  static const int _maxSeekLevel = 2;
  static const Duration _seekEscalateEvery = Duration(milliseconds: 750);
  bool _seekForward = true;
  bool _seekWasPlaying = true;
  bool _seekInProgress = false; // ventana de gracia del re-buffer tras el seek
  DateTime? _lastSeekPressAt;
  // Rich pause panel (TV only): while paused, show title + synopsis + cast.
  bool _showPausePanel = false;
  // "Siguiente episodio" prompt (phone only): shown over the player in the last
  // ~30s of a SERIES episode that has a next in the queue — a Netflix-style
  // early manual skip. media_kit still auto-advances at EOF; this only offers to
  // jump sooner. Reset per episode; [_nextEpisodePromptDismissed] suppresses it
  // for the current episode once the user dismisses (or acts on) it.
  bool _showNextEpisodePrompt = false;
  bool _nextEpisodePromptDismissed = false;
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
  // PERF: throttle del bookkeeping que ASIGNA (Media + Timer del debounce) en el
  // listener de posición, para no presionar el GC en cada tick (varios Hz).
  DateTime? _lastResumeSync;
  // Safety net for hard kills that never reach didChangeAppLifecycleState at
  // all (some OEM/OOM kills tear the process down without going through the
  // normal Flutter lifecycle callbacks): flush the resume position on a fixed
  // cadence instead of relying solely on _watchHistoryTimer above, which is a
  // pure debounce — during uninterrupted playback every new position tick
  // re-arms it before its 5s elapse, so in practice it only ever fires once
  // ticks stop (pause/stall), never mid-play.
  Timer? _periodicHistoryTimer;
  // Reentrancy guard for _saveWatchHistory: inactive→paused fire back-to-back
  // on a normal backgrounding, and the periodic timer can overlap a
  // lifecycle-triggered flush. _pendingWatchDuration is only nulled out AFTER
  // the DB await completes, so two concurrent calls could both read it
  // non-null before either finishes → double saveWatchHistory +
  // markWatchedAndMaybeDelete + history_changed. This flag stops a second
  // call from ever starting while one is in flight (a later, non-concurrent
  // call still no-ops on its own via the null pendingWatchDuration).
  bool _savingHistory = false;
  Duration? _pendingWatchDuration;
  Duration? _pendingTotalDuration;
  // Última posición REAL observada (>0), NUNCA anulada. _pendingWatchDuration se
  // pone a null tras cada guardado de historial, así que si una caída de red
  // resetea la posición del player a 0 justo después de un guardado, el reopen
  // no tendría ancla y reiniciaría desde el principio. Este campo la conserva
  // como red de seguridad para el resume del reopen.
  Duration? _lastGoodPosition;
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
  // Watchdog de AVANCE de posición en vivo (hallazgo de QA). En un corte de red
  // que excede el readahead (~15s), `_player.state.position` NO sigue avanzando:
  // se RESETEA a 0 y ahí se queda con `playing=true`, sin recuperación cuando la
  // red vuelve. El `_stallTimer` de arriba nunca dispara porque lo arma la señal
  // `buffering`, que `cache-pause=no` suprime. Este watchdog es INDEPENDIENTE de
  // esa señal: mira solo si la posición avanza y, si lleva >20s sin avanzar en
  // vivo, reabre el stream (que reabre en el borde en vivo, ya es seguro).
  Timer? _liveWatchdogTimer;
  int _lastLivePosMs = -1;
  DateTime? _lastLiveAdvanceAt;
  // Guarda de reentrada de _reopenCurrent(): todos sus llamadores (stall-timer,
  // error-handler, conectividad, retry y este watchdog) pueden solaparse; sin
  // esto dos `_player.open()` concurrentes compiten sobre el mismo player.
  bool _reopenInProgress = false;

  // Experimental DVR (record-while-watching): only surfaced on a live channel
  // when the developer flag is on. _recording tracks an in-flight dump.
  bool _dvrEnabled = false;
  bool _recording = false;
  // In-flight guard so a double-tap can't launch two concurrent start/stop
  // calls (which would race the post-await _recording flip and orphan a file).
  bool _dvrBusy = false;
  // Guard against disposing the native player twice (lifecycle + dispose()).
  bool _playerDisposed = false;

  // BACK-para-salir con confirmación (Fix #10a): un primer BACK (sin overlays
  // abiertos) muestra un aviso breve; solo un segundo BACK dentro de ~3s sale de
  // verdad. Evita salidas accidentales de la reproducción con el mando.
  bool _backExitArmed = false;
  Timer? _backExitTimer;
  // Debounce channel surfing (holding channel up/down) so we reopen the stream
  // once the user stops, not on every key repeat.
  int? _pendingChannelIndex;
  Timer? _channelDebounceTimer;

  // --- Casting (segunda pantalla) ---
  CastSenderController? _cast;
  bool _wasCasting = false;

  // Metadatos TMDb resueltos EN EL MÓVIL para adjuntarlos al LOAD de casting
  // (sinopsis + reparto para el panel de pausa de la TV, que no tiene clave
  // TMDb). Best-effort: si no resuelve a tiempo o no hay coincidencia, el LOAD va
  // sin meta y el panel degrada a solo-título (como hoy). Se resuelve UNA vez por
  // contenido (guardado por id); para series es el meta de la SERIE, que se
  // reutiliza en todos los episodios de la cola (auto-avance).
  CastMeta? _castMeta;
  String? _castMetaForId; // id de contenido al que pertenece _castMeta
  Future<CastMeta?>? _castMetaFuture;

  // Feature H (fix) — seriesId de la SERIE del episodio actual, resuelto por BD
  // para el CAST. Un ContentItem de episodio (Xtream) NO lleva seriesStream (lo
  // construyen series_screen/episode_screen sin él), así que sin esto el
  // `_castMedia.seriesId` viaja null → la fila `__cast__` de la TV queda sin
  // seriesId → el auto-avance standalone NUNCA arranca. Todos los episodios de la
  // cola comparten la misma serie, así que un solo id vale para toda la cola.
  String? _castSeriesId;
  String? _castSeriesIdForId; // id del episodio al que pertenece _castSeriesId

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
    // Reconstruir para que la UI refleje el handoff: mientras la pantalla siga
    // montada (el cierre por maybePop es best-effort y puede correr una carrera
    // o saltarse por `!mounted`), el indicador de carga debe mostrar "en la TV"
    // en vez de un spinner eterno (isLoading se queda en true tras el gate).
    setState(() {});
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

  /// Lanza (una vez por contenido) la resolución TMDb del meta a adjuntar al
  /// LOAD. No bloquea nada: guarda el resultado en [_castMeta] cuando llega. Solo
  /// para VOD/serie (el panel de pausa no aplica a vivo). Idempotente por id.
  void _kickoffCastMeta() {
    final item = widget.contentItem;
    if (item.contentType == ContentType.liveStream) return;
    if (_castMetaForId == item.id && (_castMeta != null || _castMetaFuture != null)) {
      return;
    }
    _castMetaForId = item.id;
    _castMeta = null;
    // Leer el locale AQUÍ (sync, con contexto válido); la resolución es async y
    // no debe tocar el BuildContext tras el await.
    final locale = Localizations.localeOf(context);
    final future = _resolveCastMeta(item, locale);
    _castMetaFuture = future;
    future.then((m) {
      // Ignorar si el contenido cambió mientras resolvía (evita pisar el meta del
      // título entrante con el del saliente).
      if (!mounted || _castMetaForId != item.id) return;
      if (m != null) _castMeta = m;
    });
  }

  /// Espera (acotado) a que [_kickoffCastMeta] termine, para que el LOAD que se
  /// va a enviar incluya el meta si ya resolvió. NUNCA retrasa el LOAD más que
  /// este techo corto: si TMDb tarda, se envía sin meta (degrada a solo-título).
  Future<void> _ensureCastMeta() async {
    if (widget.contentItem.contentType == ContentType.liveStream) return;
    if (_castMeta != null && _castMetaForId == widget.contentItem.id) return;
    _kickoffCastMeta();
    final f = _castMetaFuture;
    if (f == null) return;
    final m = await f.timeout(const Duration(milliseconds: 2500),
        onTimeout: () => null);
    if (!mounted) return;
    if (m != null && _castMetaForId == widget.contentItem.id) _castMeta = m;
  }

  /// Feature H (fix) — resuelve (una vez por episodio, acotado) el `seriesId` de
  /// la SERIE del episodio actual para que el LOAD lo lleve. El ContentItem de un
  /// episodio Xtream se construye SIN seriesStream (ver series_screen /
  /// episode_screen), así que `contentItem.seriesStream?.seriesId` es null y el
  /// auto-avance standalone de la TV nunca podía arrancar. Se lee de la BD por la
  /// MISMA vía que [_reliableCastInfo] (`findEpisodesById`), que es local y
  /// rápida. Best-effort: ante cualquier fallo / sin fila / no-Xtream / no-serie
  /// queda null y el LOAD degrada al comportamiento de un solo episodio.
  Future<void> _ensureCastSeriesId() async {
    final item = widget.contentItem;
    if (item.contentType != ContentType.series) return;
    // Si el propio item ya trae el seriesId (algún camino sí lo adjunta), o ya lo
    // resolvimos para este episodio, no repetir.
    if ((item.seriesStream?.seriesId.isNotEmpty ?? false) ||
        (_castSeriesIdForId == item.id && _castSeriesId != null)) {
      return;
    }
    if (!isXtreamCode) return;
    final playlistId = AppState.currentPlaylist?.id;
    if (playlistId == null) return;
    try {
      final ep = await _database
          .findEpisodesById(item.id, playlistId)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      final sid = ep?.seriesId;
      if (!mounted) return;
      if (sid != null && sid.isNotEmpty && item.id == widget.contentItem.id) {
        _castSeriesId = sid;
        _castSeriesIdForId = item.id;
      }
    } catch (_) {/* best-effort: sin seriesId → cola de un solo episodio */}
  }

  /// seriesId a usar al armar un CastMedia de serie: el del propio item si lo
  /// trae, si no el resuelto por BD ([_ensureCastSeriesId]).
  String? _castSeriesIdFor(ContentItem it) =>
      it.seriesStream?.seriesId ?? _castSeriesId;

  /// Resuelve el meta TMDb del contenido actual (best-effort). Para SERIE usa el
  /// nombre de la SERIE (no el del episodio) y su tmdbId de serie; para película,
  /// el título de la peli y su tmdbId. Locale del contexto. Devuelve null ante
  /// cualquier fallo (sin clave, sin coincidencia, red…): el LOAD irá sin meta.
  Future<CastMeta?> _resolveCastMeta(ContentItem item, Locale locale) async {
    try {
      final isSeries = item.contentType == ContentType.series;
      // Datos FIABLES por id — lo MISMO que la pantalla de detalle del móvil
      // muestra al usuario (que resuelve por tmdb_id, no por búsqueda de
      // título). Antes el casting hacía una búsqueda por título que falla para
      // algunos títulos (traducción, sin coincidencia, límite) → la TV se
      // quedaba sin sinopsis/reparto NI póster. Resolver el id fiable aquí hace
      // que "lo que ve el móvil = lo que recibe la TV".
      final reliable = await _reliableCastInfo(item, isSeries);
      // Serie → nombre de la SERIE (el episodio no coincide en TMDb); película →
      // título de la peli. Se prefiere el nombre real de la serie que devuelve
      // get_series_info; si no, el del item (episodio) como antes.
      final title = isSeries
          ? (reliable.seriesName?.trim().isNotEmpty ?? false
              ? reliable.seriesName!
              : (item.seriesStream?.name.trim().isNotEmpty ?? false
                  ? item.seriesStream!.name
                  : item.name))
          : item.name;
      final year = isSeries
          ? (reliable.year ?? _yearFrom(item.seriesStream?.releaseDate))
          : null;
      return TmdbCastResolver().resolve(
        title: title,
        mediaType: isSeries ? TmdbMediaType.tv : TmdbMediaType.movie,
        locale: locale,
        year: year,
        // Id fiable si se resolvió; si no, el que trajera el item (bulk).
        tmdbId: reliable.tmdbId ?? item.tmdbId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Resuelve el tmdb_id FIABLE del contenido (y, para series, el nombre/año de
  /// la SERIE) por la MISMA vía autoritativa que usa la pantalla de detalle:
  /// `get_vod_info` (`info.tmdb_id`) para películas y `get_series_info` para
  /// series. El id de la lista bulk suele venir vacío —los paneles solo exponen
  /// el tmdb_id en la ficha de detalle— y por eso el casting caía a una búsqueda
  /// por título fallible. Todo es best-effort: ante cualquier fallo devuelve lo
  /// que ya se supiera del item (degrada como hoy, sin romper el LOAD).
  Future<({int? tmdbId, String? seriesName, int? year})> _reliableCastInfo(
      ContentItem item, bool isSeries) async {
    // Punto de partida: lo que ya trae el item (suele venir sin id en bulk).
    int? id = (item.tmdbId != null && item.tmdbId! > 0) ? item.tmdbId : null;
    String? seriesName;
    int? year;

    // Solo Xtream expone get_vod_info / get_series_info; en M3U no hay de dónde.
    if (!isXtreamCode) {
      return (tmdbId: id, seriesName: seriesName, year: year);
    }
    final repo = AppState.xtreamCodeRepository;
    if (repo == null) {
      return (tmdbId: id, seriesName: seriesName, year: year);
    }

    try {
      if (isSeries) {
        // El episodio no lleva su seriesId en memoria; se resuelve por BD y con
        // él se pide la ficha de la SERIE (tmdb_id a nivel serie + nombre real).
        final playlistId = AppState.currentPlaylist?.id;
        if (playlistId == null) {
          return (tmdbId: id, seriesName: seriesName, year: year);
        }
        final ep = await _database.findEpisodesById(item.id, playlistId);
        final seriesId = ep?.seriesId;
        if (seriesId == null || seriesId.isEmpty) {
          return (tmdbId: id, seriesName: seriesName, year: year);
        }
        final SeriesDetailResponse? info = await repo.getSeriesInfo(seriesId);
        if (info != null) {
          if ((info.tmdbId ?? 0) > 0) id = info.tmdbId;
          final n = info.seriesInfo.name.trim();
          if (n.isNotEmpty) seriesName = n;
          year = _yearFrom(info.seriesInfo.releaseDate);
        }
      } else if (id == null) {
        // Película: item.id ES el vod id. Primero se intenta el tmdb_id ya
        // guardado en BD (la ficha lo persiste al abrirla) para no repetir un
        // get_vod_info por red en el flujo más común (abrir ficha → enviar a TV);
        // solo si sigue ausente se lee de la red y se persiste.
        final playlistId = AppState.currentPlaylist?.id;
        if (playlistId != null) {
          final cached = (await _database.findMovieById(item.id, playlistId))
              ?.tmdbId;
          if (cached != null && cached > 0) id = cached;
        }
        if (id == null) {
          final info = await repo.getVodInfo(item.id);
          final fetched = _tmdbIdFromVodInfo(info);
          if (fetched != null) {
            id = fetched;
            unawaited(repo.persistVodTmdbId(item.id, fetched));
          }
        }
      }
    } catch (_) {/* best-effort: se devuelve lo que se tenga */}
    return (tmdbId: id, seriesName: seriesName, year: year);
  }

  /// Extrae el tmdb_id de la respuesta cruda de `get_vod_info` (vive en
  /// `info.tmdb_id`, con un `tmdb_id` plano de reserva). Espejo del getter
  /// `_tmdbId` de MovieScreen. 0/"" se tratan como ausente.
  static int? _tmdbIdFromVodInfo(Map<String, dynamic>? vodInfo) {
    if (vodInfo == null) return null;
    final info = vodInfo['info'];
    final raw = info is Map ? info['tmdb_id'] : vodInfo['tmdb_id'];
    if (raw is num) {
      final v = raw.toInt();
      return v > 0 ? v : null;
    }
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      return (v != null && v > 0) ? v : null;
    }
    return null;
  }

  static int? _yearFrom(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  CastMedia get _castMedia => CastMedia(
        channelId: widget.contentItem.id,
        contentType: _castType(widget.contentItem.contentType),
        title: widget.contentItem.name,
        ext: widget.contentItem.containerExtension ?? '',
        imagePath: widget.contentItem.imagePath,
        playlistId: AppState.currentPlaylist?.id ?? '',
        seriesId: _castSeriesIdFor(widget.contentItem),
        // Misma clave de historial que _saveWatchHistory (Xtream: id; M3U:
        // m3uItem.id) para no duplicar "continuar viendo".
        historyId: isXtreamCode
            ? widget.contentItem.id
            : widget.contentItem.m3uItem?.id ?? widget.contentItem.id,
        // Meta TMDb resuelto en el móvil (sinopsis/reparto) para el panel de
        // pausa de la TV. Null si aún no resolvió → LOAD sin meta (como hoy).
        meta: _castMeta,
      );

  /// Catálogo actual mapeado a CastMedia (para el zapping desde el móvil).
  List<CastMedia>? get _castQueue {
    final q = _queue;
    if (q == null || q.length <= 1) return null;
    // Para una serie todos los episodios comparten la misma ficha (la de la
    // serie), así que se adjunta el MISMO _castMeta a cada item: el auto-avance
    // de episodio sigue mostrando el reparto/sinopsis correctos. Para vivo el
    // panel no aplica y _castMeta es null.
    return [
      for (final it in q)
        CastMedia(
          channelId: it.id,
          contentType: _castType(it.contentType),
          title: it.name,
          ext: it.containerExtension ?? '',
          imagePath: it.imagePath,
          playlistId: AppState.currentPlaylist?.id ?? '',
          // Todos los episodios de la cola son de la MISMA serie → el seriesId
          // resuelto por BD para el episodio actual vale para todos.
          seriesId: _castSeriesIdFor(it),
          historyId: isXtreamCode ? it.id : it.m3uItem?.id ?? it.id,
          meta: _castMeta,
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
  // Estado TERMINAL del pre-buffer (hallazgo de QA): cuando se agota el techo de
  // 8s y el colchón sigue vacío / las lecturas de propiedades se colgaron, forzar
  // play sobre un player atascado es PEOR que el overlay. En su lugar se marca
  // esto y se muestra una tarjeta "conexión demasiado lenta" con Reintentar. Se
  // reinicia a false al reintentar / al empezar un nuevo pre-buffer.
  bool _preBufferTooSlow = false;
  // Ticks consecutivos con techo agotado y buffer vacío antes de dar por
  // terminal (auditor): una ÚNICA lectura ≤0.05 / timeout de getProperty NO debe
  // tapar con la tarjeta terminal un vídeo que en TV ya reproduce por debajo. Se
  // exige confirmarlo 2 ticks seguidos; cualquier tick con colchón lo resetea.
  int _tooSlowStreak = 0;
  // FIX-1 (overlay vs. reproducción real): posición y reloj del tick anterior del
  // pre-buffer, para detectar reproducción REAL (la TV ya reproduce por debajo del
  // overlay). Se comparan SIEMPRE entre dos lecturas (nunca contra 0) y se siembran
  // en el primer tick (null = aún sin sembrar) para que un LOAD con reanudación
  // —que pone position>0 de golpe— no se confunda con avance de reproducción.
  Duration? _lastPreBufferPos;
  Duration? _lastPreBufferElapsed;

  // Watchdog de la carga inicial: cuenta el tiempo en "Preparando…" para poder
  // avisar (y ofrecer Reintentar) si la apertura del stream se cuelga sin lanzar
  // error — el caso reportado en algunas cajas de TV.
  Timer? _loadTicker;
  final Stopwatch _loadClock = Stopwatch();
  bool _autoRetried = false; // un solo auto-reintento del primer arranque
  // Fase de la carga (audio/open/ready), para diagnosticar dónde se cuelga.
  String _loadStage = '';
  // Watchdog de "buffering sin arrancar" para VOD/serie: el botón Reintentar
  // vivía SOLO dentro del indicador de carga (gated por isLoading). Cuando la
  // init termina (isLoading=false) pero el stream se queda en buffering sin
  // llegar NUNCA a reproducir (cuelgue silencioso en algunas cajas de TV),
  // desaparecía el Reintentar y quedaba el círculo pelado de media_kit sin
  // salida. Este watchdog repone el Reintentar en ese caso (en vivo ya lo cubre
  // _stallTimer, que reabre solo).
  Timer? _vodStuckTimer;
  bool _stuckBuffering = false; // muestra el overlay de Reintentar
  bool _hasStartedPlaying = false; // ¿alguna vez llegó a reproducir?
  // Re-buffer A MITAD (Fix #5): indicador informativo (no el círculo pelado de
  // media_kit) cuando un stream que YA arrancó se para a rebufferizar. Coexiste
  // con _vodStuckTimer (ese es para el cuelgue "nunca arrancó"; esto es el
  // re-buffer de un stream vivo). Un poll ligero refresca segundos/velocidad.
  bool _midPlayBuffering = false;
  Timer? _midPlayBufferTimer;
  double _midPlayBufferedSecs = 0;
  double _midPlaySpeedBps = 0;
  // Repaint acotado al HUD de buffering (pre-buffer + rebuffer a mitad): en vez
  // de un setState por tick (500/600 ms) que reconstruye TODO el árbol del
  // player —justo cuando el equipo ya está cargado abriendo el stream—, se
  // bombea este notifier y solo el overlay del HUD (envuelto en
  // ValueListenableBuilder) se repinta. Las TRANSICIONES (aparecer / ocultar /
  // terminal) siguen yendo por setState.
  final ValueNotifier<int> _bufferHudTick = ValueNotifier<int>(0);
  // Ancla para detectar AVANCE REAL de posición (frames renderizando de verdad)
  // en el listener de posición y así bajar el pre-buffer/terminal. NO se usa el
  // flag `playing` de mpv, que solo significa "no pausado" (se emite aunque no
  // llegue un byte); un stream muerto tiene playing=true pero posición congelada.
  Duration? _lastAdvancePos;
  DateTime? _lastAdvanceWall;

  void _startPreBuffer() {
    final isLive = widget.contentItem.contentType == ContentType.liveStream;
    final tv = ResponsiveHelper.isTelevisionDevice;
    // INVARIANTE: el target debe ser < demuxer-readahead-secs (ver
    // _tuneForPerformance), o `isReady` (buf ≥ target) es INALCANZABLE porque el
    // demuxer-cache topa en el readahead. VOD readahead=10 → target 7 (colchón
    // razonable y alcanzable); vivo readahead=15 → target 4.
    _preBuffer = PreBufferMonitor(targetSecs: isLive ? 4 : 7);
    _preBuffering = true;
    _preBufferTooSlow = false; // nuevo pre-buffer: limpiar el estado terminal
    _tooSlowStreak = 0;
    _lastPreBufferPos = null; // sin sembrar → el primer tick solo siembra
    _lastPreBufferElapsed = null;
    _lastAdvancePos = null; // ancla del dismissal por avance real (listener pos)
    _lastAdvanceWall = null;
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
      // (a) CORRECCIÓN (hallazgo de QA): calcular `elapsed` y evaluar el TECHO de
      // 8s ANTES de los `getProperty`. Bajo inanición de red esos reads se
      // cuelgan; si el techo se evaluara DESPUÉS (como antes), nunca se alcanzaría
      // y el overlay quedaría pegado con métricas congeladas para siempre. Con el
      // techo calculado primero, la salida es alcanzable en cada tick.
      final elapsed = _preBufferClock.elapsed;
      final maxWaited = elapsed >= const Duration(seconds: 8);
      // (b) Cada `getProperty` con timeout de 1s: un read colgado no puede atascar
      // el tick. Centinela '-1' = "no se pudo leer" → buffer sin datos utilizables.
      double buf = 0, spd = 0;
      final pf = _player.platform;
      if (pf is NativePlayer) {
        try {
          final bufStr = await pf
              .getProperty('demuxer-cache-duration')
              .timeout(const Duration(seconds: 1), onTimeout: () => '-1');
          final spdStr = await pf
              .getProperty('cache-speed')
              .timeout(const Duration(seconds: 1), onTimeout: () => '-1');
          buf = double.tryParse(bufStr) ?? -1;
          spd = double.tryParse(spdStr) ?? 0;
        } catch (_) {
          buf = -1; // read fallido → tratar como sin datos utilizables
        }
      }
      // Solo alimentar el monitor con una lectura BUENA (buf>=0): un -1 (read
      // colgado/fallido) no debe contaminar las métricas mostradas.
      final readOk = buf >= 0;
      if (readOk) {
        _preBuffer!.add(PreBufferSample(buf, spd, elapsed));
      }
      // FIX-1: señal AUTORITATIVA de reproducción real. En TV el vídeo ya
      // reproduce por debajo del overlay (`_player.play()` en el open), así que si
      // el player está `playing` y la posición avanza a ~tiempo real, el overlay
      // (cosmético en TV) y el estado terminal "conexión lenta" son un falso
      // positivo. Se mide contra el tick anterior (nunca contra 0) usando el reloj
      // de pared: reproducción real ⇒ Δpos ≈ Δwall; un SEEK (p.ej. reanudación)
      // ⇒ Δpos ≫ Δwall. Comparar contra Δwall (no un techo fijo) tolera ticks
      // retrasados por los getProperty colgados —justo el caso del bug—, donde
      // Δpos y Δwall crecen juntos.
      final pos = _player.state.position;
      bool realPlayback = false;
      if (_lastPreBufferPos != null && _lastPreBufferElapsed != null) {
        realPlayback = isRealPlaybackAdvance(
          playing: _player.state.playing,
          dPos: pos - _lastPreBufferPos!,
          dWall: elapsed - _lastPreBufferElapsed!,
        );
      }
      _lastPreBufferPos = pos;
      _lastPreBufferElapsed = elapsed;
      if (mounted) _bufferHudTick.value++; // repinta SOLO el HUD, no el árbol
      final tv = ResponsiveHelper.isTelevisionDevice;
      // Piso (solo TV): mostrar "preparando" al menos 1.5s tras enviar el
      // contenido; con buena conexión el colchón se llena en 1-2 ticks y no se
      // llegaba a ver el estado. En el móvil se inicia en cuanto hay colchón.
      final minShown = !tv || elapsed >= const Duration(milliseconds: 1500);
      // Sin datos (stalled): no tiene sentido seguir reteniendo — soltar y dejar
      // que el player normal (buffering/stall-watchdog/error) tome el control.
      final stalled = _preBuffer!.phase == BufferPhase.stalled;
      // Colchón utilizable realmente acumulado (lectura buena Y algo en caché).
      final hasUsableBuffer = readOk && buf > 0.05;
      // FIX-1: reproducción real confirmada ⇒ no es terminal por definición
      // (aunque las métricas del demuxer estén ciegas), como tampoco lo es si hay
      // colchón. Cualquiera de las dos resetea la racha.
      if (hasUsableBuffer || realPlayback) _tooSlowStreak = 0;
      if (maxWaited && !hasUsableBuffer && !realPlayback) {
        // TERMINAL (RETADOR + auditor): techo agotado y el buffer sigue vacío /
        // los reads se colgaron → forzar play sobre un player atascado es PEOR que
        // el overlay. Pero se exigen 2 ticks SEGUIDOS así (una lectura ≤0.05 /
        // timeout aislada no tapa un vídeo que ya reproduce por debajo). El guard
        // `!realPlayback` (FIX-1) evita el falso positivo del bug reportado: la TV
        // ya reproduce por debajo con caché ilegible → NUNCA marcar terminal.
        _tooSlowStreak++;
        if (_tooSlowStreak >= 2) {
          _preBufferTimer?.cancel();
          _preBufferClock.stop();
          if (mounted) setState(() => _preBufferTooSlow = true);
          return;
        }
      }
      if ((_preBuffer!.isReady && minShown) ||
          stalled ||
          (maxWaited && hasUsableBuffer) ||
          (realPlayback && minShown)) {
        // Arranca (baja el overlay) si: hay colchón listo; no hay datos (stalled →
        // cede al player normal); el techo se agotó con colchón utilizable; o —
        // FIX-1— se confirmó reproducción REAL (respetando el piso de 1.5s en TV).
        // Tras bajar el overlay, si la red muere al instante, el control pasa a
        // _midPlayBuffering / _vodStuckTimer / _stallTimer (red de seguridad).
        _finishPreBuffer();
      }
    });
  }

  /// Poll ligero de segundos-en-caché / velocidad mientras el stream rebufferiza
  /// A MITAD (Fix #5), para que el indicador informe sin depender del pre-buffer
  /// (que solo corre en el open inicial). Se detiene al reanudar/soltar.
  void _startMidPlayBufferPoll() {
    _midPlayBufferTimer?.cancel();
    void sample() async {
      if (!mounted || !_midPlayBuffering) return;
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
      if (!mounted || !_midPlayBuffering) return;
      // Repaint acotado: actualizar los campos y bombear el notifier del HUD en
      // vez de un setState que reconstruye todo el player cada 600 ms.
      _midPlayBufferedSecs = buf;
      _midPlaySpeedBps = spd;
      _bufferHudTick.value++;
    }

    sample();
    _midPlayBufferTimer =
        Timer.periodic(const Duration(milliseconds: 600), (_) => sample());
  }

  void _stopMidPlayBufferPoll() {
    _midPlayBufferTimer?.cancel();
    _midPlayBufferTimer = null;
  }

  /// Reproduce: automático al alcanzar la meta de caché, o forzado por el usuario.
  void _finishPreBuffer() {
    _preBufferTimer?.cancel();
    _preBufferClock.stop();
    _preBufferTooSlow = false; // sale del pre-buffer: limpiar el estado terminal
    _tooSlowStreak = 0;
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
    // Handoff a la TV: tras enviar el contenido a la TV, `_initializePlayer`
    // retorna sin abrir el stream local, así que `isLoading` se queda en true.
    // El cierre de esta pantalla lo dispara `_onGateSendToTv` con un maybePop
    // best-effort; si ese pop se salta (`!mounted`) o corre una carrera, el
    // player quedaría montado con un SPINNER ETERNO mientras la TV ya
    // reproduce. En ese caso mostramos un estado de casting en vez del spinner.
    if (_cast?.isCasting ?? false) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cast_connected, color: Color(0xFFD2603A), size: 52),
              const SizedBox(height: 18),
              Text(
                loc?.cast_playing_on ?? 'Reproduciendo en la TV',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: AppThemes.tenFoot(context, 16),
                ),
              ),
            ],
          ),
        ),
      );
    }
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

  /// Overlay de "atascado": VOD/serie que se queda en buffering sin arrancar
  /// nunca (cuelgue silencioso). El watchdog `_vodStuckTimer` lo activa tras
  /// ~12s; repone el botón Reintentar (que antes solo vivía dentro del indicador
  /// de carga y desaparecía al terminar la init). Se auto-oculta al reproducir.
  Widget _buildStuckRetry(BuildContext context) {
    final loc = AppLocalizations.of(context);
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
              'Está tardando más de lo normal. Puede que no se logre abrir el '
              'stream.',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: () {
                setState(() => _stuckBuffering = false);
                _retryPlayback();
              },
              icon: const Icon(Icons.refresh),
              label: Text(
                loc?.cast_retry ?? 'Reintentar',
                style: TextStyle(fontSize: AppThemes.tenFoot(context, 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreBuffer(BuildContext context) {
    if (!_preBuffering || _preBuffer == null) return const SizedBox.shrink();
    final loc = context.loc;
    // Estado TERMINAL (hallazgo de QA): el techo se agotó con el buffer vacío /
    // reads colgados. En vez del overlay pegado con métricas congeladas, una
    // tarjeta clara con Reintentar (y "Reproducir ahora" como acción secundaria).
    if (_preBufferTooSlow) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.92),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: Colors.redAccent, size: 46),
                const SizedBox(height: 16),
                Text(
                  loc.prebuffer_too_slow,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: AppThemes.tenFoot(context, 17),
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(
                    autofocus: ResponsiveHelper.isTelevisionDevice,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD2603A),
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: () {
                      // Reintentar: limpiar el pre-buffer y reabrir el stream.
                      setState(() {
                        _preBufferTooSlow = false;
                        _preBuffering = false;
                      });
                      _retryPlayback();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(loc.cast_retry),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 260,
                  child: TextButton(
                    // Secundario: reproducir igual (acepta el riesgo de arrancar
                    // sin colchón). Usa el mismo _finishPreBuffer de siempre.
                    onPressed: _finishPreBuffer,
                    child: Text(loc.prebuffer_play_now,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
    // Catch-up/timeshift NO es casteable: su URL de archivo (overrideUrl) no
    // viaja por CastMedia, así que la TV reconstruiría una URL VOD desde el id
    // del canal live → contenido equivocado/404; y el historial de cast lo
    // persistiría en "Continuar viendo" (URL que caduca). Se queda en el móvil.
    if (contentItem.isCatchup) return false;
    // Reproducción LOCAL/offline (descargas): su url es una ruta del sistema de
    // archivos, no http/https. No gasta datos y castear un archivo local es una
    // acción explícita aparte, así que el gate pre-reproducción solo es fricción
    // → suprimirlo. Mismo criterio de "archivo local" que usa _recastToTv.
    if (!contentItem.url.startsWith('http')) return false;
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
    // Catch-up nunca se reenvía a la TV (ver _needsCastGate): la TV no puede
    // reconstruir la URL de archivo. Se reproduce localmente aunque haya sesión.
    if (contentItem.isCatchup) return null;
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
    // Solo un stream normal lleva ficha TMDb; el archivo local no. Resolver
    // (acotado) antes del re-LOAD para que el meta viaje si está disponible.
    if (!isLocalFile) {
      await _ensureCastMeta();
      await _ensureCastSeriesId();
    }
    // Serie descargada abierta mientras se castea: arma la cola de episodios
    // hermanos descargados para que el re-LOAD también auto-avance en la TV.
    (List<CastMedia>?, int) localQueue = (null, 0);
    if (isLocalFile) {
      final row = await DownloadService.instance.findByContentId(contentItem.id);
      if (row != null) localQueue = await buildDownloadedSeriesQueue(row);
    }
    bool ok;
    try {
      ok = isLocalFile
          ? await cast.castNextLocalFile(
              filePath: url,
              contentId: contentItem.id,
              title: contentItem.name,
              ext: contentItem.containerExtension ?? '',
              imagePath: contentItem.imagePath,
              queue: localQueue.$1,
              index: localQueue.$2,
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
    _popAfterCastHandoff();
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
    // Asegurar (acotado) que el meta TMDb esté listo antes de armar el CastMedia,
    // para que el LOAD lo incluya. Ya se lanzó al activar el gate, así que aquí
    // normalmente ya resolvió y no añade espera.
    await _ensureCastMeta();
    // Resolver también el seriesId (BD, rápido) para que el LOAD de una serie
    // lleve el sid → la TV puede auto-avanzar sola por toda la serie.
    await _ensureCastSeriesId();
    if (!mounted) return; // el player pudo cerrarse durante la espera del meta
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
      _popAfterCastHandoff(showControls: true);
    }
  }

  /// Cierre PROGRAMÁTICO tras ceder la reproducción a la TV (handoff o recast).
  /// DEBE saltarse el guard de "confirmar salida con doble BACK" (el PopScope de
  /// Fix #10a: `canPop = !_anyOverlayOpen && _backExitArmed`): ese guard existe
  /// para el BACK del USUARIO, no para este cierre intencional. Con `maybePop()`
  /// el pop quedaba VETADO (_backExitArmed=false, el usuario nunca pulsó BACK) y
  /// el player se quedaba montado mostrando el fallback "Reproduciendo en" (sin
  /// nombre de TV ni controles), sin poder llegar a la CastingScreen (donde vive
  /// el volumen). `pop()` imperativo ignora `canPop`; `canPop()` del navigator
  /// evita reventar si el player fuese la ruta raíz.
  void _popAfterCastHandoff({bool showControls = false}) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    // Tras devolver a la navegación, abrir el panel de controles de la TV (el
    // mismo del mini-control: volumen, play/pausa, pistas, detener) para que el
    // usuario los tenga a mano justo después de enviar a la TV. Diferido al
    // siguiente frame para que el pop del player asiente antes de la hoja modal;
    // usa el navegador raíz (el context del player ya no sirve tras el pop).
    if (showControls) {
      final c = _cast;
      final ctx = appNavigatorKey.currentContext;
      if (c != null && ctx != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => openCastControls(ctx, c));
      }
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
    // Fix #10b: start clean so a stale one-shot flag from a previous player can't
    // swallow the first BACK of this one.
    PlayerState.overlayClosedByBack = false;
    // NOTA: en media_kit, PlayerConfiguration.bufferSize fija demuxer-max-bytes
    // /-back-bytes al CONSTRUIR (real.dart:2417-2418); _tuneForPerformance (justo
    // debajo) los sobrescribe con setProperty, que es lo autoritativo en régimen.
    // Este valor solo gobierna la ventana inicial: en VIVO se mantiene grande
    // (2× el default, señal débil en cajas de TV); en VOD se deja en el default
    // (32 MiB) para no reservar de más al abrir.
    final isLiveStream =
        widget.contentItem.contentType == ContentType.liveStream;
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: (isLiveStream ? 64 : 32) * 1024 * 1024,
      ),
    );
    _tuneForPerformance();
    watchHistoryService = WatchHistoryService();

    // Experimental DVR is opt-in and live-only; load the flag without blocking.
    if (contentItem.contentType == ContentType.liveStream) {
      UserPreferences.getDvrExperimental().then((on) {
        if (mounted && on) setState(() => _dvrEnabled = true);
      });
    }

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

    // Cast: el móvil movió el slider de volumen del sheet de control; aplicar
    // en el player receptor (la TV). Escala 0-100 (igual que UserPreferences).
    _castSetVolumeSubscription =
        EventBus().on<double>('cast_set_volume').listen((v) {
      _player.setVolume(v);
    });

    // Cast: el móvil arrastró el slider de scrub del sheet de control; saltar la
    // reproducción del receptor (la TV) a la posición absoluta que envía (ms).
    _castSeekSubscription = EventBus().on<int>('cast_seek').listen((ms) {
      // [GUARD RETADOR — crítico] Excluir vivo AQUÍ, no solo en la UI del emisor:
      // `_player.seek` sobre un stream en vivo lanza el error no-fatal
      // "Cannot seek … --force-seekable=yes". La UI ya oculta el slider en vivo,
      // pero este guard es la defensa real (un emisor viejo/otra ruta podría
      // emitir igual).
      if (widget.contentItem.contentType == ContentType.liveStream) return;
      // Clampa el ms entrante a [0, dur-1s] ANTES de saltar — replica la
      // protección de _seekBy (~:_seekBy): (a) descarta un objetivo fuera de rango
      // (consistente con el clamp de setVolume) y (b) tapa 1s antes del final para
      // NO aterrizar EXACTO en EOF, que carrearía con `completed`/auto-avance de
      // serie. Con duración desconocida (0, aún sin metadatos) solo se garantiza
      // >= 0 (no hay tope superior fiable).
      final durMs = _player.state.duration.inMilliseconds;
      var target = ms < 0 ? 0 : ms;
      if (durMs > 0) {
        final capMs = durMs > 1000 ? durMs - 1000 : durMs;
        if (target > capMs) target = capMs;
      }
      _pendingSeekTarget = Duration(milliseconds: target);
      // Reusar EXACTAMENTE la ruta del seek local: confirmar con `resume` según el
      // estado ACTUAL de reproducción — un scrub NO debe des-pausar la TV (si el
      // usuario la había pausado, sigue pausada tras el salto). Así _commitSeek
      // activa la gracia (`_seekInProgress`) que impide que el re-buffer del salto
      // levante el panel de pausa, hace el seek y reinicia la línea base del
      // watchdog; solo reanuda con play() si ya estaba reproduciendo.
      _commitSeek(resume: _player.state.playing);
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

    // See the field doc on _periodicHistoryTimer: this is the safety net for
    // abrupt kills that bypass didChangeAppLifecycleState entirely. 20s keeps
    // the DB write cheap (one insertOnConflictUpdate per tick) while bounding
    // how much progress a truly-uncaught kill could lose. Live TV has no
    // meaningful "resume position" (getContinueWatching already excludes it
    // on read — see WatchHistory — this just avoids writing it at all).
    _periodicHistoryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      // Same min-position guard the lifecycle flush uses: never let the periodic
      // stamp a 0/near-0 position (e.g. a stuck/buffering open that only emitted
      // Duration.zero) over a good "Continuar viendo" resume.
      final pending = _pendingWatchDuration;
      if (contentItem.contentType != ContentType.liveStream &&
          pending != null &&
          pending >= _minMeaningfulPosition) {
        _saveWatchHistory();
      }
    });

    // Watchdog de AVANCE de posición en vivo (hallazgo de QA — ver el campo
    // [_liveWatchdogTimer]). Timer SEPARADO del de historial: cada 5s comprueba
    // si la posición del stream en vivo sigue avanzando. Es basado en POSICIÓN (no
    // en la señal `buffering`) porque un corte que excede el readahead resetea la
    // posición a 0 con `playing=true` y SIN emitir `buffering` (lo suprime
    // `cache-pause=no`), así que el `_stallTimer` clásico nunca lo ve.
    _liveWatchdogTimer =
        Timer.periodic(const Duration(seconds: 5), (_) {
      // Blindaje (auditor cond. 2): el timer puede sobrevivir un instante a la
      // liberación del player (detached / dispose) — nunca leer `_player.state`
      // sobre un player ya liberado ni actuar tras el unmount.
      if (_playerDisposed || !mounted) return;
      final ci = widget.contentItem;
      if (ci.contentType != ContentType.liveStream) return;
      // Estados en que una posición "quieta" es esperada y NO es un cuelgue:
      // pausa, seek en curso, cast comprometido, o un reopen ya en vuelo. Se
      // reinicia la línea base y se espera al próximo tick.
      if (!_player.state.playing ||
          _seekInProgress ||
          _pendingSeekTarget != null ||
          _castCommitted ||
          _reopenInProgress) {
        _resetLiveWatchdogBaseline();
        return;
      }
      final pos = _player.state.position.inMilliseconds;
      if (pos > _lastLivePosMs) {
        // Avanzó: todo bien, mover la línea base.
        _lastLivePosMs = pos;
        _lastLiveAdvanceAt = DateTime.now();
      } else if (_lastLiveAdvanceAt != null &&
          DateTime.now().difference(_lastLiveAdvanceAt!) >
              const Duration(seconds: 20)) {
        // >20s sin avanzar (incluye el reset-a-0, que NO es > lastPos): reabrir en
        // el borde en vivo. _reopenCurrent ya es seguro para live y reentrante.
        _reopenCurrent();
      }
    });
  }

  @override
  void dispose() {
    PlayerState.isPlayerActive = false;
    // Cancel timer and save watch history one last time before disposing
    WidgetsBinding.instance.removeObserver(this);
    _watchHistoryTimer?.cancel();
    _periodicHistoryTimer?.cancel();
    _liveWatchdogTimer?.cancel();
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
    _castSetVolumeSubscription?.cancel();
    _castSeekSubscription?.cancel();
    _seekHideTimer?.cancel();
    _seekCommitTimer?.cancel();
    _seekGraceTimer?.cancel();
    _vodStuckTimer?.cancel();
    _midPlayBufferTimer?.cancel();
    _backExitTimer?.cancel();
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
    _bufferHudTick.dispose();
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
    // Idem para el watchdog en vivo: sin esto podría hacer un tick contra el
    // player recién liberado (detached libera aquí sin pasar por dispose()).
    _liveWatchdogTimer?.cancel();
    // Finalize any in-flight DVR recording BEFORE freeing the native player:
    // stop() sets stream-record='' (flushing the file) and clears the service's
    // _activePath. Without this, closing the player mid-record would leave the
    // file unfinalized and the singleton stuck, disabling recording for the rest
    // of the process. Best-effort — never let it block teardown.
    if (DvrService.instance.isRecording) {
      try {
        await DvrService.instance.stop(_player);
      } catch (_) {}
    }
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
    // El salto cambia de episodio (el listener de playlist reinicia el prompt);
    // ocultarlo ya evita un frame con el prompt del episodio viejo.
    _showNextEpisodePrompt = false;
    // El seek acumulado (si lo hay) se descarta centralizadamente en la
    // suscripción a 'player_content_item_index_changed' (rama no-live), que cubre
    // este salto y el resto de emisores.
    EventBus()
        .emit('player_content_item_index_changed', _currentItemIndex + 1);
  }

  /// Ventana "últimos segundos" del episodio en la que se ofrece el salto
  /// anticipado al siguiente (prompt tipo Netflix).
  static const Duration _nextEpisodeLeadIn = Duration(seconds: 30);

  /// Muestra u oculta el prompt "Siguiente episodio" según la posición. Solo en
  /// el MÓVIL (nunca en la TV receptora, que auto-avanza + usa el panel de
  /// pausa), solo para una SERIE con un episodio siguiente REAL, una vez que la
  /// reproducción arrancó de verdad y no está re-buffereando, y únicamente en los
  /// últimos [_nextEpisodeLeadIn]. Hace setState SOLO al cruzar el umbral (no por
  /// tick) para no reconstruir el player en cada posición.
  void _maybeUpdateNextEpisodePrompt(Duration position, Duration duration) {
    final eligible = !ResponsiveHelper.isTelevisionDevice &&
        contentItem.contentType == ContentType.series &&
        _hasNextEpisode &&
        _hasStartedPlaying &&
        !_midPlayBuffering &&
        !_nextEpisodePromptDismissed &&
        duration > Duration.zero &&
        position > Duration.zero;
    final remaining = duration - position;
    final show = eligible &&
        remaining > Duration.zero &&
        remaining <= _nextEpisodeLeadIn;
    if (show != _showNextEpisodePrompt && mounted) {
      setState(() => _showNextEpisodePrompt = show);
    }
  }

  /// Acción del prompt "Siguiente episodio". Durante el casting gobierna la TV
  /// (política "casting manda"): reenvía el siguiente episodio a la TV en vez de
  /// saltar el player local. Sin casting, salta el episodio localmente.
  void _onNextEpisodePromptPressed() {
    final casting = _castingController();
    if (casting != null && casting.canCastNextEpisode) {
      unawaited(casting.castNextEpisode());
    } else {
      _skipToNextEpisode();
    }
    _nextEpisodePromptDismissed = true;
    if (mounted) setState(() => _showNextEpisodePrompt = false);
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

  /// Ancla de resume (ms) del ítem actual. Cuando quien monta el player trae un
  /// override [PlayerWidget.startPositionMs] (hoy SOLO el receptor de cast: le
  /// llega en el LOAD la posición REAL del móvil), ese valor es AUTORITATIVO y se
  /// usa TAL CUAL — NO se compara con el historial local de la TV. Si no, un
  /// rewatch o un cast previo que avanzó más dejaría en la TV un historial mayor
  /// para el mismo streamId y arrancaría cerca del final, ignorando el punto que
  /// envió el móvil. En reproducción normal el override es null → se usa el
  /// historial local (comportamiento de siempre). Un cast sin posición llega con
  /// override 0 (no null) → arranca desde el principio, como debe.
  int _resumeMsFor(WatchHistory? history) {
    final override = widget.startPositionMs;
    if (override != null) return override;
    return history?.watchDuration?.inMilliseconds ?? 0;
  }

  /// Posición de inicio (ms) para un episodio NO-actual de la cola. Si ya se vio
  /// prácticamente entero (≥95% del total), arranca en 0. Si no, al auto-avanzar
  /// media_kit haría seek cerca del final del episodio ya visto → `completed` al
  /// instante → lo salta y cascada al episodio equivocado. El ítem seleccionado
  /// NO usa esto (reanuda vía _resumeMsFor); el reopen ya pasa 0 a los no-actuales.
  int _queueStartMsFor(WatchHistory? history) {
    return queuedItemStartMs(
      history?.watchDuration?.inMilliseconds ?? 0,
      history?.totalDuration?.inMilliseconds ?? 0,
    );
  }

  Future<void> _saveWatchHistory({bool ignoreMounted = false}) async {
    // In dispose the State is already unmounted, so allow an explicit
    // ignoreMounted to still flush the final position.
    if (_pendingWatchDuration == null || (!mounted && !ignoreMounted)) return;
    // Catch-up/timeshift plays as a seekable VOD but is transient: its archive
    // URL expires with the provider's retention window, so never persist it to
    // "Continue watching" (a saved resume would 404 once the window passes).
    if (contentItem.isCatchup) return;
    // See the field doc on _savingHistory: a call already in flight wins: a
    // second, CONCURRENT call must not start (it would race the first's
    // still-pending null-out of _pendingWatchDuration below and double-save).
    if (_savingHistory) return;
    _savingHistory = true;

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
          // Los episodios del camino local no llevan seriesStream; usan el
          // seriesId propio del ContentItem (poblado desde las pantallas de
          // episodios) para vincular el historial a la serie. El cast standalone
          // sí inyecta seriesStream, que tiene prioridad.
          seriesId: contentItem.seriesStream?.seriesId ?? contentItem.seriesId,
          // Feature H — solo en un cast STANDALONE (widget.standaloneProviderId
          // no-null) se persisten estas dos columnas para el replay de fase 4;
          // en toda otra reproducción quedan null, como siempre.
          providerId: widget.standaloneProviderId,
          containerExtension: widget.standaloneProviderId != null
              ? contentItem.containerExtension
              : null,
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
    } finally {
      _savingHistory = false;
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
    // Guarda de reentrada (hallazgo de QA): varios caminos pueden llamar aquí a
    // la vez (stall-timer, error-handler, conectividad, retry, live-watchdog).
    // Sin esto se solaparían dos `_player.open()` sobre el mismo player. Se pone
    // true SOLO tras pasar las guardas de arriba (si retornáramos antes, el flag
    // quedaría atascado en true y bloquearía todo reopen futuro).
    if (_reopenInProgress) return;
    _reopenInProgress = true;
    try {
      // Live streams are not seekable: passing start:Duration.zero makes libmpv
      // attempt a seek-to-0 on reopen, which fires the non-fatal
      // "Cannot seek … --force-seekable=yes" error (triggered by the 15s stall
      // watchdog). Omit start entirely for live; VOD/series keep their resume.
      // VOD/series: reanudar desde la posición REAL del player (no
      // _pendingWatchDuration, que se pone a null tras cada guardado de historial
      // → reabría en 0 y "reiniciaba desde el principio"). Live no lleva start.
      final Duration? start = computeReopenStart(
        isLive: contentItem.contentType == ContentType.liveStream,
        livePos: _player.state.position,
        lastGood: _lastGoodPosition,
        pending: _pendingWatchDuration,
      );
      // Preserve a multi-item VOD queue: reopening a bare Media would collapse
      // the native Playlist to a single item and break jump/next for the rest of
      // the session. The current item's url is read live (it may have been
      // healed).
      if (_queue != null &&
          _queue!.length > 1 &&
          contentItem.contentType != ContentType.liveStream) {
        final medias = [
          for (var i = 0; i < _queue!.length; i++)
            Media(i == _currentItemIndex ? contentItem.url : _queue![i].url,
                start: i == _currentItemIndex ? start : Duration.zero),
        ];
        await _player
            .open(Playlist(medias, index: _currentItemIndex), play: true)
            // Timeout defensivo (auditor): un `open()` colgado NO debe dejar
            // `_reopenInProgress=true` atascado bloqueando toda recuperación
            // futura. En el caso normal (open rápido) es transparente.
            .timeout(const Duration(seconds: 12), onTimeout: () {});
      } else {
        await _player
            .open(Media(contentItem.url, start: start), play: true)
            .timeout(const Duration(seconds: 12), onTimeout: () {});
      }
    } finally {
      _reopenInProgress = false;
      // GRACIA tras el reopen: reiniciar la línea base del watchdog en vivo para
      // que espere ~20s frescos antes de poder volver a disparar (el stream nuevo
      // tarda un momento en arrancar y avanzar; sin esto se dispararía en bucle).
      _resetLiveWatchdogBaseline();
    }
  }

  /// Reinicia la línea base del watchdog de avance en vivo: la posición actual
  /// pasa a ser el último avance conocido y el reloj arranca de cero. Se llama al
  /// (re)abrir, al reanudar, al salir de un buffering legítimo, en cada seek y al
  /// cambiar de contenido — cualquier evento tras el cual una posición "quieta"
  /// es esperada y NO debe contar hacia el umbral de reopen.
  void _resetLiveWatchdogBaseline() {
    _lastLiveAdvanceAt = DateTime.now();
    _lastLivePosMs = _player.state.position.inMilliseconds;
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
    _preBufferTooSlow = false; // cualquier reintento limpia el estado terminal
    _tooSlowStreak = 0;
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
    // En DATOS MÓVILES no hay LAN donde pueda vivir un receptor, así que
    // preguntar "¿enviar a la TV?" es pura fricción (el descubrimiento fallaría
    // a los 4s con 'no_devices'): se suprime el prompt y se reproduce local.
    // Conservador: solo se salta cuando la red es EXCLUSIVAMENTE celular (ver
    // ConnectivityHelper), nunca en Wi‑Fi/Ethernet/VPN ni ante ambigüedad.
    final wantCastGate = _needsCastGate();
    final onCellularOnly =
        wantCastGate && await ConnectivityHelper.isCellularOnly();
    if (!mounted) return; // el widget pudo desmontarse durante el await de red
    if (wantCastGate && !onCellularOnly) {
      _castGateActive = true;
      setState(() {});
      // Resolver el meta TMDb en paralelo mientras el usuario decide/empareja:
      // así, si elige "Enviar a la TV", el LOAD ya lo lleva sin añadir latencia.
      _kickoffCastMeta();
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
              // Resume del ítem actual: el override AUTORITATIVO si viene (hoy el
              // receptor de cast, que recibe la posición del móvil en el LOAD),
              // si no el historial local. Para el resto de la cola, solo historial.
              'startPosition': item.id == contentItem.id
                  ? _resumeMsFor(itemWatchHistory)
                  : _queueStartMsFor(itemWatchHistory),
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
          'startPosition': _resumeMsFor(watchHistory),
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
            start: Duration(milliseconds: _resumeMsFor(watchHistory)),
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
        (x) => langMatchesPref(x.language, x.title, selectedAudioLanguage),
        orElse: AudioTrack.auto,
      );

      await _player.setAudioTrack(possibleAudioTrack);

      // Subtítulos APAGADOS por defecto: solo se enciende una pista si el usuario
      // eligió una explícitamente (ver chooseInitialSubtitle). Antes, sin
      // preferencia caía a SubtitleTrack.auto → subtítulos encendidos.
      final selectedSubtitleLanguage = await UserPreferences.getSubtitleTrack();
      await _player.setSubtitleTrack(
        chooseInitialSubtitle(event.subtitle, selectedSubtitleLanguage),
      );

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
      // Puente de casting: la TV receptora reenvía su volumen real al móvil
      // (eco para el slider del sheet de control). Mismo patrón que
      // 'cast_player_position' — solo emite en TV, donde tv_receiver_host
      // escucha; en móvil nadie consume el evento.
      if (ResponsiveHelper.isTelevisionDevice) {
        EventBus().emit('cast_player_volume', event);
      }
    });

    _player.stream.position.listen((position) {
      // Dismissal del pre-buffer / terminal "conexión demasiado lenta" por AVANCE
      // REAL de posición: si la posición progresa ~a tiempo de pared
      // (isRealPlaybackAdvance descarta seeks/resume), el vídeo reproduce DE
      // VERDAD → bajar el overlay, incluso si ya cayó en terminal (donde el timer
      // del pre-buffer se canceló y dejaba el aviso pegado sobre el vídeo — el bug
      // del receptor de cast). Un stream muerto (playing=true pero posición
      // congelada) NO dispara esto, así que conserva la terminal con Reintentar.
      if (_preBuffering || _preBufferTooSlow) {
        final now = DateTime.now();
        if (_lastAdvancePos != null &&
            _lastAdvanceWall != null &&
            isRealPlaybackAdvance(
              playing: _player.state.playing,
              dPos: position - _lastAdvancePos!,
              dWall: now.difference(_lastAdvanceWall!),
            )) {
          // Piso anti-flicker (igual que `minShown` del tick): en TV no bajar el
          // overlay "Preparando…" antes de 1.5s para que no parpadee. En TERMINAL
          // no aplica (ya pasaron ≥8s y se quiere que se vaya en cuanto reproduce).
          final minShown = !ResponsiveHelper.isTelevisionDevice ||
              _preBufferTooSlow ||
              _preBufferClock.elapsed >= const Duration(milliseconds: 1500);
          if (minShown) _finishPreBuffer();
        }
        _lastAdvancePos = position;
        _lastAdvanceWall = now;
      }

      // Asignaciones BARATAS por tick (sin objetos nuevos) → resume preciso.
      _pendingWatchDuration = position;
      _pendingTotalDuration = _player.state.duration;
      // Ancla de resume que sobrevive al vaciado de _pendingWatchDuration (ver
      // el campo): solo avanza con posiciones reales (>0), nunca se anula.
      if (position > Duration.zero) _lastGoodPosition = position;

      // Prompt "Siguiente episodio" (móvil): edge-triggered (solo setState al
      // cruzar el umbral de los últimos ~30s), barato por tick.
      _maybeUpdateNextEpisodePrompt(position, _player.state.duration);

      // Puente de casting: solo la TV receptora reenvía su posición al móvil
      // para alimentar "continuar viendo".
      if (ResponsiveHelper.isTelevisionDevice) {
        EventBus().emit('cast_player_position', {
          'pos': position.inMilliseconds,
          'dur': _player.state.duration.inMilliseconds,
        });
      }

      // PERF: lo que ASIGNA —un `Media` nuevo + recrear el `Timer` del debounce—
      // se throttlea a ~1 Hz. El stream de posición emite a varios Hz durante
      // TODA la reproducción; hacerlo por tick era churn de GC sostenido (pausas
      // que se sienten como microtironeos). Sin pérdida de precisión de resume:
      // `_pendingWatchDuration`/`_lastGoodPosition` se actualizan igual cada tick,
      // y `_reopenCurrent` reanuda vía `_lastGoodPosition`, NO vía
      // `medias[i].start` (que aquí solo se mantiene "fresco" por si acaso).
      final now = DateTime.now();
      if (_lastResumeSync == null ||
          now.difference(_lastResumeSync!) >= const Duration(seconds: 1)) {
        _lastResumeSync = now;
        // Keep the resume position fresh, but never index past the current
        // playlist length (guards against RangeError during open/reset).
        final medias = _player.state.playlist.medias;
        if (currentItemIndex >= 0 && currentItemIndex < medias.length) {
          medias[currentItemIndex] = Media(contentItem.url, start: position);
        }
        // Debounce: guarda el historial ~5s tras la última actualización.
        _watchHistoryTimer?.cancel();
        _watchHistoryTimer =
            Timer(const Duration(seconds: 5), () => _saveWatchHistory());
      }
    });

    // Keep the screen on while actually playing; release it on pause/stop so
    // we don't hold the wakelock in the background.
    _playingSubscription = _player.stream.playing.listen((playing) {
      // FIX-2: la TV receptora reenvía su estado play/pausa REAL al móvil (junto
      // al 'cast_player_position'), para que el emisor no lo tenga que INFERIR por
      // el avance de la posición (que en pausa se congela y no distingue bien).
      // Solo en TV: en el móvil nadie consume el evento.
      if (ResponsiveHelper.isTelevisionDevice) {
        EventBus().emit('cast_player_playing', playing);
      }
      if (playing) {
        WakelockPlus.enable();
        // Reanudó (p. ej. tras una pausa): reiniciar la línea base del watchdog en
        // vivo para no contar el tiempo pausado como "sin avanzar".
        _resetLiveWatchdogBaseline();
        // Arrancó de verdad: matar el watchdog de "buffering sin arrancar" y
        // quitar el overlay de Reintentar si estaba puesto.
        _hasStartedPlaying = true;
        _vodStuckTimer?.cancel();
        if (_stuckBuffering && mounted) {
          setState(() => _stuckBuffering = false);
        }
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
      _vodStuckTimer?.cancel();
      // Mid-play re-buffer indicator (Fix #5): show it only once the stream has
      // actually started (not during the initial load / pre-buffer / error, and
      // never for the never-started stuck case, which _vodStuckTimer owns). Also
      // NOT during a seek's transient re-buffer (that's the jump recomposing, not
      // a network stall) — same guards the pause panel uses.
      final midPlay = buffering &&
          _hasStartedPlaying &&
          !isLoading &&
          !_preBuffering &&
          !hasError &&
          !_seekInProgress &&
          _pendingSeekTarget == null;
      if (midPlay != _midPlayBuffering) {
        if (mounted) setState(() => _midPlayBuffering = midPlay);
        if (midPlay) {
          _startMidPlayBufferPoll();
        } else {
          _stopMidPlayBufferPoll();
        }
      }
      if (!buffering) {
        // Salió de un buffering legítimo: reiniciar la línea base del watchdog en
        // vivo (la posición pudo quedar quieta durante el re-buffer sin ser un
        // cuelgue de red).
        _resetLiveWatchdogBaseline();
        return;
      }
      final isLiveContent = contentItem.contentType == ContentType.liveStream;
      if (isLiveContent && contentItem.url.isNotEmpty) {
        _stallTimer = Timer(const Duration(seconds: 15), () {
          if (!mounted || _playerDisposed) return;
          if (_player.state.buffering) {
            _reopenCurrent();
          }
        });
      } else if (!isLiveContent) {
        // VOD/serie que se queda buffering SIN haber arrancado nunca: tras ~12s
        // exponer el botón Reintentar (no hay error que dispare la pantalla de
        // error, y la init ya puso isLoading=false). No aplica una vez que sí
        // reprodujo (_hasStartedPlaying) — eso es un stall a mitad, no un cuelgue.
        _vodStuckTimer = Timer(const Duration(seconds: 12), () {
          if (!mounted || _playerDisposed) return;
          // Cacheado POR DELANTE de la posición (≈ demuxer-cache-duration). OJO:
          // _player.state.buffer es demuxer-cache-TIME (timestamp absoluto), así
          // que en contenido reanudado (p. ej. min 20) salta a ~1200s aunque esté
          // colgado; hay que restar la posición para obtener la magnitud relativa.
          final bufferedAhead = _player.state.buffer - _player.state.position;
          if (_player.state.buffering &&
              !_player.state.playing &&
              !_hasStartedPlaying &&
              // ~nada por delante = apertura colgada, NO "lento pero descargando"
              // (un stream lento acumula buffer y no debe disparar el overlay).
              bufferedAhead < const Duration(seconds: 1) &&
              !hasError &&
              !isLoading) {
            setState(() => _stuckBuffering = true);
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
      // Rearmar el watchdog de "buffering sin arrancar" para el episodio nuevo:
      // sin esto, tras reproducir el episodio 1 quedaría desactivado y un
      // episodio 2 colgado no repondría el Reintentar.
      _hasStartedPlaying = false;
      // CRÍTICO (corrupción de datos): las anclas de resume son del episodio
      // SALIENTE. Sin resetearlas, una caída de red justo tras el auto-avance
      // haría que _reopenCurrent reanudara el episodio NUEVO en la posición del
      // ANTERIOR (p. ej. min 40 del ep1 → seek a 40min en ep2) y guardara esa
      // posición como historial del ep2. El nuevo episodio arranca en 0.
      _lastGoodPosition = null;
      _pendingWatchDuration = null;
      _lastResumeSync = null; // throttle "frío" para el nuevo episodio
      // Cambió el contenido: reiniciar la línea base del watchdog en vivo (no
      // arrastrar la posición del ítem saliente).
      _resetLiveWatchdogBaseline();
      // El prompt "Siguiente episodio" pertenecía al episodio SALIENTE: reinícialo
      // para el nuevo (vuelve a poder ofrecerse en sus últimos ~30s).
      _showNextEpisodePrompt = false;
      _nextEpisodePromptDismissed = false;

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

      // Reconstruir la UI del player al cambiar de episodio: refleja el prompt
      // "Siguiente episodio" ya reseteado arriba (si no, quedaría CONGELADO y
      // accionable sobre el episodio equivocado tras un auto-avance/EOF — la ruta
      // manual ya hace setState, esta faltaba) y actualiza la lista de canales si
      // está abierta. Un cambio de episodio es infrecuente → sin coste de rebuild.
      if (mounted) {
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

            // A live channel switch finalizes any in-flight DVR recording: it
            // belongs to the channel being left, and leaving stream-record set
            // would splice the new channel into the same file.
            if (DvrService.instance.isRecording) {
              await DvrService.instance.stop(_player);
              if (mounted) setState(() => _recording = false);
            }

            await _player.open(Playlist([Media(item.url)]), play: true);
            // Cambio de canal en vivo: reiniciar la línea base del watchdog para no
            // arrastrar la posición del canal anterior.
            _resetLiveWatchdogBaseline();
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

  /// Minimum position worth persisting as a resume point. Guards the two
  /// lifecycle-triggered saves below against stamping "Continuar viendo" with
  /// a near-zero position if the user backgrounds within the first couple of
  /// seconds of opening something — before this fix an abrupt background/kill
  /// saved nothing at all, so there was no such edge case to worry about.
  static const _minMeaningfulPosition = Duration(seconds: 5);

  /// Flush the resume position for [contentItem] RIGHT NOW, instead of
  /// waiting for whatever would normally trigger a save. Two paths currently
  /// do that, and an abrupt background/kill reaches neither:
  ///  - the position-stream debounce (_watchHistoryTimer), which only fires
  ///    once position ticks go quiet (e.g. on a manual pause) — during
  ///    uninterrupted playback each new tick re-arms it, so it never fires;
  ///  - State.dispose()'s final flush, which never runs on a task kill (the
  ///    engine tears down via AppLifecycleState.detached instead, which used
  ///    to call _disposePlayer() directly and skip the save entirely).
  /// ignoreMounted mirrors dispose()'s own flush: by the time `detached`
  /// fires the State may already be considered unmounted-adjacent, but the
  /// position we hold is still the right one to persist.
  Future<void> _flushWatchHistoryOnLifecycle() async {
    // Live TV has no meaningful resume position (see resumableFrom in
    // watch_history.dart, which already excludes it on read); don't let a
    // lifecycle event write one either.
    if (contentItem.contentType == ContentType.liveStream) return;
    final pending = _pendingWatchDuration;
    if (pending == null || pending < _minMeaningfulPosition) return;
    _watchHistoryTimer?.cancel();
    try {
      await _saveWatchHistory(ignoreMounted: true);
    } catch (_) {
      // Best-effort, same as the other lifecycle-adjacent saves.
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // Home button / task switcher / about to be backgrounded-then-killed:
        // persist the current resume point immediately. Root cause this
        // fixes — neither of the two normal save paths (see
        // _flushWatchHistoryOnLifecycle's doc) ever ran for an abrupt
        // background, so "Continuar viendo" silently kept whatever was saved
        // at the LAST pause/quiescence, or nothing at all for a movie played
        // start-to-interrupt without ever pausing.
        await _flushWatchHistoryOnLifecycle();
        break;
      case AppLifecycleState.detached:
        // Flush BEFORE tearing the player down. Previously this branch only
        // disposed the player and stopped the audio handler — never saved —
        // so a task kill that reached `detached` still lost the position.
        await _flushWatchHistoryOnLifecycle();
        // _flushWatchHistoryOnLifecycle already cancels _watchHistoryTimer;
        // the periodic safety-net timer isn't tied to dispose() on this path
        // (detached doesn't guarantee State.dispose() runs), so cancel it
        // explicitly — otherwise it can keep firing every 20s against an
        // already-disposed player/content if the engine survives detach.
        _periodicHistoryTimer?.cancel();
        _liveWatchdogTimer?.cancel();
        await _disposePlayer();
        _audioHandler.setPlayer(null);
        await _audioHandler.stop();
        break;
      default:
        break;
    }
  }


  /// Toggle the experimental DVR dump of the live stream currently playing.
  /// Best-effort: on start failure or an empty stop, tell the user plainly.
  Future<void> _toggleRecording() async {
    if (_dvrBusy) return; // ignore a re-tap while a start/stop is in flight
    _dvrBusy = true;
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    try {
      if (_recording) {
        final path = await DvrService.instance.stop(_player);
        if (!mounted) return;
        setState(() => _recording = false);
        messenger.showSnackBar(SnackBar(
          content: Text(path != null ? loc.dvr_saved : loc.dvr_failed),
        ));
      } else {
        final path = await DvrService.instance
            .start(_player, channelName: contentItem.name);
        if (!mounted) return;
        if (path == null) {
          messenger.showSnackBar(SnackBar(content: Text(loc.dvr_failed)));
          return;
        }
        setState(() => _recording = true);
        messenger.showSnackBar(SnackBar(content: Text(loc.dvr_recording)));
      }
    } finally {
      _dvrBusy = false;
    }
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
        // Perfil de caché diferenciado live/VOD (esto es lo AUTORITATIVO: pisa
        // los valores que bufferSize dejó en la construcción — ver nota arriba).
        // VIVO queda IGUAL que antes (señal débil en cajas de TV). En VOD el
        // TECHO de demuxer baja 128→64 MiB; pero lo que gobierna el consumo y el
        // BURST inicial es readahead-secs (abajo): mpv solo llena esos segundos,
        // acotado por este techo. 64 MiB deja holgura para VOD 4K de bitrate alto
        // (10s a ~50 Mbps ≈ 62 MB).
        await platform.setProperty(
            'demuxer-max-bytes', isLive ? '128MiB' : '64MiB');
        await platform.setProperty(
            'demuxer-max-back-bytes', isLive ? '32MiB' : '16MiB');
        // Colchón de lectura anticipada — la palanca REAL contra el arranque
        // lento: mpv descarga A TOPE para llenar estos segundos, así que en VOD
        // 20→10 ~halva el burst inicial que saturaba red/memoria. Vivo se
        // mantiene en 15s (era 5s; se subió para señal débil).
        await platform.setProperty(
            'demuxer-readahead-secs', isLive ? '15' : '10');
        // Don't freeze on brief IPTV network hiccups.
        await platform.setProperty('cache-pause', 'no');
        // AUTO-RECONEXIÓN de red (ffmpeg): si el stream HTTP se corta un instante
        // (señal débil), reconecta solo en vez de quedarse entrecortado o parar
        // (evita además el reopen que reinicia). Clave para conexiones malas.
        await platform.setProperty(
            'demuxer-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
                'reconnect_delay_max=5');
        // DESENTRELAZADO: mucho contenido IPTV es ENTRELAZADO (1080i/576i) y sin
        // desentrelazar se ve con microcortes/"peine" — justo el síntoma de
        // "algunos formatos cortan". mpv solo desentrelaza los frames MARCADOS
        // como entrelazados (respeta el flag de campo), así que el contenido
        // PROGRESIVO no se toca ni se suaviza. En su propio try para que, si el
        // build de libmpv no acepta el valor, no afecte a los ajustes de arriba.
        try {
          await platform.setProperty('deinterlace', 'yes');
        } catch (_) {}
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
      _lastSeekEscalationAt = now;
      _seekForward = forward;
      _seekWasPlaying = _player.state.playing || _seekInProgress;
      _pendingSeekTarget = _player.state.position;
    } else if (shouldEscalateSeek(
      level: _seekStreak,
      lastEscalation: _lastSeekEscalationAt,
      now: now,
      maxLevel: _maxSeekLevel,
      every: _seekEscalateEvery,
    )) {
      // Subir de nivel como mucho una vez cada ~750ms de mantener pulsado (no por
      // evento): así un KeyRepeat veloz no dispara el paso a su tope de golpe.
      _seekStreak++;
      _lastSeekEscalationAt = now;
    }
    final step = seekStepForLevel(_seekStreak);
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
    // La posición saltó por el seek: reiniciar la línea base del watchdog en vivo
    // para que el salto no cuente como avance ni como cuelgue.
    _resetLiveWatchdogBaseline();
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

    // Overlay "atascado" (VOD/serie que no arranca): es ADITIVO sobre el player,
    // así que el foco lo conserva _remoteFocusNode y el autofocus del botón es
    // no-op → interceptar OK aquí para que el mando pueda reintentar (si no,
    // quedaría visible pero inalcanzable en una caja de TV solo-mando).
    if (_stuckBuffering && isOkKey) {
      if (event is KeyUpEvent) {
        setState(() => _stuckBuffering = false);
        _retryPlayback();
      }
      return KeyEventResult.handled;
    }

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
        // BACK con el foco en el botón "Siguiente episodio": devolver el ring al
        // player y NO consumir, para que este BACK siga el mismo camino de salida
        // que cualquier otro (PopScope). Con la confirmación de salida (#10a) eso
        // significa que la salida del player SIEMPRE es doble-atrás — este BACK
        // arma la confirmación (primer toque) igual que desde el player, no sale
        // directo.
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
        // BACK consumed here (key path). If the platform ALSO fires a route pop
        // for the same press, byBack:true lets PopScope swallow it (Fix #10b).
        _closePlayerOverlays(byBack: true);
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
            ValueListenableBuilder<int>(
              valueListenable: _bufferHudTick,
              builder: (_, __, ___) => _buildPreBuffer(context),
            ),
            // Atascado (VOD/serie que no arranca): repone el Reintentar.
            if (_stuckBuffering && !isLoading && !hasError)
              Positioned.fill(child: _buildStuckRetry(context)),
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
            ValueListenableBuilder<int>(
              valueListenable: _bufferHudTick,
              builder: (_, __, ___) => _buildPreBuffer(context),
            ),
            // Atascado (VOD/serie que no arranca): repone el Reintentar.
            if (_stuckBuffering && !isLoading && !hasError)
              Positioned.fill(child: _buildStuckRetry(context)),
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
      // And leaving the player (no overlay open) needs a CONFIRMING second BACK
      // within ~3s (Fix #10a): only once armed does canPop allow the pop.
      canPop: !_anyOverlayOpen && _backExitArmed,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Priority: an open overlay eats BACK to close, never exits. THIS pop is
        // the close, so consume the one-shot flag too (no trailing pop follows a
        // pop we handled here → don't let it leak to the next BACK).
        if (_anyOverlayOpen) {
          _closePlayerOverlays();
          PlayerState.overlayClosedByBack = false;
          return;
        }
        // Fix #10b: an overlay (channel list / settings / info) may have JUST
        // closed on THIS same BACK via its own key handler (which set the flag),
        // while the platform ALSO delivered the route-level pop. Consume the
        // one-shot flag to swallow that trailing pop — do NOT leave the player.
        if (PlayerState.overlayClosedByBack) {
          PlayerState.overlayClosedByBack = false;
          return;
        }
        // No overlay: first BACK arms the exit + shows a brief hint; the second
        // BACK within the window flips canPop true and actually leaves.
        _armBackToExit();
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

  /// Primer BACK para salir (Fix #10a): arma la salida y muestra un aviso breve;
  /// el segundo BACK dentro de la ventana (canPop pasa a true) sale de verdad. A
  /// los ~3s se desarma solo. No aplica cuando hay un overlay abierto (ese BACK
  /// lo cierra) — este método solo se llama sin overlays.
  void _armBackToExit() {
    if (_backExitArmed) return; // ya armado → el pop real ya está permitido
    // maybeOf (null-safe): si no hay Scaffold/Messenger en el árbol, NO se ve el
    // aviso, pero igual se arma la salida — así el usuario nunca queda atrapado
    // sin poder salir; el segundo BACK sale de todos modos (a lo sumo pierde la
    // pista visual). En la app real el player siempre vive bajo un Scaffold.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.loc.player_exit_press_back_again),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    setState(() => _backExitArmed = true);
    _backExitTimer?.cancel();
    _backExitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _backExitArmed = false);
    });
  }

  /// Close every player overlay (internal Stack panels + the button widgets'
  /// own root OverlayEntries via the EventBus toggles). [byBack] true when this
  /// close is driven by a BACK press whose trailing route pop must be swallowed
  /// (Fix #10b — covers the CHANNEL LIST too, which closes through here).
  void _closePlayerOverlays({bool byBack = false}) {
    if (byBack) PlayerState.overlayClosedByBack = true;
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
      // El cambio de contenido por swipe vertical táctil se eliminó a propósito
      // (chocaba con el gesto del sistema para mostrar la barra de Android y con
      // el gesto de brillo/volumen de media_kit). La navegación por mando/teclado
      // sigue vía _handleRemoteKey → _changeChannel; el prompt "Siguiente
      // episodio" cubre el salto anticipado en móvil.
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

          // Experimental DVR: record-while-watching a live channel (opt-in flag).
          if (_dvrEnabled &&
              contentItem.contentType == ContentType.liveStream)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: _toggleRecording,
                tooltip: _recording ? context.loc.dvr_stop : context.loc.dvr_record,
                icon: Icon(
                  _recording
                      ? Icons.stop_circle
                      : Icons.fiber_manual_record,
                  color: _recording ? Colors.red : Colors.white,
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
              // Metadatos TMDb que envió el móvil (la TV no tiene clave). Null en
              // reproducción local → el panel cae a TmdbEnrichment como hoy.
              sentMeta: widget.castMeta,
            ),

          // Transient seek progress bar (D-pad ±10s feedback).
          _buildSeekOverlay(),

          // Mid-play re-buffer indicator (Fix #5): a small informative overlay
          // when a stream that ALREADY started playing stalls to re-buffer —
          // distinct from the initial pre-buffer panel and from the
          // never-started stuck watchdog. Auto-hides when buffering clears.
          ValueListenableBuilder<int>(
            valueListenable: _bufferHudTick,
            builder: (_, __, ___) => PlayerBufferingIndicator(
              visible: _midPlayBuffering,
              bufferedSecs: _midPlayBufferedSecs,
              speedBps: _midPlaySpeedBps,
              label: context.loc.prebuffer_preparing,
            ),
          ),

          // Transient TV hint: "Hold OK for audio & subtitles".
          _buildOkHintOverlay(context),

          // "Siguiente episodio" prompt (móvil): en los últimos ~30s de un
          // episodio de serie con un siguiente en la cola. NO auto-reproduce
          // (media_kit ya lo hace al EOF): es un salto anticipado manual, o —
          // si se está casteando— el envío del siguiente episodio a la TV.
          if (_showNextEpisodePrompt) _buildNextEpisodePrompt(context),

        ],
      ),
    );
  }

  Widget _buildNextEpisodePrompt(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 28,
      child: Material(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(10)),
              onTap: _onNextEpisodePromptPressed,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.skip_next, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      context.loc.next_episode,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            // Descartar el prompt para este episodio (no reaparece hasta el
            // siguiente cambio de episodio).
            InkWell(
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(10)),
              onTap: () {
                _nextEpisodePromptDismissed = true;
                if (mounted) setState(() => _showNextEpisodePrompt = false);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ),
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

// --- Pure, testable helpers (top-level so tests can exercise them without a
// real Player). Extracted from the state for Fix #6 (seek ramp) and Fix #8
// (subtitles-off default). ---

// Tolerant language match so a saved preference like "spa" picks up tracks
// labelled spa / es / spanish / castellano / latino, etc.
const Map<String, List<String>> _kLangSynonyms = {
  'spa': ['spa', 'es', 'esp', 'spanish', 'castellano', 'español', 'lat', 'latino'],
  'eng': ['eng', 'en', 'english', 'ingles', 'inglés'],
  'por': ['por', 'pt', 'portugu'],
  'fra': ['fra', 'fre', 'fr', 'french', 'franc'],
  'ita': ['ita', 'it', 'italian'],
  'deu': ['deu', 'ger', 'de', 'german', 'aleman'],
};

@visibleForTesting
bool langMatchesPref(String? lang, String? title, String pref) {
  if (pref == 'auto' || pref.isEmpty) return false;
  final hay = '${lang ?? ''} ${title ?? ''}'.toLowerCase();
  final syns = _kLangSynonyms[pref] ?? [pref.toLowerCase()];
  return syns.any((s) => hay.contains(s));
}

/// Initial subtitle track for a saved preference. Default OFF: only enable a
/// track when the user chose one EXPLICITLY (a real language preference). No
/// preference ('auto'/'null'/empty) or an explicit 'off' → off; and an explicit
/// preference that matches no available track also stays off (never auto-on).
@visibleForTesting
SubtitleTrack chooseInitialSubtitle(List<SubtitleTrack> subtitles, String pref) {
  if (pref == 'off' || pref == 'auto' || pref == 'null' || pref.isEmpty) {
    return SubtitleTrack.no();
  }
  return subtitles.firstWhere(
    (x) => langMatchesPref(x.language, x.title, pref),
    orElse: SubtitleTrack.no,
  );
}

/// Resume anchor for reopening a stream (reconnect / stall watchdog / error
/// retry). Live restarts from the live edge (null → no `start:`). For VOD/series
/// prefer the player's live position; but a network drop can reset it to 0 right
/// after a history save nulled [pending] — so fall back to [lastGood] (the last
/// real position, never nulled) before giving up to zero (Fix #4).
@visibleForTesting
Duration? computeReopenStart({
  required bool isLive,
  required Duration livePos,
  Duration? lastGood,
  Duration? pending,
}) {
  if (isLive) return null;
  if (livePos > Duration.zero) return livePos;
  return lastGood ?? pending ?? Duration.zero;
}

/// Seek step by escalation LEVEL (0..N): starts fine (10s) and ramps gently to a
/// moderate cap (60s) — never to high minutes, so holding the arrow accelerates
/// controllably without racing past the end.
@visibleForTesting
Duration seekStepForLevel(int level) {
  switch (level) {
    case 0:
      return const Duration(seconds: 10);
    case 1:
      return const Duration(seconds: 30);
    default:
      return const Duration(seconds: 60);
  }
}

/// Whether the seek step should escalate one level. Throttled by TIME (not per
/// key event) so a fast KeyRepeat can't rocket the step to its cap: at most one
/// level per [every] of holding, capped at [maxLevel].
@visibleForTesting
bool shouldEscalateSeek({
  required int level,
  required DateTime? lastEscalation,
  required DateTime now,
  int maxLevel = 2,
  Duration every = const Duration(milliseconds: 750),
}) {
  if (level >= maxLevel) return false;
  return lastEscalation == null || now.difference(lastEscalation) >= every;
}

/// Small informative mid-play re-buffer indicator (Fix #5). A pill with a
/// spinner, a localized label ("Loading…") and the buffered seconds / download
/// speed — shown while a stream that already started stalls to re-buffer, so the
/// viewer sees progress instead of media_kit's bare circle. Stateless + public
/// so its visibility contract is unit-testable without a real Player.
class PlayerBufferingIndicator extends StatelessWidget {
  const PlayerBufferingIndicator({
    super.key,
    required this.visible,
    required this.label,
    this.bufferedSecs = 0,
    this.speedBps = 0,
  });

  final bool visible;
  final String label;
  final double bufferedSecs;
  final double speedBps;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final speedMbps = speedBps / (1024 * 1024);
    return Positioned(
      left: 0,
      right: 0,
      top: 24,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFD2603A),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (bufferedSecs > 0 || speedMbps > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${bufferedSecs.toStringAsFixed(0)}s · '
                    '${speedMbps.toStringAsFixed(2)} MB/s',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: AppThemes.tenFoot(context, 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
