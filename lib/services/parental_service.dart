import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Top-level so it can run in a background isolate via [compute]: PBKDF2 is CPU-
/// heavy and must never derive on the UI isolate (a multi-second freeze / ANR on
/// a low-end TV box). No native backend (`cryptography_flutter`) is registered,
/// so this is pure Dart — the isolate keeps it off the main thread.
Future<List<int>> _deriveKeyInIsolate(Map<String, dynamic> args) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: args['iterations'] as int,
    bits: 256,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(args['pin'] as String)),
    nonce: args['salt'] as List<int>,
  );
  return key.extractBytes();
}

/// Parental control: a PIN (hashed, never stored in clear) that gates locked
/// categories. The PIN is derived with PBKDF2-HMAC-SHA256 (same primitive the
/// encrypted backup uses) over a random salt; only `salt:hash` (base64) is kept
/// in the OS secure storage. A successful [verifyPin] unlocks locked content for
/// the rest of the app session (until restart).
class ParentalService {
  ParentalService._();
  static final ParentalService instance = ParentalService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _key = 'parental.pin';
  // For a 4-digit NUMERIC PIN the iteration count is not the security boundary
  // (the 10^4 keyspace is brute-forceable in seconds regardless) — flutter_secure
  // _storage is the real protection. So a moderate count keeps the derive fast
  // even in a background isolate. (600k here caused ~12s derives / test timeout.)
  static const _iterations = 120000;

  // Session unlock: once the PIN is entered, locked categories are revealed for
  // the rest of this app run. Not persisted (a fresh launch re-locks).
  bool _unlocked = false;
  bool get isUnlocked => _unlocked;

  Future<bool> hasPin() async => (await _storage.read(key: _key)) != null;

  Future<void> setPin(String pin) async {
    final salt = _randomBytes(16);
    final hash = await _derive(pin, salt);
    await _storage.write(
        key: _key, value: '${base64Encode(salt)}:${base64Encode(hash)}');
    _unlocked = true; // setting a PIN implies you're the parent, unlocked now
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = base64Decode(parts[0]);
    final expected = base64Decode(parts[1]);
    final actual = await _derive(pin, salt);
    if (!_constantTimeEquals(expected, actual)) return false;
    _unlocked = true;
    return true;
  }

  /// Remove the PIN entirely (requires the caller to have verified first).
  Future<void> clearPin() async {
    await _storage.delete(key: _key);
    _unlocked = false;
  }

  /// Re-lock for this session (e.g. from a "lock now" action).
  void relock() => _unlocked = false;

  Future<List<int>> _derive(String pin, List<int> salt) {
    // Off the UI isolate (see [_deriveKeyInIsolate]).
    return compute(_deriveKeyInIsolate, <String, dynamic>{
      'pin': pin,
      'salt': salt,
      'iterations': _iterations,
    });
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
