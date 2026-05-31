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
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
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

    final tmdbFuture = _tmdbService.search(query, locale: locale);
    final wishlistFuture = TmdbWishlistService.getKeys();
    final localFuture = _searchAllLocal(query);

    final tmdbResults = _filterTmdb(await tmdbFuture, filter);
    final wishlistKeys = await wishlistFuture;
    final localResults = _filterLocal(await localFuture, filter)
        .toList(growable: false);

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

    for (final result in localResults) {
      if (!matchedKeys.contains(result.dedupKey)) {
        localOnly.add(result);
      }
    }

    return UnifiedSearchResults(
      withLocal: withLocal.take(15).toList(),
      tmdbOnly: tmdbOnly.take(10).toList(),
      localOnly: localOnly.take(15).toList(),
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
      case SearchFilter.all:
      case SearchFilter.wishlist:
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
      case SearchFilter.all:
      case SearchFilter.wishlist:
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
      final strength = classify(match.content.name, tmdb.title);
      if (strength == MatchStrength.none) continue;
      out.add(match.withStrength(strength));
    }
    out.sort((a, b) => a.strength.index.compareTo(b.strength.index));
    return out;
  }

  Future<List<LocalContentMatch>> _searchAllLocal(String query) async {
    final playlists = await PlaylistService.getPlaylists();
    final results = await Future.wait(
      playlists.map(
        (playlist) => playlist.type == PlaylistType.xtream
            ? _searchXtream(playlist, query)
            : _searchM3u(playlist, query),
      ),
    );
    return results.expand((e) => e).toList(growable: false);
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
    final localResults = await _searchAllLocal(query.isEmpty ? '' : query);
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
      final matches = _findMatchesFor(t, localResults);
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
  }) =>
      _tmdbService.detail(item.id, item.mediaType, locale: locale);

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
