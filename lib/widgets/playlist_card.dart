import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:flutter/material.dart';
import '../../../../models/playlist_model.dart';
import '../../utils/playlist_utils.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool autofocus;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onDelete,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: r.surface2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: r.hairline),
          ),
          child: InkWell(
            onTap: onTap,
            autofocus: autofocus,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _PlaylistIcon(type: playlist.type),
                  const SizedBox(width: 16),
                  Expanded(child: _PlaylistInfo(playlist: playlist)),
                  _PlaylistMenu(onDelete: onDelete),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistIcon extends StatelessWidget {
  final PlaylistType type;

  const _PlaylistIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: PlaylistUtils.getPlaylistColor(type),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Icon(
        PlaylistUtils.getPlaylistIcon(type),
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _PlaylistInfo extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistInfo({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          playlist.name,
          style: const TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: AppThemes.bodySize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _TypeChip(type: playlist.type),
            const SizedBox(width: 8),
            Icon(Icons.access_time, size: 12, color: r.text3),
            const SizedBox(width: 4),
            Text(
              PlaylistUtils.formatDate(playlist.createdAt),
              style: TextStyle(fontSize: AppThemes.tenFoot(context, 12), color: r.text3),
            ),
          ],
        ),
        if (playlist.url != null) ...[
          const SizedBox(height: 4),
          Text(
            // M3U playlists carry user+password in this URL — never render it raw.
            scrubUrlForDisplay(playlist.url),
            style: TextStyle(fontSize: AppThemes.tenFoot(context, 12), color: r.text3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final PlaylistType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: r.accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toString().split('.').last.toUpperCase(),
        style: TextStyle(
          fontSize: AppThemes.tenFoot(context, 12),
          fontWeight: FontWeight.bold,
          color: r.accent,
        ),
      ),
    );
  }
}

class _PlaylistMenu extends StatelessWidget {
  final VoidCallback onDelete;

  const _PlaylistMenu({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    // Its own ring so the D-pad shows when the ⋮ menu is focused, distinct from
    // the card's ring.
    return FocusHighlight(
      borderRadius: BorderRadius.circular(24),
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: r.text2),
        color: r.surface3,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: r.hairline),
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(context.loc.delete, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'delete') {
            onDelete();
          }
        },
      ),
    );
  }
}
