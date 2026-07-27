import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';

import 'tmdb_search_result.dart';

/// How strongly a local content item matches a TMDb title.
///
/// `id` means the local stream's persisted TMDb id equals the TMDb result's id
/// (same media type) — the strongest, title-independent reconciliation. `exact`
/// means the normalized titles are equal (ignoring year/brackets/punctuation).
/// `fuzzy` is a substring match in either direction. `none` means no
/// relationship. Ordered strongest-first, so `.index` compares as strength
/// (lower wins) in the franchise owner-dedup.
enum MatchStrength { id, exact, fuzzy, none }

class LocalContentMatch {
  final Playlist playlist;
  final ContentItem content;
  final MatchStrength strength;

  const LocalContentMatch({
    required this.playlist,
    required this.content,
    this.strength = MatchStrength.none,
  });

  /// An id match is a definitive same-title reconciliation, so it counts as (at
  /// least) exact for the "owned" treatment even when the localized titles read
  /// differently.
  bool get isExactMatch =>
      strength == MatchStrength.id || strength == MatchStrength.exact;

  /// The TMDb id of the owned stream this match points at, when known. Sourced
  /// from the underlying VodStream/SeriesStream so search can reconcile by id.
  int? get tmdbId => content.tmdbId;

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
///
/// [people] is a distinct MODE, not a type filter: it searches TMDb for a
/// person and shows that person's filmography cross-referenced against the local
/// catalogue. The service treats it like [all] for the type-narrowing switches;
/// the UI routes it to the person picker instead of the text pipeline.
enum SearchFilter { all, movies, tv, live, wishlist, people }

class UnifiedSearchResults {
  final List<GlobalSearchResult> withLocal;
  final List<GlobalSearchResult> tmdbOnly;
  final List<LocalContentMatch> localOnly;

  /// Why the TMDb half produced nothing, or null when it succeeded. The local
  /// buckets are ALWAYS returned regardless — a TMDb failure must never take
  /// the user's own catalogue down with it, which the old `await tmdbFuture`
  /// without a catch did.
  final TmdbFailure? tmdbFailure;

  /// True for the first, local-only paint of a progressive search: the TMDb
  /// half has not resolved yet. Lets the UI show a discover-section skeleton
  /// instead of concluding "no TMDb results".
  final bool tmdbPending;

  const UnifiedSearchResults({
    required this.withLocal,
    required this.tmdbOnly,
    required this.localOnly,
    this.tmdbFailure,
    this.tmdbPending = false,
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
      // Carry the failure/pending state through: a wishlist toggle must not
      // silently clear the "TMDb was rejected" banner or the pending flag.
      tmdbFailure: tmdbFailure,
      tmdbPending: tmdbPending,
    );
  }
}
