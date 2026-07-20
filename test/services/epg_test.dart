import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/epg_entry.dart';

// Xtream's short-EPG payload is awkward in ways that matter:
// titles arrive base64-encoded, the human-readable times carry no timezone, and
// panels disagree on the envelope. Each of these has a wrong-looking-but-plausible
// handling that puts the wrong programme on screen, so they are pinned here.
void main() {
  String b64(String s) => base64.encode(utf8.encode(s));

  Map<String, dynamic> raw({
    required int startEpoch,
    required int endEpoch,
    String title = 'Noticias',
  }) =>
      {
        'id': '42',
        'title': b64(title),
        'description': b64('Resumen del día'),
        // Panels send this without an offset, in their own timezone. Parsing it
        // instead of the unix fields shifts the whole schedule for anyone
        // elsewhere — the classic "EPG is two hours off" bug.
        'start': '2026-07-19 20:00:00',
        'end': '2026-07-19 21:00:00',
        'start_timestamp': '$startEpoch',
        'stop_timestamp': '$endEpoch',
      };

  test('decodes base64 title and description', () {
    final e = EpgEntry.fromJson(
        raw(startEpoch: 1000, endEpoch: 4600, title: 'Telediario'), 'ch1')!;
    expect(e.title, 'Telediario');
    expect(e.description, 'Resumen del día');
  });

  test('plain-text title survives — not every panel encodes it', () {
    final json = raw(startEpoch: 1000, endEpoch: 4600);
    json['title'] = 'En directo';
    expect(EpgEntry.fromJson(json, 'ch1')!.title, 'En directo');
  });

  test('times come from the unix fields, not the ambiguous strings', () {
    final e = EpgEntry.fromJson(raw(startEpoch: 1000, endEpoch: 4600), 'ch1')!;
    expect(e.start.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000, isUtc: true));
    expect(e.duration, const Duration(hours: 1));
  });

  test('an entry with no usable window is dropped, not shown', () {
    // A programme without a time window cannot be placed on a timeline, and
    // keeping it would paint a "now playing" row that is neither.
    final json = raw(startEpoch: 0, endEpoch: 0);
    expect(EpgEntry.fromJson(json, 'ch1'), isNull);
  });

  test('isLiveAt is half-open: end belongs to the next programme', () {
    final e = EpgEntry.fromJson(raw(startEpoch: 1000, endEpoch: 4600), 'ch1')!;
    expect(e.isLiveAt(e.start), isTrue);
    expect(e.isLiveAt(e.start.add(const Duration(minutes: 30))), isTrue);
    expect(e.isLiveAt(e.end), isFalse,
        reason: 'at the boundary the next programme is the live one');
  });

  test('progress is clamped and never divides by zero', () {
    final e = EpgEntry.fromJson(raw(startEpoch: 1000, endEpoch: 4600), 'ch1')!;
    expect(e.progressAt(e.start), 0);
    expect(e.progressAt(e.start.add(const Duration(minutes: 30))),
        closeTo(0.5, 0.01));
    expect(e.progressAt(e.end.add(const Duration(hours: 5))), 1.0);

    // Some panels emit start == end.
    final zero = EpgEntry.fromJson(raw(startEpoch: 1000, endEpoch: 1000), 'ch1');
    expect(zero?.progressAt(DateTime.now()), 0);
  });
}
