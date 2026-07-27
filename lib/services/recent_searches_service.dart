import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's recent search queries in [SharedPreferences] as a plain
/// string list, newest-first. Mirrors the static, prefs-backed shape of
/// [TmdbWishlistService].
///
/// Rules:
///  * Newest-first, capped at [_maxEntries].
///  * Case-insensitive dedupe — a re-searched term moves to the front and keeps
///    the NEWEST casing the user typed.
///  * Queries shorter than 2 characters are ignored (matches the search floor).
///  * Deliberately kept OUT of the backup key set — recent searches are private
///    session data, not settings to sync.
class RecentSearchesService {
  static const _key = 'recent.searches';

  /// A prior build stored a search history under this key; it is orphaned now.
  /// Removed on the first write and on [clear] so it can't linger forever.
  static const _legacyKey = 'tmdb.search.history';

  static const _maxEntries = 10;

  static Future<List<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const <String>[];
  }

  /// Records [query] as the most-recent search. Trims it, ignores anything under
  /// two characters, dedupes case-insensitively (keeping the new casing at the
  /// front), and truncates to [_maxEntries].
  static Future<void> record(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final prefs = await SharedPreferences.getInstance();
    // First write cleans up the orphaned legacy key.
    await prefs.remove(_legacyKey);
    final list = prefs.getStringList(_key) ?? <String>[];
    final lower = q.toLowerCase();
    list.removeWhere((e) => e.toLowerCase() == lower);
    list.insert(0, q);
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }
    await prefs.setStringList(_key, list);
  }

  /// Removes a single entry (case-insensitive match).
  static Future<void> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);
    if (list == null) return;
    final lower = query.trim().toLowerCase();
    final next = list.where((e) => e.toLowerCase() != lower).toList();
    if (next.length != list.length) {
      await prefs.setStringList(_key, next);
    }
  }

  /// Clears all recent searches (and the orphaned legacy key).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_legacyKey);
  }
}
