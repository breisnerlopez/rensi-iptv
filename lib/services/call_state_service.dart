import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bridges the phone's telephony call state to Dart so the app can pause the
/// TV cast on an incoming call and resume it when the call ends (Android only).
///
/// The native side ([MainActivity]) registers a telephony listener ONLY while
/// something is listening on the [_channel] EventChannel, and unregisters it on
/// cancel — so the READ_PHONE_STATE permission is only exercised while the
/// feature is actually active (casting + toggle on).
///
/// Every platform call is wrapped so a missing native peer (unit tests, desktop,
/// iOS) or a denied permission degrades to a silent no-op and NEVER throws or
/// hangs — mirrors [HardwareVolumeService]/[VoiceSearchService].
class CallStateService {
  const CallStateService();

  static const EventChannel _channel =
      EventChannel('info.breisner.rensi.iptv/callstate');

  /// Emits `'ringing'` | `'offhook'` | `'idle'` on each call-state change.
  /// Subscribing registers the native listener (see the class doc); cancelling
  /// the subscription unregisters it. Errors from a missing native peer are
  /// swallowed so the stream simply yields nothing off-device.
  Stream<String> callStates() {
    try {
      return _channel
          .receiveBroadcastStream()
          .map((e) => e is String ? e : '$e')
          // No native peer (tests/desktop) surfaces a MissingPluginException on
          // the stream — swallow it so a subscriber never sees an error event.
          .handleError((_) {});
    } catch (_) {
      return const Stream<String>.empty();
    }
  }

  /// Requests the READ_PHONE_STATE permission (permission_handler's
  /// [Permission.phone]). Returns whether it is granted. Silent `false` when
  /// there is no native peer (unit tests / desktop) or the request throws.
  Future<bool> ensurePermission() async {
    try {
      final status = await Permission.phone.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
