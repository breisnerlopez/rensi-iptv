import 'dart:convert';
import 'dart:ui';

import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A localized movie genre list as TMDb returns it for `/genre/movie/list`.
String _genreListBody() => jsonEncode({
      'genres': [
        {'id': 28, 'name': 'Acción'},
        {'id': 16, 'name': 'Animación'},
        {'id': 35, 'name': 'Comedia'},
        {'id': 18, 'name': 'Drama'},
      ],
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TmdbService.genreIdForName', () {
    test('maps a localized chip name to its TMDb genre id', () async {
      await TmdbCredentialsService.saveCredential('api-key');
      final service = TmdbService(
        client: MockClient((request) async {
          expect(request.url.path, '/3/genre/movie/list');
          return http.Response(_genreListBody(), 200);
        }),
      );

      final id = await service.genreIdForName('Animación',
          locale: const Locale('es'));
      expect(id, 16);
    });

    test('match is accent- and case-insensitive', () async {
      await TmdbCredentialsService.saveCredential('api-key');
      final service = TmdbService(
        client: MockClient((request) async => http.Response(_genreListBody(), 200)),
      );

      // No accent, lowercase — still resolves to "Acción" → 28.
      expect(await service.genreIdForName('accion', locale: const Locale('es')),
          28);
      // Different casing.
      expect(await service.genreIdForName('DRAMA', locale: const Locale('es')),
          18);
    });

    test('a compound TMDb-TV genre chip falls back to its first movie-mappable '
        'component ("Action & Adventure" → Action)', () async {
      // The confirmed on-device cause of the empty "Populares por género" rail:
      // the catalogue carries TMDb-TV compound genres ("Action & Adventure",
      // "Sci-Fi & Fantasy") that NEVER exist in the MOVIE list. Accent/case were
      // already folded, so plain "Acción" resolved — these "&" compounds are
      // what returned null and hid the rail. They now resolve to a real movie id.
      await TmdbCredentialsService.saveCredential('api-key');
      final service = TmdbService(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'genres': [
                  {'id': 28, 'name': 'Action'},
                  {'id': 12, 'name': 'Adventure'},
                  {'id': 14, 'name': 'Fantasy'},
                  {'id': 878, 'name': 'Science Fiction'},
                ],
              }),
              200,
            )),
      );

      expect(await service.genreIdForName('Action & Adventure'), 28,
          reason: 'the "&" compound maps to its first movie component, Action');
      // "Sci-Fi" has no movie-list entry, but the second component "Fantasy"
      // does — so the rail still surfaces (Fantasy movies) rather than hiding.
      expect(await service.genreIdForName('Sci-Fi & Fantasy'), 14);
      // Connector spelled as a word folds the same as the ampersand.
      expect(await service.genreIdForName('Action and Adventure'), 28);
    });

    test('matching is connector-, punctuation- and whitespace-tolerant',
        () async {
      await TmdbCredentialsService.saveCredential('api-key');
      final service = TmdbService(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'genres': [
                  {'id': 878, 'name': 'Ciencia ficción'},
                  {'id': 28, 'name': 'Acción'},
                ],
              }),
              200,
            )),
      );

      // Hyphen instead of the space TMDb uses, and no accent — still resolves.
      expect(
          await service.genreIdForName('Ciencia-Ficcion',
              locale: const Locale('es')),
          878);
      expect(
          await service.genreIdForName('ACCIÓN', locale: const Locale('es')),
          28);
    });

    test('an unmapped chip name resolves to null (degradation trigger)',
        () async {
      await TmdbCredentialsService.saveCredential('api-key');
      final service = TmdbService(
        client: MockClient((request) async => http.Response(_genreListBody(), 200)),
      );

      final id = await service.genreIdForName('Telenovela',
          locale: const Locale('es'));
      expect(id, isNull);
    });

    test('the localized genre map is fetched once, then cached', () async {
      await TmdbCredentialsService.saveCredential('api-key');
      var calls = 0;
      final service = TmdbService(
        client: MockClient((request) async {
          calls++;
          return http.Response(_genreListBody(), 200);
        }),
      );

      await service.genreIdForName('Animación', locale: const Locale('es'));
      await service.genreIdForName('Drama', locale: const Locale('es'));
      await service.genreIdForName('Comedia', locale: const Locale('es'));
      expect(calls, 1);
    });

    test('no TMDb key throws noKey so the caller can degrade', () async {
      // No saveCredential → getCredential() is null.
      final service = TmdbService(
        client: MockClient((request) async {
          fail('must not hit the network without a credential');
        }),
      );

      expect(
        () => service.genreIdForName('Animación', locale: const Locale('es')),
        throwsA(isA<TmdbException>()
            .having((e) => e.reason, 'reason', TmdbFailure.noKey)),
      );
    });
  });

  group('TmdbService.popularMovies with genreId', () {
    test('year window adds with_genres to discover/movie', () async {
      await TmdbCredentialsService.saveCredential('api-key');
      Uri? seen;
      final service = TmdbService(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );

      await service.popularMovies(PopularWindow.year, genreId: 16, year: 2025);
      expect(seen!.path, '/3/discover/movie');
      expect(seen!.queryParameters['with_genres'], '16');
      expect(seen!.queryParameters['primary_release_year'], '2025');
    });

    test('month window with a genre switches from trending to discover/movie',
        () async {
      await TmdbCredentialsService.saveCredential('api-key');
      Uri? seen;
      final service = TmdbService(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );

      await service.popularMovies(PopularWindow.month, genreId: 16);
      // Trending has no with_genres; the genre month path uses discover/movie.
      expect(seen!.path, '/3/discover/movie');
      expect(seen!.queryParameters['with_genres'], '16');
      expect(seen!.queryParameters.containsKey('primary_release_date.gte'),
          isTrue);
    });

    test('month window WITHOUT a genre still uses trending (unchanged)',
        () async {
      await TmdbCredentialsService.saveCredential('api-key');
      Uri? seen;
      final service = TmdbService(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );

      await service.popularMovies(PopularWindow.month);
      expect(seen!.path, '/3/trending/movie/week');
      expect(seen!.queryParameters.containsKey('with_genres'), isFalse);
    });

    test('a genre-scoped page caches separately from the all-genres page',
        () async {
      await TmdbCredentialsService.saveCredential('api-key');
      var calls = 0;
      final service = TmdbService(
        client: MockClient((request) async {
          calls++;
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );

      await service.popularMovies(PopularWindow.year, year: 2025);
      await service.popularMovies(PopularWindow.year, genreId: 16, year: 2025);
      // Distinct cache keys → two fetches, no cross-eviction.
      expect(calls, 2);
    });
  });
}
