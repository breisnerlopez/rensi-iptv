import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges system Picture-in-Picture (Android only).
///
/// Auto-PiP fires when the user leaves the app while playing video, provided
/// [setAutoEnter] was last called with `true` from Dart.
class PipService {
  PipService._();
  static final PipService instance = PipService._();

  static const _method =
      MethodChannel('info.breisner.rensi.iptv/pip');
  static const _events =
      EventChannel('info.breisner.rensi.iptv/pip_events');

  bool? _isAvailable;
  bool _autoEnabled = false;
  bool _eventsBound = false;

  /// Whether the current OS / hardware supports system PiP.
  ///
  /// Cached after the first call. Returns false on non-Android platforms.
  final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  Future<bool> isAvailable() async {
    if (!defaultTargetPlatform.isAndroid) return false;
    if (_isAvailable != null) return _isAvailable!;
    try {
      _isAvailable = await _method.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      _isAvailable = false;
    } on MissingPluginException {
      _isAvailable = false;
    }
    if (_isAvailable!) _bindEvents();
    return _isAvailable!;
  }

  /// Tell the native layer whether to auto-enter PiP when the user presses
  /// home or swipes the app away while a video is playing.
  Future<void> setAutoEnter(bool enabled) async {
    if (!await isAvailable()) return;
    if (_autoEnabled == enabled) return;
    _autoEnabled = enabled;
    try {
      await _method.invokeMethod('setAutoEnter', enabled);
    } on PlatformException {
      // Best-effort; the next call will retry.
    }
  }

  /// Push the current video aspect ratio to the native side so auto-PiP
  /// uses the correct shape.
  Future<void> updateAspectRatio({required int width, required int height}) async {
    if (!await isAvailable()) return;
    try {
      await _method.invokeMethod('updateAspectRatio', {
        'width': width,
        'height': height,
      });
    } on PlatformException {
      // Ignore.
    }
  }

  /// Explicitly enter PiP now (button-triggered).
  Future<bool> enterPip({int width = 16, int height = 9}) async {
    if (!await isAvailable()) return false;
    try {
      final ok = await _method.invokeMethod<bool>('enterPip', {
        'width': width,
        'height': height,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  void _bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;
    _events.receiveBroadcastStream().listen(
      (event) {
        if (event is bool) isInPip.value = event;
      },
      onError: (_) {
        // EventChannel errors mean we lost the stream; nothing actionable.
      },
    );
  }
}

extension on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;
}
