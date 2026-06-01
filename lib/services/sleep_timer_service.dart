import 'dart:async';

import 'package:flutter/foundation.dart';

/// In-memory sleep timer.
///
/// Keeps a countdown that ticks every second and emits a one-shot callback
/// when it reaches zero. Designed so the UI can listen to [remaining] for
/// the chip in the player chrome, and so the player widget can subscribe
/// to [onFire] (a broadcast stream) to call `player.pause()` at zero.
///
/// The service is process-scoped: closing the player widget should call
/// [cancel] so the timer doesn't fire while a different screen is active.
class SleepTimerService {
  SleepTimerService._();
  static final SleepTimerService instance = SleepTimerService._();

  /// The remaining time, or `null` when the timer is idle.
  ///
  /// Emits a new value on every tick (one second granularity) while active,
  /// and emits `null` when [cancel] is called or after the timer fires.
  final ValueNotifier<Duration?> remaining = ValueNotifier<Duration?>(null);

  final StreamController<void> _fireController =
      StreamController<void>.broadcast();

  /// Fires exactly once when the active timer hits zero.
  ///
  /// Subscribers can use this to pause playback, dim the screen, etc.
  /// Subsequent timers will emit again, one event per fire.
  Stream<void> get onFire => _fireController.stream;

  Timer? _ticker;

  /// Whether a timer is currently counting down.
  bool get isActive => _ticker != null;

  /// Start (or restart) the countdown with [duration].
  ///
  /// If [duration] is zero or negative the timer fires immediately on the
  /// next event-loop turn. Any previously-running timer is cancelled first.
  void start(Duration duration) {
    cancel();
    if (duration <= Duration.zero) {
      // Schedule the fire asynchronously so listeners can attach before it
      // happens, matching the behaviour of a 1s timer hitting zero.
      remaining.value = Duration.zero;
      _ticker = Timer(Duration.zero, _fire);
      return;
    }
    remaining.value = duration;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = remaining.value;
      if (current == null) {
        // Defensive: somebody nulled the notifier underneath us.
        cancel();
        return;
      }
      final next = current - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        remaining.value = Duration.zero;
        _fire();
      } else {
        remaining.value = next;
      }
    });
  }

  /// Cancel an active timer. No-op when already idle.
  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    remaining.value = null;
  }

  void _fire() {
    _ticker?.cancel();
    _ticker = null;
    remaining.value = null;
    _fireController.add(null);
  }
}
