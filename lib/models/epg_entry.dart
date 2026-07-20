import 'dart:convert';

/// One programme in a channel's schedule.
///
/// Xtream's `get_short_epg` returns the next few entries for a stream, with the
/// title and description **base64-encoded** and the times as local strings plus
/// a unix timestamp. The unix fields are the ones to trust: `start` and `end`
/// come back in the panel's own timezone with no offset, so parsing them as
/// local time silently shifts the schedule for anyone not in that timezone.
class EpgEntry {
  const EpgEntry({
    required this.id,
    required this.channelId,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  final String id;
  final String channelId;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// 0..1 through the programme, clamped. Returns 0 for a zero-length entry
  /// rather than dividing by zero — some panels emit start == end.
  double progressAt(DateTime now) {
    final total = duration.inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  static String _decode(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(raw));
    } catch (_) {
      // Not every panel encodes these; some return plain text.
      return raw;
    }
  }

  static DateTime? _fromUnix(Object? value) {
    final seconds = int.tryParse(value?.toString() ?? '');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toLocal();
  }

  /// Returns null when the entry has no usable time window — a programme
  /// without a start and end cannot be placed on a timeline, and keeping it
  /// would put a "now playing" row on screen that is not now and not playing.
  static EpgEntry? fromJson(Map<String, dynamic> json, String channelId) {
    final start = _fromUnix(json['start_timestamp']);
    final end = _fromUnix(json['stop_timestamp']);
    if (start == null || end == null) return null;

    return EpgEntry(
      id: json['id']?.toString() ?? '$channelId-${start.millisecondsSinceEpoch}',
      channelId: channelId,
      title: _decode(json['title']),
      description: _decode(json['description']),
      start: start,
      end: end,
    );
  }
}
