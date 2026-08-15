import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show compute;
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/services/xmltv_parser.dart';

/// Downloads an external XMLTV guide and stores it as the playlist's full EPG.
/// Best-effort and degradation-friendly: any failure (no URL, network, bad XML)
/// throws a typed [EpgRefreshException] the caller can surface, and never leaves
/// a half-written guide (the DB write is a single atomic replace).
class EpgRefreshException implements Exception {
  final String code; // 'no_url' | 'http' | 'parse' | 'network' | 'too_large'
  final String? detail;
  EpgRefreshException(this.code, [this.detail]);
  @override
  String toString() => 'EpgRefreshException($code)';
}

/// Hard cap on the downloaded (post-decompression) XMLTV payload. Real national
/// guides sit well under this; the cap turns a hostile/misconfigured multi-GB
/// feed into a clean error instead of an OOM on a weak TV box.
const int _kMaxXmltvBytes = 256 * 1024 * 1024; // 256 MB

/// Top-level so it can run in a background isolate via [compute] — parsing a
/// national XMLTV (tens of MB of XML → tens of thousands of nodes) on the UI
/// isolate would jank/ANR.
List<XmltvProgramme> _parseXmltvIsolate(String xml) => XmltvParser.parse(xml);

class EpgRefreshService {
  final AppDatabase _db;
  EpgRefreshService(this._db);

  /// Fetch [xmltvUrl], parse it (off the UI isolate), and replace the EPG rows
  /// for [playlistId]. Returns the number of programmes stored.
  Future<int> refreshFromXmltv(String xmltvUrl, String playlistId) async {
    if (xmltvUrl.trim().isEmpty) throw EpgRefreshException('no_url');
    final xml = await _fetch(xmltvUrl.trim());
    final List<XmltvProgramme> programmes;
    try {
      // Parse on a background isolate so a large feed never blocks the UI.
      programmes = await compute(_parseXmltvIsolate, xml);
    } catch (e) {
      throw EpgRefreshException('parse', e.toString());
    }
    final companions = [
      for (final p in programmes)
        EpgProgramsCompanion.insert(
          channelId: p.channelId,
          playlistId: playlistId,
          start: p.start,
          stop: p.stop,
          title: p.title,
          description: Value(p.description),
        ),
    ];
    await _db.replaceEpgForPlaylist(playlistId, companions);
    return companions.length;
  }

  Future<String> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw EpgRefreshException('no_url', 'invalid URL');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    // Decode gzip ourselves so the logic is single-path and deterministic. With
    // the default autoUncompress=true, dart:io silently strips the
    // Content-Encoding header AND inflates the body — our manual gzip.decode
    // would then double-decompress a `.gz` feed and throw. Turning it off keeps
    // the header intact and hands us the raw (possibly compressed) bytes.
    client.autoUncompress = false;
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw EpgRefreshException('http', res.statusCode.toString());
      }
      final gzipped = (res.headers.value(HttpHeaders.contentEncodingHeader) ??
                  '')
              .toLowerCase()
              .contains('gzip') ||
          url.toLowerCase().endsWith('.gz');
      // Stream with a running size guard instead of an unbounded fold, so a
      // hostile/huge feed is rejected before it exhausts memory.
      final bytes = await _collectCapped(res, gzipped);
      final data = gzipped ? gzip.decode(bytes) : bytes;
      if (data.length > _kMaxXmltvBytes) {
        throw EpgRefreshException('too_large', data.length.toString());
      }
      return utf8.decode(data, allowMalformed: true);
    } on EpgRefreshException {
      rethrow;
    } catch (e) {
      throw EpgRefreshException('network', e.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// Accumulate the response body but abort once it exceeds [_kMaxXmltvBytes].
  /// When the payload is gzip we allow the same cap on the *compressed* stream
  /// (a valid guide compresses far below it; the post-inflate size is checked
  /// again by the caller), which also bounds a decompression-bomb's input.
  Future<List<int>> _collectCapped(
      HttpClientResponse res, bool gzipped) async {
    final out = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 90))) {
      out.addAll(chunk);
      if (out.length > _kMaxXmltvBytes) {
        throw EpgRefreshException('too_large', out.length.toString());
      }
    }
    return out;
  }
}
