import 'dart:async';
import 'dart:convert' show LineSplitter, utf8;
import 'dart:io' show File, HttpClient;
import 'package:rensi_iptv/models/content_type.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/m3u_item.dart';

class M3uParseException implements Exception {
  final String code;
  final String? detail;
  M3uParseException(this.code, [this.detail]);

  @override
  String toString() =>
      detail == null ? 'M3uParseException($code)' : 'M3uParseException($code): $detail';
}

class M3uParser {
  static const int _maxResponseBytes = 50 * 1024 * 1024; // 50 MB cap
  static const _allowedSchemes = {'http', 'https'};

  static final RegExp _tvgIdRe = RegExp(r'tvg-id="(.*?)"');
  static final RegExp _tvgNameRe = RegExp(r'tvg-name="(.*?)"');
  static final RegExp _tvgLogoRe = RegExp(r'tvg-logo="(.*?)"');
  static final RegExp _tvgUrlRe = RegExp(r'tvg-url="(.*?)"');
  static final RegExp _tvgRecRe = RegExp(r'tvg-rec="(.*?)"');
  static final RegExp _tvgShiftRe = RegExp(r'tvg-shift="(.*?)"');
  static final RegExp _groupTitleRe = RegExp(r'group-title="(.*?)"');
  static final RegExp _userAgentRe = RegExp(r'user-agent="(.*?)"');

  static Future<List<M3uItem>> parseM3uFile(Map<String, String> params) async {
    return await M3uParser.parseFile(params['id']!, params['filePath']!);
  }

  static Future<List<M3uItem>> parseFile(
    String playlistId,
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      return await parseLines(playlistId, lines);
    } catch (e) {
      debugPrint('M3U file parse error: $e');
      throw M3uParseException('m3u_file_read_failed', e.toString());
    }
  }

  static Future<List<M3uItem>> parseM3uUrl(Map<String, String> params) async {
    return await M3uParser.parseUrl(params['id']!, params['url']!);
  }

  static Future<List<M3uItem>> parseUrl(String playlistId, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      throw M3uParseException('m3u_url_invalid_scheme', url);
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..maxConnectionsPerHost = 4;

    try {
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw M3uParseException(
          'm3u_url_http_status',
          response.statusCode.toString(),
        );
      }

      final contentLength = response.contentLength;
      if (contentLength > 0 && contentLength > _maxResponseBytes) {
        throw M3uParseException(
          'm3u_url_response_too_large',
          contentLength.toString(),
        );
      }

      var received = 0;
      final lineStream = response
          .transform<List<int>>(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleData: (data, sink) {
                received += data.length;
                if (received > _maxResponseBytes) {
                  sink.addError(
                    M3uParseException(
                      'm3u_url_response_too_large',
                      received.toString(),
                    ),
                  );
                  sink.close();
                  return;
                }
                sink.add(data);
              },
            ),
          )
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      return await parseLines(playlistId, lineStream);
    } on M3uParseException {
      rethrow;
    } catch (e) {
      debugPrint('M3U URL parse error: $e');
      throw M3uParseException('m3u_url_fetch_failed', e.toString());
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, List<M3uItem>> groupChannels(List<M3uItem> channels) {
    final grouped = <String, List<M3uItem>>{};

    for (final channel in channels) {
      final group = channel.groupTitle ?? 'Other';
      grouped.putIfAbsent(group, () => []).add(channel);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final sortedGrouped = <String, List<M3uItem>>{};

    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  static List<M3uItem> parseM3u(String playlistId, String content) {
    return parseRawLines(playlistId, const LineSplitter().convert(content));
  }

  static Future<List<M3uItem>> parseLines(
    String playlistId,
    Stream<String> lines,
  ) async {
    final parser = _M3uLineParser(playlistId);
    await for (final line in lines) {
      parser.addLine(line);
    }
    return parser.items;
  }

  static List<M3uItem> parseRawLines(
    String playlistId,
    Iterable<String> lines,
  ) {
    final parser = _M3uLineParser(playlistId);
    for (final line in lines) {
      parser.addLine(line);
    }
    return parser.items;
  }

  static String? _extractTvgId(String line) =>
      _tvgIdRe.firstMatch(line)?.group(1);
  static String? _extractTvgName(String line) =>
      _tvgNameRe.firstMatch(line)?.group(1);
  static String? _extractTvgLogo(String line) =>
      _tvgLogoRe.firstMatch(line)?.group(1);
  static String? _extractTvgUrl(String line) =>
      _tvgUrlRe.firstMatch(line)?.group(1);
  static String? _extractTvgRec(String line) =>
      _tvgRecRe.firstMatch(line)?.group(1);
  static String? _extractTvgShift(String line) =>
      _tvgShiftRe.firstMatch(line)?.group(1);
  static String? _extractGroupTitle(String line) =>
      _groupTitleRe.firstMatch(line)?.group(1);
  static String? _extractUserAgent(String line) =>
      _userAgentRe.firstMatch(line)?.group(1);

  static ContentType _detectContentType(String url) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('movie')) {
      return ContentType.vod;
    } else if (lowerUrl.contains('series')) {
      return ContentType.series;
    } else {
      return ContentType.liveStream;
    }
  }
}

