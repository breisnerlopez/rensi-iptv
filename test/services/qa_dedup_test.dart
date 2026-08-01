import 'dart:ui';

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

/// QA matrix cases C2 (quality-variant collapse vs. same-name/different-year
/// separation) and C3 (different-dub separation). These exercise the REAL
/// GlobalSearchService dedup — no existing test in
/// global_search_service_test.dart uses quality tags, same-name/different-year
/// pairs, or dub/language suffixes, so this file closes that coverage gap.
class _FakeTmdbService extends TmdbService {
  _FakeTmdbService(this.results);
  final List<TmdbSearchResult> results;
  @override
  Future<List<TmdbSearchResult>> search(String query, {Locale? locale}) async =>
      results;
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

  Future<void> savePl(String id) => PlaylistService.savePlaylist(Playlist(
        id: id,
        name: id,
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      ));

  Future<void> insertMovie(String name, String pl, {int? tmdbId}) async {
    await database.into(database.vodStreams).insert(
          VodStream(
            streamId: 'movie-${name.hashCode}',
            name: name,
            streamIcon: '',
            categoryId: 'movies',
            rating: '',
            rating5based: 0,
            containerExtension: 'mp4',
            playlistId: pl,
            createdAt: DateTime(2026),
            genre: '',
            tmdbId: tmdbId,
          ).toDriftCompanion(),
        );
  }

  group('C2 — quality-variant collapse vs. same-name/different-year', () {
    test('C2a: parenthesized quality variants of ONE title collapse to a single '
        'card exposing every copy', () async {
      // A catalogue tags the same movie by encode quality in brackets/parens
      // ("The Lion King (1080p)", "The Lion King (4K)"). _normalizeTitle strips
      // the parenthetical, so both fold onto the one TMDb "The Lion King" card as
      // exact matches — one card, two play-from rows.
      await savePl('pl1');
      await insertMovie('The Lion King (1080p)', 'pl1');
      await insertMovie('The Lion King (4K)', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 8587,
            mediaType: TmdbMediaType.movie,
            title: 'The Lion King',
            voteAverage: 8,
          ),
        ]),
      );
      final r = await service.search('lion king');

      expect(r.withLocal, hasLength(1),
          reason: 'the two quality encodes are one logical title → one card');
      expect(
        r.withLocal.single.localMatches.map((m) => m.content.name).toSet(),
        {'The Lion King (1080p)', 'The Lion King (4K)'},
        reason: 'both quality copies are exposed as play-from rows',
      );
      expect(r.localOnly, isEmpty,
          reason: 'no quality variant leaks out as its own card');
    });

    test('C2b: two DISTINCT same-name/different-year films with NO tmdbId stay '
        'separate when there is no TMDb card to fold into', () async {
      // The 1994 animated film and the 2019 remake share a normalized title
      // ("the lion king" — the year is stripped) and carry no tmdb id, so the
      // key alone cannot tell them apart. In the local-only path there is no
      // withLocal card, no variant-fold runs, and localOnly is never deduped —
      // so the two genuinely-different films correctly remain two cards.
      await savePl('pl1');
      await insertMovie('The Lion King (1994)', 'pl1');
      await insertMovie('The Lion King (2019)', 'pl1');

      final service = GlobalSearchService(tmdbService: _FakeTmdbService([]));
      final r = await service.search('lion king');

      expect(r.withLocal, isEmpty);
      expect(
        r.localOnly.map((e) => e.content.name).toSet(),
        {'The Lion King (1994)', 'The Lion King (2019)'},
        reason: 'the two distinct films must NOT be merged into one card',
      );
    });

    test('C2c: with matching TMDb "The Lion King" results, the two id-less '
        'same-name/different-year films stay SEPARATE — each folds onto its own '
        'year-card, neither is lost', () async {
      // The FIX for the former C2b LIMITATION: TMDb returns "The Lion King"
      // twice, one dated 1994 and one dated 2019 (as the real API does). Both
      // id-less local copies still normalize-match the yearless TMDb title, but
      // the BRACKETED year in each local name ("(1994)" / "(2019)") now
      // disambiguates against the TMDb result's release year, so the 1994 copy
      // attaches ONLY to the 1994 card and the 2019 copy ONLY to the 2019 card.
      // Two distinct films → two cards, zero loss.
      await savePl('pl1');
      await insertMovie('The Lion King (1994)', 'pl1');
      await insertMovie('The Lion King (2019)', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 8587,
            mediaType: TmdbMediaType.movie,
            title: 'The Lion King',
            releaseDate: '1994-06-15',
            voteAverage: 8,
          ),
          const TmdbSearchResult(
            id: 420818,
            mediaType: TmdbMediaType.movie,
            title: 'The Lion King',
            releaseDate: '2019-07-12',
            voteAverage: 7,
          ),
        ]),
      );
      final r = await service.search('lion king');

      expect(r.withLocal, hasLength(2),
          reason: 'the two distinct-year films must remain two cards');
      final byId = {for (final c in r.withLocal) c.tmdb.id: c};
      expect(byId.keys.toSet(), {8587, 420818},
          reason: 'both TMDb year-cards are owned, neither dropped to Discover');
      expect(
        byId[8587]!.localMatches.map((m) => m.content.name).toSet(),
        {'The Lion King (1994)'},
        reason: 'the 1994 film folds onto the 1994 card only',
      );
      expect(
        byId[420818]!.localMatches.map((m) => m.content.name).toSet(),
        {'The Lion King (2019)'},
        reason: 'the 2019 film folds onto the 2019 card only',
      );
      expect(r.tmdbOnly, isEmpty,
          reason: 'both TMDb entries are owned, so neither is a Discover card');
      expect(r.localOnly, isEmpty,
          reason: 'both films are attached, so nothing leaks to localOnly');
    });
  });

  group('C3 — different dubs stay separate', () {
    test('C3: "Batman Latino" and "Batman Castellano" (bare dub suffixes) stay '
        'as two separate cards, never merged', () async {
      // The dub/audio word is a plain suffix, not a bracket, so it survives
      // normalization: "batman latino" != "batman castellano" (they classify as
      // none to each other) and each is only a FUZZY substring of the TMDb
      // "Batman" — which _findMatchesFor rejects (exact/id only). Neither
      // attaches, so both stay their own localOnly card.
      await savePl('pl1');
      await insertMovie('Batman Latino', 'pl1');
      await insertMovie('Batman Castellano', 'pl1');

      final service = GlobalSearchService(
        tmdbService: _FakeTmdbService([
          const TmdbSearchResult(
            id: 268,
            mediaType: TmdbMediaType.movie,
            title: 'Batman',
            voteAverage: 7,
          ),
        ]),
      );
      final r = await service.search('batman');

      expect(r.withLocal, isEmpty,
          reason: 'a bare-suffix dub is only a fuzzy match — never attaches');
      expect(
        r.localOnly.map((e) => e.content.name).toSet(),
        {'Batman Latino', 'Batman Castellano'},
        reason: 'the two dubs must remain two distinct cards',
      );
      expect(r.tmdbOnly.map((e) => e.tmdb.title), contains('Batman'),
          reason: 'the unowned TMDb title stays its own Discover card');
    });
  });
}
