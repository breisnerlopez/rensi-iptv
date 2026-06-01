import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
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
