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
import 'package:rensi_iptv/widgets/channel_number_overlay.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/utils/subtitle_configuration.dart';
import 'package:rensi_iptv/widgets/video_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/content_type.dart';
import '../../services/player_state.dart';
import '../../services/service_locator.dart';
import '../../utils/audio_handler.dart';
import '../utils/player_error_handler.dart';

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
  late StreamSubscription contentItemIndexChangedSubscription;
  late StreamSubscription _connectivitySubscription;

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
  Timer? _watchHistoryTimer;
  Duration? _pendingWatchDuration;
  Duration? _pendingTotalDuration;
  final FocusNode _remoteFocusNode = FocusNode(debugLabel: 'PlayerRemote');
  StreamSubscription<int?>? _pipWidthSubscription;
  StreamSubscription<int?>? _pipHeightSubscription;
  int? _lastVideoWidth;
  int? _lastVideoHeight;
  StreamSubscription<void>? _sleepTimerSubscription;
  final ChannelNumberBuffer _channelBuffer = ChannelNumberBuffer();
  StreamSubscription<int>? _channelBufferSubscription;

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
    _player = Player(configuration: PlayerConfiguration());
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
    if (_pendingWatchDuration != null) {
      // Use unawaited to save without blocking dispose
      _saveWatchHistory().catchError((e) {
        // Ignore errors during dispose
      });
    }

    _player.dispose();
    _audioHandler.setPlayer(null);
    _audioHandler.stop();
    videoTrackSubscription.cancel();
    audioTrackSubscription.cancel();
    subtitleTrackSubscription.cancel();
    _externalSubUriSubscription?.cancel();
    _externalSubDataSubscription?.cancel();
    _playbackSpeedSubscription?.cancel();
    _seekHideTimer?.cancel();
    contentItemIndexChangedSubscription.cancel();
    _connectivitySubscription.cancel();
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
    super.dispose();
  }

  void _jumpToChannel(int oneBasedIndex) {
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

  Future<void> _saveWatchHistory() async {
    if (_pendingWatchDuration == null || !mounted) return;

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
      print('Error saving watch history: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;

    PlayerState.subtitleConfiguration = await getSubtitleConfiguration();

    PlayerState.backgroundPlay = await UserPreferences.getBackgroundPlay();
    _audioHandler.setPlayer(_player);
    _videoController = VideoController(_player);

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
        if (_wasDisconnected &&
            contentItem.contentType == ContentType.liveStream &&
            contentItem.url.isNotEmpty) {
          try {
            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Online", style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.green,
              ),
            );

            // TODO: Implement watch history duration for vod and series
            await _player.open(Media(contentItem.url));
          } catch (e) {
            print('Error opening media: $e');
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
      _player.state.playlist.medias[currentItemIndex] = Media(
        contentItem.url,
        start: position,
      );

      // Debounce: Save watch history every 5 seconds instead of on every position update
      _pendingWatchDuration = position;
      _pendingTotalDuration = _player.state.duration;

      _watchHistoryTimer?.cancel();
      _watchHistoryTimer = Timer(const Duration(seconds: 5), () {
        _saveWatchHistory();
      });
    });

    _player.stream.error.listen((error) async {
      print('PLAYER ERROR -> $error');
      if (error.contains('Failed to open')) {
        _errorHandler.handleError(
          error,
          () async {
            if (contentItem.contentType == ContentType.liveStream) {
              await _player.open(Media(contentItem.url));
            }
          },
          (errorMessage) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                duration: Duration(seconds: 3),
              ),
            );
          },
        );
      }
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

    // Kanal listesi göster/gizle event'i
    EventBus().on<bool>('toggle_channel_list').listen((bool show) {
      if (mounted) {
        setState(() {
          _showChannelList = show;
          PlayerState.showChannelList = show;
        });
      }
    });

    // Video bilgisi göster/gizle event'i
    EventBus().on<bool>('toggle_video_info').listen((bool show) {
      if (mounted) {
        setState(() {
          PlayerState.showVideoInfo = show;
        });
      }
    });

    // Video ayarları göster/gizle event'i
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
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        await _player.dispose();
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

    final newIndex = _currentItemIndex + direction;
    if (newIndex < 0 || newIndex >= _queue!.length) return;

    EventBus().emit('player_content_item_index_changed', newIndex);
  }

  // Android TV / D-pad / keyboard handler. Returns handled when the key is
  // consumed so it does not propagate to media_kit's own bindings.
  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
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
        EventBus().emit('toggle_channel_list', !_showChannelList);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Channel list is open: let arrow keys traverse the list itself.
    if (_showChannelList) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        EventBus().emit('toggle_channel_list', false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Play / pause
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
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

  Widget _buildChannelListOverlay(BuildContext context) {
    final items = _queue!;
    final currentContent = PlayerState.currentContent;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    // Mevcut index'i bul
    int selectedIndex = _currentItemIndex;
    if (currentContent != null) {
      final foundIndex = items.indexWhere(
        (item) => item.id == currentContent.id,
      );
      if (foundIndex != -1) {
        selectedIndex = foundIndex;
      }
    }

    String overlayTitle = 'Kanal Seç';
    if (currentContent?.contentType == ContentType.vod) {
      overlayTitle = 'Filmler';
    } else if (currentContent?.contentType == ContentType.series) {
      overlayTitle = 'Bölümler';
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
                                fontSize: 18,
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
                    // Channel list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = index == selectedIndex;

                          return _buildChannelListItem(
                            context,
                            item,
                            index,
                            isSelected,
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

  Widget _buildChannelListItem(
    BuildContext context,
    ContentItem item,
    int index,
    bool isSelected,
  ) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
      autofocus: isSelected,
      onTap: () {
        EventBus().emit('player_content_item_index_changed', index);
        // Panel kapanmasın, sadece kanal değişsin
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
    switch (contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}s ${minutes}dk';
    } else {
      return '${minutes}dk';
    }
  }

  String _getContentTypeDisplayName() {
    switch (widget.contentItem.contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
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

    return Container(
      color: Colors.black,
      child: isFullScreen ? playerWidget : Column(children: [playerWidget]),
    );
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

          // Channel-number entry overlay (TV remote).
          ChannelNumberOverlay(buffer: _channelBuffer.buffer),

          // Transient seek progress bar (D-pad ±10s feedback).
          _buildSeekOverlay(),
        ],
      ),
      ),
    );
  }
}
