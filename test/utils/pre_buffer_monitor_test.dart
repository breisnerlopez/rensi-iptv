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

  // FIX-1: discriminador reproducción-real-vs-seek. Prueba determinista del bug
  // "la TV muestra 'conexión lenta' pero ya reproduce por detrás".
  group('isRealPlaybackAdvance', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('reproducción real: Δpos ≈ Δwall (tick de 500ms) → true', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(500), dWall: ms(500)),
        isTrue,
      );
    });

    test('EL BUG: reads del demuxer colgados retrasan el tick, Δpos y Δwall '
        'crecen juntos (~2s) → SIGUE siendo reproducción real', () {
      // Este es el caso exacto: getProperty hace timeout (1s c/u) → el tick se
      // retrasa ~2s; el vídeo avanzó ~2s por debajo. Un techo fijo de 1.5s lo
      // rechazaría; comparar contra Δwall lo acepta correctamente.
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(2000), dWall: ms(2000)),
        isTrue,
      );
    });

    test('SEEK al abrir (reanudación "Continuar viendo" a 84s): Δpos ≫ Δwall '
        '→ NO es reproducción (no descartar el overlay ante el salto)', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(84000), dWall: ms(500)),
        isFalse,
      );
    });

    test('en pausa (playing=false) → false, aunque la posición saltara', () {
      expect(
        isRealPlaybackAdvance(playing: false, dPos: ms(500), dWall: ms(500)),
        isFalse,
      );
    });

    test('congelado (Δpos=0) → false (protege el latch terminal legítimo)', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(0), dWall: ms(500)),
        isFalse,
      );
    });

    test('retroceso de posición (Δpos<0) → false', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(-200), dWall: ms(500)),
        isFalse,
      );
    });

    test('jitter dentro del margen (Δpos = Δwall + 600ms) → true', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(1100), dWall: ms(500)),
        isTrue,
      );
    });

    test('salto justo por encima del margen (Δpos = Δwall + 900ms) → false', () {
      expect(
        isRealPlaybackAdvance(playing: true, dPos: ms(1400), dWall: ms(500)),
        isFalse,
      );
    });
  });
}
