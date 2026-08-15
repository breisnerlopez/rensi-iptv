import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// "Seguir viendo → Ver todo": the full grid of what the viewer left
/// unfinished (already filtered by [resumableFrom] and capped at 20 by the
/// caller, most-recent-first). Mirrors [BrowseRedesign]'s Scaffold + header +
/// GridView, but each cell is a landscape continue-watching thumbnail — the
/// same [RensiKeyArt.raw] card the Home rail uses — with a per-card progress
/// bar. The first cell autofocuses so the TV remote lands on it.
class ContinueWatchingAllScreen extends StatelessWidget {
  const ContinueWatchingAllScreen({
    super.key,
    required this.listenable,
    required this.itemsBuilder,
    required this.onResume,
  });

  /// The watch-history controller (a [Listenable]); when it notifies after a
  /// resume/remove, the grid rebuilds so a removed dead entry disappears
  /// without leaving the screen.
  final Listenable listenable;

  /// Recomputes the current, resumable-filtered, ≤20, most-recent-first list
  /// on every rebuild — e.g. `resumableFrom(ctrl.continueWatching).take(20)`.
  final List<WatchHistory> Function() itemsBuilder;

  /// Resume a tapped entry at its stored position — the SAME block the Home
  /// rail's onResume runs (play + reload + dead-entry snackbar).
  final void Function(WatchHistory) onResume;

  @override
  Widget build(BuildContext context) {
    final cross = ResponsiveHelper.getCrossAxisCount(context);
    final sidePad = ResponsiveHelper.safeInset(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(sidePad - 8, 4, sidePad, 10),
              child: Row(
                children: [
                  // Directionality-aware; points the correct way in RTL and is a
                  // D-pad focus target.
                  const BackButton(),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      context.loc.continue_watching,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Bricolage Grotesque',
                        fontSize: AppThemes.h2Size,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: listenable,
                builder: (context, _) {
                  final items = itemsBuilder();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: sidePad),
                        child: Text(
                          context.loc.history_empty_message,
                          textAlign: TextAlign.center,
                          // SYS-M2: mensaje de empty-state sobre surface (no video)
                          // → token temático en vez de white70 literal.
                          style: TextStyle(color: rensi(context).text2),
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(sidePad, 4, sidePad, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      // Landscape thumbnails (matches the Home rail's card).
                      childAspectRatio: 16 / 10,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _card(context, items[i], autofocus: i == 0),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, WatchHistory h, {required bool autofocus}) {
    final r = rensi(context);
    final total = h.totalDuration?.inSeconds ?? 0;
    final done = h.watchDuration?.inSeconds ?? 0;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return FocusHighlight(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.black,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          autofocus: autofocus,
          onTap: () => onResume(h),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // .raw: a thumbnail needs only a picture and a name, not a
              // ContentItem (which would drag AppState.currentPlaylist in).
              RensiKeyArt.raw(
                seed: h.streamId,
                title: h.title,
                imagePath: h.imagePath ?? '',
                titleScale: 0,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xD1000000), Color(0x00000000)],
                    stops: [0.0, 0.6],
                  ),
                ),
              ),
              const Center(
                child: Icon(Icons.play_circle_outline, size: 44, color: Colors.white),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 20,
                child: Text(
                  h.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: AppThemes.tenFoot(context, 14),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: r.hairline,
                    valueColor: AlwaysStoppedAnimation(r.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
