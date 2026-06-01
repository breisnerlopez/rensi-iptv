import 'dart:io';

import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:media_kit/media_kit.dart';

GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One-shot migration: the SQLite file used to live under the old
  // upstream name. Move it to the rebranded filename before drift opens
  // it so existing installs keep their playlists/history.
  await _migrateLegacyDatabaseFile();

  getIt.registerSingleton<MyAudioHandler>(await initAudioService());
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  MediaKit.ensureInitialized();
}

/// Renames the legacy Drift SQLite file from
/// `another-iptv-player.sqlite` to `rensi-iptv.sqlite` (and the related
/// `-wal` / `-shm` companions) so the rebranded build can open the same
/// library a previous version wrote.
///
/// Web/desktop-only platforms that don't use a filesystem-backed Drift
/// are short-circuited via [defaultTargetPlatform] / OS checks before
/// touching path_provider.
Future<void> _migrateLegacyDatabaseFile() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid &&
      !Platform.isIOS &&
      !Platform.isLinux &&
      !Platform.isMacOS &&
      !Platform.isWindows) {
    return;
  }
  try {
    final supportDir = await getApplicationSupportDirectory();
    const oldBase = 'another-iptv-player';
    const newBase = 'rensi-iptv';
    for (final suffix in const ['.sqlite', '.sqlite-wal', '.sqlite-shm']) {
      final oldFile = File('${supportDir.path}/$oldBase$suffix');
      final newFile = File('${supportDir.path}/$newBase$suffix');
      if (!await oldFile.exists()) continue;
      if (await newFile.exists()) continue;
      await oldFile.rename(newFile.path);
    }
  } catch (_) {
    // Migration is best-effort: if any IO step fails the worst case is
    // a fresh DB on the new name, which the user can repopulate from a
    // backup. Never block app startup over it.
  }
}

void setupLocator(BuildContext context) {
  getIt.registerSingleton<AppLocalizations>(AppLocalizations.of(context)!);
}
