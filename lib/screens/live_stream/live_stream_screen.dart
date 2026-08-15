import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../utils/get_playlist_type.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';
import '../../../widgets/playlist_states.dart';

class LiveStreamScreen extends StatefulWidget {
  final ContentItem content;

  const LiveStreamScreen({super.key, required this.content});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  late ContentItem contentItem;
  List<ContentItem> allContents = [];
  bool allContentsLoaded = false;
  int selectedContentItemIndex = 0;
  // Nullable, NOT `late`: it is only assigned after the async fetch below. If
  // that fetch throws (or the widget is disposed before it completes), dispose
  // would call `.cancel()` on an unassigned `late` field → LateInitializationError.
  StreamSubscription<int>? contentItemIndexChangedSubscription;
  // Set when the category fetch fails (panel offline / creds expired / no net).
  // While non-null we show a retry state instead of an infinite spinner.
  String? _loadError;
  // Reentrancy guard: a double-tap on "Reintentar" must not run two concurrent
  // _initializeQueue() (the 2nd would leak/overwrite the subscription).
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    contentItem = widget.content;
    _hideSystemUI();
    _initializeQueue();
  }

  Future<void> _initializeQueue() async {
    if (_initializing) return;
    _initializing = true;
    try {
    List<ContentItem> loaded;
    try {
      if (isXtreamCode) {
        final repo = AppState.xtreamCodeRepository;
        final live = widget.content.liveStream;
        if (repo == null || live == null) {
          throw StateError('No active Xtream repository / live payload');
        }
        loaded =
            ((await repo.getLiveChannelsByCategoryId(
                      categoryId: live.categoryId,
                    )) ??
                    const [])
                .map((x) {
                  return ContentItem(
                    x.streamId,
                    x.name,
                    x.streamIcon,
                    ContentType.liveStream,
                    liveStream: x,
                  );
                })
                .toList();
      } else {
        final repo = AppState.m3uRepository;
        final catId = widget.content.m3uItem?.categoryId;
        if (repo == null || catId == null) {
          throw StateError('No active M3U repository / category');
        }
        loaded =
            ((await repo.getM3uItemsByCategoryId(
                      categoryId: catId,
                    )) ??
                    const [])
                .map((x) {
                  return ContentItem(
                    x.url,
                    x.name ?? 'NO NAME',
                    x.tvgLogo ?? '',
                    ContentType.liveStream,
                    m3uItem: x,
                  );
                })
                .toList();
      }
    } catch (e) {
      // Panel down / expired subscription / no network: surface an error with a
      // retry instead of hanging on the loading widget forever.
      if (!mounted) return;
      setState(() => _loadError = e.toString());
      return;
    }

    if (!mounted) return;

    // If the category fetch came back empty, still play the channel the user
    // actually tapped rather than showing an empty error — the single-item
    // queue keeps playback working (and the player has its own error UI).
    if (loaded.isEmpty) {
      loaded = [widget.content];
    }

    setState(() {
      allContents = loaded;
      var idx = allContents.indexWhere(
        (element) => element.id == widget.content.id,
      );
      if (idx < 0) idx = 0; // never leave the index at -1 (RangeError source)
      selectedContentItemIndex = idx;
      _loadError = null;
      allContentsLoaded = true;
    });

    contentItemIndexChangedSubscription?.cancel(); // avoid leaking a prior sub
    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (!mounted) return;
          if (index < 0 || index >= allContents.length) return; // clamp guard

          setState(() {
            selectedContentItemIndex = index;
            contentItem = allContents[selectedContentItemIndex];
          });
        });
    } finally {
      _initializing = false;
    }
  }

  void _retry() {
    setState(() {
      _loadError = null;
      allContentsLoaded = false;
    });
    _initializeQueue();
  }

  @override
  void dispose() {
    contentItemIndexChangedSubscription?.cancel();
    _showSystemUI();
    super.dispose();
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _showSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              PlaylistErrorState(error: _loadError!, onRetry: _retry),
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!allContentsLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: buildFullScreenLoadingWidget(context)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SizedBox.expand(
          child: PlayerWidget(contentItem: widget.content, queue: allContents),
        ),
      ),
    );
  }

}
