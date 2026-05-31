import 'dart:convert';

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

  group('TmdbService cache', () {
    test('expired cache entries are removed by pruneCache', () async {
      final prefs = await SharedPreferences.getInstance();
      final ancient = DateTime.now().subtract(const Duration(days: 30));
      await prefs.setString(
        'tmdb.search.expired',
        jsonEncode({
          'cachedAt': ancient.toIso8601String(),
          'results': [],
        }),
      );
      await prefs.setStringList('tmdb.search.index.v1', ['tmdb.search.expired']);

      await TmdbService.pruneCache();

      expect(prefs.getString('tmdb.search.expired'), isNull);
      expect(prefs.getStringList('tmdb.search.index.v1'), isEmpty);
    });

    test('fresh queries are tracked in the cache index', () async {
      await TmdbCredentialsService.saveCredential('k');
      final service = TmdbService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 1, 'media_type': 'movie', 'title': 'Dune'},
              ],
            }),
            200,
          );
        }),
      );

      await service.search('dune');
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList('tmdb.search.index.v1');
      // Key format is `tmdb.search.<language-tag>.<folded query>`.
      expect(index, contains('tmdb.search.en-US.dune'));
    });
  });
}
