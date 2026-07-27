import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tmdb_search_result.dart';
import 'tmdb_credentials_service.dart';

/// Typed failure so callers can tell "no key" from "bad key" from "rate
/// limited" without string-matching an Exception message. Generic Exceptions
/// used to conflate all of these, which forced the search layer to either lose
/// the reason or parse English text.
class TmdbException implements Exception {
  const TmdbException(this.reason, this.message);
  final TmdbFailure reason;
  final String message;
  @override
  String toString() => 'TmdbException($reason): $message';
}

/// Time window for the Home "Popular" rail. Each maps to a different TMDb
/// endpoint (see [TmdbService.popularMovies]) so the three chips surface
/// genuinely distinct sets rather than the same list re-sorted.
enum PopularWindow { month, year, allTime }

class TmdbService {
  TmdbService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _cachePrefix = 'tmdb.search.';
  static const _cacheTtl = Duration(hours: 24);
  static const _cacheMaxEntries = 100;
  static const _cacheIndexKey = 'tmdb.search.index.v1';

  // Detail cache — a SEPARATE LRU index from the search one so a burst of
  // detail lookups can never evict cached search results (or vice versa). A
  // detail payload changes far less often than a search does, hence the longer
  // TTL. The raw TMDb body is cached verbatim and re-parsed on read, so the
  // parse path (credits/videos too) has exactly one implementation.
  static const _detailsCachePrefix = 'tmdb.details.';
  static const _detailsCacheTtl = Duration(days: 7);
  static const _detailsCacheMaxEntries = 100;
  static const _detailsCacheIndexKey = 'tmdb.details.index.v1';

  // Discover cache — a THIRD LRU index, separate from search and details, so a
  // studio's filmography (a discover/movie|tv page) can never evict cached
  // searches or details. A discover page churns more than a detail but less than
  // a live search, hence the 12h middle-ground TTL and a smaller 60-entry cap
  // (a studio browse is narrower than free-text search).
  static const _discoverCachePrefix = 'tmdb.discover.';
  static const _discoverCacheTtl = Duration(hours: 12);
  static const _discoverCacheMaxEntries = 60;
  static const _discoverCacheIndexKey = 'tmdb.discover.index.v1';

  // Curated networks merged into [searchCompany] results by case-insensitive
  // substring: TMDb has NO network search endpoint, only company search, yet
  // users type the streaming brands ("HBO", "Apple TV+"…) far more than the
  // production houses. `isNetwork:true` routes discovery to
  // discover/tv?with_networks. NOTE: these network ids should be verified
  // on-device — TMDb network ids are not as stable as company ids.
  static const _curatedNetworks = <TmdbCompany>[
    TmdbCompany(id: 49, name: 'HBO', isNetwork: true),
    TmdbCompany(id: 2552, name: 'Apple TV+', isNetwork: true),
    TmdbCompany(id: 213, name: 'Netflix', isNetwork: true),
    TmdbCompany(id: 2739, name: 'Disney+', isNetwork: true),
    // TMDb network 1024 is "Prime Video"; keep both words so "amazon" and
    // "prime" both match the substring filter below (verified id → Prime Video).
    TmdbCompany(id: 1024, name: 'Amazon Prime Video', isNetwork: true),
  ];

  final http.Client _client;

  Future<List<TmdbSearchResult>> search(
    String query, {
    Locale? locale,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) return [];

    final languageTag = _languageTagFor(locale);
    final cached = await _readCachedSearch(normalizedQuery, languageTag);
    if (cached != null) return cached;

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }

    final uri = _buildSearchUri(normalizedQuery, credential, languageTag);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    // Dedupe by (id, mediaType) BEFORE taking 20: search/multi can return the
    // same title more than once (e.g. the feature plus a same-named making-of),
    // which produced two near-duplicate Discover cards. Keep the first (highest
    // relevance) occurrence.
    final seen = <String>{};
    final results = (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where(
          (item) => item['media_type'] == 'movie' || item['media_type'] == 'tv',
        )
        .map(TmdbSearchResult.fromTmdbJson)
        .where((item) => item.title.isNotEmpty)
        .where((item) => seen.add('${item.id}|${item.mediaType.name}'))
        .take(20)
        .toList();
    await _writeCachedSearch(normalizedQuery, languageTag, results);
    return results;
  }

