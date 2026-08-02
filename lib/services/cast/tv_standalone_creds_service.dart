// Almacena, EN LA TV, las credenciales Xtream que la TV necesita para poder
// reproducir de forma standalone (sin depender del móvil como emisor) una vez
// que el usuario dio consentimiento explícito para ese emparejamiento.
// Cifrado en reposo vía FlutterSecureStorage — mismo patrón que
// playlist_secrets_service.dart / tmdb_credentials_service.dart.
//
// Scaffolding only: este servicio NO está conectado a ningún flujo de
// cast/LOAD/UI todavía. Solo provee el store.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TvStandaloneCredsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Índice de providerIds conocidos (JSON list de Strings). La secure
  /// storage no permite enumerar claves, así que este índice es la única
  /// forma de saber qué providerIds tienen credenciales guardadas —mismo
  /// truco que el índice de tokens de tv_receiver_host.dart.
  static const _indexKey = 'tv.standalone.creds.index';

  static String _key(String providerId, String field) =>
      'tv.standalone.creds.$providerId.$field';

  /// Guarda los 3 campos Xtream de [providerId]. Si algún campo viene vacío se
  /// borra (via [_writeOrDelete]).
  ///
  /// El índice se mantiene consistente con el contrato ATÓMICO de [load]: un
  /// providerId sólo queda indexado si sus 3 campos quedaron efectivamente
  /// guardados (no vacíos). Si alguno viene vacío, [load] devolvería null →
  /// se QUITA del índice para no dejar una entrada fantasma (un providerId que
  /// [listProviderIds] reporta pero [load] no puede resolver). Con esto,
  /// índice y store nunca divergen; el borrado también vive en [delete].
  static Future<void> save(
    String providerId, {
    required String url,
    required String user,
    required String pass,
  }) async {
    await Future.wait([
      _writeOrDelete(_key(providerId, 'url'), url),
      _writeOrDelete(_key(providerId, 'user'), user),
      _writeOrDelete(_key(providerId, 'pass'), pass),
    ]);
    final complete = url.isNotEmpty && user.isNotEmpty && pass.isNotEmpty;
    if (complete) {
      await _addToIndex(providerId);
    } else {
      await _removeFromIndex(providerId);
    }
  }

  /// Carga las credenciales de [providerId].
  ///
  /// Contrato: devuelve null si CUALQUIERA de los 3 campos falta (no hay
  /// credenciales parciales válidas — url/user/pass se guardan y se leen
  /// como un conjunto atómico).
  static Future<({String url, String user, String pass})?> load(
    String providerId,
  ) async {
    final values = await Future.wait([
      _storage.read(key: _key(providerId, 'url')),
      _storage.read(key: _key(providerId, 'user')),
      _storage.read(key: _key(providerId, 'pass')),
    ]);
    final url = values[0];
    final user = values[1];
    final pass = values[2];
    if (url == null || user == null || pass == null) return null;
    return (url: url, user: user, pass: pass);
  }

  /// Borra las credenciales de [providerId] y lo quita del índice.
  static Future<void> delete(String providerId) async {
    await Future.wait([
      _storage.delete(key: _key(providerId, 'url')),
      _storage.delete(key: _key(providerId, 'user')),
      _storage.delete(key: _key(providerId, 'pass')),
    ]);
    await _removeFromIndex(providerId);
  }

  /// providerIds con credenciales guardadas (según el índice).
  static Future<List<String>> listProviderIds() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  static Future<void> _addToIndex(String providerId) async {
    final ids = await listProviderIds();
    if (ids.contains(providerId)) return;
    ids.add(providerId);
    await _storage.write(key: _indexKey, value: jsonEncode(ids));
  }

  static Future<void> _removeFromIndex(String providerId) async {
    final ids = await listProviderIds();
    if (!ids.remove(providerId)) return;
    await _storage.write(key: _indexKey, value: jsonEncode(ids));
  }

  static Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
