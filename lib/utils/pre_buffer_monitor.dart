// Lógica de pre-buffer inteligente: decide cuándo hay suficiente caché para una
// reproducción FLUIDA, sin depender de estimaciones de bitrate. La señal clave
// es el "fill-rate": cuántos segundos de contenido se bufferizan por cada
// segundo real. Con el stream en pausa (pre-buffer), el buffer solo crece; si
// crece a ≥1.0 s/s, la conexión sostiene la reproducción → fluida asegurada.
//
// Puro (sin Flutter): se alimenta con muestras (buffer en s, velocidad en B/s)
// y expone la fase y el progreso. Testeable headless; lo usan el player local y
// el reporte del receptor por el canal de casting.
import 'dart:math' as math;

enum BufferPhase {
  warming, // aún tomando muestras
  buffering, // llenando hacia la meta, ritmo sostenible
  slow, // la conexión no sostiene el ritmo (fill-rate < 1)
  stalled, // no entra dato (posible caída/sin conexión)
  ready, // buffer ≥ meta y ritmo sostenible → auto-inicia
}

class PreBufferSample {
  final double bufferedSecs; // demuxer-cache-duration
  final double speedBps; // raw-input-rate (bytes/s)
  final Duration at; // reloj monótono
  const PreBufferSample(this.bufferedSecs, this.speedBps, this.at);
}

class PreBufferMonitor {
  PreBufferMonitor({
    this.targetSecs = 15, // colchón objetivo para arrancar fluido
    this.window = const Duration(seconds: 3), // ventana para el fill-rate
    this.stallAfter = const Duration(seconds: 6), // sin datos → stalled
    this.minSpeedBps = 1024, // < 1 KB/s se considera "sin datos"
    this.sustainable = 1.0, // fill-rate mínimo sostenible (s de contenido / s real)
  });

  final double targetSecs;
  final Duration window;
  final Duration stallAfter;
  final double minSpeedBps;
  final double sustainable;

  final List<PreBufferSample> _samples = [];

  void add(PreBufferSample s) {
    _samples.add(s);
    // Conservar solo la ventana reciente (+1 muestra de margen).
    final cutoff = s.at - window * 2;
    _samples.removeWhere((x) => x.at < cutoff && _samples.length > 2);
  }

  PreBufferSample? get latest => _samples.isEmpty ? null : _samples.last;

  double get bufferedSecs => latest?.bufferedSecs ?? 0;
  double get speedBps => latest?.speedBps ?? 0;

  /// Segundos de contenido bufferizados por segundo real, sobre la ventana.
  /// >1 = la descarga adelanta a la reproducción (sostenible).
  double get fillRate {
    if (_samples.length < 2) return 0;
    final last = _samples.last;
    // La muestra más antigua dentro de la ventana.
    final ref = _samples.firstWhere((x) => last.at - x.at <= window,
        orElse: () => _samples.first);
    final dt = (last.at - ref.at).inMilliseconds / 1000.0;
    if (dt <= 0) return 0;
    return (last.bufferedSecs - ref.bufferedSecs) / dt;
  }

  double get progress =>
      targetSecs <= 0 ? 1 : math.min(1, bufferedSecs / targetSecs);

  /// Tiempo con la velocidad por debajo del umbral (para detectar estancamiento).
  Duration get _idleFor {
    if (_samples.isEmpty) return Duration.zero;
    final last = _samples.last;
    Duration idle = Duration.zero;
    for (var i = _samples.length - 1; i >= 0; i--) {
      if (_samples[i].speedBps >= minSpeedBps) break;
      idle = last.at - _samples[i].at;
    }
    return idle;
  }

  BufferPhase get phase {
    if (_samples.length < 2) return BufferPhase.warming;
    if (_idleFor >= stallAfter) return BufferPhase.stalled;
    // Listo = hay colchón suficiente (meta alcanzada). No se exige fill-rate en
    // este punto porque, al topar el readahead, el buffer deja de crecer y el
    // fill-rate caería a 0 aunque la conexión sea buena.
    if (bufferedSecs >= targetSecs) return BufferPhase.ready;
    // Aún llenando: si crece por debajo del ritmo sostenible, avisar "lento".
    if (fillRate < sustainable * 0.9) return BufferPhase.slow;
    return BufferPhase.buffering;
  }

  bool get isReady => phase == BufferPhase.ready;
}

/// Pure discriminator (FIX-1): between two pre-buffer ticks, decide whether the
/// player is GENUINELY reproducing (video advancing on screen) versus paused,
/// frozen, or seeking. Real playback advances the position by roughly the
/// wall-clock elapsed between ticks (Δpos ≈ Δwall); a SEEK — e.g. a resume/
/// "Continue watching" jump — moves the position far beyond the wall time in a
/// single tick, so it is NOT counted as real playback.
///
/// Comparing against Δwall (not a fixed ceiling) is deliberate: under the exact
/// bug condition the demuxer `getProperty` reads hang and delay the tick, so
/// both Δpos and Δwall grow together and the check still holds. [slack] absorbs
/// timer/decoder jitter. Pure so it can be exercised headlessly (no media_kit).
bool isRealPlaybackAdvance({
  required bool playing,
  required Duration dPos,
  required Duration dWall,
  Duration slack = const Duration(milliseconds: 750),
}) {
  if (!playing) return false;
  if (dPos <= Duration.zero || dWall <= Duration.zero) return false;
  return dPos <= dWall + slack;
}