  /// Fetches the detail payload for a single TMDb id (movie or tv).
  ///
  /// [withCredits] appends `credits,videos` so the result carries the cast list
  /// and trailer videos; leave it false for the light overview-only payload.
  /// Cached for [_detailsCacheTtl] in a dedicated index (keyed by id, media
  /// type, language AND the withCredits variant, so a light cached copy never
  /// satisfies a request that needs the cast).
  Future<TmdbDetailResult> detail(
    int id,
    TmdbMediaType mediaType, {
    Locale? locale,
    bool withCredits = false,
    // Internal guard: the overview language fallback issues ONE extra detail()
    // call in the title's original language. That inner call must never itself
    // trigger another fallback, so it passes false to bound the recursion at a
    // single hop. Callers should leave this at its default.
    bool allowOriginalLanguageFallback = true,
  }) async {
    final segment = mediaType == TmdbMediaType.movie ? 'movie' : 'tv';
    final languageTag = _languageTagFor(locale);

    final cached =
        await _readCachedDetail(id, segment, languageTag, withCredits, mediaType);

    final TmdbDetailResult result;
    if (cached != null) {
      result = cached;
    } else {
      final credential = await TmdbCredentialsService.getCredential();
      if (credential == null) {
        throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
      }
      final params = <String, String>{
        'language': languageTag,
      };
      if (withCredits) {
        params['append_to_response'] = 'credits,videos';
      }
      if (!_looksLikeBearerToken(credential)) {
        params['api_key'] = credential;
      }
      final uri = Uri.parse(
        '$_baseUrl/$segment/$id',
      ).replace(queryParameters: params);
      final response = await _client
          .get(uri, headers: _buildHeaders(credential))
          .timeout(const Duration(seconds: 8),
              onTimeout: () => throw const TmdbException(
                  TmdbFailure.network, 'TMDb request timed out'));
      if (response.statusCode == 401) {
        throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
      }
      if (response.statusCode == 429) {
        throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await _writeCachedDetail(
          id, segment, languageTag, withCredits, response.body);
      result = TmdbDetailResult.fromTmdbJson(decoded, mediaType);
    }

    // Overview language fallback: TMDb frequently has no translated overview for
    // the requested language and returns an empty string. Rather than show a
    // blank synopsis, fetch the overview once in the title's ORIGINAL language
    // and splice it in (localized genres/cast are kept). Applied on BOTH the
    // cache-hit and network paths so a re-viewed title stays consistent. The
    // fallback goes through detail() so it reuses the same LRU cache (no repeat
    // network on re-view); a light (no-credits) variant is enough since only the
    // overview is read. Skipped when the localized overview is already present
    // (no double-fetch) and bounded to a single hop by the guard flag.
    if (allowOriginalLanguageFallback &&
        (result.overview?.trim().isEmpty ?? true)) {
      final originalLanguage = result.originalLanguage?.trim();
      final fallbackLocale =
          Locale((originalLanguage == null || originalLanguage.isEmpty)
              ? 'en'
              : originalLanguage);
      if (_languageTagFor(fallbackLocale) != languageTag) {
        try {
          final fallback = await detail(
            id,
            mediaType,
            locale: fallbackLocale,
            allowOriginalLanguageFallback: false,
          );
          final fallbackOverview = fallback.overview?.trim() ?? '';
          if (fallbackOverview.isNotEmpty) {
            return result.withOverview(fallback.overview);
          }
        } on TmdbException {
          // Best-effort: keep the localized (empty-overview) result on failure.
        }
      }
    }
    return result;
  }

  /// Title+year search against the typed endpoint (`search/movie` or
  /// `search/tv`, NOT `search/multi`), used to resolve an IPTV title to a TMDb
  /// id when no `tmdb_id` was persisted. Replicates the same dual auth and
  /// error typing as [detail]. Result selection (confident-match guard) is the
  /// caller's job.
  Future<List<TmdbSearchResult>> searchTitle(
    String title, {
    int? year,
    required TmdbMediaType mediaType,
    Locale? locale,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return const [];

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }
    final segment = mediaType == TmdbMediaType.movie ? 'movie' : 'tv';
    final params = <String, String>{
      'query': normalizedTitle,
      'include_adult': 'false',
      'language': _languageTagFor(locale),
      'page': '1',
    };
    if (year != null && year > 0) {
      params[mediaType == TmdbMediaType.movie ? 'year' : 'first_air_date_year'] =
          '$year';
    }
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri =
        Uri.parse('$_baseUrl/search/$segment').replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          // search/movie and search/tv omit media_type; inject it so
          // fromTmdbJson reads name/first_air_date for tv and title/release_date
          // for movie instead of defaulting everything to movie.
          item['media_type'] = segment;
          return TmdbSearchResult.fromTmdbJson(item);
        })
        .where((item) => item.title.isNotEmpty)
        .take(20)
        .toList();
  }

  /// Person search against `search/person`, used by "search by actor". Returns
  /// the matching people (name + photo + id) so the caller can then pull one
  /// person's filmography with [getPersonCredits]. Replicates the same dual
  /// auth, 8s timeout and typed error degradation as [detail]/[searchTitle].
  /// Not cached (person picks are one-shot and cheap; caching would need its own
  /// index — see [pruneCaches]).
  Future<List<TmdbPerson>> searchPerson(
    String query, {
    Locale? locale,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }
    final params = <String, String>{
      'query': normalizedQuery,
      'include_adult': 'false',
      'language': _languageTagFor(locale),
      'page': '1',
    };
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri =
        Uri.parse('$_baseUrl/search/person').replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TmdbPerson.fromTmdbJson)
        .where((p) => p.name.isNotEmpty)
        .take(20)
        .toList();
  }

  /// A person's cast filmography via `person/{id}/combined_credits`, mapped into
  /// [TmdbSearchResult] so each film/show flows through the exact same buckets,
  /// cards and matching as a `search/multi` result — no parallel result surface.
  /// Only the `cast` array is used (roles the person acted in). Deduped by
  /// media-type+id and ordered most-recent-first. Same dual auth / 8s timeout /
  /// typed errors as the other calls.
  Future<List<TmdbSearchResult>> getPersonCredits(
    int personId, {
    Locale? locale,
  }) async {
    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }
    final params = <String, String>{
      'language': _languageTagFor(locale),
    };
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri = Uri.parse('$_baseUrl/person/$personId/combined_credits')
        .replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final seen = <String>{};
    final out = <TmdbSearchResult>[];
    for (final raw in (decoded['cast'] as List<dynamic>? ?? [])) {
      if (raw is! Map<String, dynamic>) continue;
      // combined_credits entries already carry media_type (movie|tv); anything
      // else (rare) is skipped so fromTmdbJson never mis-defaults to movie.
      if (raw['media_type'] != 'movie' && raw['media_type'] != 'tv') continue;
      final item = TmdbSearchResult.fromTmdbJson(raw);
      if (item.title.isEmpty) continue;
      final key = '${item.mediaType.name}|${item.id}';
      if (!seen.add(key)) continue; // a person can be cast in a show many times
      out.add(item);
    }
    // Most recent first, undated last — a filmography reads newest-to-oldest.
    out.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    // Bound a very prolific actor's credits: the cross-reference does one local
    // catalogue search PER title, so an unbounded list would fan out into
    // hundreds of DB queries. 60 comfortably covers the display caps.
    return out.length > 60 ? out.sublist(0, 60) : out;
  }

  /// Company search against `search/company`, used by "search by studio".
  /// Returns matching production companies (name + logo + id) so the caller can
  /// then pull that studio's filmography with [discoverByCompany]. Because TMDb
  /// has no NETWORK search, a small curated network list (HBO, Apple TV+…) is
  /// merged in, filtered by case-insensitive substring on the query, and placed
  /// FIRST (a user typing "hbo" wants the network, not a same-named company).
  /// Replicates the same dual auth, 8s timeout and typed error degradation as
  /// [searchPerson]. `search/company` has no `language` parameter, so [locale]
  /// is accepted for signature symmetry but not sent.
  Future<List<TmdbCompany>> searchCompany(
    String query, {
    Locale? locale,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }
    final params = <String, String>{
      'query': normalizedQuery,
      'page': '1',
    };
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri =
        Uri.parse('$_baseUrl/search/company').replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final companies = (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TmdbCompany.fromTmdbJson)
        .where((c) => c.name.isNotEmpty)
        .take(20)
        .toList();
    final lowerQuery = normalizedQuery.toLowerCase();
    final networks = _curatedNetworks
        .where((n) => n.name.toLowerCase().contains(lowerQuery))
        .toList();
    return [...networks, ...companies];
  }

  /// A studio's filmography via `discover`, mapped into [TmdbSearchResult] so
  /// each film/show flows through the exact same buckets/cards/matching as a
  /// `search/multi` result — no parallel result surface. A network browses TV
  /// shows (`discover/tv?with_networks=`), a company browses films
  /// (`discover/movie?with_companies=`), both sorted by popularity. Injects
  /// `media_type` (discover omits it) before parsing, dedupes by media-type+id
  /// and takes 40. Cached for [_discoverCacheTtl] in its own LRU index. Same
  /// dual auth / 8s timeout / typed errors as the other calls.
  Future<List<TmdbSearchResult>> discoverByCompany(
    TmdbCompany company, {
    int page = 1,
    Locale? locale,
  }) async {
    final languageTag = _languageTagFor(locale);
    final cached = await _readCachedDiscover(company, languageTag, page);
    if (cached != null) return cached;

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }
    final segment = company.isNetwork ? 'tv' : 'movie';
    final params = <String, String>{
      'language': languageTag,
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
      'page': '$page',
    };
    params[company.isNetwork ? 'with_networks' : 'with_companies'] =
        '${company.id}';
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri =
        Uri.parse('$_baseUrl/discover/$segment').replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final seen = <String>{};
    final results = (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          // discover/movie and discover/tv omit media_type; inject it so
          // fromTmdbJson reads name/first_air_date for tv and title/release_date
          // for movie instead of defaulting everything to movie.
          item['media_type'] = segment;
          return TmdbSearchResult.fromTmdbJson(item);
        })
        .where((item) => item.title.isNotEmpty)
        .where((item) => seen.add('${item.id}|${item.mediaType.name}'))
        .take(40)
        .toList();
    await _writeCachedDiscover(company, languageTag, page, results);
    return results;
  }

  /// The Home "Popular" rail's data: a ranked list of popular MOVIES for the
  /// chosen [window], mapped into [TmdbSearchResult] so it rides the exact same
  /// cards/matching as search. Endpoints per window:
  ///   - [PopularWindow.month]   → `trending/movie/week` (already carries
  ///     media_type, so nothing is injected)
  ///   - [PopularWindow.year]    → `discover/movie?sort_by=popularity.desc`
  ///     &primary_release_year={year ?? current}
  ///   - [PopularWindow.allTime] → `discover/movie?sort_by=vote_count.desc`
  ///     &vote_count.gte=5000
  /// The two discover branches inject `media_type='movie'` before parsing (the
  /// discover endpoints omit it). Cached in the SHARED [_discoverCacheTtl] LRU
  /// index, keyed by window + year + language, so the three chips never evict
  /// each other's page and a re-view is offline-instant. Same dual auth / 8s
  /// timeout / typed [TmdbException] as the other calls. [year] defaults to the
  /// current year for [PopularWindow.year]; pass it explicitly from tests.
  Future<List<TmdbSearchResult>> popularMovies(
    PopularWindow window, {
    int? year,
    Locale? locale,
  }) async {
    final languageTag = _languageTagFor(locale);
    final resolvedYear = year ?? DateTime.now().year;
    final cacheKey = _popularCacheKey(window, languageTag, resolvedYear);
    final cached = await _readDiscoverCacheByKey(cacheKey);
    if (cached != null) return cached;

    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw const TmdbException(TmdbFailure.noKey, 'TMDb credential is not configured');
    }

    // trending carries media_type; the discover branches do not, so those two
    // inject it before parsing.
    final bool isTrending = window == PopularWindow.month;
    final String path;
    final params = <String, String>{'language': languageTag};
    switch (window) {
      case PopularWindow.month:
        path = 'trending/movie/week';
        break;
      case PopularWindow.year:
        path = 'discover/movie';
        params['sort_by'] = 'popularity.desc';
        params['include_adult'] = 'false';
        params['primary_release_year'] = '$resolvedYear';
        break;
      case PopularWindow.allTime:
        path = 'discover/movie';
        params['sort_by'] = 'vote_count.desc';
        params['include_adult'] = 'false';
        params['vote_count.gte'] = '5000';
        break;
    }
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _buildHeaders(credential))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw const TmdbException(
                TmdbFailure.network, 'TMDb request timed out'));
    if (response.statusCode == 401) {
      throw const TmdbException(TmdbFailure.rejected, 'TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw const TmdbException(TmdbFailure.rateLimited, 'TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(TmdbFailure.httpError, 'TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final seen = <String>{};
    final results = (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          if (!isTrending) item['media_type'] = 'movie';
          return TmdbSearchResult.fromTmdbJson(item);
        })
        .where((item) => item.title.isNotEmpty)
        .where((item) => seen.add('${item.id}|${item.mediaType.name}'))
        .take(20)
        .toList();
    await _writeDiscoverCacheByKey(cacheKey, results);
    return results;
  }

  /// Removes expired entries and trims the cache to [_cacheMaxEntries].
  /// Safe to call on app startup.
  static Future<void> pruneCache() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_cacheIndexKey) ?? const <String>[];
    final now = DateTime.now();
    final kept = <String>[];

    for (final key in index) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
        if (cachedAt == null || now.difference(cachedAt) > _cacheTtl) {
          await prefs.remove(key);
        } else {
          kept.add(key);
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }

    while (kept.length > _cacheMaxEntries) {
      final oldest = kept.removeAt(0);
      await prefs.remove(oldest);
    }

    if (kept.length != index.length) {
      await prefs.setStringList(_cacheIndexKey, kept);
    }
  }

  /// Removes expired detail entries and trims the detail cache to
  /// [_detailsCacheMaxEntries]. Its own index, separate from [pruneCache].
  static Future<void> pruneDetailsCache() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_detailsCacheIndexKey) ?? const <String>[];
    final now = DateTime.now();
    final kept = <String>[];

    for (final key in index) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
        if (cachedAt == null || now.difference(cachedAt) > _detailsCacheTtl) {
          await prefs.remove(key);
        } else {
          kept.add(key);
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }

    while (kept.length > _detailsCacheMaxEntries) {
      final oldest = kept.removeAt(0);
      await prefs.remove(oldest);
    }

    if (kept.length != index.length) {
      await prefs.setStringList(_detailsCacheIndexKey, kept);
    }
  }

  /// Removes expired discover entries and trims the discover cache to
  /// [_discoverCacheMaxEntries]. Its own index, separate from [pruneCache] and
  /// [pruneDetailsCache].
  static Future<void> pruneDiscoverCache() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_discoverCacheIndexKey) ?? const <String>[];
    final now = DateTime.now();
    final kept = <String>[];

    for (final key in index) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
        if (cachedAt == null || now.difference(cachedAt) > _discoverCacheTtl) {
          await prefs.remove(key);
        } else {
          kept.add(key);
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }

    while (kept.length > _discoverCacheMaxEntries) {
      final oldest = kept.removeAt(0);
      await prefs.remove(oldest);
    }

    if (kept.length != index.length) {
      await prefs.setStringList(_discoverCacheIndexKey, kept);
    }
  }

  /// Prunes all three TMDb caches. Safe to call fire-and-forget on app startup:
  /// swallows any storage error so a prune failure can never surface as an
  /// unhandled async error at launch.
  static Future<void> pruneCaches() async {
    try {
      await pruneCache();
      await pruneDetailsCache();
      await pruneDiscoverCache();
    } catch (_) {
      // Best-effort housekeeping; a failed prune is harmless.
    }
  }

  Uri _buildSearchUri(String query, String credential, String languageTag) {
    final params = {
      'query': query,
      'include_adult': 'false',
      'language': languageTag,
      'page': '1',
    };
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    return Uri.parse('$_baseUrl/search/multi').replace(queryParameters: params);
  }

  Map<String, String> _buildHeaders(String credential) {
    if (!_looksLikeBearerToken(credential)) return const {};
    return {'Authorization': 'Bearer $credential'};
  }

  bool _looksLikeBearerToken(String credential) {
    return credential.startsWith('eyJ') || credential.length > 80;
  }

  static String _languageTagFor(Locale? locale) {
    if (locale == null) return 'en-US';
    final code = locale.languageCode.toLowerCase();
    // TMDb expects xx-XX. Build a reasonable region from the language when
    // the caller didn't pass one.
    final region = (locale.countryCode ?? _defaultRegionFor(code)).toUpperCase();
    return '$code-$region';
  }

  static String _defaultRegionFor(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'US';
      case 'es':
        return 'ES';
      case 'pt':
        return 'BR';
      case 'fr':
        return 'FR';
      case 'de':
        return 'DE';
      case 'ru':
        return 'RU';
      case 'tr':
        return 'TR';
      case 'ar':
        return 'SA';
      case 'hi':
        return 'IN';
      case 'zh':
        return 'CN';
      default:
        return languageCode.toUpperCase();
    }
  }

  String _cacheKey(String query, String languageTag) {
    return '$_cachePrefix$languageTag.${_foldForCache(query)}';
  }

  /// Lowercases and strips diacritics so 'düne' and 'Dune' map to the same
  /// cache key. Keeps the implementation tiny — no `intl`/`unorm` dependency.
  static String _foldForCache(String input) {
    const accents =
        'àáâäãåèéêëìíîïòóôöõùúûüñçÀÁÂÄÃÅÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÑÇ';
    const plain =
        'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
    final buf = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = accents.indexOf(ch);
      buf.write(i >= 0 ? plain[i].toLowerCase() : ch);
    }
    return buf.toString();
  }

  Future<List<TmdbSearchResult>?> _readCachedSearch(
    String query,
    String languageTag,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKey(query, languageTag);
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
      if (cachedAt == null || DateTime.now().difference(cachedAt) > _cacheTtl) {
        await prefs.remove(key);
        await _removeFromIndex(prefs, key);
        return null;
      }
      final items = decoded['results'] as List<dynamic>? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(TmdbSearchResult.fromJson)
          .toList();
    } catch (_) {
      await prefs.remove(key);
      await _removeFromIndex(prefs, key);
      return null;
    }
  }

  Future<void> _writeCachedSearch(
    String query,
    String languageTag,
    List<TmdbSearchResult> results,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKey(query, languageTag);
    await prefs.setString(
      key,
      jsonEncode({
        'cachedAt': DateTime.now().toIso8601String(),
        'results': results.map((item) => item.toJson()).toList(),
      }),
    );
    await _addToIndex(prefs, key);
  }

  Future<void> _addToIndex(SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_cacheIndexKey) ?? <String>[];
    index.remove(key);
    index.add(key);
    while (index.length > _cacheMaxEntries) {
      final evict = index.removeAt(0);
      await prefs.remove(evict);
    }
    await prefs.setStringList(_cacheIndexKey, index);
  }

  Future<void> _removeFromIndex(SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_cacheIndexKey);
    if (index == null) return;
    if (index.remove(key)) {
      await prefs.setStringList(_cacheIndexKey, index);
    }
  }

  // --- Detail cache --------------------------------------------------------

  String _detailsCacheKey(
    int id,
    String segment,
    String languageTag,
    bool withCredits,
  ) =>
      '$_detailsCachePrefix$languageTag.$segment.$id.${withCredits ? 'c' : 'n'}';

  Future<TmdbDetailResult?> _readCachedDetail(
    int id,
    String segment,
    String languageTag,
    bool withCredits,
    TmdbMediaType mediaType,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _detailsCacheKey(id, segment, languageTag, withCredits);
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > _detailsCacheTtl) {
        await prefs.remove(key);
        await _removeFromDetailsIndex(prefs, key);
        return null;
      }
      final body = jsonDecode(decoded['body'] as String) as Map<String, dynamic>;
      return TmdbDetailResult.fromTmdbJson(body, mediaType);
    } catch (_) {
      await prefs.remove(key);
      await _removeFromDetailsIndex(prefs, key);
      return null;
    }
  }

  Future<void> _writeCachedDetail(
    int id,
    String segment,
    String languageTag,
    bool withCredits,
    String body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _detailsCacheKey(id, segment, languageTag, withCredits);
    await prefs.setString(
      key,
      jsonEncode({
        'cachedAt': DateTime.now().toIso8601String(),
        'body': body,
      }),
    );
    await _addToDetailsIndex(prefs, key);
  }

  Future<void> _addToDetailsIndex(SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_detailsCacheIndexKey) ?? <String>[];
    index.remove(key);
    index.add(key);
    while (index.length > _detailsCacheMaxEntries) {
      final evict = index.removeAt(0);
      await prefs.remove(evict);
    }
    await prefs.setStringList(_detailsCacheIndexKey, index);
  }

  Future<void> _removeFromDetailsIndex(
      SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_detailsCacheIndexKey);
    if (index == null) return;
    if (index.remove(key)) {
      await prefs.setStringList(_detailsCacheIndexKey, index);
    }
  }

  // --- Discover cache ------------------------------------------------------

  String _discoverCacheKey(TmdbCompany company, String languageTag, int page) =>
      '$_discoverCachePrefix$languageTag.${company.isNetwork ? 'n' : 'c'}.${company.id}.p$page';

  /// Cache key for a [popularMovies] page. Keyed by window (+ year for the
  /// year window) and language, in the SAME discover index so the three chips
  /// and any studio browse share one LRU without a fourth cache.
  String _popularCacheKey(PopularWindow window, String languageTag, int year) {
    switch (window) {
      case PopularWindow.month:
        return '$_discoverCachePrefix$languageTag.pop.month';
      case PopularWindow.year:
        return '$_discoverCachePrefix$languageTag.pop.year.$year';
      case PopularWindow.allTime:
        return '$_discoverCachePrefix$languageTag.pop.alltime';
    }
  }

  Future<List<TmdbSearchResult>?> _readCachedDiscover(
    TmdbCompany company,
    String languageTag,
    int page,
  ) =>
      _readDiscoverCacheByKey(_discoverCacheKey(company, languageTag, page));

  Future<void> _writeCachedDiscover(
    TmdbCompany company,
    String languageTag,
    int page,
    List<TmdbSearchResult> results,
  ) =>
      _writeDiscoverCacheByKey(
          _discoverCacheKey(company, languageTag, page), results);

  /// Key-based discover cache read, shared by the studio browse and the Home
  /// popular rail so both hit the SAME LRU index.
  Future<List<TmdbSearchResult>?> _readDiscoverCacheByKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > _discoverCacheTtl) {
        await prefs.remove(key);
        await _removeFromDiscoverIndex(prefs, key);
        return null;
      }
      final items = decoded['results'] as List<dynamic>? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(TmdbSearchResult.fromJson)
          .toList();
    } catch (_) {
      await prefs.remove(key);
      await _removeFromDiscoverIndex(prefs, key);
      return null;
    }
  }

  Future<void> _writeDiscoverCacheByKey(
    String key,
    List<TmdbSearchResult> results,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'cachedAt': DateTime.now().toIso8601String(),
        'results': results.map((item) => item.toJson()).toList(),
      }),
    );
    await _addToDiscoverIndex(prefs, key);
  }

  Future<void> _addToDiscoverIndex(SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_discoverCacheIndexKey) ?? <String>[];
    index.remove(key);
    index.add(key);
    while (index.length > _discoverCacheMaxEntries) {
      final evict = index.removeAt(0);
      await prefs.remove(evict);
    }
    await prefs.setStringList(_discoverCacheIndexKey, index);
  }

  Future<void> _removeFromDiscoverIndex(
      SharedPreferences prefs, String key) async {
    final index = prefs.getStringList(_discoverCacheIndexKey);
    if (index == null) return;
    if (index.remove(key)) {
      await prefs.setStringList(_discoverCacheIndexKey, index);
    }
  }
}
