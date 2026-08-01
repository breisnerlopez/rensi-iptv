import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/favorite.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:drift/drift.dart' show Variable, Value;
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

      // Watch history has no foreign key onto playlists, so nothing reaps it
      // implicitly. Deleting a playlist used to leave these rows behind for
      // good, and a later playlist reusing the id resurrected them in the
      // "Continue watching" rail.
      await database
          .into(database.watchHistories)
          .insertOnConflictUpdate(WatchHistory(
            playlistId: 'playlist-1',
            contentType: ContentType.vod,
            streamId: 'watched-1',
            watchDuration: const Duration(minutes: 5),
            totalDuration: const Duration(hours: 1),
            lastWatched: DateTime(2026),
            title: 'Watched',
          ).toDriftCompanion());

      // Favourites carry the user's own picks, names included, keyed the same
      // way as history and with no foreign key either. The cascade looked
      // closed while this sibling table kept everything.
      await database.insertFavorite(Favorite(
        id: 'fav-1',
        playlistId: 'playlist-1',
        contentType: ContentType.vod,
        streamId: 'watched-1',
        name: 'A Very Private Title',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      // Offline downloads carry a playlistId too and were the one branch the
      // cascade forgot: a completed download left its row (and, separately, its
      // file on disk) behind when its playlist was deleted.
      await database.into(database.downloads).insert(
            DownloadsCompanion.insert(
              contentId: 'watched-1',
              contentType: 'vod',
              title: 'Downloaded Movie',
              addedAt: DateTime(2026).millisecondsSinceEpoch,
              playlistId: 'playlist-1',
              status: const Value('complete'),
              filePath: const Value('/tmp/rensi/watched-1.mp4'),
            ),
          );

      await database.deletePlaylistById('playlist-1');

      expect(await database.getPlaylistById('playlist-1'), isNull);
      expect(await database.getCategoriesByPlaylist('playlist-1'), isEmpty);
      expect(await database.getM3uItemsByPlaylist('playlist-1'), isEmpty);
      expect(
        await (database.select(database.downloads)
              ..where((tbl) => tbl.playlistId.equals('playlist-1')))
            .get(),
        isEmpty,
        reason: 'deleting a playlist must reap its download rows too',
      );
      expect(
        await (database.select(database.watchHistories)
              ..where((tbl) => tbl.playlistId.equals('playlist-1')))
            .get(),
        isEmpty,
      );
      expect(
        await (database.select(database.favorites)
              ..where((tbl) => tbl.playlistId.equals('playlist-1')))
            .get(),
        isEmpty,
        reason: 'deleting a playlist must not leave the titles the user '
            'favourited behind',
      );
    });

    test('deletePlaylistById leaves another playlist\'s history alone',
        () async {
      await database.insertPlaylist(
        Playlist(
          id: 'playlist-1',
          name: 'Doomed',
          type: PlaylistType.m3u,
          createdAt: DateTime(2026),
        ),
      );
      for (final playlistId in ['playlist-1', 'playlist-2']) {
        await database
            .into(database.watchHistories)
            .insertOnConflictUpdate(WatchHistory(
              playlistId: playlistId,
              contentType: ContentType.vod,
              streamId: 'stream-$playlistId',
              watchDuration: const Duration(minutes: 5),
              totalDuration: const Duration(hours: 1),
              lastWatched: DateTime(2026),
              title: 'Movie',
            ).toDriftCompanion());
        await database.insertFavorite(Favorite(
          id: 'fav-$playlistId',
          playlistId: playlistId,
          contentType: ContentType.vod,
          streamId: 'stream-$playlistId',
          name: 'Fav $playlistId',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      }

      await database.deletePlaylistById('playlist-1');

      // The cascade must be scoped by playlistId, not a blanket wipe: this is
      // the mutation that a "delete everything" implementation would survive
      // if only the assertion above existed.
      final survivors = await database.select(database.watchHistories).get();
      expect(survivors.map((row) => row.playlistId), ['playlist-2']);
      final favSurvivors = await database.select(database.favorites).get();
      expect(favSurvivors.map((row) => row.playlistId), ['playlist-2']);
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
