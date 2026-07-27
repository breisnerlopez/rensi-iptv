import 'package:rensi_iptv/models/playlist_content_model.dart';

/// Single source of truth for reading, splitting and matching the packed
/// `genre` string carried by VOD/series content.
///
/// Genres live as one multi-value string per row (e.g. `"Acción, Aventura"` or
/// `"Drama / Suspense"`), never normalized at ingest. Historically two screens
/// parsed this differently — Browse used a weak `[,/]` split with a *substring*
/// match (so a "Drama" chip also caught "Melodrama"), while CategoryDetail used
/// the richer separator set with exact-token matching. These helpers unify on
/// the correct behaviour so Browse, Search and CategoryDetail agree.
///
/// Matching is deliberately in-memory and token-exact against genres enumerated
/// FROM the catalogue itself: the chip label and the item's token come from the
/// same stored bytes, so a lowercase equality is accent-safe by construction —
/// something a SQLite `LIKE '%acción%'` (ASCII-only case folding) cannot promise.

/// Separators seen across providers: comma, slash, backslash, pipe, semicolon
/// and the Arabic comma, each with optional surrounding whitespace. Ampersand is
/// deliberately NOT a separator — TMDb-style genres embed it as one name
/// ("Action & Adventure", "Sci-Fi & Fantasy", "War & Politics"), so splitting on
/// it would fragment a real genre into two that never match a full-name chip.
final RegExp _genreSeparators = RegExp(r'\s*[,/\\|;،]+\s*');

/// The raw packed genre string for [item] — series read `seriesStream.genre`,
/// everything else reads `vodStream.genre`. Null when absent.
String? genreOf(ContentItem item) {
  if (item.contentType.name == 'series') {
    return item.seriesStream?.genre;
  }
  return item.vodStream?.genre;
}

/// Split one packed genre string into its distinct, trimmed, non-empty tokens.
List<String> splitGenres(String raw) {
  return raw
      .split(_genreSeparators)
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();
}

/// Every distinct genre across [items], sorted case-insensitively. Preserves the
/// first-seen display casing of each genre (so "Acción" shows, not "acción").
List<String> enumerateGenres(Iterable<ContentItem> items) {
  final byLower = <String, String>{};
  for (final item in items) {
    final raw = genreOf(item);
    if (raw == null || raw.isEmpty) continue;
    for (final g in splitGenres(raw)) {
      byLower.putIfAbsent(g.toLowerCase(), () => g);
    }
  }
  final result = byLower.values.toList();
  result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

/// Whether [item] carries [genre] as one of its tokens (lowercase exact match —
/// not substring, so "Drama" never matches "Melodrama").
bool itemHasGenre(ContentItem item, String genre) {
  final raw = genreOf(item);
  if (raw == null || raw.isEmpty) return false;
  final target = genre.trim().toLowerCase();
  if (target.isEmpty) return false;
  for (final g in splitGenres(raw)) {
    if (g.toLowerCase() == target) return true;
  }
  return false;
}
