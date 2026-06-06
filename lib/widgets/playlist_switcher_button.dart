import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/active_playlist_controller.dart';
import '../models/playlist_model.dart';
import '../screens/m3u/m3u_home_screen.dart';
import '../screens/xtream-codes/xtream_code_home_screen.dart';

class PlaylistSwitcherButton extends StatelessWidget {
  final Playlist currentPlaylist;
  final int currentIndex;

  const PlaylistSwitcherButton({
    super.key,
    required this.currentPlaylist,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showPlaylistSheet(context),
      icon: const Icon(Icons.playlist_play),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(currentPlaylist.name, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _showPlaylistSheet(BuildContext context) async {
    final controller = context.read<ActivePlaylistController>();
    final playlists = await controller.loadPlaylists(forceRefresh: true);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final selected = playlist.id == currentPlaylist.id;
              return ListTile(
                leading: Icon(
                  playlist.type == PlaylistType.xtream
                      ? Icons.cloud_queue
                      : Icons.list_alt,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  playlist.type == PlaylistType.xtream ? 'Xtream Codes' : 'M3U',
                ),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: selected
                    ? () => Navigator.pop(sheetContext)
                    : () => _switchPlaylist(sheetContext, controller, playlist),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _switchPlaylist(
    BuildContext context,
    ActivePlaylistController controller,
    Playlist playlist,
  ) async {
    await controller.selectPlaylist(playlist);
    if (!context.mounted) return;

    final screen = switch (playlist.type) {
      PlaylistType.xtream => XtreamCodeHomeScreen(
        playlist: playlist,
        initialIndex: currentIndex.clamp(0, 4).toInt(),
      ),
      PlaylistType.m3u => M3UHomeScreen(
        playlist: playlist,
        initialIndex: currentIndex.clamp(0, 4).toInt(),
      ),
    };

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }
}
