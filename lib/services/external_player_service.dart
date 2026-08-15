import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';

/// Launch a stream in an external video player (VLC, MX Player, …) via an
/// Android ACTION_VIEW intent with a `video/*` MIME. Needed because url_launcher
/// can only fire a bare VIEW without a type/package, which those players ignore.
/// Android-only.
class ExternalPlayerService {
  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Opens [url] in the system chooser of video-capable apps. Throws if not on
  /// Android or if no handler resolves the intent.
  static Future<void> open(String url, {String? title}) async {
    if (!isSupported) {
      throw UnsupportedError('External player is Android-only');
    }
    final intent = AndroidIntent(
      action: 'action_view',
      data: Uri.encodeFull(url),
      type: 'video/*',
      // 'title' is the extra VLC/MX read for the on-screen title.
      arguments: <String, dynamic>{if (title != null && title.isNotEmpty) 'title': title},
    );
    await intent.launch();
  }
}
