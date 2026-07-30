// Tests de la lógica de pre-buffer (fill-rate → fluidez). Deterministas.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/pre_buffer_monitor.dart';

void main() {
  PreBufferSample s(double buf, double bps, int ms) =>
      PreBufferSample(buf, bps, Duration(milliseconds: ms));

  test('warming: con menos de 2 muestras', () {
    final m = PreBufferMonitor();
    expect(m.phase, BufferPhase.warming);
    m.add(s(0, 500000, 0));
    expect(m.phase, BufferPhase.warming);
  });

  test('ready: buffer llega a la meta con ritmo sostenible (fill-rate ≥ 1)', () {
    final m = PreBufferMonitor(targetSecs: 15);
    // ~1.2 s de contenido por segundo real (sostenible), hasta pasar la meta.
    var buf = 0.0;
    for (var t = 0; t <= 14000; t += 1000) {
      m.add(s(buf, 800000, t));
      buf += 1.2;
    }
    expect(m.bufferedSecs, greaterThanOrEqualTo(15));
    expect(m.fillRate, greaterThanOrEqualTo(1.0));
    expect(m.phase, BufferPhase.ready);
    expect(m.isReady, isTrue);
  });

  test('slow: la conexión no sostiene el ritmo (fill-rate < 1)', () {
    final m = PreBufferMonitor(targetSecs: 15);
    var buf = 0.0;
    for (var t = 0; t <= 8000; t += 1000) {
      m.add(s(buf, 120000, t));
      buf += 0.5; // 0.5 s de contenido por segundo real → no alcanza
    }
    expect(m.fillRate, lessThan(0.9));
    expect(m.phase, BufferPhase.slow);
    expect(m.isReady, isFalse);
  });

  test('stalled: sin datos durante stallAfter', () {
    final m = PreBufferMonitor(stallAfter: const Duration(seconds: 6));
    m.add(s(3, 500000, 0)); // llegó algo
    // 7 s sin velocidad (sin datos entrando).
    for (var t = 1000; t <= 7000; t += 1000) {
      m.add(s(3, 0, t));
    }
    expect(m.phase, BufferPhase.stalled);
  });

  test('progress refleja buffer/meta y se satura en 1', () {
    final m = PreBufferMonitor(targetSecs: 20);
    m.add(s(0, 1, 0));
    m.add(s(10, 1, 1000));
    expect(m.progress, closeTo(0.5, 0.01));
    m.add(s(25, 1, 2000));
    expect(m.progress, 1.0);
  });
}
