import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/backup_service.dart';

void main() {
  group('BackupService.fetchBackupFromUrl', () {
    test('rejects non-http(s) schemes with backup_url_invalid', () async {
      await expectLater(
        BackupService.fetchBackupFromUrl('file:///etc/passwd'),
        throwsA(
          predicate<BackupFormatException>(
            (e) => e.code == 'backup_url_invalid',
          ),
        ),
      );
    });

    test('rejects malformed URLs with backup_url_invalid', () async {
      await expectLater(
        BackupService.fetchBackupFromUrl('not a url'),
        throwsA(
          predicate<BackupFormatException>(
            (e) => e.code == 'backup_url_invalid',
          ),
        ),
      );
    });

    test('downloads a small backup over HTTP', () async {
      final server =
          await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      final payload = Uint8List.fromList(<int>[
        // Minimal valid backup-ish JSON: importBytes isn't called here, so
        // any byte stream is fine.
        ...'rensi-iptv-backup'.codeUnits,
      ]);
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType =
              io.ContentType('application', 'octet-stream')
          ..add(payload);
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/backup.aipbak';
        final got = await BackupService.fetchBackupFromUrl(url);
        expect(got, equals(payload));
      } finally {
        await server.close(force: true);
      }
    });

    test('non-2xx response throws backup_url_http_error', () async {
      final server =
          await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/missing.aipbak';
        await expectLater(
          BackupService.fetchBackupFromUrl(url),
          throwsA(
            predicate<BackupFormatException>(
              (e) =>
                  e.code == 'backup_url_http_error' &&
                  (e.detail ?? '').contains('404'),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('aborts when content-length exceeds the 50 MB cap', () async {
      final server =
          await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      final liveSockets = <io.Socket>[];
      server.listen((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        liveSockets.add(socket);
        const giant = 60 * 1024 * 1024;
        final headers =
            'HTTP/1.1 200 OK\r\n'
            'Content-Length: $giant\r\n'
            'Content-Type: application/octet-stream\r\n\r\n';
        socket.write(headers);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await socket.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/big.aipbak';
        await expectLater(
          BackupService.fetchBackupFromUrl(url),
          throwsA(
            predicate<BackupFormatException>(
              (e) => e.code == 'backup_url_too_large',
            ),
          ),
        );
      } finally {
        for (final s in liveSockets) {
          try {
            await s.close();
          } catch (_) {}
        }
        await server.close(force: true);
      }
    });
  });
}
