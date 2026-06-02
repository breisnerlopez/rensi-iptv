import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/screens/file_browser_screen.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// A file the user picked through [pickFileBytes], normalised to a small
/// bytes-plus-name record so every caller can hand the result straight to
/// the import pipeline regardless of which channel produced it.
class PickedFileBytes {
  const PickedFileBytes({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

/// Picks a file and returns its bytes + display name, transparently
/// choosing the channel that actually works on the device.
///
/// - On TV / desktop / large landscape tablets (width >= 900 dp): pushes
///   the in-app [FileBrowserScreen] which walks the filesystem directly
///   via dart:io. This is the only path that works on Android-TV
///   firmwares (Mi Box, Realtek boxes) whose stripped DocumentsUI
///   rejects the system file picker.
/// - Everywhere else: hands off to file_picker, configured with
///   FileType.any + withData:true so the read happens inside the SAF
///   callback (no READ_EXTERNAL_STORAGE needed).
///
/// Returns null when the user cancels at either layer.
Future<PickedFileBytes?> pickFileBytes({
  required BuildContext context,
  required String title,
  required List<String> extensions,
}) async {
  if (ResponsiveHelper.isDesktopOrTV(context)) {
    final picked = await Navigator.of(context).push<File?>(
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(
          title: title,
          extensions: extensions,
        ),
      ),
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final segments = picked.path.split(Platform.pathSeparator);
    final name = segments.isEmpty ? picked.path : segments.last;
    return PickedFileBytes(bytes: bytes, name: name);
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) return null;
  return PickedFileBytes(bytes: bytes, name: file.name);
}
