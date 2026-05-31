import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TmdbService', () {
    test(
      'search sends api_key credentials and parses movie and tv results',
      () async {
        await TmdbCredentialsService.saveCredential('api-key');
        final service = TmdbService(
          client: MockClient((request) async {
            expect(request.url.queryParameters['api_key'], 'api-key');
            expect(request.headers.containsKey('Authorization'), isFalse);
            return http.Response('''
          {
            "results": [
              {"id": 1, "media_type": "movie", "title": "Dune", "poster_path": "/p.jpg", "release_date": "2021-01-01", "vote_average": 8.1},
              {"id": 2, "media_type": "tv", "name": "Dark", "first_air_date": "2017-01-01", "vote_average": 8.0},
              {"id": 3, "media_type": "person", "name": "Ignored"}
            ]
          }
          ''', 200);
          }),
        );

        final results = await service.search('dune');

        expect(results, hasLength(2));
        expect(results.first.title, 'Dune');
        expect(
          results.first.posterUrl,
          'https://image.tmdb.org/t/p/w342/p.jpg',
        );
        expect(results.last.title, 'Dark');
      },
    );

    test('search uses cached results for repeated queries', () async {
      await TmdbCredentialsService.saveCredential('api-key');
      var calls = 0;
      final service = TmdbService(
        client: MockClient((request) async {
          calls++;
          return http.Response('''
          {"results": [{"id": 1, "media_type": "movie", "title": "Dune"}]}
          ''', 200);
        }),
      );

      await service.search('dune');
      final second = await service.search('DUNE');

      expect(calls, 1);
      expect(second.single.title, 'Dune');
    });

    test(
      'search sends bearer credentials when a read token is configured',
      () async {
        final token = 'eyJ${'a' * 90}';
        await TmdbCredentialsService.saveCredential(token);
        final service = TmdbService(
          client: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer $token');
            expect(request.url.queryParameters.containsKey('api_key'), isFalse);
            return http.Response('{"results": []}', 200);
          }),
        );

        await service.search('dune');
      },
    );
  });
}
