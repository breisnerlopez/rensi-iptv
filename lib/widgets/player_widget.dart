import 'dart:async';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/channel_number_buffer.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/pip_service.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/channel_order.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/widgets/channel_number_overlay.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_info_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_settings_widget.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
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
  Duration? _seekPos;
  Duration? _seekDur;
  Timer? _seekHideTimer;
  // Nullable (not `late`): they're assigned inside the async _initializePlayer,
  // so a fast BACK before init finishes must not crash dispose().
  StreamSubscription? contentItemIndexChangedSubscription;
  StreamSubscription? _connectivitySubscription;

  late Player _player;
  VideoController? _videoController;
  late WatchHistoryService watchHistoryService;
  final MyAudioHandler _audioHandler = getIt<MyAudioHandler>();
  List<ContentItem>? _queue;
  late ContentItem contentItem;
  final PlayerErrorHandler _errorHandler = PlayerErrorHandler();

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

    _initializePlayer();
  }

  @override
  void dispose() {
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
    _seekHideTimer?.cancel();
    contentItemIndexChangedSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _errorHandler.reset();
    _remoteFocusNode.dispose();
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
      _pendingWatchDuration = null;
      _pendingTotalDuration = null;
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
    final start = contentItem.contentType == ContentType.liveStream
        ? Duration.zero
        : (_pendingWatchDuration ?? Duration.zero);
    await _player.open(Media(contentItem.url, start: start), play: true);
  }

  /// User-triggered retry from the error screen.
  void _retryPlayback() {
    _errorHandler.reset();
    if (mounted) {
      setState(() {
        hasError = false;
        isLoading = true;
      });
    }
    _reopenCurrent().whenComplete(() {
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

    PlayerState.subtitleConfiguration = await getSubtitleConfiguration();

    PlayerState.backgroundPlay = await UserPreferences.getBackgroundPlay();
    _audioHandler.setPlayer(_player);
    final decoderMode = await UserPreferences.getVideoDecoder();
    _videoController = _createVideoController(decoderMode);

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

    var watchHistory = await watchHistoryService.getWatchHistory(
      AppState.currentPlaylist!.id,
      isXtreamCode ? contentItem.id : contentItem.m3uItem?.id ?? contentItem.id,
    );

    List<MediaItem> mediaItems = [];
    var currentItemIndex = 0;

    if (_queue != null) {
      for (int i = 0; i < _queue!.length; i++) {
        final item = _queue![i];
        final itemWatchHistory = await watchHistoryService.getWatchHistory(
          AppState.currentPlaylist!.id,
          isXtreamCode ? item.id : item.m3uItem?.id ?? item.id,
        );

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

      await _audioHandler.setQueue(mediaItems, initialIndex: currentItemIndex);

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

      await _audioHandler.setQueue([mediaItem]);

      await _player.open(
        Playlist([
          Media(
            contentItem.url,
            start: watchHistory?.watchDuration ?? Duration(),
          ),
        ]),
        play: true,
      );
    }

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
        final currentConnectivity = await Connectivity().checkConnectivity();
        hasConnection = currentConnectivity.any(
          (connectivity) =>
              connectivity == ConnectivityResult.mobile ||
              connectivity == ConnectivityResult.wifi ||
              connectivity == ConnectivityResult.ethernet,
        );
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

            // Reconnect: live restarts from the edge; VOD/series resume from
            // the last saved position.
            await _reopenCurrent();
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
      } else {
        WakelockPlus.disable();
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
      );
    });

    _player.stream.playlist.listen((playlist) {
      if (!mounted) return;

      if (contentItem.contentType == ContentType.liveStream) {
        return;
      }

      _currentItemIndex = playlist.index;
      currentItemIndex = _currentItemIndex;
      contentItem = _queue?[playlist.index] ?? widget.contentItem;

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

    _player.stream.completed.listen((playlist) async {
      if (contentItem.contentType == ContentType.liveStream) {
        await _player.open(Media(contentItem.url));
      }
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) async {
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
        await platform.setProperty('demuxer-max-bytes', '64MiB');
        await platform.setProperty('demuxer-max-back-bytes', '32MiB');
        // High readahead smooths VOD jitter; keep it low on live to reduce
        // zap latency and RAM.
        await platform.setProperty(
            'demuxer-readahead-secs', isLive ? '5' : '20');
        // Don't freeze on brief IPTV network hiccups.
        await platform.setProperty('cache-pause', 'no');
      } catch (_) {
        // Best-effort; defaults are fine if a property is unsupported.
      }
    }
  }

  void _showSeekFeedback(Duration pos, Duration dur) {
    _seekHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _seekPos = pos;
        _seekDur = dur;
      });
    }
    _seekHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _seekPos = null);
    });
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _buildSeekOverlay() {
    final pos = _seekPos, dur = _seekDur;
    if (pos == null || dur == null || dur.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }
    final progress = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
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
          child: Row(
            children: [
              Text(_fmtDur(pos),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

    // OK/center: SHORT press = play/pause; LONG press (≈450ms) = open the player
    // options panel (audio/subtitles). On a basic Android TV remote this is the
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
        if (!wasHold) _player.playOrPause();
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
      _player.playOrPause();
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

    // Seek (for VOD / non-live content). Live streams ignore seek calls.
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaStepForward) {
      if (!isLive) {
        final pos = _player.state.position;
        final dur = _player.state.duration;
        final target = pos + const Duration(seconds: 10);
        final clamped = target > dur ? dur : target;
        _player.seek(clamped);
        _showSeekFeedback(clamped, dur);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaStepBackward) {
      if (!isLive) {
        final pos = _player.state.position;
        final dur = _player.state.duration;
        final target = pos - const Duration(seconds: 10);
        final clamped = target < Duration.zero ? Duration.zero : target;
        _player.seek(clamped);
        _showSeekFeedback(clamped, dur);
      }
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
                              fontSize: 12,
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
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
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
                      fontSize: 13,
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
                            fontSize: 11,
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
        child: isLoading
            ? Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildPlayerContent(),
      );
    } else {
      // Diğer içerikler için aspect ratio kullan
      playerWidget = AspectRatio(
        aspectRatio: calculateAspectRatio(),
        child: isLoading
            ? Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildPlayerContent(),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // Focusable so the D-pad can reach it on Android TV.
            ElevatedButton.icon(
              autofocus: true,
              onPressed: _retryPlayback,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
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
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppThemes.labelSize,
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
