import 'dart:async';

import 'package:flutter/foundation.dart';

/// Buffers digits typed on a TV remote so the user can jump to a channel by
/// number ("4", "2", "Enter" → channel 42).
///
/// Auto-commits after [idleTimeout] of no input or once [maxDigits] is
/// reached. The buffer is exposed as a [ValueNotifier] so an overlay can
/// render it; [onCommit] fires once with the parsed integer per commit.
class ChannelNumberBuffer {
  ChannelNumberBuffer({
    this.idleTimeout = const Duration(milliseconds: 1500),
    this.maxDigits = 4,
  });

  final Duration idleTimeout;
  final int maxDigits;

  /// Currently-typed digits as a string (e.g. "4", "42", ""). Empty when
  /// the buffer is idle.
  final ValueNotifier<String> buffer = ValueNotifier<String>('');

  final StreamController<int> _commitController =
      StreamController<int>.broadcast();
  Stream<int> get onCommit => _commitController.stream;

  Timer? _idleTimer;

  /// Append a digit (0-9). No-op for invalid input. Resets the idle timer.
  /// Auto-commits when [maxDigits] is reached.
  void appendDigit(int digit) {
    if (digit < 0 || digit > 9) return;
    if (buffer.value.length >= maxDigits) return;
    buffer.value = '${buffer.value}$digit';
    if (buffer.value.length >= maxDigits) {
      commit();
      return;
    }
    _resetIdleTimer();
  }

  /// Remove the last digit. Cancels the idle timer when the buffer empties.
  void backspace() {
    if (buffer.value.isEmpty) return;
    buffer.value = buffer.value.substring(0, buffer.value.length - 1);
    if (buffer.value.isEmpty) {
      _idleTimer?.cancel();
      _idleTimer = null;
    } else {
      _resetIdleTimer();
    }
  }

  /// Commit the current buffer immediately. Emits [onCommit] with the parsed
  /// integer and resets internal state. No-op when the buffer is empty.
  void commit() {
    if (buffer.value.isEmpty) return;
    final parsed = int.tryParse(buffer.value);
    _idleTimer?.cancel();
    _idleTimer = null;
    buffer.value = '';
    if (parsed != null) {
      _commitController.add(parsed);
    }
  }

  /// Clear without committing. Cancels the idle timer.
  void clear() {
    _idleTimer?.cancel();
    _idleTimer = null;
    buffer.value = '';
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, commit);
  }

  /// Whether the buffer has at least one digit.
  bool get isActive => buffer.value.isNotEmpty;

  /// Dispose the stream controller and any pending timer. Safe to call
  /// multiple times.
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_commitController.isClosed) {
      _commitController.close();
    }
  }
}
