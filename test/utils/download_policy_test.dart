// Tests de la política de descargas (visto + purga por tope de espacio).
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/download_policy.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  group('isWatched', () {
    const p = DownloadPolicy();
    test('visto al alcanzar el 95%', () {
      expect(p.isWatched(const Duration(minutes: 95), const Duration(minutes: 100)), isTrue);
    });
    test('no visto por debajo del umbral', () {
      expect(p.isWatched(const Duration(minutes: 80), const Duration(minutes: 100)), isFalse);
    });
    test('conservador: sin duración fiable NO marca visto', () {
      expect(p.isWatched(const Duration(minutes: 90), null), isFalse);
      expect(p.isWatched(const Duration(minutes: 90), Duration.zero), isFalse);
      expect(p.isWatched(null, const Duration(minutes: 100)), isFalse);
    });
  });

  group('idsToPurge', () {
    const p = DownloadPolicy(capBytes: 10 * gb);
    DownloadEntry e(int id, int gbSize, bool watched, int at) =>
        DownloadEntry(id: id, bytes: gbSize * gb, watched: watched, addedAt: at);

    test('bajo el tope → no purga nada', () {
      expect(p.idsToPurge([e(1, 3, false, 1), e(2, 4, false, 2)]), isEmpty);
    });

    test('sobre el tope → purga primero los vistos (más antiguos)', () {
      final purge = p.idsToPurge([
        e(1, 5, false, 100), // no visto, nuevo
        e(2, 4, true, 50), // visto, antiguo → primer sacrificio
        e(3, 4, false, 10), // no visto, muy antiguo
      ]);
      // total 13 > 10 → sacrifica el visto (id 2, 4GB) → 9 ≤ 10.
      expect(purge, [2]);
    });

    test('si no basta con vistos, sigue por los no-vistos más antiguos', () {
      final purge = p.idsToPurge([
        e(1, 6, false, 100),
        e(2, 3, true, 50), // visto → primero
        e(3, 5, false, 10), // no visto más antiguo → segundo
      ]);
      // total 14 > 10 → quita visto id2 (→11) aún >10 → quita no-visto más antiguo id3 (→6).
      expect(purge, [2, 3]);
    });

    test('considera los bytes que van a entrar', () {
      final purge = p.idsToPurge([e(1, 7, false, 1)], incomingBytes: 5 * gb);
      // 7 + 5 = 12 > 10 → purga id1.
      expect(purge, [1]);
    });
  });

  // ------------------------------------------------------------------
  // Wave-2 QA cases (Z1..Z5): explicit, measurable coverage of the
  // download-space policy. Inputs and expected ids/bools are spelled out
  // so the assertion output is the evidence.
  // ------------------------------------------------------------------
  group('Wave-2 Z cases', () {
    DownloadEntry e(int id, int gbSize, bool watched, int at) =>
        DownloadEntry(id: id, bytes: gbSize * gb, watched: watched, addedAt: at);

    int sumBytes(List<DownloadEntry> all, List<int> purged) => all
        .where((x) => !purged.contains(x.id))
        .fold<int>(0, (s, x) => s + x.bytes);

    test('Z1 — cap 10GB purge: removes ids until total <= cap', () {
      const p = DownloadPolicy(capBytes: 10 * gb);
      // Four 4GB unwatched entries = 16GB > 10GB cap. Oldest-first LRU:
      // remove id1 (→12), still >10 → remove id2 (→8) <=10 → stop.
      final all = [
        e(1, 4, false, 1),
        e(2, 4, false, 2),
        e(3, 4, false, 3),
        e(4, 4, false, 4),
      ];
      final purge = p.idsToPurge(all);
      expect(purge, [1, 2]);
      // Post-purge total is within the cap (the invariant Z1 asserts).
      expect(sumBytes(all, purge), lessThanOrEqualTo(10 * gb));
      expect(sumBytes(all, purge), 8 * gb);
    });

    test('Z2 — LRU sacrifice order: watched-oldest, then unwatched-oldest', () {
      // Tiny cap forces ALL entries to be purged so the full sacrifice
      // ORDER is observable. Mixed set: watched-new, watched-old,
      // unwatched-old, unwatched-new.
      const p = DownloadPolicy(capBytes: 1); // 1 byte → nothing fits
      final purge = p.idsToPurge([
        e(1, 3, true, 200), // watched, NEW
        e(2, 3, true, 100), // watched, OLD  → sacrificed 1st
        e(3, 3, false, 50), // unwatched, OLD → sacrificed 3rd
        e(4, 3, false, 300), // unwatched, NEW → sacrificed 4th
      ]);
      // Exact order: watched-old, watched-new, unwatched-old, unwatched-new.
      expect(purge, [2, 1, 3, 4]);
    });

    test('Z3 — delete-on-watched: isWatched true at >= 0.95*total', () {
      const p = DownloadPolicy(); // threshold 0.95
      // Exactly at the boundary: 9500ms of 10000ms = 95% → watched.
      expect(
          p.isWatched(const Duration(milliseconds: 9500),
              const Duration(milliseconds: 10000)),
          isTrue);
      // 1ms below the boundary (9499/10000 = 94.99%) → NOT watched.
      expect(
          p.isWatched(const Duration(milliseconds: 9499),
              const Duration(milliseconds: 10000)),
          isFalse);
    });

    test('Z4 — no reliable duration: isWatched false (conservative)', () {
      const p = DownloadPolicy();
      const pos = Duration(minutes: 90);
      expect(p.isWatched(pos, null), isFalse); // null total
      expect(p.isWatched(pos, Duration.zero), isFalse); // zero total
      expect(p.isWatched(pos, const Duration(milliseconds: -5)),
          isFalse); // negative total
      expect(p.isWatched(null, const Duration(minutes: 100)),
          isFalse); // null position
    });

    test('Z5 — no purge if it fits: idsToPurge == [] when total <= cap', () {
      const p = DownloadPolicy(capBytes: 10 * gb);
      // 3 + 4 = 7GB < 10 → nothing to purge.
      expect(p.idsToPurge([e(1, 3, false, 1), e(2, 4, false, 2)]), isEmpty);
      // Boundary: exactly at the cap (total == cap) → still no purge.
      expect(p.idsToPurge([e(1, 6, false, 1), e(2, 4, false, 2)]), isEmpty);
    });
  });
}