class _M3uLineParser {
  final String playlistId;
  final Uuid _uuid = Uuid();
  final List<M3uItem> items = [];
  Map<String, String?> _currentMeta = {};
  String? _currentName;

  _M3uLineParser(this.playlistId);

  void addLine(String rawLine) {
    final line = rawLine.trim();

    if (line.startsWith('#EXTINF')) {
      final commaIndex = line.indexOf(',');
      final metadataPart = commaIndex != -1
          ? line.substring(0, commaIndex)
          : line;

      _currentName = commaIndex != -1
          ? line.substring(commaIndex + 1).trim()
          : null;

      _currentMeta = {
        'tvg-id': M3uParser._extractTvgId(metadataPart),
        'tvg-name': M3uParser._extractTvgName(metadataPart),
        'tvg-logo': M3uParser._extractTvgLogo(metadataPart),
        'tvg-url': M3uParser._extractTvgUrl(metadataPart),
        'tvg-rec': M3uParser._extractTvgRec(metadataPart),
        'tvg-shift': M3uParser._extractTvgShift(metadataPart),
        'group-title': M3uParser._extractGroupTitle(metadataPart),
        'user-agent': M3uParser._extractUserAgent(metadataPart),
      };
      return;
    }

    if (line.startsWith('#EXTGRP:')) {
      _currentMeta['group-name'] = line.substring(8).trim();
      return;
    }

    if (line.isEmpty || line.startsWith('#')) return;

    items.add(
      M3uItem(
        id: _uuid.v4(),
        playlistId: playlistId,
        url: line,
        contentType: M3uParser._detectContentType(line),
        name: _currentName,
        tvgId: _currentMeta['tvg-id'],
        tvgName: _currentMeta['tvg-name'],
        tvgLogo: _currentMeta['tvg-logo'],
        tvgUrl: _currentMeta['tvg-url'],
        tvgRec: _currentMeta['tvg-rec'],
        tvgShift: _currentMeta['tvg-shift'],
        groupTitle: _currentMeta['group-title'],
        groupName: _currentMeta['group-name'],
        userAgent: _currentMeta['user-agent'],
        referrer: null,
      ),
    );

    _currentMeta.clear();
    _currentName = null;
  }
}

class M3uTempSeries {
  final String name;
  final int seasonNumber;
  final int episodeNumber;
  final M3uItem m3uItem;

  M3uTempSeries(this.name, this.seasonNumber, this.episodeNumber, this.m3uItem);

  @override
  String toString() {
    return "$name $seasonNumber $episodeNumber";
  }
}

class SeriesParser {
  static final RegExp _seriesRegex = RegExp(
    r'^(.+?)\s+S(\d{1,2})\s+E(\d{1,3})',
    caseSensitive: false,
  );

  static final RegExp _alternativeRegex = RegExp(
    r'^(.+?)\s+Season\s+(\d{1,2})\s+Episode\s+(\d{1,3})',
    caseSensitive: false,
  );

  static M3uTempSeries? parse(M3uItem item) {
    if (item.name == null) {
      return null;
    }

    RegExpMatch? match = _seriesRegex.firstMatch(item.name!.trim());

    match ??= _alternativeRegex.firstMatch(item.name!.trim());

    if (match != null) {
      final seriesName = match.group(1)?.trim() ?? '';
      final seasonNumber = int.tryParse(match.group(2) ?? '') ?? 0;
      final episodeNumber = int.tryParse(match.group(3) ?? '') ?? 0;

      return M3uTempSeries(seriesName, seasonNumber, episodeNumber, item);
    }

    return null;
  }

  static String generateSeriesId(String playlistId, String seriesName) {
    return '${playlistId}_${seriesName.toLowerCase().replaceAll(' ', '_')}';
  }

  static String generateSeasonId(String seriesId, int seasonNumber) {
    return '${seriesId}_s${seasonNumber.toString().padLeft(2, '0')}';
  }

  static String generateEpisodeId(String seasonId, int episodeNumber) {
    return '${seasonId}_e${episodeNumber.toString().padLeft(2, '0')}';
  }
}
