import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:flutter/material.dart';
import 'xtream-codes/new_xtream_code_playlist_screen.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';

class PlaylistTypeScreen extends StatelessWidget {
  const PlaylistTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.loc.create_new_playlist,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The ConstrainedBox+IntrinsicHeight pair exists so the Spacer can
          // push the notice to the bottom of a tall phone screen. On TV there is
          // no Spacer and the content is taller than the 540dp viewport, so the
          // same pair forced the column to at least viewport height and then
          // overflowed it by ~91px — invisible in a profile build, but the
          // notice was clipped and the layout was in an error state.
          final tv = ResponsiveHelper.isDesktopOrTV(context);
          final body = RensiSafeColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        context.loc.select_playlist_type,
                        style: const TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          letterSpacing: -0.7,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.loc.select_playlist_message,
                        style: const TextStyle(fontSize: 16),
                      ),
                      SizedBox(
                          height: ResponsiveHelper.isDesktopOrTV(context)
                              ? 24
                              : 40),
                      _buildPlaylistTypeCard(
                        context,
                        title: 'Xtream Codes',
                        subtitle: context.loc.xtream_code_title,
                        description: context.loc.xtream_code_description,
                        icon: Icons.stream,
                        accent: colorScheme.primary,
                        onAccent: colorScheme.onPrimary,
                        autofocus: ResponsiveHelper.isDesktopOrTV(context),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  NewXtreamCodePlaylistScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildPlaylistTypeCard(
                        context,
                        title: 'M3U Playlist',
                        subtitle: context.loc.m3u_playlist_title,
                        description: context.loc.m3u_playlist_description,
                        icon: Icons.playlist_play,
                        accent: colorScheme.tertiary,
                        onAccent: colorScheme.onTertiary,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NewM3uPlaylistScreen(),
                            ),
                          );
                        },
                      ),
                      SizedBox(
                          height:
                              ResponsiveHelper.isDesktopOrTV(context) ? 24 : 0),
                      if (!ResponsiveHelper.isDesktopOrTV(context))
                        const Spacer(),
                      // Focusable on TV. The notice does not fit above the fold
                      // on a 540dp surface, and being non-interactive it was not
                      // a focus target — so DOWN from the last card had nowhere
                      // to go, Scrollable.ensureVisible never fired, and a
                      // privacy notice was literally unreachable with a remote.
                      // Making it a focus stop is what lets the D-pad scroll to
                      // it; fitting it above the fold would not be enough on
                      // shorter panels anyway.
                      Focus(
                        canRequestFocus:
                            ResponsiveHelper.isDesktopOrTV(context),
                        child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.loc.select_playlist_type_footer,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
          return SingleChildScrollView(
            child: tv
                ? body
                : ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(child: body),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistTypeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color accent,
    required Color onAccent,
    required VoidCallback onTap,
    bool autofocus = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return FocusHighlight(
      borderRadius: BorderRadius.circular(16),
      child: Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(
              ResponsiveHelper.isDesktopOrTV(context) ? 16 : 24),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(icon, size: 30, color: onAccent),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        // Not the accent: a coloured paragraph reads as a link
                        // or an error. The accent's job is state and brand, not
                        // body copy.
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: colorScheme.onSurface.withOpacity(0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
