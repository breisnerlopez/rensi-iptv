import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createTestDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  group('AppDatabase.searchM3uItems', () {
    setUp(() async {
      await database.insertM3uItems([
        M3uItem(
          id: '1',
          playlistId: 'p1',
          url: 'https://example.com/a.m3u8',
          contentType: ContentType.liveStream,
          name: 'BBC News HD',
          groupTitle: 'News',
        ),
        M3uItem(
          id: '2',
          playlistId: 'p1',
          url: 'https://example.com/b.m3u8',
          contentType: ContentType.vod,
          name: 'Dune (2021)',
          groupTitle: 'Movies',
        ),
        M3uItem(
          id: '3',
          playlistId: 'p2', // different playlist; should not leak
          url: 'https://example.com/c.m3u8',
          contentType: ContentType.liveStream,
          name: 'BBC One Other Playlist',
          groupTitle: 'News',
        ),
      ]);
    });

    test('returns matches by name within the playlist scope', () async {
      final result = await database.searchM3uItems('p1', 'bbc');
      expect(result, hasLength(1));
      expect(result.single.id, '1');
    });

    test('matches by group title as well', () async {
      final result = await database.searchM3uItems('p1', 'Movies');
      expect(result, hasLength(1));
      expect(result.single.id, '2');
    });

    test('respects the limit argument', () async {
      // Insert many.
      await database.insertM3uItems(
        List.generate(
          50,
          (i) => M3uItem(
            id: 'extra-$i',
            playlistId: 'p1',
            url: 'https://example.com/$i.m3u8',
            contentType: ContentType.liveStream,
            name: 'Channel $i',
            groupTitle: 'Other',
          ),
        ),
      );

      final result = await database.searchM3uItems('p1', 'channel', limit: 5);
      expect(result, hasLength(5));
    });

    test('returns empty list for blank query', () async {
      final result = await database.searchM3uItems('p1', '');
      expect(result, isEmpty);
    });

    test('does not leak items from other playlists', () async {
      final result = await database.searchM3uItems('p1', 'BBC');
      expect(result.map((m) => m.id), isNot(contains('3')));
    });
  });
}
