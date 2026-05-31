import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist_model.dart';

class PlaylistSecretsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const _migrationFlagKey = 'playlist.secrets.migrated.v1';

  static String _key(String playlistId, String field) =>
      'playlist.$playlistId.$field';

  static Future<void> save(Playlist playlist) async {
    await Future.wait([
      _writeOrDelete(_key(playlist.id, 'url'), playlist.url),
      _writeOrDelete(_key(playlist.id, 'username'), playlist.username),
      _writeOrDelete(_key(playlist.id, 'password'), playlist.password),
    ]);
  }

  static Future<Playlist> hydrate(Playlist playlist) async {
    final values = await Future.wait([
      _storage.read(key: _key(playlist.id, 'url')),
      _storage.read(key: _key(playlist.id, 'username')),
      _storage.read(key: _key(playlist.id, 'password')),
    ]);

    return playlist.copyWith(
      url: values[0] ?? playlist.url,
      username: values[1] ?? playlist.username,
      password: values[2] ?? playlist.password,
    );
  }

  static Future<void> delete(String playlistId) async {
    await Future.wait([
      _storage.delete(key: _key(playlistId, 'url')),
      _storage.delete(key: _key(playlistId, 'username')),
      _storage.delete(key: _key(playlistId, 'password')),
    ]);
  }

  static Future<void> migrateLegacyIfNeeded(Playlist playlist) async {
    if (playlist.url == null &&
        playlist.username == null &&
        playlist.password == null) {
      return;
    }
    await save(playlist);
  }

  static Future<bool> hasMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migrationFlagKey) ?? false;
  }

  static Future<void> markMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationFlagKey, true);
  }

  static Future<void> resetMigrationFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationFlagKey);
  }

  static Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
