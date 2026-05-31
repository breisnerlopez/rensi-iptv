import 'dart:async';
import 'dart:io';

import 'package:rensi_iptv/services/http_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HttpService', () {
    late HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test('returns successful responses', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.first.then((request) {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('ok')
            ..close();
        }),
      );

      final response = await HttpService.get(
        Uri.parse('http://${server.address.host}:${server.port}/ok'),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'ok');
    });

    test('throws TimeoutException when request exceeds timeout', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.first.then((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          request.response
            ..statusCode = HttpStatus.ok
            ..write('late')
            ..close();
        }),
      );

      expect(
        () => HttpService.get(
          Uri.parse('http://${server.address.host}:${server.port}/slow'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
