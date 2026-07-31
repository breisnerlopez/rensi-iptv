import 'dart:async';

import 'package:flutter/material.dart';

import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/player_state.dart';

/// Pure "is there a next episode?" predicate, shared by the player widget's
/// `_hasNextEpisode` getter and this button so both agree on visibility.
///
/// True only for non-live content that has a queue and is not already sitting
/// on the last item. Live streams never advance a queue, a null queue means
/// there is nothing to advance into, and the last item has no successor.
bool hasNextEpisode({
  required ContentType? contentType,
  required List<ContentItem>? queue,
  required int currentIndex,
}) {
  if (contentType == ContentType.liveStream) return false;
  if (queue == null) return false;
  return currentIndex >= 0 && currentIndex < queue.length - 1;
}

/// Mobile/desktop player-control button that jumps to the next queue item
/// (next episode / next movie) without waiting for the current one to finish.
///
/// It renders only when [hasNextEpisode] is true. Advancing reuses the exact
/// same path the in-app episode picker uses: it emits
/// `player_content_item_index_changed`, which PlayerWidget turns into a
/// `_player.jump(index)` for non-live content — the same media_kit playlist
/// advance that the end-of-file auto-advance drives — so index, contentItem,
/// history and PlayerState all update through one consistent code path.
class VideoNextEpisodeWidget extends StatefulWidget {
  const VideoNextEpisodeWidget({super.key});

  @override
  State<VideoNextEpisodeWidget> createState() => _VideoNextEpisodeWidgetState();
}

class _VideoNextEpisodeWidgetState extends State<VideoNextEpisodeWidget> {
  StreamSubscription<int>? _indexSub;
  StreamSubscription<ContentItem>? _itemSub;

  @override
  void initState() {
    super.initState();
    // The current index/content changes as the queue advances; rebuild so the
    // button hides once the last item is reached.
    _indexSub = EventBus()
        .on<int>('player_content_item_index')
        .listen((_) => _rebuild());
    _itemSub = EventBus()
        .on<ContentItem>('player_content_item')
        .listen((_) => _rebuild());
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _itemSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = hasNextEpisode(
      contentType: PlayerState.currentContent?.contentType,
      queue: PlayerState.queue,
      currentIndex: PlayerState.currentIndex,
    );
    if (!hasNext) return const SizedBox.shrink();

    return IconButton(
      tooltip: context.loc.next_episode,
      icon: const Icon(Icons.skip_next, color: Colors.white),
      onPressed: () {
        EventBus().emit(
          'player_content_item_index_changed',
          PlayerState.currentIndex + 1,
        );
      },
    );
  }
}
