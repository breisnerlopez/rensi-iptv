import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/playlist_secrets_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PlaylistSecretsService', () {
    test('save and hydrate roundtrips secrets', () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistSecretsService.save(playlist);

      final stripped = playlist.withoutSecrets();
      final hydrated = await PlaylistSecretsService.hydrate(stripped);

      expect(hydrated.url, 'https://x.com');
      expect(hydrated.username, 'u');
      expect(hydrated.password, 'p');
    });

    test('delete removes all stored fields for a playlist', () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistSecretsService.save(playlist);
      await PlaylistSecretsService.delete('p1');

      final hydrated =
          await PlaylistSecretsService.hydrate(playlist.withoutSecrets());
      expect(hydrated.url, isNull);
      expect(hydrated.username, isNull);
      expect(hydrated.password, isNull);
    });

    test('hasMigrated flips after markMigrated is called', () async {
      expect(await PlaylistSecretsService.hasMigrated(), isFalse);
      await PlaylistSecretsService.markMigrated();
      expect(await PlaylistSecretsService.hasMigrated(), isTrue);

      await PlaylistSecretsService.resetMigrationFlag();
      expect(await PlaylistSecretsService.hasMigrated(), isFalse);
    });

    test('migrateLegacyIfNeeded is a no-op when no legacy values exist',
        () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );
      await PlaylistSecretsService.migrateLegacyIfNeeded(playlist);
      final hydrated = await PlaylistSecretsService.hydrate(playlist);
      expect(hydrated.url, isNull);
    });

    test('save with empty/null values deletes the corresponding keys',
        () async {
      // First populate the storage.
      final playlist = Playlist(
        id: 'p1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      await PlaylistSecretsService.save(playlist);

      // Now replace with empties.
      final cleared = playlist.copyWith(url: '', username: '', password: '');
      await PlaylistSecretsService.save(cleared);

      final hydrated = await PlaylistSecretsService.hydrate(
        playlist.withoutSecrets(),
      );
      expect(hydrated.url, isNull);
      expect(hydrated.username, isNull);
      expect(hydrated.password, isNull);
    });
  });
}
