import 'dart:ui';

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/models/series.dart';
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

/// TMDb that always fails, to prove the local buckets survive a TMDb outage.
class _ThrowingTmdbService extends TmdbService {
  _ThrowingTmdbService(this.error);

  final Object error;

  @override
  Future<List<TmdbSearchResult>> search(
    String query, {
    Locale? locale,
  }) async {
    throw error;
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
    int? tmdbId,
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
            tmdbId: tmdbId,
          ).toDriftCompanion(),
        );
  }

  Future<void> _insertSeries(
    AppDatabase db,
    String name,
    String playlistId, {
    int? tmdbId,
    String cast = '',
    String? seriesId,
  }) async {
    await db
        .into(db.seriesStreams)
        .insert(
          SeriesStream(
            seriesId: seriesId ?? 'series-${name.hashCode}',
            name: name,
            cover: '',
            categoryId: 'series',
            plot: '',
            cast: cast,
            director: '',
            genre: '',
            releaseDate: '',
            rating: '',
            rating5based: 0,
            playlistId: playlistId,
            tmdbId: tmdbId,
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

    test('classifies non-Latin titles (Cyrillic/Arabic/CJK/Devanagari)', () {
      // The normalizer used to strip every non-Latin character, so a Russian or
      // Arabic user's own owned title matched nothing and showed up duplicated
      // as a non-playable "discovery". This app ships those locales.
      for (final title in ['Дюна', 'الكثيب', '沙丘', 'ड्यून']) {
        expect(GlobalSearchService.classify(title, title), MatchStrength.exact,
            reason: 'a title must match itself in "$title"');
      }
      expect(GlobalSearchService.classify('Дюна (2021)', 'Дюна'),
          MatchStrength.exact,
          reason: 'year/brackets stripping must still work on Cyrillic');
      expect(GlobalSearchService.classify('Дюна', 'Аватар'), MatchStrength.none);
    });

    test('an owned stream matched by several TMDb results appears once',
        () async {
      // Real-TV finding: one owned "Dune 2021" showed up twice in "your
      // library" because it fuzzy-matched both "Dune" and "Dune: Part Two".
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
      await _insertMovie(database, 'Dune 2021', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
              id: 1,
              mediaType: TmdbMediaType.movie,
              title: 'Dune',
              voteAverage: 8),
          const TmdbSearchResult(
              id: 2,
              mediaType: TmdbMediaType.movie,
              title: 'Dune: Part Two',
              voteAverage: 8),
        ]),
      );
      final r = await service.search('dune');

      expect(r.withLocal, hasLength(1),
          reason: 'the owned stream must appear once, not once per TMDb match');
      expect(r.withLocal.single.tmdb.title, 'Dune',
          reason: 'kept under its strongest (exact) match');
      expect(r.withLocal.single.localMatches.single.content.name, 'Dune 2021');
      expect(r.tmdbOnly.map((e) => e.tmdb.title), contains('Dune: Part Two'),
          reason: 'the unowned franchise entry drops to Discover, not vanishes');
    });

    test('an owned non-Latin title lands in withLocal, not tmdbOnly', () async {
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
      await _insertMovie(database, 'Дюна', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 1,
            mediaType: TmdbMediaType.movie,
            title: 'Дюна',
            voteAverage: 8,
          ),
        ]),
      );
      final r = await service.search('Дюна');

      expect(r.withLocal, hasLength(1),
          reason: 'the owned Russian title must be recognised as owned');
      expect(r.tmdbOnly, isEmpty,
          reason: 'it must NOT appear as a non-playable discovery');
      expect(r.localOnly, isEmpty, reason: 'and must not be duplicated');
    });

    test('lowercase Cyrillic query finds a Title-case owned title', () async {
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1', name: 'X', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertMovie(database, 'Дюна', 'pl1'); // stored Title-case
      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(id: 1, mediaType: TmdbMediaType.movie, title: 'Дюна', voteAverage: 8),
        ]),
      );
      // User types all lowercase — SQLite LIKE alone would miss it.
      final r = await service.search('дюна');
      expect(r.withLocal, hasLength(1),
          reason: 'the case-variant union must find the owned Cyrillic title');
      expect(r.tmdbOnly, isEmpty);
      expect(r.localOnly, isEmpty);
    });

    test('first-word query does not let a cross-type TMDb title hijack an '
        'owned show', () async {
      // Real-phone bug: searching "Rick" did not surface owned "Rick y Morty"
      // while "morty" did. TMDb returns a movie literally titled "Rick" for the
      // first token; the owned SERIES fuzzy-matched that MOVIE
      // ("rick y morty".contains("rick")) and was swallowed into the movie's
      // Discover card, vanishing as itself. A title match must agree on media
      // type, so the series now stays findable.
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1', name: 'X', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertSeries(database, 'Rick y Morty', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
              id: 10, mediaType: TmdbMediaType.movie, title: 'Rick',
              voteAverage: 6),
        ]),
      );
      final r = await service.search('Rick');

      expect(
        r.withLocal.where((e) =>
            e.localMatches.any((m) => m.content.name == 'Rick y Morty')),
        isEmpty,
        reason: 'the owned series must NOT be hijacked under the "Rick" movie',
      );
      expect(
        r.localOnly.map((e) => e.content.name),
        contains('Rick y Morty'),
        reason: 'searching the first word must still surface the owned show',
      );
      expect(r.tmdbOnly.map((e) => e.tmdb.title), contains('Rick'),
          reason: 'the unrelated TMDb movie remains its own Discover card');
    });

    test('a common first word buried under cast/genre matches still surfaces '
        'the owned show (real-device repro)', () async {
      // The SHIPPED bug: searching "rick" does NOT surface owned "Rick y Morty"
      // while "morty" does. Root cause is NOT the TMDb hijack the prior fix
      // addressed — it is the LOCAL DB search. searchSeriesBroad matches name |
      // genre | cast | director, ordered name ASC, capped at 30; then localOnly
      // is capped at 15. "rick" is a substring of countless cast names
      // (Patrick, Frederick, Kendrick, Rick...), so it matches many owned titles
      // and, sorted alphabetically, buries/truncates "Rick y Morty" past the
      // cap. "morty" is rare, so it survives — exactly the reported asymmetry.
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1', name: 'X', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      // 30 decoys that only match via a cast member ("Patrick" contains "rick")
      // and whose names all sort alphabetically BEFORE "Rick y Morty".
      for (var i = 0; i < 30; i++) {
        await _insertSeries(
          database,
          'Aaa Decoy ${i.toString().padLeft(2, '0')}',
          'pl1',
          cast: 'Patrick Star',
        );
      }
      await _insertSeries(database, 'Rick y Morty', 'pl1');

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));

      // "morty" (rare token) finds it — the working half of the report.
      final morty = await service.search('morty');
      expect(
        [...morty.localOnly.map((e) => e.content.name),
         ...morty.withLocal.expand((e) => e.localMatches.map((m) => m.content.name))],
        contains('Rick y Morty'),
        reason: '"morty" must surface the owned show',
      );

      // "rick" (common token) must ALSO find it — the failing half of the report.
      final rick = await service.search('rick');
      expect(
        [...rick.localOnly.map((e) => e.content.name),
         ...rick.withLocal.expand((e) => e.localMatches.map((m) => m.content.name))],
        contains('Rick y Morty'),
        reason: 'searching a common first word must still surface the owned show',
      );
    });

    test('a later, unambiguous word still promotes the owned show to withLocal',
        () async {
      // The twin of the case above: "morty" returns the real show, which is an
      // exact title match of the SAME type, so it lands in withLocal as owned.
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'pl1', name: 'X', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await _insertSeries(database, 'Rick y Morty', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
              id: 20, mediaType: TmdbMediaType.tv, title: 'Rick y Morty',
              voteAverage: 8),
        ]),
      );
      final r = await service.search('morty');

      expect(r.withLocal, hasLength(1));
      expect(r.withLocal.single.localMatches.single.content.name,
          'Rick y Morty');
      expect(r.localOnly, isEmpty);
    });

    test('same-title variants across playlists collapse to ONE card exposing '
        'every distinct copy (incl. a copy that only matches by title)',
        () async {
      // The shipped "Rick y Morty" bug: the show is owned as several distinct
      // streams — two series_ids inside list 3 that pack different season ranges,
      // plus a copy in list 5 — but the user saw one card and one play-from row.
      // Only the id-tagged copies string-reconcile to the English TMDb title; the
      // untagged list-5 copy matches nothing and used to scatter into localOnly.
      // All of them must fold into the SINGLE owned card so the detail sheet can
      // list every playable variant.
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'list3', name: 'LopezCueto3', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      await PlaylistService.savePlaylist(
        Playlist(
          id: 'list5', name: 'LopezCueto5', type: PlaylistType.xtream,
          url: 'https://x.com', username: 'u', password: 'p',
          createdAt: DateTime(2026),
        ),
      );
      // list 3: two season-pack variants, both tagged with the TMDb id.
      await _insertSeries(database, 'Rick y Morty', 'list3',
          tmdbId: 100, seriesId: 'rm3-s1');
      await _insertSeries(database, 'Rick y Morty', 'list3',
          tmdbId: 100, seriesId: 'rm3-s7');
      // list 5: untagged, English-vs-localized name mismatch → no id, no title
      // match against "Rick and Morty"; reachable only through the title fold.
      await _insertSeries(database, 'Rick y Morty', 'list5',
          seriesId: 'rm5');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
              id: 100, mediaType: TmdbMediaType.tv, title: 'Rick and Morty',
              voteAverage: 9),
        ]),
      );
      final r = await service.search('morty');

      expect(r.withLocal, hasLength(1),
          reason: 'one logical title → one result card');
      final matches = r.withLocal.single.localMatches;
      expect(matches.map((m) => m.dedupKey).toSet(), hasLength(3),
          reason: 'all three distinct streams are attached to the one card');
      expect(matches.map((m) => m.playlist.id).toSet(), {'list3', 'list5'},
          reason: 'both playlists are represented, distinctly labelable');
      expect(
        r.localOnly.where((m) => m.content.name == 'Rick y Morty'),
        isEmpty,
        reason: 'no variant leaks out as a separate localOnly card',
      );
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

  group('TMDb degrades without taking local down', () {
    Future<void> seedAvatar() async {
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
      await _insertMovie(database, 'Avatar', 'pl1');
    }

    // The whole point of the refactor: a user with no key, or a TMDb outage,
    // must still see their own catalogue. The old bare `await tmdbFuture` threw
    // out of search() and left them with nothing.
    for (final entry in {
      'no key': (const TmdbException(TmdbFailure.noKey, 'x'), TmdbFailure.noKey),
      'rejected key':
          (const TmdbException(TmdbFailure.rejected, 'x'), TmdbFailure.rejected),
      'rate limited': (
        const TmdbException(TmdbFailure.rateLimited, 'x'),
        TmdbFailure.rateLimited
      ),
    }.entries) {
      test('${entry.key}: local survives, failure is ${entry.value.$2.name}',
          () async {
        await seedAvatar();
        final service =
            GlobalSearchService(tmdbService: _ThrowingTmdbService(entry.value.$1));

        final r = await service.search('avatar');

        expect(r.localOnly, hasLength(1),
            reason: 'the local catalogue must survive a TMDb failure');
        expect(r.localOnly.single.content.name, 'Avatar');
        expect(r.withLocal, isEmpty);
        expect(r.tmdbOnly, isEmpty);
        expect(r.tmdbFailure, entry.value.$2);
      });
    }

    test('an offline/unknown error maps to network, local survives', () async {
      await seedAvatar();
      final service =
          GlobalSearchService(tmdbService: _ThrowingTmdbService(StateError('offline')));

      final r = await service.search('avatar');

      expect(r.localOnly, hasLength(1));
      expect(r.tmdbFailure, TmdbFailure.network);
    });

    test('a successful TMDb call leaves tmdbFailure null', () async {
      await seedAvatar();
      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));
      final r = await service.search('avatar');
      expect(r.tmdbFailure, isNull);
    });
  });

  group('Progressive first paint', () {
    test('searchLocalFirst returns local only, pending, without touching TMDb',
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
      await _insertMovie(database, 'Avatar', 'pl1');

      // A throwing TMDb proves the first paint never consults the network: if
      // it did, this would throw instead of returning the local phase.
      final service = GlobalSearchService(
        tmdbService: _ThrowingTmdbService(const TmdbException(TmdbFailure.noKey, 'x')),
      );

      final r = await service.searchLocalFirst('avatar');

      expect(r.tmdbPending, isTrue);
      expect(r.localOnly, hasLength(1));
      expect(r.withLocal, isEmpty);
      expect(r.tmdbOnly, isEmpty);
      expect(r.tmdbFailure, isNull);
    });
  });

  group('Wishlist browse classification', () {
    test('an owned wishlisted title is found even past the alphabetical cap',
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
      // 35 fillers that sort before "Zodiac". The old browse did one broad
      // search on the empty query — LIKE '%%' capped at 30 alphabetical rows —
      // so Zodiac (past row 30) was never in the local set and got
      // misclassified as "not in your lists". Per-title search finds it.
      for (var i = 0; i < 35; i++) {
        await _insertMovie(database, 'AAA Filler ${i.toString().padLeft(2, '0')}', 'pl1');
      }
      await _insertMovie(database, 'Zodiac', 'pl1');
      await TmdbWishlistService.toggle(const TmdbSearchResult(
        id: 9,
        mediaType: TmdbMediaType.movie,
        title: 'Zodiac',
        voteAverage: 7,
      ));

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));
      final r = await service.search('', filter: SearchFilter.wishlist);

      expect(r.withLocal.map((e) => e.tmdb.title), contains('Zodiac'),
          reason: 'the owned title must be recognised as in the user\'s lists');
      expect(r.tmdbOnly, isEmpty);
    });
  });

  group('Empty-query DB guard', () {
    test('searchMovieBroad/SeriesBroad return nothing for blank queries',
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
      await _insertMovie(database, 'Avatar', 'pl1');
      await _insertMovie(database, 'Dune', 'pl1');

      expect(await database.searchMovieBroad('pl1', ''), isEmpty);
      expect(await database.searchMovieBroad('pl1', '   '), isEmpty);
      expect(await database.searchSeriesBroad('pl1', ''), isEmpty);
      // A real query still works.
      expect(await database.searchMovieBroad('pl1', 'dune'), hasLength(1));
    });
  });

  group('tmdb-id dedup', () {
    Future<void> savePl() => PlaylistService.savePlaylist(
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

    test('a translated-title owned movie matches by id, not a Discover card',
        () async {
      await savePl();
      // The local title is the localized name and does NOT string-match the
      // TMDb "Dune"; only the persisted tmdb_id ties them together.
      await _insertMovie(database, 'Duna', 'pl1', tmdbId: 438631);

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 438631,
            mediaType: TmdbMediaType.movie,
            title: 'Dune',
            voteAverage: 8,
          ),
        ]),
      );
      final r = await service.search('duna');

      expect(r.withLocal, hasLength(1),
          reason: 'owned by id even though the titles differ');
      expect(r.withLocal.single.localMatches.single.content.name, 'Duna');
      expect(r.withLocal.single.hasExactMatch, isTrue,
          reason: 'an id match reads as owned/exact');
      expect(r.tmdbOnly, isEmpty,
          reason: 'the same result must NOT also be a Discover card');
      expect(r.localOnly, isEmpty, reason: 'and must not be duplicated');
    });

    test('id match takes precedence over a title-only match on another result',
        () async {
      await savePl();
      // One owned stream: its id ties it to result A; its title string-matches
      // result B. The id match must win, so the stream is owned under A and B
      // drops to Discover.
      await _insertMovie(database, 'Duna', 'pl1', tmdbId: 100);

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
              id: 100,
              mediaType: TmdbMediaType.movie,
              title: 'Dune',
              voteAverage: 8),
          const TmdbSearchResult(
              id: 999,
              mediaType: TmdbMediaType.movie,
              title: 'Duna',
              voteAverage: 7),
        ]),
      );
      final r = await service.search('duna');

      expect(r.withLocal, hasLength(1));
      expect(r.withLocal.single.tmdb.id, 100,
          reason: 'kept under its id match, not the title match');
      expect(r.tmdbOnly.map((e) => e.tmdb.id), contains(999),
          reason: 'the title-only result drops to Discover');
    });

    test('a stored id does not match across media types', () async {
      await savePl();
      // A movie row whose tmdb_id collides with a TV result id must not match:
      // ids are only unique within a media type.
      await _insertMovie(database, 'Duna', 'pl1', tmdbId: 500);

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 500,
            mediaType: TmdbMediaType.tv,
            title: 'Something Else',
            voteAverage: 8,
          ),
        ]),
      );
      final r = await service.search('duna');

      expect(r.withLocal, isEmpty,
          reason: 'a movie must not id-match a TV result of the same numeric id');
      expect(r.localOnly, hasLength(1),
          reason: 'the owned movie stays in its own catalogue');
      expect(r.tmdbOnly, hasLength(1),
          reason: 'the unrelated TV result stays a Discover card');
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
