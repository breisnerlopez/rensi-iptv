import 'dart:convert';
import 'dart:ui';

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

  group('TmdbService locale propagation', () {
    test('default locale is en-US', () async {
      await TmdbCredentialsService.saveCredential('k');
      String? sentLanguage;
      final service = TmdbService(
        client: MockClient((request) async {
          sentLanguage = request.url.queryParameters['language'];
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await service.search('dune');
      expect(sentLanguage, 'en-US');
    });

    test('es locale becomes es-ES', () async {
      await TmdbCredentialsService.saveCredential('k');
      String? sentLanguage;
      final service = TmdbService(
        client: MockClient((request) async {
          sentLanguage = request.url.queryParameters['language'];
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await service.search('dune', locale: const Locale('es'));
      expect(sentLanguage, 'es-ES');
    });

    test('locale with explicit country code is preserved', () async {
      await TmdbCredentialsService.saveCredential('k');
      String? sentLanguage;
      final service = TmdbService(
        client: MockClient((request) async {
          sentLanguage = request.url.queryParameters['language'];
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await service.search('dune', locale: const Locale('pt', 'PT'));
      expect(sentLanguage, 'pt-PT');
    });
  });

  group('TmdbService cache key', () {
    test('queries differing only by accent share a cache entry', () async {
      await TmdbCredentialsService.saveCredential('k');
      var calls = 0;
      final service = TmdbService(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 1, 'media_type': 'movie', 'title': 'Düne'},
              ],
            }),
            200,
          );
        }),
      );
      await service.search('düne');
      await service.search('dune');
      expect(calls, 1);
    });

    test('different locales do not share cache entries', () async {
      await TmdbCredentialsService.saveCredential('k');
      var calls = 0;
      final service = TmdbService(
        client: MockClient((request) async {
          calls++;
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await service.search('dune', locale: const Locale('en'));
      await service.search('dune', locale: const Locale('es'));
      expect(calls, 2);
    });
  });
}
