import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tmdb_search_result.dart';
import 'tmdb_credentials_service.dart';

class TmdbService {
  TmdbService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _cachePrefix = 'tmdb.search.';
  static const _cacheTtl = Duration(hours: 24);
  static const _cacheMaxEntries = 100;
  static const _cacheIndexKey = 'tmdb.search.index.v1';

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
      throw Exception('TMDb credential is not configured');
    }

    final uri = _buildSearchUri(normalizedQuery, credential, languageTag);
    final response = await _client.get(uri, headers: _buildHeaders(credential));
    if (response.statusCode == 401) {
      throw Exception('TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw Exception('TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDb request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (decoded['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where(
          (item) => item['media_type'] == 'movie' || item['media_type'] == 'tv',
        )
        .map(TmdbSearchResult.fromTmdbJson)
        .where((item) => item.title.isNotEmpty)
        .take(20)
        .toList();
    await _writeCachedSearch(normalizedQuery, languageTag, results);
    return results;
  }

  /// Fetches the detail payload for a single TMDb id (movie or tv).
  Future<TmdbDetailResult> detail(
    int id,
    TmdbMediaType mediaType, {
    Locale? locale,
  }) async {
    final credential = await TmdbCredentialsService.getCredential();
    if (credential == null) {
      throw Exception('TMDb credential is not configured');
    }
    final segment = mediaType == TmdbMediaType.movie ? 'movie' : 'tv';
    final params = <String, String>{
      'language': _languageTagFor(locale),
    };
    if (!_looksLikeBearerToken(credential)) {
      params['api_key'] = credential;
    }
    final uri = Uri.parse(
      '$_baseUrl/$segment/$id',
    ).replace(queryParameters: params);
    final response = await _client.get(uri, headers: _buildHeaders(credential));
    if (response.statusCode == 401) {
      throw Exception('TMDb credential was rejected');
    }
    if (response.statusCode == 429) {
      throw Exception('TMDb rate limit reached. Try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDb request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return TmdbDetailResult.fromTmdbJson(decoded, mediaType);
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
}
