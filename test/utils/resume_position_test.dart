import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/resume_position.dart';

/// Fix 4-extra: el episodio ya visto de la cola debe arrancar en 0, no cerca del
/// final (si no, el auto-avance lo "completa" al instante y lo salta).
void main() {
  test('episodio terminado (≥95%) arranca en 0', () {
    expect(queuedItemStartMs(95000, 100000), 0); // 95%
    expect(queuedItemStartMs(100000, 100000), 0); // 100%
    expect(queuedItemStartMs(99000, 100000), 0); // 99%
  });

  test('episodio a medias conserva su posición', () {
    expect(queuedItemStartMs(30000, 100000), 30000); // 30%
    expect(queuedItemStartMs(0, 100000), 0); // recién empezado
    expect(queuedItemStartMs(94000, 100000), 94000); // 94% < umbral
  });

  test('sin duración total conocida no se toca la posición', () {
    expect(queuedItemStartMs(50000, 0), 50000);
  });
}
