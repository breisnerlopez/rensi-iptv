import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/local_file_server.dart';

void main() {
  group('LocalFileServer', () {
    late Directory tmpDir;
    late File tmpFile;
    late Uint8List bytes;
    late LocalFileServer server;
    late HttpClient client;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('local_file_server_test');
      tmpFile = File('${tmpDir.path}/video.mp4');
      // Bytes conocidos: 0, 1, 2, ..., 19.
      bytes = Uint8List.fromList(List<int>.generate(20, (i) => i));
      await tmpFile.writeAsBytes(bytes);
      server = LocalFileServer();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      await tmpDir.delete(recursive: true);
    });

    // No cerramos el HttpClient tras cada request: eso cortaría la conexión
    // antes de terminar de leer el body. Se cierra una sola vez en tearDown.
    Future<HttpClientResponse> request(int port, {String? range}) async {
      final req = await client.getUrl(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:$port/f'),
      );
      if (range != null) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }
      return req.close();
    }

    test('GET completo devuelve todos los bytes con 200 y Accept-Ranges',
        () async {
      final url = await server.serve(tmpFile.path);
      final port = Uri.parse(url).port;

      final response = await request(port);
      final body = await response.fold<List<int>>(
          <int>[], (acc, chunk) => acc..addAll(chunk));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(response.headers.value(HttpHeaders.contentLengthHeader),
          '${bytes.length}');
      expect(body, bytes);
    });

    test('Range bytes=5-9 devuelve 206 con esos bytes exactos y Content-Range',
        () async {
      final url = await server.serve(tmpFile.path);
      final port = Uri.parse(url).port;

      final response = await request(port, range: 'bytes=5-9');
      final body = await response.fold<List<int>>(
          <int>[], (acc, chunk) => acc..addAll(chunk));

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 5-9/${bytes.length}');
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '5');
      expect(body, bytes.sublist(5, 10));
    });

    test('Range fuera de rango devuelve 416', () async {
      final url = await server.serve(tmpFile.path);
      final port = Uri.parse(url).port;

      final response = await request(port, range: 'bytes=1000-2000');
      // Se drena el body (vacío) para no dejar el socket colgado.
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */${bytes.length}');
    });

    test('HEAD devuelve headers sin cuerpo', () async {
      final url = await server.serve(tmpFile.path);
      final port = Uri.parse(url).port;

      final headClient = HttpClient();
      final req = await headClient.headUrl(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:$port/f'),
      );
      final response = await req.close();
      final body = await response.fold<List<int>>(
          <int>[], (acc, chunk) => acc..addAll(chunk));
      headClient.close(force: true);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.contentLengthHeader),
          '${bytes.length}');
      expect(body, isEmpty);
    });

    test('stop() cierra el server y deja de responder', () async {
      final url = await server.serve(tmpFile.path);
      final port = Uri.parse(url).port;
      await server.stop();

      expect(
        () => request(port),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
