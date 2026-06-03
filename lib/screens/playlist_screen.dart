import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/playlist_controller.dart';
import '../../models/playlist_model.dart';
import '../../services/backup_service.dart';
import '../../utils/backup_import_flow.dart';
import '../../widgets/confirm_exit_scope.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/playlist_states.dart';
import 'playlist_type_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  PlaylistScreenState createState() => PlaylistScreenState();
}

class PlaylistScreenState extends State<PlaylistScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlaylistController(),
      child: _PlaylistScreenBody(),
    );
  }
}

class _PlaylistScreenBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlaylistsIfNeeded(context);
    });

    return ConfirmExitScope(
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: Consumer<PlaylistController>(
          builder: (context, controller, child) =>
              _buildBodyFromState(context, controller),
        ),
        floatingActionButton: _buildFloatingActionButton(context),
      ),
    );
  }

  void _initializePlaylistsIfNeeded(BuildContext context) {
    final controller = context.read<PlaylistController>();
    if (!controller.isLoading &&
        controller.playlists.isEmpty &&
        controller.error == null) {
      controller.loadPlaylists(context);
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        context.loc.my_playlists,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBodyFromState(
    BuildContext context,
    PlaylistController controller,
  ) {
    if (controller.isLoading) {
      return const PlaylistLoadingState();
    }

    if (controller.error != null) {
      return PlaylistErrorState(
        error: controller.error!,
        onRetry: () => controller.loadPlaylists(context),
      );
    }

    if (controller.playlists.isEmpty) {
      return PlaylistEmptyState(
        onCreatePlaylist: () => _navigateToCreatePlaylist(context),
        onImportBackup: () => _importBackup(context, controller),
      );
    }

    return _buildPlaylistList(context, controller);
  }

  Widget _buildPlaylistList(
    BuildContext context,
    PlaylistController controller,
  ) {
    return RefreshIndicator(
      onRefresh: () => controller.loadPlaylists(context),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.playlists.length,
        itemBuilder: (context, index) {
          return PlaylistCard(
            playlist: controller.playlists[index],
            onTap: () =>
                controller.openPlaylist(context, controller.playlists[index]),
            onDelete: () => _showDeleteDialog(
              context,
              controller,
              controller.playlists[index],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _navigateToCreatePlaylist(context),
      tooltip: context.loc.create_new_playlist,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  void _navigateToCreatePlaylist(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PlaylistTypeScreen()),
    );
  }

  Future<void> _importBackup(
    BuildContext context,
    PlaylistController controller,
  ) async {
    // Onboarding-style sheet: the user just installed the app and we
    // can't assume they want a local file vs a hosted URL. Both are
    // first-class entry points; settings keeps the two as separate
    // tiles since users there usually know what they want.
    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.folder_open),
                title: Text(sheetContext.loc.import_playlists_and_settings),
                subtitle: Text(sheetContext.loc.import_subtitle),
                onTap: () =>
                    Navigator.pop(sheetContext, _ImportSource.file),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(sheetContext.loc.import_from_url),
                subtitle: Text(sheetContext.loc.import_url_subtitle),
                onTap: () => Navigator.pop(sheetContext, _ImportSource.url),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !context.mounted) return;

    final BackupImportResult? result;
    if (source == _ImportSource.file) {
      result = await runBackupImportFlow(context);
    } else {
      // ignore: use_build_context_synchronously
      result = await runBackupImportFromUrlFlow(context);
    }
    if (result != null && result.total > 0 && context.mounted) {
      await controller.loadPlaylists(context);
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    PlaylistController controller,
    Playlist playlist,
  ) {
    showDialog(
      context: context,
      builder: (context) => _DeletePlaylistDialog(
        playlist: playlist,
        onDelete: () async {
          final success = await controller.deletePlaylist(playlist.id);
          if (success && context.mounted) {
            _showSuccessSnackBar(context, playlist.name);
          }
        },
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String playlistName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.loc.playlist_deleted(playlistName)),
        backgroundColor: Colors.green,
      ),
    );
  }
}

enum _ImportSource { file, url }

class _DeletePlaylistDialog extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onDelete;

  const _DeletePlaylistDialog({required this.playlist, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.playlist_delete_confirmation_title),
      content: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              text: context.loc.playlist_delete_confirmation_message(
                playlist.name,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.loc.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onDelete();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(context.loc.delete),
        ),
      ],
    );
  }
}
