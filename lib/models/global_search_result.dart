import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';

import 'tmdb_search_result.dart';

/// How strongly a local content item matches a TMDb title.
///
/// `exact` means the normalized titles are equal (ignoring year/brackets/
/// punctuation). `fuzzy` is a substring match in either direction. `none`
/// means no relationship.
enum MatchStrength { exact, fuzzy, none }

class LocalContentMatch {
  final Playlist playlist;
  final ContentItem content;
  final MatchStrength strength;

  const LocalContentMatch({
    required this.playlist,
    required this.content,
    this.strength = MatchStrength.none,
  });

  bool get isExactMatch => strength == MatchStrength.exact;

  /// Stable identity used for dedup across sections. Two matches that point
  /// at the same stream inside the same playlist are considered the same row.
  String get dedupKey => '${playlist.id}|${content.id}|${content.contentType}';

  LocalContentMatch withStrength(MatchStrength next) => LocalContentMatch(
        playlist: playlist,
        content: content,
        strength: next,
      );
}

class GlobalSearchResult {
  final TmdbSearchResult tmdb;
  final List<LocalContentMatch> localMatches;
  final bool isWishlisted;

  bool get hasExactMatch => localMatches.any((m) => m.isExactMatch);

  const GlobalSearchResult({
    required this.tmdb,
    required this.localMatches,
    required this.isWishlisted,
  });

  GlobalSearchResult copyWith({
    TmdbSearchResult? tmdb,
    List<LocalContentMatch>? localMatches,
    bool? isWishlisted,
  }) {
    return GlobalSearchResult(
      tmdb: tmdb ?? this.tmdb,
      localMatches: localMatches ?? this.localMatches,
      isWishlisted: isWishlisted ?? this.isWishlisted,
    );
  }
}

/// Restricts what kinds of items the search will return.
enum SearchFilter { all, movies, tv, wishlist }

class UnifiedSearchResults {
  final List<GlobalSearchResult> withLocal;
  final List<GlobalSearchResult> tmdbOnly;
  final List<LocalContentMatch> localOnly;

  const UnifiedSearchResults({
    required this.withLocal,
    required this.tmdbOnly,
    required this.localOnly,
  });

  bool get isEmpty =>
      withLocal.isEmpty && tmdbOnly.isEmpty && localOnly.isEmpty;

  /// Re-stamps the wishlist flag on each TMDb result without touching matches.
  /// Used by the UI to flip the bookmark icon immediately on toggle.
  UnifiedSearchResults withWishlistKeys(Set<String> keys) {
    bool inWishlist(TmdbSearchResult t) =>
        keys.contains('${t.id}|${t.mediaType.name}');
    return UnifiedSearchResults(
      withLocal: withLocal
          .map((r) => r.copyWith(isWishlisted: inWishlist(r.tmdb)))
          .toList(growable: false),
      tmdbOnly: tmdbOnly
          .map((r) => r.copyWith(isWishlisted: inWishlist(r.tmdb)))
          .toList(growable: false),
      localOnly: localOnly,
    );
  }
}
