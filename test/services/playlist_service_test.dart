import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/playlist_secrets_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

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

  group('PlaylistService', () {
    test('savePlaylist writes secrets to secure storage, not the database',
        () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistService.savePlaylist(playlist);

      final rawDb = await database.getPlaylistById('p1');
      expect(rawDb!.url, isNull);
      expect(rawDb.username, isNull);
      expect(rawDb.password, isNull);

      PlaylistService.invalidateCache();
      final hydrated = await PlaylistService.getPlaylistById('p1');
      expect(hydrated!.url, 'https://x.com');
      expect(hydrated.username, 'u');
      expect(hydrated.password, 'p');
    });

    test('cached read does not re-fetch from secure storage', () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistService.savePlaylist(playlist);

      // Manually clear the secure storage. If the service hits secure storage
      // again, the second call would return nulls.
      FlutterSecureStorage.setMockInitialValues({});

      final hydrated = await PlaylistService.getPlaylistById('p1');
      expect(hydrated!.username, 'u'); // came from cache
    });

    test('legacy DB row triggers migration once, then is sanitized', () async {
      // Insert a legacy row that still carries secrets in the SQLite table.
      await database.insertPlaylist(
        Playlist(
          id: 'legacy',
          name: 'Legacy',
          type: PlaylistType.xtream,
          url: 'https://legacy.com',
          username: 'legacy-user',
          password: 'legacy-pass',
          createdAt: DateTime(2024),
        ),
      );

      final hydrated = await PlaylistService.getPlaylistById('legacy');
      expect(hydrated, isNotNull);
      expect(hydrated!.username, 'legacy-user');
      expect(hydrated.password, 'legacy-pass');

      // The DB row should have been sanitized.
      final rawDb = await database.getPlaylistById('legacy');
      expect(rawDb!.username, isNull);
      expect(rawDb.password, isNull);
    });

    test('deletePlaylist clears secrets and removes from cache', () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistService.savePlaylist(playlist);
      await PlaylistService.deletePlaylist('p1');

      final hydrated = await PlaylistService.getPlaylistById('p1');
      expect(hydrated, isNull);

      // Secrets storage is also drained — write a new row with same id to confirm.
      final fresh = await PlaylistSecretsService.hydrate(
        Playlist(
          id: 'p1',
          name: 'Main',
          type: PlaylistType.xtream,
          createdAt: DateTime(2026),
        ),
      );
      expect(fresh.url, isNull);
    });

    test('getXStreamPlaylists and getM3UPlaylists filter by type', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'x1',
          name: 'X',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'm1',
          name: 'M',
          type: PlaylistType.m3u,
          url: 'https://m.com/p.m3u',
          createdAt: DateTime(2026),
        ),
      );

      expect((await PlaylistService.getXStreamPlaylists()), hasLength(1));
      expect((await PlaylistService.getM3UPlaylists()), hasLength(1));
    });
  });
}
