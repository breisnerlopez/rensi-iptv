// Recuerda las TVs emparejadas en el MÓVIL durante 7 días, para no volver a
// pedir el PIN en cada envío. Guarda, por id de TV, un token de larga duración
// (emitido por la TV al emparejar) con su vencimiento. Sencillo a propósito: sin
// UI de gestión ni "olvidar" — simplemente caduca.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CastTrustStore {
  const CastTrustStore();

  static const _key = 'cast.trust.v1';
  static const Duration ttl = Duration(days: 7);

  FlutterSecureStorage get _storage => const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Token vigente para [tvId], o null si no hay o ya venció.
  Future<String?> tokenFor(String tvId) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final entry = map[tvId] as Map<String, dynamic>?;
    if (entry == null) return null;
    if (_now > (entry['e'] as int)) return null; // vencido
    return entry['t'] as String;
  }

  /// Guarda el token de [tvId] con vencimiento a 7 días.
  Future<void> save(String tvId, String token) async {
    final raw = await _storage.read(key: _key);
    final map = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : <String, dynamic>{};
    map[tvId] = {'t': token, 'e': _now + ttl.inMilliseconds};
    await _storage.write(key: _key, value: jsonEncode(map));
  }
}
