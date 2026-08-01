// Pure, deterministic unit tests for the player helpers extracted from
// PlayerWidget: the subtitles-off default (Fix #8), the gentler time-throttled
// seek ramp (Fix #6) and the reconnect resume anchor (Fix #4). No Player needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:rensi_iptv/widgets/player_widget.dart';

void main() {
  group('Fix #8 — subtitles OFF by default', () {
    final subs = [
      const SubtitleTrack('s1', 'spa', 'Español'),
      const SubtitleTrack('s2', 'eng', 'English'),
    ];

    test('sin preferencia (auto) → apagados', () {
      expect(chooseInitialSubtitle(subs, 'auto').id, SubtitleTrack.no().id);
    });
    test('preferencia vacía / null → apagados', () {
      expect(chooseInitialSubtitle(subs, '').id, SubtitleTrack.no().id);
      expect(chooseInitialSubtitle(subs, 'null').id, SubtitleTrack.no().id);
    });
    test("'off' explícito → apagados", () {
      expect(chooseInitialSubtitle(subs, 'off').id, SubtitleTrack.no().id);
    });
    test('preferencia explícita que existe → esa pista', () {
      expect(chooseInitialSubtitle(subs, 'eng').id, 's2');
    });
    test('preferencia explícita SIN pista → sigue apagado (nunca auto-on)', () {
      expect(chooseInitialSubtitle(subs, 'fra').id, SubtitleTrack.no().id);
    });
  });

  group('Fix #6 — seek ramp gentle + time-throttled', () {
    test('pasos suaves y con tope moderado (10s → 30s → 60s, cap 60s)', () {
      expect(seekStepForLevel(0), const Duration(seconds: 10));
      expect(seekStepForLevel(1), const Duration(seconds: 30));
      expect(seekStepForLevel(2), const Duration(seconds: 60));
      // Nunca a minutos altos: el tope se mantiene aunque suba el nivel.
      expect(seekStepForLevel(3), const Duration(seconds: 60));
      expect(seekStepForLevel(99), const Duration(seconds: 60));
    });

    test('un KeyRepeat rápido NO escala: <750ms desde la última subida = no', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // Solo 100ms después (repetición veloz del mando) → no escala.
      expect(
        shouldEscalateSeek(
            level: 0,
            lastEscalation: t0,
            now: t0.add(const Duration(milliseconds: 100))),
        isFalse,
      );
    });

    test('escala como mucho un nivel cada ~750ms de mantener pulsado', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        shouldEscalateSeek(
            level: 0,
            lastEscalation: t0,
            now: t0.add(const Duration(milliseconds: 800))),
        isTrue,
      );
    });

    test('no escala más allá del nivel máximo (cap)', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        shouldEscalateSeek(
            level: 2,
            lastEscalation: t0,
            now: t0.add(const Duration(seconds: 10)),
            maxLevel: 2),
        isFalse,
      );
    });

    test('primera pulsación (sin última subida) escala', () {
      expect(
        shouldEscalateSeek(
            level: 0, lastEscalation: null, now: DateTime(2026)),
        isTrue,
      );
    });
  });

  group('Fix #4 — reconnect resume anchor', () {
    test('vivo → sin start (null)', () {
      expect(
        computeReopenStart(isLive: true, livePos: Duration.zero),
        isNull,
      );
    });

    test('VOD con posición viva → reanuda ahí', () {
      expect(
        computeReopenStart(
            isLive: false, livePos: const Duration(minutes: 5)),
        const Duration(minutes: 5),
      );
    });

    test('reset de red (livePos=0) → reanuda desde _lastGoodPosition, NO 0', () {
      expect(
        computeReopenStart(
          isLive: false,
          livePos: Duration.zero,
          lastGood: const Duration(minutes: 20),
          pending: null, // ya anulado por un guardado de historial
        ),
        const Duration(minutes: 20),
      );
    });

    test('cambio de episodio: con las anclas reseteadas a null, el reopen NO '
        'reutiliza la posición del episodio anterior', () {
      // El listener de playlist resetea _lastGoodPosition y _pendingWatchDuration
      // a null al cambiar de episodio. Con esas entradas, un reopen del episodio
      // nuevo (que aún no avanzó → livePos 0) arranca en 0, NO en la posición del
      // episodio saliente (que corromperia el historial del nuevo).
      expect(
        computeReopenStart(
          isLive: false,
          livePos: Duration.zero,
          lastGood: null,
          pending: null,
        ),
        Duration.zero,
      );
    });

    test('sin lastGood cae a pending; sin ninguno → cero', () {
      expect(
        computeReopenStart(
            isLive: false,
            livePos: Duration.zero,
            pending: const Duration(minutes: 3)),
        const Duration(minutes: 3),
      );
      expect(
        computeReopenStart(isLive: false, livePos: Duration.zero),
        Duration.zero,
      );
    });
  });
}
