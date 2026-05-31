import 'dart:ui';

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

class _FakeTmdbService extends TmdbService {
  _FakeTmdbService(this.results);

  final List<TmdbSearchResult> results;
  String? lastLanguage;

  @override
  Future<List<TmdbSearchResult>> search(
    String query, {
    Locale? locale,
  }) async {
    if (locale != null) {
      lastLanguage = locale.languageCode;
    }
    return results;
  }
}

void main() {
  late AppDatabase database;

  setUp(() async {
    await getIt.reset();
    PlaylistService.invalidateCache();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
  });

  tearDown(() async {
    await getIt.reset();
    PlaylistService.invalidateCache();
    await database.close();
  });

  Future<void> _insertMovie(
    AppDatabase db,
    String name,
    String playlistId, {
    String genre = '',
    String cast = '',
    String director = '',
  }) async {
    await db
        .into(db.vodStreams)
        .insert(
          VodStream(
            streamId: 'movie-${name.hashCode}',
            name: name,
            streamIcon: '',
            categoryId: 'movies',
            rating: '',
            rating5based: 0,
            containerExtension: 'mp4',
            playlistId: playlistId,
            createdAt: DateTime(2026),
            genre: genre,
          ).toDriftCompanion(),
        );
  }

  group('GlobalSearchService unified', () {
    test('finds local match and groups in withLocal', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'Movies',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Dune 2021', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
        ]),
      );

      final results = await service.search('dune');

      expect(results.withLocal, hasLength(1));
      expect(
        results.withLocal.single.localMatches.single.content.name,
        'Dune 2021',
      );
      expect(results.tmdbOnly, isEmpty);
    });

    test('separates TMDb-only results', () async {
      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
        ]),
      );

      final results = await service.search('dune');

      expect(results.withLocal, isEmpty);
      expect(results.tmdbOnly, hasLength(1));
    });

    test('local-only content appears in localOnly', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'Movies',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Avatar', 'pl1');

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));

      final results = await service.search('avat');

      expect(results.localOnly, hasLength(1));
      expect(results.localOnly.single.content.name, 'Avatar');
    });

    test('search finds by genre', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'Movies',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Random Movie', 'pl1', genre: 'Sci-Fi');

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));

      final results = await service.search('sci-fi');
      expect(results.localOnly.single.content.name, 'Random Movie');
    });

    test('M3U search uses SQL searchM3uItems (limited & filtered)', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl-m3u',
          name: 'M3U',
          type: PlaylistType.m3u,
          url: 'https://m.com/p.m3u',
          createdAt: DateTime(2026),
        ),
      );
      await database.insertM3uItems([
        M3uItem(
          id: 'i1',
          playlistId: 'pl-m3u',
          url: 'https://example.com/dune.m3u8',
          contentType: ContentType.vod,
          name: 'Dune Stream',
          groupTitle: 'Movies',
        ),
        M3uItem(
          id: 'i2',
          playlistId: 'pl-m3u',
          url: 'https://example.com/avatar.m3u8',
          contentType: ContentType.vod,
          name: 'Avatar Stream',
          groupTitle: 'Movies',
        ),
      ]);

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));
      final results = await service.search('dune');

      expect(results.localOnly, hasLength(1));
      expect(results.localOnly.single.content.name, 'Dune Stream');
    });
  });

  group('Title matching', () {
    test('exact match with different capitalization', () {
      expect(GlobalSearchService.isExactTitleMatch('dune', 'DUNE'), isTrue);
    });

    test('exact match ignoring year and brackets', () {
      expect(
        GlobalSearchService.isExactTitleMatch('Dune 2021', 'Dune'),
        isTrue,
      );
      expect(
        GlobalSearchService.isExactTitleMatch('Dune (2021)', 'Dune'),
        isTrue,
      );
    });

    test('fuzzy match with extra content', () {
      expect(
        GlobalSearchService.isFuzzyTitleMatch('Dune Part Two', 'Dune'),
        isTrue,
      );
      expect(
        GlobalSearchService.isExactTitleMatch('Dune Part Two', 'Dune'),
        isFalse,
      );
    });

    test('no match on unrelated titles', () {
      expect(GlobalSearchService.isExactTitleMatch('Avatar', 'Dune'), isFalse);
      expect(GlobalSearchService.isFuzzyTitleMatch('Avatar', 'Dune'), isFalse);
    });

    test('classify returns exact > fuzzy > none', () {
      expect(
        GlobalSearchService.classify('Dune', 'Dune'),
        MatchStrength.exact,
      );
      expect(
        GlobalSearchService.classify('Dune Part Two', 'Dune'),
        MatchStrength.fuzzy,
      );
      expect(
        GlobalSearchService.classify('Avatar', 'Dune'),
        MatchStrength.none,
      );
    });
  });

  group('Match labelling', () {
    test('exact local titles are flagged with isExactMatch', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'X',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Dune', 'pl1');
      await _insertMovie(database, 'Dune Part Two', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
        ]),
      );
      final results = await service.search('dune');
      final matches = results.withLocal.single.localMatches;

      final exact = matches.where((m) => m.isExactMatch).toList();
      final fuzzy =
          matches.where((m) => m.strength == MatchStrength.fuzzy).toList();

      expect(exact, hasLength(1));
      expect(exact.single.content.name, 'Dune');
      expect(fuzzy, hasLength(1));
      expect(fuzzy.single.content.name, 'Dune Part Two');
      expect(results.withLocal.single.hasExactMatch, isTrue);
    });
  });

  group('SearchFilter', () {
    setUp(() async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'X',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
    });

    test('movies filter excludes TV results from TMDb section', () async {
      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
          const TmdbSearchResult(
            id: 2,
            mediaType: TmdbMediaType.tv,
            title: 'Foundation',
            voteAverage: 7,
          ),
        ]),
      );
      final all = await service.search('a');
      final movies = await service.search(
        'a',
        filter: SearchFilter.movies,
      );
      expect(all.tmdbOnly, hasLength(2));
      expect(movies.tmdbOnly, hasLength(1));
      expect(
        movies.tmdbOnly.single.tmdb.mediaType,
        TmdbMediaType.movie,
      );
    });

    test('wishlist filter returns saved items even with empty query',
        () async {
      const saved = TmdbSearchResult(
        id: 1,
        mediaType: TmdbMediaType.movie,
        title: 'Dune',
        voteAverage: 8,
      );
      await TmdbWishlistService.toggle(saved);
      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));
      final results = await service.search('', filter: SearchFilter.wishlist);
      expect(results.tmdbOnly, hasLength(1));
      expect(results.tmdbOnly.single.tmdb.id, 1);
      expect(results.tmdbOnly.single.isWishlisted, isTrue);
    });
  });

  group('Locale propagation', () {
    test('search forwards the locale to TmdbService', () async {
      final fake = _FakeTmdbService([]);
      final service = GlobalSearchService(tmdbService: fake);
      await service.search('dune', locale: const Locale('es', 'ES'));
      expect(fake.lastLanguage, 'es');
    });
  });

  group('Dedup', () {
    test('same stream in withLocal does not appear again in localOnly',
        () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1',
          name: 'X',
          type: PlaylistType.xtream,
          url: 'https://x.com',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Dune', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
        ]),
      );
      final results = await service.search('dune');
      expect(results.withLocal, hasLength(1));
      expect(results.localOnly, isEmpty);
    });
  });
}
