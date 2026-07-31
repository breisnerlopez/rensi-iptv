import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_next_episode_widget.dart';

// Guards the single source of truth behind BOTH the TV pause-panel button and
// the mobile skip-next control (PlayerWidget._hasNextEpisode delegates here).
// The control must be ABSENT for live, for a queue-less VOD, and on the last
// episode, and PRESENT mid-series — without needing a real seekable clip.
void main() {
  ContentItem ep(String id) =>
      ContentItem('http://x/$id', id, '', ContentType.series);

  final queue = [ep('e1'), ep('e2'), ep('e3')];

  test('live never has a next episode (bare Media, no queue advance)', () {
    expect(
      hasNextEpisode(
        contentType: ContentType.liveStream,
        queue: queue,
        currentIndex: 0,
      ),
      isFalse,
    );
  });

  test('a null queue has no next episode', () {
    expect(
      hasNextEpisode(
        contentType: ContentType.vod,
        queue: null,
        currentIndex: 0,
      ),
      isFalse,
    );
  });

  test('the last episode has no next episode', () {
    expect(
      hasNextEpisode(
        contentType: ContentType.series,
        queue: queue,
        currentIndex: queue.length - 1,
      ),
      isFalse,
    );
  });

  test('mid-series has a next episode', () {
    expect(
      hasNextEpisode(
        contentType: ContentType.series,
        queue: queue,
        currentIndex: 0,
      ),
      isTrue,
    );
    expect(
      hasNextEpisode(
        contentType: ContentType.series,
        queue: queue,
        currentIndex: 1,
      ),
      isTrue,
    );
  });

  test('an out-of-range index degrades to no next episode', () {
    expect(
      hasNextEpisode(
        contentType: ContentType.series,
        queue: queue,
        currentIndex: -1,
      ),
      isFalse,
    );
  });
}
