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
