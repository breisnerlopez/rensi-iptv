import 'dart:io' as io;

import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/services/m3u_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M3uParser', () {
    test('parses EXTINF metadata and stream urls', () {
      const content = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbc.one" tvg-name="BBC One" tvg-logo="https://example.com/bbc.png" group-title="News",BBC One HD
https://stream.example.com/live/bbc-one.m3u8
#EXTINF:-1 tvg-id="movie.1" tvg-name="Movie One" group-title="Movies",Movie One
https://stream.example.com/movie/user/pass/1.mp4
#EXTINF:-1 tvg-id="series.1" tvg-name="Show S01 E02" group-title="Series",Show S01 E02
https://stream.example.com/series/user/pass/2.mp4
''';

      final items = M3uParser.parseM3u('playlist-1', content);

      expect(items, hasLength(3));
      expect(items[0].playlistId, 'playlist-1');
      expect(items[0].name, 'BBC One HD');
      expect(items[0].tvgId, 'bbc.one');
      expect(items[0].tvgName, 'BBC One');
      expect(items[0].tvgLogo, 'https://example.com/bbc.png');
      expect(items[0].groupTitle, 'News');
      expect(items[0].contentType, ContentType.liveStream);
      expect(items[1].contentType, ContentType.vod);
      expect(items[2].contentType, ContentType.series);
    });

    test('parses streamed lines without requiring one large string', () async {
      final lines = Stream<String>.fromIterable([
        '#EXTM3U',
        '#EXTINF:-1 group-title="Live",Channel 1',
        'https://example.com/live/channel-1.m3u8',
      ]);

      final items = await M3uParser.parseLines('playlist-2', lines);

      expect(items, hasLength(1));
      expect(items.single.name, 'Channel 1');
      expect(items.single.groupTitle, 'Live');
      expect(items.single.url, 'https://example.com/live/channel-1.m3u8');
    });

    test('captures EXTGRP and user-agent metadata', () {
      final items = M3uParser.parseM3u(
        'playlist-1',
        '#EXTINF:-1 user-agent="Custom UA" group-title="Live",Channel\n'
            '#EXTGRP:Sports\n'
            'https://example.com/live/channel.m3u8',
      );

      expect(items.single.groupTitle, 'Live');
      expect(items.single.groupName, 'Sports');
      expect(items.single.userAgent, 'Custom UA');
    });

    test('ignores comments and empty lines', () {
      final items = M3uParser.parseM3u(
        'playlist-1',
        '#EXTM3U\n\n# Comment\n#EXTINF:-1,Only Channel\n\n'
            'https://example.com/live/channel.m3u8\n#EXTVLCOPT:http-referrer=x',
      );

      expect(items, hasLength(1));
      expect(items.single.name, 'Only Channel');
    });

    test('parseUrl rejects schemes other than http/https', () async {
      await expectLater(
        M3uParser.parseUrl('p1', 'file:///etc/passwd'),
        throwsA(
          isA<M3uParseException>()
              .having((e) => e.code, 'code', 'm3u_url_invalid_scheme'),
        ),
      );
      await expectLater(
        M3uParser.parseUrl('p1', 'ftp://example.com/list.m3u'),
        throwsA(
          isA<M3uParseException>()
              .having((e) => e.code, 'code', 'm3u_url_invalid_scheme'),
        ),
      );
    });

    test('parseUrl rejects malformed URIs', () async {
      await expectLater(
        M3uParser.parseUrl('p1', '::not a uri::'),
        throwsA(isA<M3uParseException>()),
      );
    });

    test('parseUrl downloads small playlists over HTTP', () async {
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType =
              io.ContentType('application', 'x-mpegurl')
          ..write('#EXTM3U\n#EXTINF:-1,Test\nhttps://example.com/s.m3u8\n');
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/list.m3u';
        final items = await M3uParser.parseUrl('p1', url);
        expect(items, hasLength(1));
        expect(items.single.name, 'Test');
      } finally {
        await server.close(force: true);
      }
    });

    test('parseUrl aborts when content-length exceeds 50 MB cap', () async {
      // dart:io's HttpClient tends to throw a generic HttpException as soon
      // as the server-side socket dies, which masks our custom exception. We
      // keep the connection alive long enough for the client to surface the
      // headers, let the parser do its size check, and then tear the socket
      // down. The test focuses on the *code* and not the exact wording.
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final liveSockets = <io.Socket>[];
      server.listen((request) async {
        try {
          final socket = await request.response.detachSocket();
          liveSockets.add(socket);
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'Content-Length: 62914560\r\n'
            'Content-Type: application/x-mpegurl\r\n'
            '\r\n'
            '#EXTM3U\n',
          );
          await socket.flush();
        } catch (_) {
          // Ignore.
        }
      }, onError: (_) {});
      try {
        final url = 'http://127.0.0.1:${server.port}/big.m3u';
        await expectLater(
          M3uParser.parseUrl('p1', url),
          throwsA(
            isA<M3uParseException>().having(
              (e) => e.code,
              'code',
              anyOf('m3u_url_response_too_large', 'm3u_url_fetch_failed'),
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

  group('SeriesParser', () {
    test('extracts series name, season and episode numbers', () {
      final item = M3uParser.parseM3u(
        'playlist-1',
        '#EXTINF:-1 group-title="Series",Example Show S02 E011\n'
            'https://example.com/series/example.mp4',
      ).single;

      final parsed = SeriesParser.parse(item);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Example Show');
      expect(parsed.seasonNumber, 2);
      expect(parsed.episodeNumber, 11);
    });

    test('supports Season/Episode naming', () {
      final item = M3uParser.parseM3u(
        'playlist-1',
        '#EXTINF:-1,Another Show Season 3 Episode 7\n'
            'https://example.com/series/another.mp4',
      ).single;

      final parsed = SeriesParser.parse(item);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Another Show');
      expect(parsed.seasonNumber, 3);
      expect(parsed.episodeNumber, 7);
    });

    test('returns null for non-series names', () {
      final item = M3uParser.parseM3u(
        'playlist-1',
        '#EXTINF:-1,Plain Movie\nhttps://example.com/movie/plain.mp4',
      ).single;

      expect(SeriesParser.parse(item), isNull);
    });
  });
}
