// Lado MÓVIL: recuerda qué pares (tvId, providerId) el usuario aprobó
// explícitamente para reproducción standalone en la TV (la TV podrá usar sus
// propias credenciales guardadas sin que el móvil actúe de emisor). No son
// datos sensibles (son solo flags de consentimiento), así que se guardan en
// SharedPreferences en vez de secure storage — a diferencia de las
// credenciales Xtream en sí (ver tv_standalone_creds_service.dart, que SÍ
// vive cifrado y del lado de la TV).
//
// Scaffolding only: este store NO está conectado a ningún flujo de
// cast/LOAD/UI todavía.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StandaloneConsentStore {
  static const _key = 'standalone.consent.granted';

  /// Feature H — cola PERSISTENTE de borrados pendientes por (tvId, providerId).
  /// Al revocar el consentimiento en Ajustes, además de quitar el permiso se
  /// encola aquí un wipe: el móvil no suele estar conectado a la TV en ese
  /// momento, así que el borrado REAL de las credenciales en la TV se hace la
  /// próxima vez que el móvil se conecta a ese tvId (envía CmdType.wipeStandalone
  /// y limpia el pendiente). Sobrevive a cierres de la app.
  static const _pendingWipeKey = 'standalone.consent.pending_wipe';

  /// True si el usuario ya dio consentimiento para que [tvId] reproduzca de
  /// forma standalone contenido de [providerId].
  static Future<bool> isGranted(String tvId, String providerId) async {
    final entries = await _load();
    return entries.any((e) => e['tvId'] == tvId && e['providerId'] == providerId);
  }

  /// Otorga el consentimiento. Idempotente: si ya estaba otorgado no agrega
  /// una entrada duplicada.
  static Future<void> grant(String tvId, String providerId) async {
    final entries = await _load();
    final exists =
        entries.any((e) => e['tvId'] == tvId && e['providerId'] == providerId);
    if (exists) return;
    entries.add({'tvId': tvId, 'providerId': providerId});
    await _save(entries);
  }

  /// Revoca el consentimiento (no-op si no estaba otorgado).
  static Future<void> revoke(String tvId, String providerId) async {
    final entries = await _load();
    final before = entries.length;
    entries.removeWhere(
        (e) => e['tvId'] == tvId && e['providerId'] == providerId);
    if (entries.length == before) return;
    await _save(entries);
  }

  /// Todos los pares (tvId, providerId) con consentimiento vigente.
  static Future<List<({String tvId, String providerId})>> listGranted() async {
    final entries = await _load();
    return entries
        .map((e) => (tvId: e['tvId'] as String, providerId: e['providerId'] as String))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> _save(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(entries));
  }

  // ── Cola de borrados pendientes (wipe real en la TV) ─────────────────────

  /// Encola un borrado pendiente de las credenciales de [providerId] en [tvId].
  /// Idempotente. Se llama al revocar el consentimiento en Ajustes.
  static Future<void> markPendingWipe(String tvId, String providerId) async {
    final entries = await _loadPending();
    final exists = entries
        .any((e) => e['tvId'] == tvId && e['providerId'] == providerId);
    if (exists) return;
    entries.add({'tvId': tvId, 'providerId': providerId});
    await _savePending(entries);
  }

  /// providerIds con borrado pendiente para [tvId] (los que el móvil debe pedir
  /// borrar la próxima vez que se conecte a esa TV).
  static Future<List<String>> pendingWipesFor(String tvId) async {
    final entries = await _loadPending();
    return [
      for (final e in entries)
        if (e['tvId'] == tvId) e['providerId'] as String
    ];
  }

  /// Quita el borrado pendiente de (tvId, providerId) tras enviarlo a la TV.
  static Future<void> clearPendingWipe(String tvId, String providerId) async {
    final entries = await _loadPending();
    final before = entries.length;
    entries.removeWhere(
        (e) => e['tvId'] == tvId && e['providerId'] == providerId);
    if (entries.length == before) return;
    await _savePending(entries);
  }

  static Future<List<Map<String, dynamic>>> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingWipeKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> _savePending(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingWipeKey, jsonEncode(entries));
  }
}
