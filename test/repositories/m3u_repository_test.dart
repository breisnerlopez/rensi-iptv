import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    await getIt.reset();
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
    AppState.currentPlaylist = Playlist(
      id: 'playlist-1',
      name: 'M3U',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026),
    );
  });

  tearDown(() async {
    AppState.currentPlaylist = null;
    await getIt.reset();
    await database.close();
  });

  group('M3uRepository', () {
    test('returns M3U items by category', () async {
      await database.insertM3uItems([
        M3uItem(
          id: 'item-1',
          playlistId: 'playlist-1',
          url: 'https://example.com/live.m3u8',
          contentType: ContentType.liveStream,
          categoryId: 'cat-1',
        ),
      ]);

      final repository = M3uRepository();
      final items = await repository.getM3uItemsByCategoryId(
        categoryId: 'cat-1',
        contentType: ContentType.liveStream,
      );

      expect(items, isNotNull);
      expect(items, hasLength(1));
      expect(items!.single.id, 'item-1');
    });

    test('returns null when a category has no content', () async {
      final repository = M3uRepository();

      final items = await repository.getM3uItemsByCategoryId(
        categoryId: 'missing',
        contentType: ContentType.liveStream,
      );

      expect(items, isNull);
    });

    test('searches stored M3U content by type-specific tables', () async {
      await database
          .into(database.liveStreams)
          .insert(
            LiveStreamsCompanion.insert(
              streamId: 'live-1',
              name: 'News Live',
              streamIcon: '',
              categoryId: 'cat-1',
              epgChannelId: '',
              playlistId: 'playlist-1',
            ),
          );

      final repository = M3uRepository();
      final results = await repository.searchLiveStreams('News');

      expect(results, hasLength(1));
      expect(results.single.name, 'News Live');
    });

    test('returns series by category', () async {
      await database.insertM3uSeries([
        M3uSeriesCompanion.insert(
          playlistId: 'playlist-1',
          seriesId: 'series-1',
          name: 'Show',
          categoryId: const Value('cat-1'),
        ),
      ]);

      final repository = M3uRepository();
      final series = await repository.getSeriesByCategoryId(
        categoryId: 'cat-1',
      );

      expect(series, isNotNull);
      expect(series!.single.name, 'Show');
    });
  });
}
