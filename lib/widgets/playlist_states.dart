import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

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
    final r = rensi(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: r.accent),
            const SizedBox(height: 16),
            Text(
              context.loc.error_occurred,
              style: TextStyle(
                fontFamily: 'Bricolage Grotesque',
                fontSize: AppThemes.tenFoot(context, 20),
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: r.text3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FocusHighlight(
              borderRadius: BorderRadius.circular(20),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.loc.try_again),
                style: FilledButton.styleFrom(
                  backgroundColor: r.accent,
                  foregroundColor: r.onAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(fontSize: AppThemes.bodySmallSize),
                ),
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
              style: TextStyle(
                fontFamily: 'Bricolage Grotesque',
                fontSize: AppThemes.tenFoot(context, 26),
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.loc.empty_playlist_message,
              style: TextStyle(
                fontSize: AppThemes.tenFoot(context, 15),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Say what the user needs BEFORE sending them into a form where an
            // 80-character URL has to be typed with a remote. Google TV always
            // states the cost of the next step up front; arriving at the form
            // and only then discovering the requirement is where people quit.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.loc.onboarding_requirements_hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppThemes.bodySmallSize,
                        height: 1.4,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
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
                  // Autofocus on TV so the remote has an immediate target, and
                  // a loud FocusHighlight ring visible at a 3 m distance.
                  FocusHighlight(
                    borderRadius: BorderRadius.circular(20),
                    child: FilledButton.icon(
                      autofocus: ResponsiveHelper.isDesktopOrTV(context),
                      onPressed: onCreatePlaylist,
                      icon: const Icon(Icons.add),
                      label: Text(context.loc.empty_playlist_button),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: AppThemes.bodySmallSize),
                      ),
                    ),
                  ),
                  if (onImportBackup != null) ...[
                    const SizedBox(height: 12),
                    FocusHighlight(
                      borderRadius: BorderRadius.circular(20),
                      // Explicit tonal colours: the app-wide filledButtonTheme
                      // also reaches FilledButton.tonal*, which would paint this
                      // secondary action identically to the primary button right
                      // above it.
                      child: FilledButton.tonalIcon(
                        onPressed: onImportBackup,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(context.loc.import_playlists_and_settings),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondaryContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onSecondaryContainer,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontSize: AppThemes.bodySmallSize),
                        ),
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
