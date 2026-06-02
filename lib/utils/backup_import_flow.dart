import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/screens/file_browser_screen.dart';
import 'package:rensi_iptv/services/backup_service.dart';

/// Runs the full backup-import UX: file picker → passphrase prompt (if the
/// file is encrypted) → merge strategy dialog → call into [BackupService].
///
/// Returns the [BackupImportResult] when the import ran. Returns `null` when
/// the user cancelled at any step. SnackBar feedback is emitted by this
/// helper, so the caller only has to refresh its own state.
Future<BackupImportResult?> runBackupImportFlow(BuildContext context) async {
  final loc = context.loc;
  final messenger = ScaffoldMessenger.of(context);

  Uint8List? bytes;
  try {
    bytes = await BackupService.pickBackupFile();
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(loc.import_failed)));
    return null;
  }
  if (bytes == null) {
    messenger.showSnackBar(SnackBar(content: Text(loc.import_cancelled)));
    return null;
  }

  if (!context.mounted) return null;
  return _continueBackupImport(context, bytes);
}

/// SAF-less import path #1: walk the device filesystem with the in-app
/// FileBrowserScreen, read the bytes off disk, and hand off to the
/// shared continuation. Works on Android-TV firmwares whose system
/// DocumentsUI is missing — as long as we have READ_EXTERNAL_STORAGE
/// the legacy /sdcard tree is browsable.
Future<BackupImportResult?> runBackupImportFromDeviceFlow(
  BuildContext context,
) async {
  final loc = context.loc;
  final messenger = ScaffoldMessenger.of(context);

  final picked = await Navigator.of(context).push<File?>(
    MaterialPageRoute(
      builder: (_) => FileBrowserScreen(
        title: loc.import_from_device,
        extensions: const ['json', 'aipbak'],
      ),
    ),
  );
  if (!context.mounted) return null;
  if (picked == null) {
    messenger.showSnackBar(SnackBar(content: Text(loc.import_cancelled)));
    return null;
  }

  Uint8List bytes;
  try {
    bytes = await picked.readAsBytes();
  } catch (_) {
    if (!context.mounted) return null;
    messenger.showSnackBar(SnackBar(content: Text(loc.import_failed)));
    return null;
  }

  if (!context.mounted) return null;
  return _continueBackupImport(context, bytes);
}

/// SAF-less import path #2: ask for an HTTP URL, download the backup,
/// and hand off to the shared continuation. Useful when the backup
/// lives on a phone/server but you don't have a way to push it onto
/// the TV's local storage.
Future<BackupImportResult?> runBackupImportFromUrlFlow(
  BuildContext context,
) async {
  final loc = context.loc;
  final messenger = ScaffoldMessenger.of(context);

  final url = await _askForUrl(context);
  if (url == null || url.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(loc.import_cancelled)));
    return null;
  }

  Uint8List bytes;
  try {
    bytes = await BackupService.fetchBackupFromUrl(url);
  } on BackupFormatException catch (e) {
    if (!context.mounted) return null;
    final message = switch (e.code) {
      'backup_url_invalid' => loc.import_url_invalid,
      'backup_url_too_large' => loc.import_url_failed,
      'backup_url_http_error' => loc.import_url_failed,
      _ => loc.import_url_failed,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    messenger.showSnackBar(SnackBar(content: Text(loc.import_url_failed)));
    return null;
  }

  if (!context.mounted) return null;
  return _continueBackupImport(context, bytes);
}

/// Shared tail end of both import flows: passphrase prompt (when the
/// payload is encrypted) → merge strategy dialog → call into
/// [BackupService.importBytes] → SnackBar summary / error.
Future<BackupImportResult?> _continueBackupImport(
  BuildContext context,
  Uint8List bytes,
) async {
  final loc = context.loc;
  final messenger = ScaffoldMessenger.of(context);

  String? passphrase;
  if (BackupService.looksEncrypted(bytes)) {
    if (!context.mounted) return null;
    passphrase = await _askPassphrase(context);
    if (passphrase == null) {
      messenger.showSnackBar(SnackBar(content: Text(loc.import_cancelled)));
      return null;
    }
  }

  if (!context.mounted) return null;
  final strategy = await _askMergeStrategy(context);
  if (strategy == null) return null;

  try {
    final result = await BackupService.importBytes(
      bytes,
      passphrase: passphrase,
      strategy: strategy,
    );
    if (!context.mounted) return result;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          loc.import_summary(result.created, result.updated, result.skipped),
        ),
      ),
    );
    return result;
  } on BackupFormatException catch (e) {
    if (!context.mounted) return null;
    final message = switch (e.code) {
      'backup_passphrase_invalid' => loc.backup_passphrase_invalid,
      'backup_passphrase_required' => loc.backup_passphrase_required,
      'backup_invalid_format' => loc.backup_invalid_format,
      'backup_schema_unsupported' =>
        loc.backup_schema_unsupported(e.detail ?? '?'),
      _ => loc.import_failed,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    messenger.showSnackBar(SnackBar(content: Text(loc.import_failed)));
    return null;
  }
}

Future<String?> _askForUrl(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          Navigator.pop(dialogContext, controller.text.trim());
        }

        return AlertDialog(
          title: Text(dialogContext.loc.import_from_url),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: dialogContext.loc.import_url_hint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: Text(dialogContext.loc.cancel),
            ),
            FilledButton(
              onPressed: submit,
              child: Text(dialogContext.loc.tmdb_search_button),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<String?> _askPassphrase(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.loc.backup_passphrase_required),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dialogContext.loc.backup_passphrase_subtitle),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    Navigator.pop(dialogContext, controller.text),
                decoration: InputDecoration(
                  labelText: dialogContext.loc.backup_passphrase_field,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: Text(dialogContext.loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: Text(dialogContext.loc.tmdb_search_button),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<BackupMergeStrategy?> _askMergeStrategy(BuildContext context) {
  return showDialog<BackupMergeStrategy?>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(dialogContext.loc.backup_strategy_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: Text(dialogContext.loc.backup_strategy_overwrite),
              onTap: () =>
                  Navigator.pop(dialogContext, BackupMergeStrategy.overwrite),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(dialogContext.loc.backup_strategy_keep_local),
              onTap: () =>
                  Navigator.pop(dialogContext, BackupMergeStrategy.keepLocal),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: Text(dialogContext.loc.cancel),
          ),
        ],
      );
    },
  );
}
