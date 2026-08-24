import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/favorite.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

WatchHistory _wh({
  String playlist = 'pl-1',
  String stream = 's-1',
  ContentType type = ContentType.series,
  String? seriesId = 'series-9',
  int watchedMs = 63000,
  int totalMs = 180000,
  String title = 'Ep 1',
}) {
  return WatchHistory(
    playlistId: playlist,
    contentType: type,
    streamId: stream,
    seriesId: seriesId,
    watchDuration: Duration(milliseconds: watchedMs),
    totalDuration: Duration(milliseconds: totalMs),
    lastWatched: DateTime.utc(2026, 3, 4, 5, 6, 7),
    imagePath: 'http://img/$stream.jpg',
    title: title,
    containerExtension: 'mp4',
    providerId: 'prov-1',
  );
}

Favorite _fav({
  String id = 'fav-1',
  String playlist = 'pl-1',
  String stream = 's-1',
  ContentType type = ContentType.vod,
}) {
  return Favorite(
    id: id,
    playlistId: playlist,
    contentType: type,
    streamId: stream,
    episodeId: null,
    m3uItemId: null,
    name: 'Fav $id',
    imagePath: 'http://img/$id.jpg',
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    updatedAt: DateTime.utc(2026, 1, 9, 10, 11, 12),
  );
}

void main() {
  late AppDatabase database;

  setUp(() async {
    await getIt.reset();
    PlaylistService.invalidateCache();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
  });

  tearDown(() async {
    await getIt.reset();
    PlaylistService.invalidateCache();
    await database.close();
  });

  Future<AppDatabase> freshDatabase() async {
    await database.close();
    await getIt.reset();
    PlaylistService.invalidateCache();
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
    return database;
  }

  group('backup export of watch history and favorites', () {
    test('includes both sections by default (includeSecrets)', () async {
      await WatchHistoryService().saveWatchHistory(_wh());
      await database.insertFavorite(_fav());

      final bytes = await BackupService.exportBytes();
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      final wh = payload['watchHistory'] as List<dynamic>;
      final fav = payload['favorites'] as List<dynamic>;
      expect(wh, hasLength(1));
      expect(fav, hasLength(1));
      expect(wh.single['stream_id'], 's-1');
      expect(wh.single['series_id'], 'series-9');
      expect(wh.single['watch_duration'], 63000);
      expect(wh.single['content_type'], ContentType.series.index);
      expect(fav.single['id'], 'fav-1');
    });

    test('excludes both sections when includeSecrets is false', () async {
      await WatchHistoryService().saveWatchHistory(_wh());
      await database.insertFavorite(_fav());

      final bytes = await BackupService.exportBytes(includeSecrets: false);
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      expect(payload.containsKey('watchHistory'), isFalse);
      expect(payload.containsKey('favorites'), isFalse);
    });
  });

  group('backup round-trip', () {
    test('restores watch history and favorites faithfully', () async {
      await WatchHistoryService().saveWatchHistory(_wh());
      // restoreFavorite conserva las marcas de tiempo del fixture (insertFavorite
      // las pisa por diseño); así probamos la ruta fiel completa.
      await database.restoreFavorite(_fav());
      final bytes = await BackupService.exportBytes();

      await freshDatabase();
      expect(await WatchHistoryService().getAllWatchHistory(), isEmpty);
      expect(await database.getAllFavorites(), isEmpty);

      await BackupService.importBytes(bytes);

      final w = (await WatchHistoryService().getAllWatchHistory()).single;
      expect(w.playlistId, 'pl-1');
      expect(w.streamId, 's-1');
      expect(w.seriesId, 'series-9');
      expect(w.contentType, ContentType.series);
      expect(w.watchDuration, const Duration(milliseconds: 63000));
      expect(w.totalDuration, const Duration(milliseconds: 180000));
      expect(w.lastWatched.toUtc(), DateTime.utc(2026, 3, 4, 5, 6, 7));
      expect(w.title, 'Ep 1');
      expect(w.containerExtension, 'mp4');
      expect(w.providerId, 'prov-1');

      final f = (await database.getAllFavorites()).single;
      expect(f.id, 'fav-1');
      expect(f.contentType, ContentType.vod);
      expect(f.createdAt.toUtc(), DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(f.updatedAt.toUtc(), DateTime.utc(2026, 1, 9, 10, 11, 12));
    });

    test('keepLocal skips existing rows, keeps local copy', () async {
      await database.insertFavorite(_fav(id: 'fav-1'));
      await WatchHistoryService().saveWatchHistory(_wh(watchedMs: 1000));
      await database.insertFavorite(_fav(id: 'fav-2', stream: 's-2'));
      await WatchHistoryService()
          .saveWatchHistory(_wh(stream: 's-2', watchedMs: 9000));
      final bytes = await BackupService.exportBytes();

      await freshDatabase();
      await database.insertFavorite(_fav(id: 'fav-1'));
      await WatchHistoryService().saveWatchHistory(_wh(watchedMs: 1000));

      await BackupService.importBytes(
        bytes,
        strategy: BackupMergeStrategy.keepLocal,
      );

      final wh = await WatchHistoryService().getAllWatchHistory();
      final favs = await database.getAllFavorites();
      final s1 = wh.firstWhere((w) => w.streamId == 's-1');
      expect(s1.watchDuration, const Duration(milliseconds: 1000));
      expect(wh.map((w) => w.streamId).toSet(), {'s-1', 's-2'});
      expect(favs.map((f) => f.id).toSet(), {'fav-1', 'fav-2'});
    });

    test('overwrite replaces existing rows', () async {
      await freshDatabase();
      await WatchHistoryService().saveWatchHistory(_wh(watchedMs: 9999));
      final bytes = await BackupService.exportBytes();

      await freshDatabase();
      await WatchHistoryService().saveWatchHistory(_wh(watchedMs: 1));

      await BackupService.importBytes(bytes);
      final s1 = (await WatchHistoryService().getAllWatchHistory()).single;
      expect(s1.watchDuration, const Duration(milliseconds: 9999));
    });
  });

  group('robustez ante ítems corruptos', () {
    test('un favorito/historial malformado no aborta el restore ni las '
        'playlists', () async {
      final payload = <String, dynamic>{
        'schemaVersion': 1,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'includesSecrets': true,
        'playlists': <dynamic>[
          Playlist(
            id: 'p-iso',
            name: 'Aislada',
            type: PlaylistType.m3u,
            url: 'https://example.com/l.m3u',
            createdAt: DateTime.utc(2026),
          ).toJson(),
        ],
        'favorites': <dynamic>[
          _fav(id: 'good').toJson(),
          <String, dynamic>{'id': 'solo-id'},
        ],
        'watchHistory': <dynamic>[
          <String, dynamic>{'nope': 1},
        ],
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      await BackupService.importBytes(bytes);

      expect(await PlaylistService.getPlaylistById('p-iso'), isNotNull);
      final favs = await database.getAllFavorites();
      expect(favs.map((f) => f.id).toList(), ['good']);
    });
  });

  group('backward compatibility', () {
    test('old backup without the new sections imports without error', () async {
      final oldPayload = <String, dynamic>{
        'schemaVersion': 1,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'includesSecrets': true,
        'playlists': <dynamic>[],
        'settings': <String, dynamic>{},
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(oldPayload)));

      await BackupService.importBytes(bytes);
      expect(await WatchHistoryService().getAllWatchHistory(), isEmpty);
      expect(await database.getAllFavorites(), isEmpty);
    });
  });
}
