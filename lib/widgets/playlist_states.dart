import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:flutter/material.dart';

class PlaylistLoadingState extends StatelessWidget {
  const PlaylistLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(context.loc.loading_playlists),
        ],
      ),
    );
  }
}

class PlaylistErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const PlaylistErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              context.loc.error_occurred,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.loc.try_again),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistEmptyState extends StatelessWidget {
  final VoidCallback onCreatePlaylist;
  final VoidCallback? onImportBackup;

  const PlaylistEmptyState({
    super.key,
    required this.onCreatePlaylist,
    this.onImportBackup,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.movie_filter_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.loc.empty_playlist_title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Bricolage Grotesque',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.loc.empty_playlist_message,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // The two CTAs match in size and stack vertically so a user
            // arriving fresh on the empty state sees both paths to
            // populate the library — create from scratch *or* restore
            // a backup — without one of them looking decorative.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: onCreatePlaylist,
                    icon: const Icon(Icons.add),
                    label: Text(context.loc.empty_playlist_button),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  if (onImportBackup != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: onImportBackup,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(context.loc.import_playlists_and_settings),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
