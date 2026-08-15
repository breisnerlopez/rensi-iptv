import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TmdbCredentialsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  static const _credentialKey = 'tmdb.credential';

  /// A build-time default TMDb key so catalogue art works out of the box on a
  /// fresh install (the #1 "looks empty" complaint). Injected at build with
  /// `--dart-define=TMDB_DEFAULT_KEY=<key>` and NEVER hard-coded in the repo; if
  /// it isn't injected this is empty and behaviour is exactly as before (no
  /// default → art only after the user adds their own key). A user-saved key
  /// always takes precedence over this shared default.
  static const _defaultKey = String.fromEnvironment('TMDB_DEFAULT_KEY');

  /// Test-only override for the embedded default (which is otherwise a
  /// compile-time constant that a runtime test can't set). Simulates a build
  /// with `--dart-define=TMDB_DEFAULT_KEY=...`.
  @visibleForTesting
  static String? debugDefaultOverride;

  static String get _effectiveDefault =>
      (debugDefaultOverride ?? _defaultKey).trim();

  /// The EFFECTIVE credential used for TMDb calls: the user's own if saved,
  /// otherwise the embedded default. Null only when neither exists.
  static Future<String?> getCredential() async {
    final stored = await getStoredCredential();
    if (stored != null) return stored;
    return _effectiveDefault.isEmpty ? null : _effectiveDefault;
  }

  /// Whether the USER saved their own key (ignores the embedded default). Used by
  /// Settings/onboarding to decide whether to offer adding a personal key.
  static Future<bool> hasStoredCredential() async => (await getStoredCredential()) != null;

  /// The RAW user-saved credential ONLY (never the embedded default). Backup
  /// export/import MUST use this, not [getCredential]: exporting the effective
  /// value would leak the shared default into backup files, and using it for the
  /// import "keep existing" check would silently drop a real key from a backup on
  /// a fresh install (where only the default exists).
  static Future<String?> getStoredCredential() async {
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
