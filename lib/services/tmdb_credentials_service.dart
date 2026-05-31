import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TmdbCredentialsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  static const _credentialKey = 'tmdb.credential';

  static Future<String?> getCredential() async {
    final value = await _storage.read(key: _credentialKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Future<void> saveCredential(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await deleteCredential();
      return;
    }
    await _storage.write(key: _credentialKey, value: trimmed);
  }

  static Future<void> deleteCredential() async {
    await _storage.delete(key: _credentialKey);
  }
}
