import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/epg_entry.dart';
import 'package:rensi_iptv/services/epg_service.dart';

// EpgService is the stateful, concurrent half of the EPG feature: a cache, a
// TTL, and in-flight sharing. `get_short_epg` is per channel, so on a
// 5000-channel playlist the difference between asking well and asking naively
// is thousands of requests — which makes these behaviours load-bearing rather
// than nice to have.
class _FakeSource {
  int calls = 0;
  List<EpgEntry> next = const [];
  Completer<void>? gate;

  Future<List<EpgEntry>> fetch(String streamId) async {
    calls++;
    if (gate != null) await gate!.future;
    return next;
  }
}

EpgEntry _entry(String id, DateTime start, DateTime end) => EpgEntry(
      id: id,
      channelId: 'ch1',
      title: 'Programa $id',
      description: '',
      start: start,
      end: end,
    );

void main() {
  late _FakeSource repo;
  late EpgService service;
  final now = DateTime(2026, 7, 19, 20, 30);

  setUp(() {
    repo = _FakeSource();
    service = EpgService(repo.fetch);
  });

  test('a second read inside the TTL does not hit the panel again', () async {
    repo.next = [
      _entry('a', now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)))
    ];
    await service.entriesFor('ch1');
    await service.entriesFor('ch1');
    expect(repo.calls, 1);
  });

  test('an expired entry is refetched', () async {
    final shortLived = EpgService(repo.fetch, ttl: const Duration(milliseconds: 1));
    repo.next = [_entry('a', now, now.add(const Duration(hours: 1)))];
    await shortLived.entriesFor('ch1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await shortLived.entriesFor('ch1');
    expect(repo.calls, 2);
  });

  test('concurrent readers share one request', () async {
    repo.gate = Completer<void>();
    repo.next = [_entry('a', now, now.add(const Duration(hours: 1)))];

    final a = service.entriesFor('ch1');
    final b = service.entriesFor('ch1');
    final c = service.entriesFor('ch1');
    repo.gate!.complete();
    await Future.wait([a, b, c]);

    expect(repo.calls, 1,
        reason: 'a rail and a grid showing the same channel must not both ask');
  });

  test('an empty answer is NOT cached', () async {
    // "No data" and "the request failed" are indistinguishable here, so caching
    // the empty list would let a two-second blip hide the schedule for 30 min.
    repo.next = const [];
    await service.entriesFor('ch1');
    await service.entriesFor('ch1');
    expect(repo.calls, 2);
  });

  test('nowPlaying returns the airing programme, not merely the first', () async {
    repo.next = [
      _entry('past', now.subtract(const Duration(hours: 3)),
          now.subtract(const Duration(hours: 2))),
      _entry('live', now.subtract(const Duration(minutes: 10)),
          now.add(const Duration(minutes: 50))),
      _entry('later', now.add(const Duration(minutes: 50)),
          now.add(const Duration(hours: 2))),
    ];
    final e = await service.nowPlaying('ch1', now: now);
    expect(e?.id, 'live');
  });

  test('nowPlaying returns null rather than a finished programme', () async {
    repo.next = [
      _entry('past', now.subtract(const Duration(hours: 3)),
          now.subtract(const Duration(hours: 2)))
    ];
    expect(await service.nowPlaying('ch1', now: now), isNull,
        reason: 'showing a programme that ended is worse than showing none');
  });

  test('upNext skips what is already airing', () async {
    repo.next = [
      _entry('live', now.subtract(const Duration(minutes: 10)),
          now.add(const Duration(minutes: 50))),
      _entry('later', now.add(const Duration(minutes: 50)),
          now.add(const Duration(hours: 2))),
    ];
    expect((await service.upNext('ch1', now: now))?.id, 'later');
  });

  test('invalidate drops the cache so a new playlist cannot inherit it',
      () async {
    // Stream ids are only unique within a provider: without this, switching
    // playlists would show the previous panel's schedule.
    repo.next = [_entry('a', now, now.add(const Duration(hours: 1)))];
    await service.entriesFor('ch1');
    service.invalidate();
    await service.entriesFor('ch1');
    expect(repo.calls, 2);
  });

  test('the cache stays bounded while scrolling a large playlist', () async {
    repo.next = [_entry('a', now, now.add(const Duration(hours: 1)))];
    for (var i = 0; i < 400; i++) {
      await service.entriesFor('ch$i');
    }
    // Re-reading the oldest channel must re-fetch: it should have been evicted.
    final before = repo.calls;
    await service.entriesFor('ch0');
    expect(repo.calls, before + 1,
        reason: '5000 channels must not stay resident for the process lifetime');
  });
}
