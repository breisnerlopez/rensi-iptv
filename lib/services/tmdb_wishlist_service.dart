import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tmdb_search_result.dart';

class TmdbWishlistService {
  static const _key = 'tmdb.wishlist';

  static Future<List<TmdbSearchResult>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(TmdbSearchResult.fromJson)
        .toList();
  }

  /// Stable `'<id>|<mediaType.name>'` keys for O(1) membership checks.
  /// Old key format (`'42|TmdbMediaType.movie'`) was migrated to the short
  /// form when this service started, so callers can assume the short form.
  static Future<Set<String>> getKeys() async {
    final items = await getItems();
    return items.map(_keyFor).toSet();
  }

  static String _keyFor(TmdbSearchResult item) =>
      '${item.id}|${item.mediaType.name}';

  static Future<bool> contains(TmdbSearchResult item) async {
    final keys = await getKeys();
    return keys.contains(_keyFor(item));
  }

  static Future<bool> toggle(TmdbSearchResult item) async {
    final items = await getItems();
    final index = items.indexWhere(
      (saved) => saved.id == item.id && saved.mediaType == item.mediaType,
    );
    if (index >= 0) {
      items.removeAt(index);
      await _save(items);
      return false;
    }
    items.insert(0, item);
    await _save(items);
    return true;
  }

  static Future<void> remove(TmdbSearchResult item) async {
    final items = await getItems();
    items.removeWhere(
      (saved) => saved.id == item.id && saved.mediaType == item.mediaType,
    );
    await _save(items);
  }

  static Future<void> _save(List<TmdbSearchResult> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
