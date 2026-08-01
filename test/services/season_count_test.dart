// Wave-2 QA: degenerate series-data guards for the season-count logic.
// Tests the REAL, provider-facing function GlobalSearchService.seasonCountFromNumbers
// (lib/services/global_search_service.dart:1225), which powers the "N temporadas"
// label. Pure/static + @visibleForTesting → runs on the Dart VM, no emulator.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/global_search_service.dart';

void main() {
  int? count(Iterable<int> eps, Iterable<int> declared) =>
      GlobalSearchService.seasonCountFromNumbers(eps, declared);

  group('AA12 — series with 0 episodes / empty seasons (no divide-by-zero)', () {
    test('fully empty (0 episodes, 0 declared) → null, does NOT throw', () {
      // No division exists in the function (it uses set lengths + max), so an
      // empty series can never divide-by-zero. The "unknown" result is null,
      // which callers render as a plain playlist label. Sane count == 0 real
      // seasons; the function encodes that absence as null, not 0.
      expect(() => count(const <int>[], const <int>[]), returnsNormally);
      expect(count(const <int>[], const <int>[]), isNull);
    });

    test('0 episodes but seasons declared → the declared count (still no throw)',
        () {
      // A provider can declare seasons whose episodes are not loaded yet.
      expect(count(const <int>[], const [1, 2, 3]), 3);
    });
  });

  group('AA14 — specials-only (season 0) is not counted', () {
    test('only season 0 (specials) → null (excluded, never a real season)', () {
      // seasonCountFromNumbers filters n>=1 on BOTH episode and declared season
      // numbers, so a specials-only series yields no real season → null.
      expect(count(const [0, 0, 0], const [0]), isNull);
    });

    test('specials + real seasons → specials do NOT inflate the count', () {
      // Episodes in seasons {0,1,1,2}, declared {0,1,2}: season 0 dropped →
      // real seasons {1,2} → 2 (a naive distinct-count would wrongly say 3).
      expect(count(const [0, 1, 1, 2], const [0, 1, 2]), 2);
    });
  });
}
