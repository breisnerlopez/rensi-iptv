import 'dart:ui';

import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/database_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/type_convertions.dart';

class GlobalSearchService {
  GlobalSearchService({TmdbService? tmdbService})
    : _tmdbService = tmdbService ?? TmdbService();

  final TmdbService _tmdbService;

  // --- Title matching ------------------------------------------------------

  /// Classifies the relationship between a local title and a TMDb title.
  /// Picks the strongest applicable label.
  static MatchStrength classify(String local, String tmdb) {
    final normalizedLocal = _normalizeTitle(local);
    final normalizedTmdb = _normalizeTitle(tmdb);
    if (normalizedLocal.isEmpty || normalizedTmdb.isEmpty) {
      return MatchStrength.none;
    }
    if (normalizedLocal == normalizedTmdb) return MatchStrength.exact;
    if (normalizedLocal.contains(normalizedTmdb) ||
        normalizedTmdb.contains(normalizedLocal)) {
      return MatchStrength.fuzzy;
    }
    return MatchStrength.none;
  }

  /// The strongest classification of [local] against a TMDb result's localized
  /// title AND its original-language title (lower [MatchStrength.index] wins).
  static MatchStrength _bestClassify(String local, TmdbSearchResult tmdb) {
    var best = classify(local, tmdb.title);
    final original = tmdb.originalTitle;
    if (original != null && original.isNotEmpty) {
      final alt = classify(local, original);
      // Only let the original title UPGRADE the match to EXACT. A fuzzy
      // substring on the original ("It" ~ "It Chapter Two", "Up" ~ "7 Up")
      // would add false positives on top of what the localized title already
      // risks; an exact original-title match (an English-original catalogue vs
      // a localized TMDb title) is the legitimate win.
      if (alt == MatchStrength.exact && alt.index < best.index) best = alt;
    }
    return best;
  }

  static bool isExactTitleMatch(String local, String tmdb) =>
      classify(local, tmdb) == MatchStrength.exact;

  static bool isFuzzyTitleMatch(String local, String tmdb) {
    final c = classify(local, tmdb);
    return c == MatchStrength.fuzzy || c == MatchStrength.exact;
  }

