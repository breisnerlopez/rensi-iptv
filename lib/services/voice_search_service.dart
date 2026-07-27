import 'package:flutter/services.dart';

/// Bridges to the Android system voice-recognition overlay
/// (`RecognizerIntent.ACTION_RECOGNIZE_SPEECH`) over a native [MethodChannel].
///
/// The system overlay owns the microphone and draws its own listening UI, so
/// this needs NO `RECORD_AUDIO` permission and works on Android TV (remote mic)
/// as well as phone. Every call is wrapped so a device without a recognizer
/// degrades to `false`/`null` and NEVER throws into the UI — the mic affordance
/// simply hides when [isAvailable] is false.
class VoiceSearchService {
  const VoiceSearchService();

  static const MethodChannel _channel =
      MethodChannel('info.breisner.rensi.iptv/voice');

  /// True when a speech recognizer that can satisfy the recognize intent is
  /// installed (`resolveActivity != null`). Many TV boxes ship without one, so
  /// callers gate the mic button on this and hide it entirely when false.
  Future<bool> isAvailable() async {
    try {
      final res = await _channel.invokeMethod<bool>('isVoiceAvailable');
      return res ?? false;
    } catch (_) {
      // No handler / older platform / channel error → treat as unavailable.
      return false;
    }
  }

  /// Launches the system voice overlay and resolves to the recognized text, or
  /// `null` when the user cancelled, nothing was heard, or the platform failed.
  ///
  /// [localeTag] hints the recognizer's language (e.g. `es-ES`); [prompt] is the
  /// caption the overlay shows. Both are optional — the recognizer falls back to
  /// the device default. Never throws; a failure surfaces as `null`.
  Future<String?> listen({String? localeTag, String? prompt}) async {
    try {
      final res = await _channel.invokeMethod<String>('startVoiceSearch', {
        'locale': localeTag,
        'prompt': prompt,
      }).timeout(
        // Safety net: if the OS destroys the Activity while the overlay is up,
        // the native Result can be orphaned and never complete. This bounds the
        // await so the mic affordance can never hang; the system overlay itself
        // finishes in seconds, so a legitimate dictation never reaches this.
        const Duration(seconds: 120),
        onTimeout: () => null,
      );
      final text = res?.trim();
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }
}

/// Shared, stateless instance used by the search screen.
const voiceSearchService = VoiceSearchService();
