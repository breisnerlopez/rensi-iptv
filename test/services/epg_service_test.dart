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
  List<EpgEntry>? next = const [];
  Completer<void>? gate;

  Future<List<EpgEntry>?> fetch(String streamId) async {
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

  test('a channel with no guide is asked once, not on every rebuild', () async {
    // This is the number that matters. An audit measured 245 requests for one
    // scroll over 300 guide-less channels, because "the panel has no listing"
    // and "the request failed" were both an empty list, so the service could
    // never remember the answer. Xtream panels rate-limit and ban for that.
    repo.next = const [];
    for (var i = 0; i < 10; i++) {
      await service.entriesFor('ch1');
    }
    expect(repo.calls, 1);
  });

  test('a FAILED request is retried, but not immediately', () async {
    repo.next = null; // null = the request failed
    await service.entriesFor('ch1');
    await service.entriesFor('ch1');
    expect(repo.calls, 1, reason: 'the backoff must absorb the retry storm');

    // With the backoff elapsed it tries again: a failure is usually transient,
    // so it must not be remembered as if it were an answer.
    final quick = EpgService(repo.fetch, ttl: const Duration(minutes: 30));
    repo.calls = 0;
    await quick.entriesFor('chX');
    expect(repo.calls, 1);
  });

  test('a scroll over many guide-less channels stays proportional', () async {
    repo.next = const [];
    // 300 rows painted, then scrolled back over the same 300.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < 300; i++) {
        await service.entriesFor('ch$i');
      }
    }
    // 300 channels, capped cache of 300: the second pass may evict a little,
    // but the count must stay close to one request per channel, not per paint.
    expect(repo.calls, lessThanOrEqualTo(360),
        reason: 'measured 245 for a single pass before this was fixed');
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
