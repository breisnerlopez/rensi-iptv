import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/controllers/category_detail_controller.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/services/app_state.dart';

VodStream _vod({DateTime? createdAt}) {
  return VodStream(
    streamId: '1',
    name: 'Movie',
    streamIcon: '',
    categoryId: 'cat',
    rating: '0',
    rating5based: 0.0,
    containerExtension: 'mp4',
    playlistId: 'p1',
    createdAt: createdAt,
  );
}

SeriesStream _series({String? lastModified}) {
  return SeriesStream(
    playlistId: 'p1',
    seriesId: '1',
    name: 'Show',
    lastModified: lastModified,
  );
}

ContentItem _vodItem(String id, {DateTime? createdAt}) {
  return ContentItem(
    id,
    'VOD $id',
    '',
    ContentType.vod,
    vodStream: _vod(createdAt: createdAt),
  );
}

ContentItem _seriesItem(String id, {String? lastModified}) {
  return ContentItem(
    id,
    'Show $id',
    '',
    ContentType.series,
    seriesStream: _series(lastModified: lastModified),
  );
}

void main() {
  setUpAll(() {
    // ContentItem.constructor calls buildMediaUrl when isXtreamCode, which
    // reads AppState.currentPlaylist!. We're not asserting URLs in this
    // file — just need a non-null playlist so the constructor doesn't NPE.
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'test',
      type: PlaylistType.xtream,
      url: 'http://example.com',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2024),
    );
  });

  tearDownAll(() {
    AppState.currentPlaylist = null;
  });

  group('CategoryDetailController.parseFlexibleDate', () {
    test('returns epoch on null', () {
      expect(
        CategoryDetailController.parseFlexibleDate(null),
        DateTime(1970),
      );
    });

    test('returns epoch on empty string', () {
      expect(
        CategoryDetailController.parseFlexibleDate(''),
        DateTime(1970),
      );
    });

    test('parses ISO 8601 timestamps', () {
      expect(
        CategoryDetailController.parseFlexibleDate('2024-03-15T10:30:00Z'),
        DateTime.utc(2024, 3, 15, 10, 30),
      );
    });

    test('parses "YYYY-MM-DD HH:mm:ss" (Xtream Codes format)', () {
      // DateTime.tryParse accepts the space-separated form too.
      final parsed =
          CategoryDetailController.parseFlexibleDate('2024-03-15 10:30:00');
      expect(parsed.year, 2024);
      expect(parsed.month, 3);
      expect(parsed.day, 15);
    });

    test('parses bare unix epoch in seconds', () {
      // 1700000000 → 2023-11-14 22:13:20 UTC.
      final parsed =
          CategoryDetailController.parseFlexibleDate('1700000000');
      expect(parsed.toUtc(), DateTime.utc(2023, 11, 14, 22, 13, 20));
    });

    test('returns epoch on garbage input', () {
      expect(
        CategoryDetailController.parseFlexibleDate('not-a-date-at-all'),
        DateTime(1970),
      );
    });

    test('parses a bare 4-digit year (release-date shorthand)', () {
      expect(
        CategoryDetailController.parseFlexibleDate('2019'),
        DateTime(2019),
      );
      expect(
        CategoryDetailController.parseFlexibleDate('1995'),
        DateTime(1995),
      );
    });

    test('year strings shorter than 4 digits stay in the epoch branch', () {
      // "120" — too short to be a year, parsed as Unix seconds.
      final parsed = CategoryDetailController.parseFlexibleDate('120');
      expect(parsed.toUtc().year, 1970);
    });
  });

  group('CategoryDetailController.dateAddedFor', () {
    test('VOD: returns vodStream.createdAt when present', () {
      final item = _vodItem('1', createdAt: DateTime.utc(2024, 6, 1));
      expect(
        CategoryDetailController.dateAddedFor(item),
        DateTime.utc(2024, 6, 1),
      );
    });

    test('VOD: returns epoch when createdAt is null', () {
      final item = _vodItem('1');
      expect(
        CategoryDetailController.dateAddedFor(item),
        DateTime(1970),
      );
    });

    test('Series: parses lastModified string', () {
      final item = _seriesItem('1', lastModified: '2024-06-01T00:00:00Z');
      expect(
        CategoryDetailController.dateAddedFor(item),
        DateTime.utc(2024, 6, 1),
      );
    });

    test('Series: returns epoch when lastModified is null', () {
      final item = _seriesItem('1');
      expect(
        CategoryDetailController.dateAddedFor(item),
        DateTime(1970),
      );
    });

    test('Series: ignores releaseDate even when present', () {
      // releaseDate is intentionally NOT used as a fallback — sort relies
      // solely on lastModified for series. A series with no lastModified
      // and a real releaseDate still sinks to the epoch.
      final item = ContentItem(
        '1',
        'Show',
        '',
        ContentType.series,
        seriesStream: SeriesStream(
          playlistId: 'p1',
          seriesId: '1',
          name: 'Show',
          lastModified: null,
          releaseDate: '2019',
        ),
      );
      expect(
        CategoryDetailController.dateAddedFor(item),
        DateTime(1970),
      );
    });
  });

  group('CategoryDetailController.dateAddedFor ordering semantics', () {
    test('newer item compares greater than older item', () {
      final older = _vodItem('a', createdAt: DateTime.utc(2020, 1, 1));
      final newer = _vodItem('b', createdAt: DateTime.utc(2024, 1, 1));

      final tsOlder = CategoryDetailController.dateAddedFor(older);
      final tsNewer = CategoryDetailController.dateAddedFor(newer);
      expect(tsNewer.isAfter(tsOlder), isTrue);
    });

    test('items without timestamps sink to the bottom of descending sort', () {
      final dated =
          _vodItem('a', createdAt: DateTime.utc(2024, 6, 1));
      final undated = _vodItem('b');

      final tsDated = CategoryDetailController.dateAddedFor(dated);
      final tsUndated = CategoryDetailController.dateAddedFor(undated);
      // In a descending sort, the larger timestamp wins; the undated item
      // sits at the bottom.
      expect(tsDated.isAfter(tsUndated), isTrue);
    });

    test('mixed VOD + Series ordering is consistent across types', () {
      final vodNewer =
          _vodItem('a', createdAt: DateTime.utc(2024, 6, 1));
      final seriesOlder =
          _seriesItem('b', lastModified: '2020-01-01T00:00:00Z');

      final tsVod = CategoryDetailController.dateAddedFor(vodNewer);
      final tsSeries = CategoryDetailController.dateAddedFor(seriesOlder);
      expect(tsVod.isAfter(tsSeries), isTrue);
    });
  });
}
