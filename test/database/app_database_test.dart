import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/favorite.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:drift/drift.dart' show Variable;
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

  group('AppDatabase playlists', () {
    test('inserts and reads playlists', () async {
      final playlist = Playlist(
        id: 'playlist-1',
        name: 'Main Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );

      await database.insertPlaylist(playlist);

      final saved = await database.getPlaylistById('playlist-1');
      expect(saved, isNotNull);
      expect(saved!.name, 'Main Playlist');
      expect(saved.type, PlaylistType.m3u);
    });

    test('deletePlaylistById removes related rows', () async {
      await database.insertPlaylist(
        Playlist(
          id: 'playlist-1',
          name: 'Main Playlist',
          type: PlaylistType.m3u,
          createdAt: DateTime(2026),
        ),
      );
      await database.insertCategories([
        Category(
          categoryId: 'cat-1',
          categoryName: 'Live',
          parentId: 0,
          playlistId: 'playlist-1',
          type: CategoryType.live,
        ),
      ]);
      await database.insertM3uItems([
        M3uItem(
          id: 'item-1',
          playlistId: 'playlist-1',
          url: 'https://example.com/live.m3u8',
          contentType: ContentType.liveStream,
          categoryId: 'cat-1',
        ),
      ]);

      await database.deletePlaylistById('playlist-1');

      expect(await database.getPlaylistById('playlist-1'), isNull);
      expect(await database.getCategoriesByPlaylist('playlist-1'), isEmpty);
      expect(await database.getM3uItemsByPlaylist('playlist-1'), isEmpty);
    });
  });

  group('AppDatabase categories and M3U items', () {
    test('filters categories by playlist and type', () async {
      await database.insertCategories([
        Category(
          categoryId: 'live-1',
          categoryName: 'Live',
          parentId: 0,
          playlistId: 'playlist-1',
          type: CategoryType.live,
        ),
        Category(
          categoryId: 'vod-1',
          categoryName: 'Movies',
          parentId: 0,
          playlistId: 'playlist-1',
          type: CategoryType.vod,
        ),
      ]);

      final live = await database.getCategoriesByTypeAndPlaylist(
        'playlist-1',
        CategoryType.live,
      );

      expect(live, hasLength(1));
      expect(live.single.categoryId, 'live-1');
    });

    test('filters M3U items by category and content type', () async {
      await database.insertM3uItems([
        M3uItem(
          id: 'live-1',
          playlistId: 'playlist-1',
          url: 'https://example.com/live.m3u8',
          contentType: ContentType.liveStream,
          categoryId: 'cat-1',
        ),
        M3uItem(
          id: 'movie-1',
          playlistId: 'playlist-1',
          url: 'https://example.com/movie.mp4',
          contentType: ContentType.vod,
          categoryId: 'cat-1',
        ),
      ]);

      final live = await database.getM3uItemsByCategoryId(
        'playlist-1',
        'cat-1',
        contentType: ContentType.liveStream,
      );

      expect(live, hasLength(1));
      expect(live.single.id, 'live-1');
    });
  });

  group('AppDatabase favorites and history', () {
    test('inserts, checks and deletes favorites', () async {
      final now = DateTime(2026);
      await database.insertFavorite(
        Favorite(
          id: 'favorite-1',
          playlistId: 'playlist-1',
          contentType: ContentType.vod,
          streamId: 'stream-1',
          name: 'Movie',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        await database.isFavorite(
          'playlist-1',
          'stream-1',
          ContentType.vod,
          null,
        ),
        isTrue,
      );

      await database.deleteFavorite('favorite-1');

      expect(
        await database.isFavorite(
          'playlist-1',
          'stream-1',
          ContentType.vod,
          null,
        ),
        isFalse,
      );
    });

    test('converts watch history to and from Drift data', () async {
      final history = WatchHistory(
        playlistId: 'playlist-1',
        contentType: ContentType.vod,
        streamId: 'stream-1',
        watchDuration: const Duration(minutes: 5),
        totalDuration: const Duration(hours: 1),
        lastWatched: DateTime(2026),
        title: 'Movie',
      );

      await database
          .into(database.watchHistories)
          .insertOnConflictUpdate(history.toDriftCompanion());

      final row = await (database.select(
        database.watchHistories,
      )..where((tbl) => tbl.streamId.equals('stream-1'))).getSingle();
      final converted = WatchHistory.fromDrift(row);

      expect(converted.playlistId, 'playlist-1');
      expect(converted.contentType, ContentType.vod);
      expect(converted.watchDuration, const Duration(minutes: 5));
      expect(converted.totalDuration, const Duration(hours: 1));
    });
  });

  group('AppDatabase migrations', () {
    test('creates performance indexes on open', () async {
      final indexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
            variables: [Variable.withString('idx_m3u_items_playlist_category')],
          )
          .get();

      expect(indexes, hasLength(1));
    });
  });
}
