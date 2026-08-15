import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';

void main() {
  // buildTimeshiftUrl reads AppState.currentPlaylist for host/creds.
  AppState.currentPlaylist = Playlist(
    id: 'p',
    name: 'P',
    type: PlaylistType.xtream,
    url: 'http://host.tv:8080',
    username: 'user',
    password: 'pass',
    createdAt: DateTime(2026, 1, 1),
  );

  group('buildTimeshiftUrl', () {
    test('encodes host/creds/duration/YYYY-MM-DD:HH-MM/streamId.ts', () {
      final url = buildTimeshiftUrl(
        streamId: '4321',
        start: DateTime(2026, 8, 15, 9, 5), // local wall-clock
        durationMinutes: 45,
      );
      expect(
        url,
        'http://host.tv:8080/timeshift/user/pass/45/2026-08-15:09-05/4321.ts',
      );
    });

    test('zero/negative duration clamps to 1 minute (never /0/)', () {
      final url = buildTimeshiftUrl(
        streamId: '9',
        start: DateTime(2026, 1, 2, 23, 59),
        durationMinutes: 0,
      );
      expect(url, contains('/timeshift/user/pass/1/2026-01-02:23-59/9.ts'));
    });

    test('pads single-digit month/day/hour/minute', () {
      final url = buildTimeshiftUrl(
        streamId: '7',
        start: DateTime(2026, 3, 4, 5, 6),
        durationMinutes: 30,
      );
      expect(url, contains(':2026-03-04:05-06/7.ts'.substring(1)));
    });

    test('returns null with no current playlist', () {
      final saved = AppState.currentPlaylist;
      AppState.currentPlaylist = null;
      expect(
        buildTimeshiftUrl(
            streamId: '1', start: DateTime(2026, 1, 1), durationMinutes: 10),
        isNull,
      );
      AppState.currentPlaylist = saved;
    });
  });

  group('LiveStream tv_archive parsing', () {
    test('parses int and numeric-string forms; hasArchive gates on both', () {
      final asInt = LiveStream.fromJson({
        'stream_id': '1',
        'name': 'C1',
        'stream_icon': '',
        'category_id': 'c',
        'epg_channel_id': 'e',
        'tv_archive': 1,
        'tv_archive_duration': 7,
      }, 'p');
      expect(asInt.tvArchive, 1);
      expect(asInt.tvArchiveDuration, 7);
      expect(asInt.hasArchive, isTrue);

      final asString = LiveStream.fromJson({
        'stream_id': '2',
        'name': 'C2',
        'stream_icon': '',
        'category_id': 'c',
        'epg_channel_id': 'e',
        'tv_archive': '1',
        'tv_archive_duration': '3',
      }, 'p');
      expect(asString.tvArchive, 1);
      expect(asString.tvArchiveDuration, 3);
      expect(asString.hasArchive, isTrue);

      final none = LiveStream.fromJson({
        'stream_id': '3',
        'name': 'C3',
        'stream_icon': '',
        'category_id': 'c',
        'epg_channel_id': 'e',
      }, 'p');
      expect(none.tvArchive, 0);
      expect(none.tvArchiveDuration, 0);
      expect(none.hasArchive, isFalse);

      // archive flag set but zero retention → not usable.
      final flagOnly = LiveStream.fromJson({
        'stream_id': '4',
        'name': 'C4',
        'stream_icon': '',
        'category_id': 'c',
        'epg_channel_id': 'e',
        'tv_archive': 1,
        'tv_archive_duration': 0,
      }, 'p');
      expect(flagOnly.hasArchive, isFalse);
    });
  });

  group('ContentItem catch-up', () {
    test('overrideUrl wins over derived URL; isCatchup flag carried', () {
      final item = ContentItem(
        '4321',
        'Noon News',
        '',
        ContentType.vod,
        overrideUrl:
            'http://host.tv:8080/timeshift/user/pass/45/2026-08-15:09-05/4321.ts',
        isCatchup: true,
      );
      expect(item.url, contains('/timeshift/'));
      expect(item.isCatchup, isTrue);
    });

    test('default item derives its URL as before (no regression)', () {
      final item = ContentItem('100', 'Movie', '', ContentType.vod,
          containerExtension: 'mp4');
      expect(item.url, 'http://host.tv:8080/movie/user/pass/100.mp4');
      expect(item.isCatchup, isFalse);
    });
  });
}
