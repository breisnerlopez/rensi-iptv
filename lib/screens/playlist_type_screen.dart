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
          // Side by side wherever there is room, not only on TV: on a 800dp tablet
    // two stacked cards ran 1160dp wide for two words each.
    final tv = ResponsiveHelper.useNavigationRail(context);
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
                      _buildTypeChoices(context, colorScheme),
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

  /// Two comparable choices. On TV they sit side by side: this is a binary
  /// decision, and stacking two 860dp-wide rows — each with ~450dp of dead space
  /// and a touch-only chevron — made the user read three lines to make it. The
  /// long description now appears only under the focused card (the Google TV
  /// "contextual detail" pattern) instead of being duplicated on both.
  Widget _buildTypeChoices(BuildContext context, ColorScheme colorScheme) {
    // Side by side wherever there is room, not only on TV: on a 800dp tablet
    // two stacked cards ran 1160dp wide for two words each.
    final tv = ResponsiveHelper.useNavigationRail(context);
    final xtream = _TypeChoice(
      title: 'Xtream Codes',
      support: context.loc.xtream_code_title,
      icon: Icons.stream,
      accent: colorScheme.primary,
      onAccent: colorScheme.onPrimary,
      autofocus: tv,
      wide: !tv,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewXtreamCodePlaylistScreen()),
      ),
    );
    final m3u = _TypeChoice(
      title: 'M3U Playlist',
      support: context.loc.m3u_playlist_title,
      icon: Icons.playlist_play,
      accent: colorScheme.tertiary,
      onAccent: colorScheme.onTertiary,
      wide: !tv,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewM3uPlaylistScreen()),
      ),
    );

    if (!tv) {
      return Column(
        children: [xtream, const SizedBox(height: 20), m3u],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: xtream),
          const SizedBox(width: 24),
          Expanded(child: m3u),
        ],
      ),
    );
  }

}

/// One of the two playlist-type choices.
class _TypeChoice extends StatefulWidget {
  const _TypeChoice({
    required this.title,
    required this.support,
    required this.icon,
    required this.accent,
    required this.onAccent,
    required this.onTap,
    this.autofocus = false,
    this.wide = false,
  });

  final String title;
  final String support;
  final IconData icon;
  final Color accent;
  final Color onAccent;
  final VoidCallback onTap;
  final bool autofocus;

  /// Phone layout: full-width row with the icon beside the text.
  final bool wide;

  @override
  State<_TypeChoice> createState() => _TypeChoiceState();
}

class _TypeChoiceState extends State<_TypeChoice> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Side by side wherever there is room, not only on TV: on a 800dp tablet
    // two stacked cards ran 1160dp wide for two words each.
    final tv = ResponsiveHelper.useNavigationRail(context);

    final content = Padding(
      padding: EdgeInsets.all(tv ? 24 : 20),
      child: widget.wide
          ? Row(children: [_icon(), const SizedBox(width: 20), Expanded(child: _text(colorScheme, tv))])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [_icon(), const SizedBox(height: 16), _text(colorScheme, tv)],
            ),
    );

    return FocusHighlight(
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: InkWell(
            onTap: widget.onTap,
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(16),
            // No chevron: ">" is a touch convention meaning "swipe to detail".
            // On a remote it carries no meaning and just adds visual noise.
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _icon() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: widget.accent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(widget.icon, size: 32, color: widget.onAccent),
      );

  Widget _text(ColorScheme colorScheme, bool tv) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontFamily: 'Bricolage Grotesque',
              fontSize: tv ? 24 : 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.support,
            style: TextStyle(
              fontSize: tv ? 16 : 14,
              color: colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      );
}
