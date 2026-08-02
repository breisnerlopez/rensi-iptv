import 'package:flutter/services.dart';

/// Bridges the phone's hardware volume Up/Down buttons to the TV's cast volume
/// while casting (Android only).
///
/// The native side ([MainActivity.dispatchKeyEvent]) consumes VOLUME_UP/DOWN
/// key events ONLY while [setCastingActive] was last set to `true`, and forwards
/// each press to Dart as an `onVolumeKey` method call. When not casting, the
/// keys fall through to the system and behave as normal phone volume.
///
/// Every platform call is wrapped so a missing native peer (unit tests, desktop,
/// iOS) degrades to a silent no-op and NEVER throws or hangs into the UI —
/// mirrors [VoiceSearchService]/[PipService].
class HardwareVolumeService {
  HardwareVolumeService._() {
    _channel.setMethodCallHandler(_handle);
  }

  /// Shared singleton used by [CastSenderController].
  static final HardwareVolumeService instance = HardwareVolumeService._();

  static const MethodChannel _channel =
      MethodChannel('info.breisner.rensi.iptv/hwvolume');

  /// Step applied per hardware press: up = +[_step], down = -[_step].
  static const int _step = 5;

  /// Invoked on each hardware volume press while casting, with the signed delta
  /// (+[_step] for Up, -[_step] for Down). The controller wires this to
  /// [CastSenderController.nudgeVolume]. Null → the press is dropped.
  void Function(int delta)? onStep;

  /// Tells the native layer whether it should intercept the hardware volume
  /// keys (true while casting) or let them behave normally (false). Best-effort:
  /// a missing handler / older platform is swallowed.
  Future<void> setCastingActive(bool active) async {
    try {
      await _channel.invokeMethod('setCastingActive', active);
    } catch (_) {
      // No native peer (tests/desktop) or channel error → silent no-op.
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onVolumeKey') {
      final args = call.arguments;
      final dir = (args is Map) ? args['dir'] as String? : null;
      if (dir == 'up') {
        onStep?.call(_step);
      } else if (dir == 'down') {
        onStep?.call(-_step);
      }
    }
    return null;
  }
}