  static String _normalizeTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ')
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
        // Keep letters and digits of ANY script, not just a-z0-9. The old class
        // stripped Cyrillic, Arabic, CJK and Devanagari to nothing, so
        // classify() returned `none` for every non-Latin title: a Russian or
        // Arabic user saw their OWN owned film duplicated — once playable in
        // "your IPTV", once as a non-playable "not in your lists" discovery.
        // This app ships those locales, and it reproduces on mobile with an IME,
        // so it is a correctness defect, not the TV-keyboard ceiling.
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
  }

  // --- Search --------------------------------------------------------------

  Future<UnifiedSearchResults> search(
    String query, {
    SearchFilter filter = SearchFilter.all,
    Locale? locale,
  }) async {
    if (filter == SearchFilter.wishlist) {
      return _wishlistAsResults(query);
    }

    final wishlistFuture = TmdbWishlistService.getKeys();
    final localFuture = _searchAllLocal(query);

    // TMDb must never take the local buckets down with it. A missing/rejected
    // key, a 429, a 5xx or an offline device now degrade to "local only" with
    // a typed reason, instead of throwing out of the whole search — which is
    // exactly what the bare `await tmdbFuture` used to do, leaving a user with
    // no key seeing nothing at all, not even their own catalogue.
    List<TmdbSearchResult> tmdbRaw = const [];
    TmdbFailure? failure;
    // The live filter is local-only (_filterTmdb discards TMDb for it), so skip
    // the network call entirely rather than fetch results we would throw away.
    if (filter != SearchFilter.live) {
      try {
        tmdbRaw = await _tmdbService.search(query, locale: locale);
      } on TmdbException catch (e) {
        failure = e.reason;
      } catch (_) {
        failure = TmdbFailure.network;
      }
    }

    final tmdbResults =
        _filterTmdb(tmdbRaw, filter).toList(growable: false);
    final wishlistKeys = await wishlistFuture;
    final localResults = _filterLocal(await localFuture, filter)
        .toList(growable: false);

    return _crossReference(
      tmdbResults,
      localResults,
      wishlistKeys,
      failure: failure,
    );
  }

  /// The shared cross-reference: given TMDb results, the local matches to test
  /// them against, and the wishlist keys, produces the three reproducible-first
  /// buckets (withLocal / tmdbOnly / localOnly) with owner-dedup. Extracted so
  /// [search] (search/multi) and [searchByPerson] (a person's filmography) build
  /// buckets through ONE implementation — the matching, franchise owner-dedup
  /// and bucketing live here only. Caps default to the search/multi values so
  /// that path is byte-identical; the filmography view raises them since a
  /// prolific actor's credits overflow the 10/15 search caps.
  UnifiedSearchResults _crossReference(
    List<TmdbSearchResult> tmdbResults,
    List<LocalContentMatch> localResults,
    Set<String> wishlistKeys, {
    TmdbFailure? failure,
    int withLocalCap = 15,
    int tmdbOnlyCap = 10,
    int localOnlyCap = 15,
  }) {
    final withLocal = <GlobalSearchResult>[];
    final tmdbOnly = <GlobalSearchResult>[];
    final localOnly = <LocalContentMatch>[];

    final matchedKeys = <String>{};

    for (final tmdbItem in tmdbResults) {
      final matches = _findMatchesFor(tmdbItem, localResults);
      final isWishlisted =
          wishlistKeys.contains('${tmdbItem.id}|${tmdbItem.mediaType.name}');

      for (final m in matches) {
        matchedKeys.add(m.dedupKey);
      }

      if (matches.isNotEmpty) {
        withLocal.add(
          GlobalSearchResult(
            tmdb: tmdbItem,
            localMatches: matches,
            isWishlisted: isWishlisted,
          ),
        );
      } else {
        tmdbOnly.add(
          GlobalSearchResult(
            tmdb: tmdbItem,
            localMatches: const [],
            isWishlisted: isWishlisted,
          ),
        );
      }
    }

    // A single owned stream can match several TMDb results — a franchise: owning
    // "Dune" fuzzy-matches "Dune", "Dune: Part Two", "Dune: Prophecy"… Left as
    // is, that one file appears once under each, so "your library" repeats it
    // (caught on a real TV: two identical "Dune 2021" cards). Assign each owned
    // stream to its STRONGEST match (exact over fuzzy); a TMDb result whose only
    // matches were claimed by stronger ones has no owned copy, so it drops to a
    // Discover (tmdbOnly) result instead of duplicating an owned title.
    if (withLocal.length > 1) {
      MatchStrength strengthFor(GlobalSearchResult e, String key) =>
          e.localMatches.firstWhere((m) => m.dedupKey == key).strength;
      final owner = <String, GlobalSearchResult>{};
      for (final entry in withLocal) {
        for (final m in entry.localMatches) {
          final cur = owner[m.dedupKey];
          if (cur == null ||
              strengthFor(entry, m.dedupKey).index <
                  strengthFor(cur, m.dedupKey).index) {
            owner[m.dedupKey] = entry;
          }
        }
      }
      final keptWithLocal = <GlobalSearchResult>[];
      for (final entry in withLocal) {
        final owned = entry.localMatches
            .where((m) => identical(owner[m.dedupKey], entry))
            .toList(growable: false);
        if (owned.isEmpty) {
          tmdbOnly.add(GlobalSearchResult(
            tmdb: entry.tmdb,
            localMatches: const [],
            isWishlisted: entry.isWishlisted,
          ));
        } else {
          keptWithLocal.add(GlobalSearchResult(
            tmdb: entry.tmdb,
            localMatches: owned,
            isWishlisted: entry.isWishlisted,
          ));
        }
      }
      withLocal
        ..clear()
        ..addAll(keptWithLocal);
    }

    // tmdb-id dedup: the id-vs-title reconciliation is done inside
    // [_findMatchesFor] — a local stream whose persisted tmdb_id equals a TMDb
    // result's id is matched (MatchStrength.id, stronger than any title match)
    // even when the localized titles don't string-match, so its dedupKey lands
    // in matchedKeys and it is dropped from localOnly below AND never emitted as
    // a duplicate Discover card. Streams without a stored id fall back to title
    // matching, unchanged.
    for (final result in localResults) {
      if (!matchedKeys.contains(result.dedupKey)) {
        localOnly.add(result);
      }
    }

    return UnifiedSearchResults(
      withLocal: withLocal.take(withLocalCap).toList(),
      tmdbOnly: tmdbOnly.take(tmdbOnlyCap).toList(),
      localOnly: localOnly.take(localOnlyCap).toList(),
      tmdbFailure: failure,
    );
  }

  // --- Search by actor -----------------------------------------------------

  /// People matching [query] (name + photo), for the person picker. Thin
  /// pass-through to [TmdbService.searchPerson]; may throw [TmdbException] which
  /// the UI maps to the same typed degradation banner as a text search.
  Future<List<TmdbPerson>> searchPeople(
    String query, {
    Locale? locale,
  }) =>
      _tmdbService.searchPerson(query, locale: locale);

  /// A selected person's filmography, cross-referenced against the local
  /// catalogue. Pulls `combined_credits`, then — exactly like [_wishlistAsResults]
  /// searches local per saved title — searches the local catalogue by EACH film
  /// title, unions the matches (deduped), and runs the SAME [_crossReference]
  /// buckets/owner-dedup as search/multi. TMDb failures degrade to a typed
  /// [UnifiedSearchResults.tmdbFailure] instead of throwing, so the person view
  /// never crashes on a missing/rejected key or offline device.
  Future<UnifiedSearchResults> searchByPerson(
    TmdbPerson person, {
    Locale? locale,
  }) async {
    List<TmdbSearchResult> credits = const [];
    TmdbFailure? failure;
    try {
      credits = await _tmdbService.getPersonCredits(person.id, locale: locale);
    } on TmdbException catch (e) {
      failure = e.reason;
    } catch (_) {
      failure = TmdbFailure.network;
    }

    // Union the local matches across every film title, deduped by dedupKey —
    // the same shape [_searchAllLocal] returns for a single query, so
    // [_crossReference] (and its franchise owner-dedup) works unchanged.
    final seen = <String>{};
    final localResults = <LocalContentMatch>[];
    for (final film in credits) {
      for (final m in await _searchAllLocal(film.title)) {
        if (seen.add(m.dedupKey)) localResults.add(m);
      }
    }

    final wishlistKeys = await TmdbWishlistService.getKeys();
    return _crossReference(
      credits,
      localResults,
      wishlistKeys,
      failure: failure,
      // A filmography is larger than a title search; raise the caps so a
      // prolific actor's credits are not clipped to the search/multi 10/15.
      withLocalCap: 40,
      tmdbOnlyCap: 60,
      localOnlyCap: 40,
    );
  }

  /// The instant, local-only first paint of a progressive search. Everything
  /// found locally lands in `localOnly` (there is no TMDb yet to promote a row
  /// into `withLocal`), with `tmdbPending: true` so the UI shows a discover
  /// skeleton rather than concluding there are no TMDb results. The follow-up
  /// [search] call returns the reshuffled, final three buckets.
  Future<UnifiedSearchResults> searchLocalFirst(
    String query, {
    SearchFilter filter = SearchFilter.all,
  }) async {
    if (filter == SearchFilter.wishlist) {
      // Wishlist is a browse of saved TMDb items; there is no instant local
      // phase to show, so skip straight to the real result.
      return _wishlistAsResults(query);
    }
    final localResults = _filterLocal(await _searchAllLocal(query), filter)
        .toList(growable: false);
    return UnifiedSearchResults(
      withLocal: const [],
      tmdbOnly: const [],
      localOnly: localResults.take(15).toList(),
      tmdbPending: true,
    );
  }

  Iterable<TmdbSearchResult> _filterTmdb(
    Iterable<TmdbSearchResult> items,
    SearchFilter filter,
  ) {
    switch (filter) {
      case SearchFilter.movies:
        return items.where((t) => t.mediaType == TmdbMediaType.movie);
      case SearchFilter.tv:
        return items.where((t) => t.mediaType == TmdbMediaType.tv);
      case SearchFilter.live:
        // Live channels have no TMDb counterpart; the live filter is
        // local-only. Return nothing so no Discover row is built for it.
        return const [];
      case SearchFilter.all:
      case SearchFilter.wishlist:
      case SearchFilter.people:
        return items;
    }
  }

  Iterable<LocalContentMatch> _filterLocal(
    Iterable<LocalContentMatch> items,
    SearchFilter filter,
  ) {
    switch (filter) {
      case SearchFilter.movies:
        return items.where((m) => m.content.contentType == ContentType.vod);
      case SearchFilter.tv:
        return items.where((m) => m.content.contentType == ContentType.series);
      case SearchFilter.live:
        return items
            .where((m) => m.content.contentType == ContentType.liveStream);
      case SearchFilter.all:
      case SearchFilter.wishlist:
      case SearchFilter.people:
        return items;
    }
  }

  /// Builds match objects already labelled with the strongest strength
  /// between [tmdb] and each candidate. Returns only matches that meet the
  /// fuzzy threshold, ordered exact-first.
  List<LocalContentMatch> _findMatchesFor(
    TmdbSearchResult tmdb,
    List<LocalContentMatch> localResults,
  ) {
    final out = <LocalContentMatch>[];
    for (final match in localResults) {
      // A live channel whose name happens to look like a film/show title must
      // never be promoted into the TMDb "in your library" (withLocal) bucket:
      // it has no TMDb counterpart and plays through LiveStreamScreen. Skipping
      // it here means it is never added to matchedKeys, so it falls through to
      // the localOnly bucket in _crossReference.
      if (match.content.contentType == ContentType.liveStream) continue;
      // ID match takes precedence over any title match: a stored tmdb_id equal
      // to this result's id (same media type) is a title-independent, definitive
      // reconciliation. This is what fixes a translated-title owned movie
      // (e.g. local "Duna" vs TMDb "Dune") being duplicated as an un-owned
      // Discover card — the title classify() would return none there.
      if (_isIdMatch(match, tmdb)) {
        out.add(match.withStrength(MatchStrength.id));
        continue;
      }
      // Fallback for streams without a stored id: compare the local title
      // against BOTH the localized TMDb title and its original-language title,
      // taking the STRONGER (lowest-index) result. An English-original catalogue
      // reconciles with a localized TMDb title, and vice-versa.
      final strength = _bestClassify(match.content.name, tmdb);
      if (strength == MatchStrength.none) continue;
      out.add(match.withStrength(strength));
    }
    out.sort((a, b) => a.strength.index.compareTo(b.strength.index));
    return out;
  }

  /// True when [match]'s persisted TMDb id equals [tmdb]'s id and the media
  /// types line up (movie↔vod, tv↔series). Streams without a stored id (id null
  /// or <= 0) never id-match, so they route to the title fallback.
  static bool _isIdMatch(LocalContentMatch match, TmdbSearchResult tmdb) {
    final localId = match.tmdbId;
    if (localId == null || localId <= 0 || localId != tmdb.id) return false;
    final ct = match.content.contentType;
    return (tmdb.mediaType == TmdbMediaType.movie && ct == ContentType.vod) ||
        (tmdb.mediaType == TmdbMediaType.tv && ct == ContentType.series);
  }

  /// Case variants of a query, to work around SQLite's LIKE folding only ASCII.
  /// 'дюна' would not match a stored 'Дюна' or 'ДЮНА', so a Cyrillic (or
  /// accented-Latin) user could miss their own title. Searching the query plus
  /// its lower/UPPER/Title forms and unioning covers the shapes panels actually
  /// use. Scripts without case (Arabic, CJK, Devanagari) collapse to one variant.
  static Set<String> _caseVariants(String query) {
    final q = query.trim();
    if (q.isEmpty) return const {};
    final title = q.substring(0, 1).toUpperCase() + q.substring(1).toLowerCase();
    return {q, q.toLowerCase(), q.toUpperCase(), title};
  }

  Future<List<LocalContentMatch>> _searchAllLocal(String query) async {
    final playlists = await PlaylistService.getPlaylists();
    final variants = _caseVariants(query);
    final jobs = <Future<List<LocalContentMatch>>>[];
    for (final playlist in playlists) {
      for (final v in variants) {
        jobs.add(playlist.type == PlaylistType.xtream
            ? _searchXtream(playlist, v)
            : _searchM3u(playlist, v));
      }
    }
    final results = await Future.wait(jobs);
    // A stream matched by more than one variant is still one row.
    final seen = <String>{};
    final out = <LocalContentMatch>[];
    for (final m in results.expand((e) => e)) {
      if (seen.add(m.dedupKey)) out.add(m);
    }
    return out;
  }

  Future<List<LocalContentMatch>> _searchXtream(
    Playlist playlist,
    String query,
  ) async {
    final db = DatabaseService.database;
    final matches = <LocalContentMatch>[];

    final movies = await db.searchMovieBroad(playlist.id, query);
    for (final movie in movies) {
      matches.add(
        LocalContentMatch(
          playlist: playlist,
          content: _contentForPlaylist(
            playlist,
            () => ContentItem(
              movie.streamId,
              movie.name,
              movie.streamIcon,
              ContentType.vod,
              containerExtension: movie.containerExtension,
              vodStream: movie,
            ),
          ),
        ),
      );
    }

    final series = await db.searchSeriesBroad(playlist.id, query);
    for (final serie in series) {
      matches.add(
        LocalContentMatch(
          playlist: playlist,
          content: _contentForPlaylist(
            playlist,
            () => ContentItem(
              serie.seriesId,
              serie.name,
              serie.cover ?? '',
              ContentType.series,
              seriesStream: serie,
            ),
          ),
        ),
      );
    }

    final channels = await db.searchLiveStreams(playlist.id, query);
    for (final channel in channels) {
      matches.add(
        LocalContentMatch(
          playlist: playlist,
          content: _contentForPlaylist(
            playlist,
            // liveStream: is MANDATORY — LiveStreamScreen reads
            // content.liveStream!.categoryId on playback and crashes without it.
            () => ContentItem(
              channel.streamId,
              channel.name,
              channel.streamIcon,
              ContentType.liveStream,
              liveStream: channel,
            ),
          ),
        ),
      );
    }

    return matches;
  }

  Future<List<LocalContentMatch>> _searchM3u(
    Playlist playlist,
    String query,
  ) async {
    final items = await DatabaseService.database.searchM3uItems(
      playlist.id,
      query,
      limit: 15,
    );
    return items
        .map(
          (item) => LocalContentMatch(
            playlist: playlist,
            content: _contentForPlaylist(playlist, () => _m3uContent(item)),
          ),
        )
        .toList(growable: false);
  }

  /// Wishlist as if it were a search result set. Useful for the "show me
  /// my saved titles" view. When [query] is non-empty we also filter
  /// in-memory by normalized title prefix/contains.
  Future<UnifiedSearchResults> _wishlistAsResults(String query) async {
    final wishlist = await TmdbWishlistService.getItems();
    final filtered = query.isEmpty
        ? wishlist
        : wishlist.where(
            (t) =>
                classify(t.title, query) != MatchStrength.none ||
                t.title.toLowerCase().contains(query.toLowerCase()),
          );

    final withLocal = <GlobalSearchResult>[];
    final tmdbOnly = <GlobalSearchResult>[];
    for (final t in filtered) {
      // Search local BY THIS ITEM'S TITLE. The old code did one broad search on
      // the (empty) browse query, which is `LIKE '%%'` capped at 30 arbitrary
      // alphabetical rows — so a wishlisted title you DO own but that sorts past
      // row 30 was misclassified as "not in your lists". Querying per title
      // makes the lookup relevant instead of alphabetical.
      final localForItem = await _searchAllLocal(t.title);
      final matches = _findMatchesFor(t, localForItem);
      if (matches.isNotEmpty) {
        withLocal.add(
          GlobalSearchResult(
            tmdb: t,
            localMatches: matches,
            isWishlisted: true,
          ),
        );
      } else {
        tmdbOnly.add(
          GlobalSearchResult(
            tmdb: t,
            localMatches: const [],
            isWishlisted: true,
          ),
        );
      }
    }
    return UnifiedSearchResults(
      withLocal: withLocal,
      tmdbOnly: tmdbOnly,
      localOnly: const [],
    );
  }

  Future<List<TmdbSearchResult>> getWishlist() =>
      TmdbWishlistService.getItems();

  Future<TmdbDetailResult> getDetail(
    TmdbSearchResult item, {
    Locale? locale,
    bool withCredits = false,
  }) =>
      _tmdbService.detail(
        item.id,
        item.mediaType,
        locale: locale,
        withCredits: withCredits,
      );

  /// Switches the global AppState so [navigateByContentType] will use the
  /// correct repository when the caller navigates next. This is a synchronous
  /// method by design — the caller is expected to call it and navigate in
  /// the same event-loop tick so two rapid taps cannot interleave.
  void openLocalMatch(LocalContentMatch match) {
    AppState.currentPlaylist = match.playlist;
    if (match.playlist.type == PlaylistType.xtream) {
      AppState.xtreamCodeRepository = IptvRepository(
        ApiConfig(
          baseUrl: match.playlist.url ?? '',
          username: match.playlist.username ?? '',
          password: match.playlist.password ?? '',
        ),
        match.playlist.id,
      );
    } else {
      AppState.m3uRepository = M3uRepository();
    }
  }

  ContentItem _contentForPlaylist(
    Playlist playlist,
    ContentItem Function() build,
  ) {
    final previous = AppState.currentPlaylist;
    AppState.currentPlaylist = playlist;
    try {
      return build();
    } finally {
      AppState.currentPlaylist = previous;
    }
  }

  ContentItem _m3uContent(M3uItem item) {
    return ContentItem(
      item.id,
      item.name ?? safeString(item.tvgName),
      item.tvgLogo ?? '',
      item.contentType,
      m3uItem: item,
    );
  }
}
