import 'dart:async';

import 'package:http/http.dart' as http;

class HttpService {
  HttpService._();

  static final http.Client _client = http.Client();
  static const Duration defaultTimeout = Duration(seconds: 20);

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
