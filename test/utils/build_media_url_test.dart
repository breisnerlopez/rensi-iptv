import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';

// Guards for the "failed to recognize file format" fix (Feature A):
//  - a null/empty container extension must NOT interpolate the literal ".null"
//    (the panel answers that with an HTML error page → libmpv can't demux);
//  - swapUrlExtension must correctly rewrite the trailing extension so the
//    player can self-heal a stale one.
void main() {
  setUp(() {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'X',
      type: PlaylistType.xtream,
      url: 'http://host:8080',
      username: 'u',
      password: 'pw',
      createdAt: DateTime(2026),
    );
  });
  tearDown(() => AppState.currentPlaylist = null);

  group('buildMediaUrl', () {
    test('VOD with an extension appends it', () {
      final item = ContentItem('123', 'M', '', ContentType.vod,
          containerExtension: 'mp4');
      expect(item.url, 'http://host:8080/movie/u/pw/123.mp4');
    });

    test('VOD with a null extension does NOT emit ".null"', () {
      final item = ContentItem('123', 'M', '', ContentType.vod);
      expect(item.url, 'http://host:8080/movie/u/pw/123');
      expect(item.url.contains('.null'), isFalse);
    });

    test('VOD with an empty extension does NOT leave a trailing dot', () {
      final item = ContentItem('123', 'M', '', ContentType.vod,
          containerExtension: '');
      expect(item.url, 'http://host:8080/movie/u/pw/123');
      expect(item.url.endsWith('.'), isFalse);
    });

    test('series with a null extension does NOT emit ".null"', () {
      final item = ContentItem('55', 'S', '', ContentType.series);
      expect(item.url, 'http://host:8080/series/u/pw/55');
      expect(item.url.contains('.null'), isFalse);
    });

    test('live has no extension regardless', () {
      final item = ContentItem('9', 'L', '', ContentType.liveStream);
      expect(item.url, 'http://host:8080/u/pw/9');
    });
  });

  group('swapUrlExtension', () {
    test('replaces the trailing extension', () {
      expect(swapUrlExtension('http://h/movie/u/p/1.mkv', 'mp4'),
          'http://h/movie/u/p/1.mp4');
    });

    test('preserves a query string', () {
      expect(swapUrlExtension('http://h/movie/u/p/1.mkv?token=abc', 'mp4'),
          'http://h/movie/u/p/1.mp4?token=abc');
    });

    test('appends when there is no extension', () {
      expect(swapUrlExtension('http://h/movie/u/p/1', 'mp4'),
          'http://h/movie/u/p/1.mp4');
    });

    test('does not treat a dot in a path segment as an extension', () {
      // Only the last path segment counts; a dot before the last slash is safe.
      expect(swapUrlExtension('http://h/a.b/movie/1.mkv', 'mp4'),
          'http://h/a.b/movie/1.mp4');
    });

    test('kVodExtensionCandidates covers the dominant containers', () {
      expect(kVodExtensionCandidates, containsAll(['mp4', 'mkv']));
    });
  });
}
