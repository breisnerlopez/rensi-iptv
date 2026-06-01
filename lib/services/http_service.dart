import 'dart:async';

import 'package:http/http.dart' as http;

class HttpService {
  HttpService._();

  static final http.Client _client = http.Client();
  // 60s instead of 20s so catalogue-wide endpoints (get_vod_streams,
  // get_series, get_live_streams) have room to finish on slow providers
  // or large catalogues. Smaller endpoints (auth, VOD info) tend to
  // answer well inside this window so the bump only matters when needed.
  static const Duration defaultTimeout = Duration(seconds: 60);

  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) {
    return _client
        .get(uri, headers: headers)
        .timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException('Request timed out', timeout);
          },
        );
  }
}
