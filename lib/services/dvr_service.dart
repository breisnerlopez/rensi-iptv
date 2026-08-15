import 'dart:io';

import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:path_provider/path_provider.dart';

/// EXPERIMENTAL DVR — "record while watching".
///
/// Dumps the *currently playing* live stream to a local file via libmpv's
/// `stream-record` property (set through media_kit's [NativePlayer]). This is
/// NOT scheduled DVR (recording a channel at a future time without watching) —
/// that would need a second background connection and is out of scope.
///
/// Behind the [UserPreferences.getDvrExperimental] flag because its reliability
/// depends on the provider stream and the pinned libmpv build: `stream-record`
/// is a real but lightly-documented mpv property, and some HLS/`.ts` inputs
/// remux cleanly while others may not. Callers must treat start/stop as
/// best-effort and surface the resulting file only after a successful stop.
class DvrService {
  DvrService._();
  static final DvrService instance = DvrService._();

  /// Folder (under application support) where recordings are written.
  static const String recordingsSubdir = 'recordings';

  String? _activePath;

  /// Path of the recording in progress, or null when idle.
  String? get activePath => _activePath;
  bool get isRecording => _activePath != null;

  /// Begin dumping the live stream currently open on [player] to a new file.
  /// Returns the file path on success, or null if recording could not start
  /// (not a native player, already recording, or the property was rejected).
  Future<String?> start(Player player, {required String channelName}) async {
    if (_activePath != null) return null;
    final platform = player.platform;
    if (platform is! NativePlayer) return null;

    final dir = await getApplicationSupportDirectory();
    final recDir = Directory('${dir.path}/$recordingsSubdir');
    if (!recDir.existsSync()) recDir.createSync(recursive: true);
    final safeName = _sanitize(channelName);
    // Caller-independent timestamp keeps concurrent recordings from colliding.
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${recDir.path}/$safeName-$ts.ts';

    try {
      // Setting stream-record to a path starts the muxed dump of what plays.
      await platform.setProperty('stream-record', path);
      _activePath = path;
      return path;
    } catch (_) {
      _activePath = null;
      return null;
    }
  }

  /// Stop the active recording. Returns the finished file's path when it exists
  /// and holds data, else null (and cleans up an empty stub). Clearing
  /// `stream-record` (empty string) tells libmpv to finalize the file.
  Future<String?> stop(Player player) async {
    final path = _activePath;
    _activePath = null;
    if (path == null) return null;
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('stream-record', '');
      } catch (_) {
        // Even if the property clear fails, fall through to inspect the file.
      }
    }
    final f = File(path);
    if (f.existsSync() && f.lengthSync() > 0) return path;
    // Nothing was captured — remove the empty stub so it doesn't litter.
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return null;
  }

  static String _sanitize(String name) {
    final cleaned =
        name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    final collapsed = cleaned.replaceAll(RegExp(r'\s+'), '_');
    final capped = collapsed.isEmpty ? 'recording' : collapsed;
    return capped.length > 40 ? capped.substring(0, 40) : capped;
  }
}
