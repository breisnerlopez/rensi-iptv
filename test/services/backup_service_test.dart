import 'dart:convert';
import 'dart:typed_data';

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
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

  group('BackupService plain export', () {
    test('exportBytes includes playlists with secrets and settings', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'playlist-1',
          name: 'Main M3U',
          type: PlaylistType.m3u,
          url: 'https://example.com/list.m3u',
          username: 'user',
          password: 'pass',
          createdAt: DateTime(2026),
        ),
      );
      await UserPreferences.setLastPlaylist('playlist-1');
      await UserPreferences.setVolume(75.5);
      await UserPreferences.setBackgroundPlay(false);

      final bytes = await BackupService.exportBytes();
      expect(BackupService.looksEncrypted(bytes), isFalse);

      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final playlists = payload['playlists'] as List<dynamic>;
      final settings = payload['settings'] as Map<String, dynamic>;

      expect(payload['schemaVersion'], 1);
      expect(payload['includesSecrets'], isTrue);
      expect(playlists, hasLength(1));
      expect(playlists.single['id'], 'playlist-1');
      expect(playlists.single['url'], 'https://example.com/list.m3u');
      expect(playlists.single['username'], 'user');
      expect(playlists.single['password'], 'pass');
      expect(settings['last_playlist'], 'playlist-1');
      expect(settings['volume'], 75.5);
      expect(settings['background_play'], isFalse);
    });

    test('exportBytes can exclude secrets when requested', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'p1',
          name: 'Xtream',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );

      final bytes = await BackupService.exportBytes(includeSecrets: false);
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final entry = (payload['playlists'] as List).single as Map;
      expect(payload['includesSecrets'], isFalse);
      expect(entry.containsKey('url'), isFalse);
      expect(entry.containsKey('username'), isFalse);
      expect(entry.containsKey('password'), isFalse);
    });

    test('importBytes restores playlists and settings', () async {
      final payload = {
        'schemaVersion': 1,
        'exportedAt': DateTime(2026).toIso8601String(),
        'playlists': [
          {
            'id': 'playlist-1',
            'name': 'Restored Xtream',
            'type': PlaylistType.xtream.toString(),
            'url': 'https://example.com',
            'username': 'restored-user',
            'password': 'restored-pass',
            'createdAt': DateTime(2026).toIso8601String(),
          },
        ],
        'settings': {
          'last_playlist': 'playlist-1',
          'theme_mode': 'dark',
          'hidden_categories': ['sports', 'kids'],
          'seek_on_double_tap': false,
        },
      };

      final result = await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      final playlist = await PlaylistService.getPlaylistById('playlist-1');

      expect(result.created, 1);
      expect(result.updated, 0);
      expect(result.skipped, 0);
      expect(playlist, isNotNull);
      expect(playlist!.name, 'Restored Xtream');
      expect(playlist.type, PlaylistType.xtream);
      expect(playlist.url, 'https://example.com');
      expect(playlist.username, 'restored-user');
      expect(playlist.password, 'restored-pass');
      expect(await UserPreferences.getLastPlaylist(), 'playlist-1');
      expect(await UserPreferences.getHiddenCategories(), ['sports', 'kids']);
      expect(await UserPreferences.getSeekOnDoubleTap(), isFalse);
    });

    test('importBytes with overwrite strategy updates existing playlist',
        () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'playlist-1',
          name: 'Old Name',
          type: PlaylistType.m3u,
          url: 'https://old.example.com/list.m3u',
          createdAt: DateTime(2025),
        ),
      );
      final payload = {
        'schemaVersion': 1,
        'playlists': [
          {
            'id': 'playlist-1',
            'name': 'New Name',
            'type': PlaylistType.m3u.toString(),
            'url': 'https://new.example.com/list.m3u',
            'username': null,
            'password': null,
            'createdAt': DateTime(2026).toIso8601String(),
          },
        ],
        'settings': <String, dynamic>{},
      };

      final result = await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      final playlist = await PlaylistService.getPlaylistById('playlist-1');

      expect(result.updated, 1);
      expect(result.created, 0);
      expect(playlist!.name, 'New Name');
      expect(playlist.url, 'https://new.example.com/list.m3u');
    });

    test('importBytes with keepLocal strategy skips existing playlists',
        () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'playlist-1',
          name: 'Local',
          type: PlaylistType.m3u,
          url: 'https://local.example.com/list.m3u',
          createdAt: DateTime(2025),
        ),
      );
      final payload = {
        'schemaVersion': 1,
        'playlists': [
          {
            'id': 'playlist-1',
            'name': 'Remote',
            'type': PlaylistType.m3u.toString(),
            'url': 'https://remote.example.com/list.m3u',
            'createdAt': DateTime(2026).toIso8601String(),
          },
          {
            'id': 'playlist-2',
            'name': 'Fresh',
            'type': PlaylistType.m3u.toString(),
            'url': 'https://fresh.example.com/list.m3u',
            'createdAt': DateTime(2026).toIso8601String(),
          },
        ],
        'settings': <String, dynamic>{},
      };

      final result = await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        strategy: BackupMergeStrategy.keepLocal,
      );
      final playlist = await PlaylistService.getPlaylistById('playlist-1');

      expect(result.created, 1);
      expect(result.skipped, 1);
      expect(result.updated, 0);
      expect(playlist!.name, 'Local'); // local survived
      final fresh = await PlaylistService.getPlaylistById('playlist-2');
      expect(fresh, isNotNull);
    });

    test('importBytes rejects unsupported schema versions', () async {
      final payload = {
        'schemaVersion': 99,
        'playlists': <Map<String, dynamic>>[],
      };

      expect(
        () => BackupService.importBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        ),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.code, 'code', 'backup_schema_unsupported'),
        ),
      );
    });

    test('importBytes rejects malformed payload', () async {
      final bytes = Uint8List.fromList(utf8.encode('not-json'));
      expect(
        () => BackupService.importBytes(bytes),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('exportBytes includes the TMDb token when secrets are included',
        () async {
      await TmdbCredentialsService.saveCredential('tmdb-secret-token');
      final bytes = await BackupService.exportBytes();
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final creds = payload['credentials'] as Map<String, dynamic>;
      expect(creds['tmdb'], 'tmdb-secret-token');
    });

    test('exportBytes omits credentials when includeSecrets is false',
        () async {
      await TmdbCredentialsService.saveCredential('tmdb-secret-token');
      final bytes = await BackupService.exportBytes(includeSecrets: false);
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(payload.containsKey('credentials'), isFalse);
    });

    test('importBytes restores the TMDb token (overwrite)', () async {
      final payload = {
        'schemaVersion': 1,
        'playlists': <Map<String, dynamic>>[],
        'settings': <String, dynamic>{},
        'credentials': {'tmdb': 'restored-token'},
      };
      await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      expect(await TmdbCredentialsService.getCredential(), 'restored-token');
    });

    test('importBytes respects keepLocal for the TMDb token', () async {
      await TmdbCredentialsService.saveCredential('local-token');
      final payload = {
        'schemaVersion': 1,
        'playlists': <Map<String, dynamic>>[],
        'settings': <String, dynamic>{},
        'credentials': {'tmdb': 'remote-token'},
      };
      await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        strategy: BackupMergeStrategy.keepLocal,
      );
      expect(await TmdbCredentialsService.getCredential(), 'local-token');
    });

    test('importSettings clamps out-of-range numeric values', () async {
      final payload = {
        'schemaVersion': 1,
        'playlists': <Map<String, dynamic>>[],
        'settings': {
          'volume': 9999.0,
          'subtitle_font_size': -10.0,
          'subtitle_padding': 1000.0,
          'theme_mode': 'rogue', // invalid → skipped
        },
      };
      await BackupService.importBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      expect(await UserPreferences.getVolume(), 100.0);
      expect(await UserPreferences.getSubtitleFontSize(), 8.0);
      expect(await UserPreferences.getSubtitlePadding(), 96.0);
      // theme_mode invalid was skipped, so default 'system' is returned.
    });
  });

  group('BackupService encrypted export', () {
    const passphrase = 'correct horse battery staple';

    test('encrypted export round-trips with the same passphrase', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'p1',
          name: 'Secret',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );

      final bytes = await BackupService.exportBytes(passphrase: passphrase);
      expect(BackupService.looksEncrypted(bytes), isTrue);
      // Sanity: the plain passphrase should not appear in the ciphertext.
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('u ')));

      await PlaylistService.deletePlaylist('p1');
      final result = await BackupService.importBytes(
        bytes,
        passphrase: passphrase,
      );
      expect(result.created, 1);
      final restored = await PlaylistService.getPlaylistById('p1');
      expect(restored, isNotNull);
      expect(restored!.username, 'u');
      expect(restored.password, 'p');
    });

    test('decrypting with the wrong passphrase reports invalid passphrase',
        () async {
      final bytes = await BackupService.exportBytes(passphrase: passphrase);
      expect(
        () => BackupService.importBytes(bytes, passphrase: 'wrong'),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.code, 'code', 'backup_passphrase_invalid'),
        ),
      );
    });

    test('encrypted import requires a passphrase', () async {
      final bytes = await BackupService.exportBytes(passphrase: passphrase);
      expect(
        () => BackupService.importBytes(bytes),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.code, 'code', 'backup_passphrase_required'),
        ),
      );
    });

    test('looksEncrypted only matches the magic header', () {
      expect(
        BackupService.looksEncrypted(
          Uint8List.fromList(utf8.encode('{"schemaVersion":1}')),
        ),
        isFalse,
      );
    });
  });
}
