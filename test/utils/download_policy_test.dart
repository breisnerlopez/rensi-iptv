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
}
