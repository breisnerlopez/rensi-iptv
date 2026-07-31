import 'dart:ui';

import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/series_response.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/database_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/genre_utils.dart';
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

  /// The grouping keys that make two local streams "the same logical title":
  /// its normalized title AND, when the stream carries a persisted tmdb id, that
  /// id — both, so a copy matched only by id and a copy matched only by title
  /// still land in the same group. The content type is folded into each key so a
  /// movie and a show sharing a name never group. Used by [_crossReference] to
  /// attach a title's scattered owned copies to the one card that represents it.
  static List<String> _variantKeys(LocalContentMatch m) {
    final type = m.content.contentType;
    final keys = <String>['title:${_normalizeTitle(m.content.name)}|$type'];
    final id = m.tmdbId;
    if (id != null && id > 0) keys.add('id:$id|$type');
    return keys;
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

    // Fold same-title local variants into the card a sibling already claimed.
    // A single logical title is often owned as several DISTINCT streams: two
    // playlists that both carry it, or several series_ids inside ONE playlist
    // that pack different season ranges (a 1-, a 6- and a 7-season copy of the
    // same show). Only some of those copies string-match the TMDb result — a
    // sibling may have matched only by its persisted tmdb_id, or by the TMDb
    // original-language title, so a copy with a slightly different local name
    // (a "(Latino)" suffix, a localized-vs-original spelling) matches nothing
    // and scatters into localOnly as a separate card, vanishing from the owned
    // title's "Reproducir desde" list. Group the still-unmatched local streams
    // by the SAME keys search dedups by — normalized title AND persisted tmdb id
    // (both, so an id-matched sibling and a title-only variant still meet) — and
    // when a withLocal card already owns a stream in that group, attach the rest
    // to it. Marked matched so they are not ALSO emitted as a duplicate
    // localOnly/Discover row. Type is baked into the key so a movie "Rick" never
    // folds into a show "Rick".
    if (withLocal.isNotEmpty) {
      final cardForKey = <String, GlobalSearchResult>{};
      for (final entry in withLocal) {
        for (final m in entry.localMatches) {
          for (final k in _variantKeys(m)) {
            cardForKey.putIfAbsent(k, () => entry);
          }
        }
      }
      final folded = <GlobalSearchResult, List<LocalContentMatch>>{};
      for (final result in localResults) {
        if (matchedKeys.contains(result.dedupKey)) continue;
        if (result.content.contentType == ContentType.liveStream) continue;
        GlobalSearchResult? card;
        for (final k in _variantKeys(result)) {
          card = cardForKey[k];
          if (card != null) break;
        }
        if (card == null) continue;
        (folded[card] ??= <LocalContentMatch>[])
            .add(result.withStrength(MatchStrength.fuzzy));
        matchedKeys.add(result.dedupKey);
      }
      if (folded.isNotEmpty) {
        for (var i = 0; i < withLocal.length; i++) {
          final add = folded[withLocal[i]];
          if (add == null) continue;
          withLocal[i] = GlobalSearchResult(
            tmdb: withLocal[i].tmdb,
            localMatches: [...withLocal[i].localMatches, ...add],
            isWishlisted: withLocal[i].isWishlisted,
          );
        }
      }
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

  // --- Search by studio ----------------------------------------------------

  /// Companies/networks matching [query] (name + logo), for the studio picker.
  /// Thin pass-through to [TmdbService.searchCompany]; may throw
  /// [TmdbException] which the UI maps to the same typed degradation banner as a
  /// person/text search.
  Future<List<TmdbCompany>> searchCompanies(
    String query, {
    Locale? locale,
  }) =>
      _tmdbService.searchCompany(query, locale: locale);

  /// A selected studio's filmography, cross-referenced against the local
  /// catalogue. The exact shape of [searchByPerson]: pulls the studio's discover
  /// page, searches the local catalogue by EACH film title, unions the matches
  /// (deduped), and runs the SAME [_crossReference] buckets/owner-dedup as
  /// search/multi (owned titles play, the rest become Discover). TMDb failures
  /// degrade to a typed [UnifiedSearchResults.tmdbFailure] instead of throwing.
  Future<UnifiedSearchResults> searchByCompany(
    TmdbCompany company, {
    Locale? locale,
  }) async {
    List<TmdbSearchResult> films = const [];
    TmdbFailure? failure;
    try {
      films = await _tmdbService.discoverByCompany(company, locale: locale);
    } on TmdbException catch (e) {
      failure = e.reason;
    } catch (_) {
      failure = TmdbFailure.network;
    }

    final seen = <String>{};
    final localResults = <LocalContentMatch>[];
    for (final film in films) {
      for (final m in await _searchAllLocal(film.title)) {
        if (seen.add(m.dedupKey)) localResults.add(m);
      }
    }

    final wishlistKeys = await TmdbWishlistService.getKeys();
    return _crossReference(
      films,
      localResults,
      wishlistKeys,
      failure: failure,
      // A studio's filmography is larger than a title search; raise the caps to
      // match the person-filmography view rather than the search/multi 10/15.
      withLocalCap: 40,
      tmdbOnlyCap: 60,
      localOnlyCap: 40,
    );
  }

  // --- Search by genre -----------------------------------------------------

  /// The distinct genre names present in the CURRENT playlist's VOD + series
  /// catalogue, sorted case-insensitively via [enumerateGenres]. LOCAL-ONLY:
  /// no TMDb call, no failure surface — this answers "what genres do I own?".
  /// Returns an empty list (never throws) when there is no current playlist or
  /// it carries no genre data (e.g. an M3U playlist, whose items don't carry
  /// the packed `genre` string the helper reads).
  Future<List<String>> enumerateLocalGenres() async {
    return enumerateGenres(await _currentPlaylistCatalogue());
  }

  /// Every owned title in the CURRENT playlist that carries [genre] as one of
  /// its tokens (exact, accent-safe token match via [itemHasGenre]), wrapped as
  /// [LocalContentMatch] EXACTLY like the text-search builders in [_searchXtream]
  /// so the UI plays them through the same owned-content path. LOCAL-ONLY;
  /// returns an empty list (never throws) when nothing matches / no playlist.
  Future<List<LocalContentMatch>> searchLocalByGenre(String genre) async {
    final playlist = AppState.currentPlaylist;
    if (playlist == null) return const [];
    final out = <LocalContentMatch>[];
    for (final item in await _currentPlaylistCatalogue()) {
      if (itemHasGenre(item, genre)) {
        out.add(LocalContentMatch(playlist: playlist, content: item));
      }
    }
    return out;
  }

  // Memoized full catalogue, keyed by playlist id. Entering the genre mode
  // enumerates genres (one full load) and every genre tap filters the catalogue;
  // without this each tap re-read every VOD+series row on the UI isolate (jank on
  // weak TV boxes with large catalogues). Invalidated when the playlist changes.
  List<ContentItem>? _catalogueCache;
  String? _catalogueCacheKey;

  /// The current playlist's full VOD + series catalogue as [ContentItem]s,
  /// wrapped exactly as [_searchXtream] does (so genre matching sees the same
  /// `vodStream`/`seriesStream` the search path builds). Only Xtream playlists
  /// carry the packed `genre` string; M3U items and live channels don't, so a
  /// non-Xtream or absent current playlist yields an empty catalogue.
  Future<List<ContentItem>> _currentPlaylistCatalogue() async {
    final playlist = AppState.currentPlaylist;
    if (playlist == null || playlist.type != PlaylistType.xtream) {
      return const [];
    }
    if (_catalogueCacheKey == playlist.id && _catalogueCache != null) {
      return _catalogueCache!;
    }
    final db = DatabaseService.database;
    final out = <ContentItem>[];
    final movies = await db.getVodStreamsByPlaylistId(playlist.id);
    for (final movie in movies) {
      out.add(
        _contentForPlaylist(
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
      );
    }
    final series = await db.getSeriesStreamsByPlaylistId(playlist.id);
    for (final serie in series) {
      out.add(
        _contentForPlaylist(
          playlist,
          () => ContentItem(
            serie.seriesId,
            serie.name,
            serie.cover ?? '',
            ContentType.series,
            seriesStream: serie,
          ),
        ),
      );
    }
    _catalogueCache = out;
    _catalogueCacheKey = playlist.id;
    return out;
  }

  // Memoized GLOBAL catalogue (every playlist), keyed by the set of playlist
  // ids. Browse fans out over ALL playlists' full VOD+series catalogue; without
  // this each Browse rebuild would re-read every row of every playlist on the UI
  // isolate. The key is the playlist-id set, NOT the active playlist: the global
  // catalogue is the same regardless of which playlist is active, so merely
  // switching the active playlist does not invalidate it. Adding/removing a
  // playlist changes the key → reload. (A content re-sync of an existing
  // playlist does NOT change the key — same staleness contract as
  // [_currentPlaylistCatalogue].)
  List<LocalContentMatch>? _globalCatalogueCache;
  String? _globalCatalogueCacheKey;

  /// The FULL VOD + series catalogue across ALL playlists, each item wrapped as
  /// a [LocalContentMatch] carrying its ORIGIN playlist — the exact shape
  /// [_searchAllLocal] returns, so a caller can play any item through
  /// [openLocalMatch] with the origin playlist's credentials. Fans out per
  /// playlist exactly like [_searchAllLocal] (Xtream reads the DB directly by
  /// playlist id; M3U reads its stored items), and memoizes the merged result.
  ///
  /// Cost: O(sum of every playlist's VOD+series rows) DB reads on first call,
  /// then cached. Live channels are excluded — Browse is movies+series only.
  /// Returns an empty list (never throws) when there are no playlists.
  Future<List<LocalContentMatch>> globalCatalogue() async {
    final playlists = await PlaylistService.getPlaylists();
    final key = playlists.map((p) => p.id).join('|');
    if (_globalCatalogueCacheKey == key && _globalCatalogueCache != null) {
      return _globalCatalogueCache!;
    }
    final jobs = <Future<List<LocalContentMatch>>>[];
    for (final playlist in playlists) {
      jobs.add(playlist.type == PlaylistType.xtream
          ? _xtreamCatalogue(playlist)
          : _m3uCatalogue(playlist));
    }
    final results = await Future.wait(jobs);
    final out = results.expand((e) => e).toList();
    _globalCatalogueCache = out;
    _globalCatalogueCacheKey = key;
    return out;
  }

  /// Drops the memoized global catalogue so the next [globalCatalogue] call
  /// re-reads every playlist from the DB. Called when a playlist's catalogue is
  /// re-synced (rows added/removed with the SAME playlist-id set, which the
  /// id-set cache key alone can't detect) so Browse never shows a title whose
  /// stream was deleted upstream until an app restart.
  void invalidateGlobalCatalogue() {
    _globalCatalogueCache = null;
    _globalCatalogueCacheKey = null;
  }

  /// One playlist's full Xtream VOD + series catalogue, wrapped as
  /// [LocalContentMatch] exactly like [_currentPlaylistCatalogue] and
  /// [_searchXtream] (so genre/date/tmdbId read the same `vodStream`/
  /// `seriesStream` the rest of the app builds). Reads the DB directly by
  /// playlist id, so it does NOT require the origin playlist to be the active
  /// one — the fan-out never repoints AppState.
  Future<List<LocalContentMatch>> _xtreamCatalogue(Playlist playlist) async {
    final db = DatabaseService.database;
    final out = <LocalContentMatch>[];
    final movies = await db.getVodStreamsByPlaylistId(playlist.id);
    for (final movie in movies) {
      out.add(LocalContentMatch(
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
      ));
    }
    final series = await db.getSeriesStreamsByPlaylistId(playlist.id);
    for (final serie in series) {
      out.add(LocalContentMatch(
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
      ));
    }
    return out;
  }

  /// One M3U playlist's VOD + series items, wrapped as [LocalContentMatch] via
  /// the same [_m3uContent] the search path uses. Live channels are dropped
  /// (Browse is movies+series). M3U items carry no genre/tmdbId/createdAt, so
  /// downstream they degrade gracefully (no genre chip, no id-dedup, no date
  /// sort) — they still show and still play through the same M3U route.
  Future<List<LocalContentMatch>> _m3uCatalogue(Playlist playlist) async {
    final items =
        await DatabaseService.database.getM3uItemsByPlaylist(playlist.id);
    final out = <LocalContentMatch>[];
    for (final item in items) {
      if (item.contentType == ContentType.liveStream) continue;
      out.add(LocalContentMatch(
        playlist: playlist,
        content: _contentForPlaylist(playlist, () => _m3uContent(item)),
      ));
    }
    return out;
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
      case SearchFilter.studio:
      // Genre is a local-only mode: it never runs the TMDb text pipeline, so
      // whatever reaches here (it won't in practice) is passed through like all.
      case SearchFilter.genre:
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
      case SearchFilter.studio:
      // Genre mode filters the catalogue by genre itself (searchLocalByGenre),
      // not by content type, so it does not narrow here — passes through.
      case SearchFilter.genre:
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
      // A title-only match must ALSO agree on media type: a TMDb movie must not
      // claim a local series (or vice-versa) merely because a common leading word
      // makes the titles fuzzy-overlap. Without this, searching the FIRST word of
      // an owned show ("Rick" for "Rick y Morty") pulls in a TMDb movie literally
      // titled "Rick"; the owned series then fuzzy-matches that movie
      // ("rick y morty".contains("rick")), is hijacked into the movie's Discover
      // card, and vanishes as itself — so the first token appears to "find
      // nothing" while a later, unambiguous token ("morty") still hits. The id
      // match above is exempt: a persisted tmdb_id is a definitive, title- and
      // type-checked reconciliation on its own.
      if (!_typesLineUp(match.content.contentType, tmdb.mediaType)) continue;
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
    return _typesLineUp(match.content.contentType, tmdb.mediaType);
  }

  /// True when a local content type and a TMDb media type describe the same kind
  /// of work: movie ↔ vod, tv ↔ series. Live streams (and any other type) never
  /// line up with a TMDb film/show. Used to gate BOTH the id and the title
  /// reconciliation so a cross-type fuzzy title overlap can't claim a stream.
  static bool _typesLineUp(ContentType ct, TmdbMediaType mediaType) =>
      (mediaType == TmdbMediaType.movie && ct == ContentType.vod) ||
      (mediaType == TmdbMediaType.tv && ct == ContentType.series);

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

  // --- Popular (Home rail) -------------------------------------------------

  /// The Home "Popular" rail, cross-referenced against the local catalogue but
  /// RANK-PRESERVING: unlike [_crossReference] (which reshuffles into three
  /// buckets and would lose TMDb's popularity order), this walks
  /// [TmdbService.popularMovies] in order and, for each title, cross-references
  /// against a local search. Owned titles (localMatches non-empty) play; the
  /// rest become Discover cards — the exact matching as search, minus the
  /// bucketing. A TMDb failure degrades to an empty list (the rail hides) rather
  /// than throwing, so Home never shows an error banner for this optional rail.
  Future<List<GlobalSearchResult>> popular(
    PopularWindow window, {
    int? year,
    Locale? locale,
  }) async {
    List<TmdbSearchResult> movies;
    try {
      movies =
          await _tmdbService.popularMovies(window, year: year, locale: locale);
    } on TmdbException {
      return const [];
    }
    return _rankPreservingCrossRef(movies);
  }

  /// Browse's "Populares por género": [popular], scoped to one genre chip.
  /// Resolves the localized [genreName] to a TMDb MOVIE genre id, then runs the
  /// SAME rank-preserving cross-reference as [popular]. MOVIES-ONLY, exactly
  /// like the Home rail (see [TmdbService.popularMovies]); a series-only genre
  /// name simply resolves to no movie id and degrades. Degrades to an EMPTY list
  /// — which the Browse section renders as "no popular row, just the local grid"
  /// — on every soft-failure path: no TMDb key, a chip name that maps to no TMDb
  /// genre in this language, an empty TMDb page, or any [TmdbException].
  Future<List<GlobalSearchResult>> popularByGenre(
    String genreName,
    PopularWindow window, {
    int? year,
    Locale? locale,
  }) async {
    int? genreId;
    try {
      genreId = await _tmdbService.genreIdForName(
        genreName,
        mediaType: TmdbMediaType.movie,
        locale: locale,
      );
    } on TmdbException {
      return const [];
    }
    if (genreId == null) return const [];

    List<TmdbSearchResult> movies;
    try {
      movies = await _tmdbService.popularMovies(
        window,
        year: year,
        genreId: genreId,
        locale: locale,
      );
    } on TmdbException {
      return const [];
    }
    return _rankPreservingCrossRef(movies);
  }

  /// Cross-references an ORDERED TMDb list against the local catalogue WITHOUT
  /// reshuffling (unlike [_crossReference]): each title keeps its TMDb rank,
  /// gains its owned local matches (if any) and its wishlist flag. Shared by
  /// [popular] and [popularByGenre] so both rails match identically.
  Future<List<GlobalSearchResult>> _rankPreservingCrossRef(
    List<TmdbSearchResult> tmdbItems,
  ) async {
    if (tmdbItems.isEmpty) return const [];
    final wishlistKeys = await TmdbWishlistService.getKeys();
    final out = <GlobalSearchResult>[];
    for (final tmdb in tmdbItems) {
      final local = await _searchAllLocal(tmdb.title);
      final matches = _findMatchesFor(tmdb, local);
      out.add(GlobalSearchResult(
        tmdb: tmdb,
        localMatches: _foldSameTitleVariants(matches, local),
        isWishlisted:
            wishlistKeys.contains('${tmdb.id}|${tmdb.mediaType.name}'),
      ));
    }
    return out;
  }

  /// Attaches to [matched] the still-unmatched local streams that are the SAME
  /// logical title (share a [_variantKeys] key with a matched copy). The Popular
  /// rails cross-reference each title on its OWN local search, so unlike
  /// [_crossReference] they had no variant-folding step: a title owned as
  /// several distinct streams (two playlists, or several season-pack series_ids)
  /// showed only the copy that string/id-matched, and the others vanished from
  /// the detail sheet's "Reproducir desde" list. Fold them in the same way so a
  /// sheet opened from "Populares por género" lists ALL owned copies, exactly
  /// like search. Live streams are never folded (no TMDb counterpart).
  List<LocalContentMatch> _foldSameTitleVariants(
    List<LocalContentMatch> matched,
    List<LocalContentMatch> local,
  ) {
    if (matched.isEmpty) return matched;
    final keys = <String>{for (final m in matched) ..._variantKeys(m)};
    final have = <String>{for (final m in matched) m.dedupKey};
    final out = List<LocalContentMatch>.from(matched);
    for (final cand in local) {
      if (cand.content.contentType == ContentType.liveStream) continue;
      if (have.contains(cand.dedupKey)) continue;
      if (_variantKeys(cand).any(keys.contains)) {
        out.add(cand.withStrength(MatchStrength.fuzzy));
        have.add(cand.dedupKey);
      }
    }
    return out;
  }

  Future<List<TmdbSearchResult>> getWishlist() =>
      TmdbWishlistService.getItems();

  // Per-variant season-count cache, keyed by playlist id + series id (NOT by
  // title): a logical title can be owned as several series_ids that each pack a
  // different season range, so the count is fetched and cached per stream. A
  // cached null means "fetched, but unknown" — it is not refetched.
  final Map<String, int?> _seasonCountCache = {};

  /// The number of seasons an owned SERIES variant packs, read from the origin
  /// playlist's Xtream `get_series_info`. Lets the search detail sheet label
  /// each "Reproducir desde" row with its season count so a user can tell the
  /// 7-season copy from the 1-season one and pick deliberately. Returns null — an
  /// unknown count the row renders as a plain playlist label — for movies, M3U
  /// or live content, an empty query, or ANY fetch that fails or comes back
  /// empty; it NEVER throws, so a slow or dead provider leaves the row playable
  /// instead of blocking the sheet. Cached per playlist+series id, so reopening
  /// the sheet (or a second variant of the same stream) does not refetch.
  Future<int?> seasonCountFor(LocalContentMatch match) async {
    if (match.content.contentType != ContentType.series) return null;
    if (match.playlist.type != PlaylistType.xtream) return null;
    final seriesId = match.content.id.toString();
    if (seriesId.isEmpty) return null;
    final key = '${match.playlist.id}|$seriesId';
    if (_seasonCountCache.containsKey(key)) return _seasonCountCache[key];
    int? count;
    try {
      final repo = IptvRepository(
        ApiConfig(
          baseUrl: match.playlist.url ?? '',
          username: match.playlist.username ?? '',
          password: match.playlist.password ?? '',
        ),
        match.playlist.id,
      );
      count = _seasonCount(await repo.getSeriesInfo(seriesId));
    } catch (_) {
      count = null;
    }
    _seasonCountCache[key] = count;
    return count;
  }

  /// Distinct playable seasons in a fetched series-info response: prefer the set
  /// of season numbers the episodes actually carry (the source of truth for what
  /// plays, and robust to providers that ship a "specials"/season-0 entry in the
  /// declared list), falling back to the declared seasons list, else null.
  static int? _seasonCount(SeriesDetailResponse? info) {
    if (info == null) return null;
    final fromEpisodes = info.episodes.map((e) => e.season).toSet();
    if (fromEpisodes.isNotEmpty) return fromEpisodes.length;
    if (info.seasons.isNotEmpty) return info.seasons.length;
    return null;
  }

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
  void openLocalMatch(LocalContentMatch match) => repointTo(match.playlist);

  /// Points the global AppState (current playlist + its repository) at
  /// [playlist]. Extracted from [openLocalMatch] so a caller that temporarily
  /// repointed to an item's ORIGIN playlist to play it can RESTORE the active
  /// playlist afterwards (rebuilding the repo too) — e.g. Browse restores the
  /// user's active playlist when the player route pops, so Home's
  /// continue-watching reload and a favorite toggle target the right list.
  void repointTo(Playlist playlist) {
    AppState.currentPlaylist = playlist;
    if (playlist.type == PlaylistType.xtream) {
      AppState.xtreamCodeRepository = IptvRepository(
        ApiConfig(
          baseUrl: playlist.url ?? '',
          username: playlist.username ?? '',
          password: playlist.password ?? '',
        ),
        playlist.id,
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
