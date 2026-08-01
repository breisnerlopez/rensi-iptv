import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/epg_entry.dart';
import 'package:rensi_iptv/services/epg_service.dart';

/// QA matrix: EPG anti-ban behaviour, headless. No emulator, no HTTP.
///
/// The anti-ban gatekeeping (TTL cache of empty guides, failure backoff,
/// in-flight de-dup) lives entirely inside EpgService, so a counting fake
/// `_fetch` closure is the faithful and deterministic way to measure the
/// request count the panel would actually see.
void main() {
  const int channelCount = 300; // exactly _maxEntries, so no LRU eviction.

  List<String> channels() =>
      List<String>.generate(channelCount, (i) => 'ch_$i');

  group('EPG anti-ban', () {
    test('N2 no-guide 300 channels: re-scroll adds ZERO fetches', () async {
      var calls = 0;
      // Every channel has NO guide -> panel returns an EMPTY list (a real
      // answer, not a failure). This is the exact anti-ban case.
      final service = EpgService((streamId) async {
        calls++;
        return <EpgEntry>[];
      });

      // Full guide pass.
      for (final id in channels()) {
        await service.entriesFor(id);
      }
      final afterFirstPass = calls;

      // SCROLL BACK within the TTL window: same 300 channels again.
      for (final id in channels()) {
        await service.entriesFor(id);
      }
      final afterRescroll = calls;

      expect(afterFirstPass, 300,
          reason: 'first pass asks each unique channel exactly once');
      expect(afterRescroll, 300,
          reason: 'empty guides are cached under TTL; re-scroll re-asks none');
    });

    test('N3 failure (null) 300 channels: no retry storm within backoff',
        () async {
      var calls = 0;
      // Every request FAILS (HTTP 500 / timeout) -> `_fetch` returns null.
      final service = EpgService((streamId) async {
        calls++;
        return null;
      });

      for (final id in channels()) {
        await service.entriesFor(id);
      }
      final afterFirstPass = calls;

      // Immediate re-scroll, still inside the 2min failure backoff window.
      for (final id in channels()) {
        await service.entriesFor(id);
      }
      final afterRescroll = calls;

      expect(afterFirstPass, 300,
          reason: 'first pass asks each channel once');
      expect(afterRescroll, 300,
          reason: 'within 2min backoff a re-scroll issues ZERO extra fetches');
      // The "retries after 2min" half is real-time (DateTime.now(), not
      // injectable without touching lib/) and is confirmed by code inspection:
      // entriesFor() only short-circuits on _failedAt while
      // now.difference(failed) < _failureBackoff (2min); past that it falls
      // through to _fetch again. Verified deterministically: no storm.
    });

    test('N5 in-flight de-dup: two concurrent calls -> ONE fetch', () async {
      var calls = 0;
      final gate = Completer<List<EpgEntry>?>();
      final service = EpgService((streamId) {
        calls++;
        return gate.future; // stays pending until we release it.
      });

      // Fire two concurrent calls for the SAME channel before fetch completes.
      final a = service.entriesFor('same');
      final b = service.entriesFor('same');

      expect(calls, 1, reason: 'second caller joins the in-flight request');

      gate.complete(<EpgEntry>[]);
      await a;
      await b;

      expect(calls, 1, reason: 'still one fetch after both resolve');
    });
  });
}
