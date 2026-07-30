// Home screen shown INSIDE `TvReceiverHost` when the app is running on an
// Android TV / leanback device: a lean-back "waiting for a phone" screen with
// a rail of previously watched titles the viewer can resume without a remote
// pairing, plus a minimal playback-settings entry point.
//
// Deliberately narrow scope: no search, no catalogue browsing, no
// Drawer/BottomNav. `TvReceiverHost` already owns starting the Cast receiver
// and showing the pairing PIN — this widget only renders the passive content
// underneath it.
import 'package:flutter/material.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/m3u_item.dart';
import '../../models/playlist_content_model.dart';
import '../../models/playlist_model.dart';
import '../../models/watch_history.dart';
import '../../redesign/rensi_widgets.dart';
import '../../repositories/m3u_repository.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../services/watch_history_service.dart';
import '../../utils/app_themes.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/player_widget.dart';
import '../../widgets/tv/focus_highlight.dart';

class TvReceiverHome extends StatefulWidget {
  const TvReceiverHome({super.key});

  @override
  State<TvReceiverHome> createState() => _TvReceiverHomeState();
}

class _TvReceiverHomeState extends State<TvReceiverHome> {
  final _historyService = WatchHistoryService();
  late final Future<List<WatchHistory>> _historyFuture = _loadHistory();

  // Guards against overlapping `_replay` calls: `AppState.currentPlaylist` is
  // a shared static field that gets swapped-then-restored during replay, so a
  // double D-pad "select" on a history tile (or selects on two different
  // tiles before the first navigation settles) could otherwise interleave
  // two swap/restore cycles and leave the app on the wrong playlist.
  bool _replaying = false;

  /// Merges the three content-type history queries the service exposes into
  /// one most-recent-first list.
  ///
  /// WatchHistoryService has no "every content type" or "every playlist"
  /// query, only `getWatchHistoryByContentType(type, playlistId)` and the
  /// narrower `getContinueWatching(playlistId)` (which drops finished titles
  /// and live channels). Calling the by-type query once per [ContentType] and
  /// sorting client-side is the closest existing API gets to a plain "recent
  /// history" list.
  Future<List<WatchHistory>> _loadHistory() async {
    final playlistId = AppState.currentPlaylist?.id;
    if (playlistId == null) return const [];
    final byType = await Future.wait([
      _historyService.getWatchHistoryByContentType(
          ContentType.liveStream, playlistId),
      _historyService.getWatchHistoryByContentType(
          ContentType.vod, playlistId),
      _historyService.getWatchHistoryByContentType(
          ContentType.series, playlistId),
    ]);
    final merged = [for (final list in byType) ...list]
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return merged.take(15).toList();
  }

  /// Rebuilds a playable [ContentItem] from a history row and pushes the
  /// player, mirroring `TvReceiverHost._play`: the active playlist is
  /// temporarily swapped for an M3U-typed one scoped to the row's own
  /// playlistId, so `ContentItem`'s constructor resolves `url` from the
  /// [M3uItem] instead of trying to build an Xtream media URL, and is
  /// restored once the player is dismissed.
  ///
  /// Scoped to M3U history on purpose: an Xtream row only stores an id, and
  /// turning that back into a playable stream needs the movie/episode's own
  /// catalogue record (container extension, series episode lookup, etc.) —
  /// out of reach from `WatchHistory` alone without pulling in the catalogue
  /// screens this widget must not depend on. When the lookup misses (the
  /// common case for an Xtream-sourced row), the tile fails gracefully with a
  /// message instead of crashing.
  Future<void> _replay(BuildContext context, WatchHistory history) async {
    if (_replaying) return;
    _replaying = true;
    final restore = AppState.currentPlaylist;
    try {
      AppState.currentPlaylist = Playlist(
        id: history.playlistId,
        name: 'Rensi TV',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026, 1, 1),
      );

      M3uItem? m3uItem;
      try {
        m3uItem = await M3uRepository().getM3uItemById(id: history.streamId);
      } catch (_) {
        m3uItem = null;
      }

      if (m3uItem == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.loc.tv_replay_failed),
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;

      final item = ContentItem(
        history.streamId,
        history.title,
        history.imagePath ?? '',
        history.contentType,
        m3uItem: m3uItem,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: PlayerWidget(contentItem: item, queue: [item]),
          ),
        ),
      );
    } finally {
      AppState.currentPlaylist = restore;
      _replaying = false;
    }
  }

  Future<void> _openDecoderSettings(BuildContext context) async {
    final current = await UserPreferences.getVideoDecoder();
    if (!context.mounted) return;
    var selected =
        const ['auto', 'hw_direct', 'software'].contains(current) ? current : 'auto';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF15151A),
          title: Text(
            dialogContext.loc.video_decoding_label,
            style: TextStyle(
              fontSize: AppThemes.tenFoot(dialogContext, AppThemes.h3Size),
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: DropdownTileWidget<String>(
              icon: Icons.memory,
              label: dialogContext.loc.video_decoding_label,
              description: dialogContext.loc.video_decoding_description,
              value: selected,
              items: [
                DropdownMenuItem(
                    value: 'auto',
                    child: Text(dialogContext.loc.video_decoding_auto)),
                DropdownMenuItem(
                    value: 'hw_direct',
                    child: Text(dialogContext.loc.video_decoding_hw)),
                DropdownMenuItem(
                    value: 'software',
                    child: Text(dialogContext.loc.video_decoding_software)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await UserPreferences.setVideoDecoder(value);
                setDialogState(() => selected = value);
              },
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RensiSafeColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _waitingHeader(context),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: _settingsButton(context),
              ),
              const SizedBox(height: 32),
              Expanded(child: _historySection(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waitingHeader(BuildContext context) {
    final titleSize = AppThemes.tenFoot(context, AppThemes.displaySize);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo de la app (la "R"), en vez del emoji de TV genérico.
            Image.asset(
              'assets/logo_foreground.png',
              height: titleSize * 1.35,
              filterQuality: FilterQuality.medium,
            ),
            SizedBox(width: titleSize * 0.28),
            Text(
              'Rensi TV',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          context.loc.tv_ready_subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppThemes.tenFoot(context, AppThemes.bodySize),
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _settingsButton(BuildContext context) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(12),
      child: OutlinedButton.icon(
        autofocus: true,
        onPressed: () => _openDecoderSettings(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        icon: const Icon(Icons.settings),
        label: Text(
          context.loc.tv_playback_settings,
          style: TextStyle(fontSize: AppThemes.tenFoot(context, AppThemes.bodySize)),
        ),
      ),
    );
  }

  Widget _historySection(BuildContext context) {
    return FutureBuilder<List<WatchHistory>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              context.loc.history_empty_message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppThemes.tenFoot(context, AppThemes.bodySmallSize),
                color: Colors.white70,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                context.loc.history,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, AppThemes.h3Size),
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: RensiRail(
                posterWidth: 260,
                height: 175,
                children: [
                  for (final h in items) _historyCard(context, h),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _historyCard(BuildContext context, WatchHistory h) {
    final r = rensi(context);
    final total = h.totalDuration?.inSeconds ?? 0;
    final done = h.watchDuration?.inSeconds ?? 0;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 260,
      child: FocusHighlight(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.black,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            onTap: () => _replay(context, h),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
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
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: total > 0 ? 20 : 10,
                    child: Text(
                      h.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppThemes.tenFoot(context, 14),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (total > 0)
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
        ),
      ),
    );
  }
}
