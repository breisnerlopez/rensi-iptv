// Home screen shown INSIDE `TvReceiverHost` when the app is running on an
// Android TV / leanback device: a lean-back "waiting for a phone" screen with
// a rail of previously watched titles the viewer can resume without a remote
// pairing, plus a minimal playback-settings entry point.
//
// Deliberately narrow scope: no search, no catalogue browsing, no
// Drawer/BottomNav. `TvReceiverHost` already owns starting the Cast receiver
// and showing the pairing PIN — this widget only renders the passive content
// underneath it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
import '../../services/event_bus.dart';
import '../../services/watch_history_service.dart';
import '../../utils/app_themes.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/cast/tv_receiver_host.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/player_widget.dart';
import '../../widgets/tv/focus_highlight.dart';

class TvReceiverHome extends StatefulWidget {
  const TvReceiverHome({super.key});

  @override
  State<TvReceiverHome> createState() => _TvReceiverHomeState();
}

/// Playlist sintética bajo la que el receptor guarda lo que se castea a la TV
/// (ver TvReceiverHost). Debe coincidir con `_castPlaylistId` de ese archivo.
const _castPlaylistId = '__cast__';

class _TvReceiverHomeState extends State<TvReceiverHome> {
  final _historyService = WatchHistoryService();
  late Future<List<WatchHistory>> _historyFuture = _loadHistory();
  late final Future<String> _versionFuture = _loadVersion();

  // Recargar el historial cuando el receptor termina de reproducir algo: lo
  // casteado se guarda bajo '__cast__' mientras el player está encima; al volver
  // aquí el rail debe reflejarlo (sin esto solo aparecería tras reiniciar).
  StreamSubscription<void>? _historyChangedSub;

  @override
  void initState() {
    super.initState();
    _historyChangedSub =
        EventBus().on<void>('tv_history_changed').listen((_) {
      if (mounted) setState(() => _historyFuture = _loadHistory());
    });
  }

  @override
  void dispose() {
    _historyChangedSub?.cancel();
    super.dispose();
  }

  Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      return build.isEmpty ? 'v${info.version}' : 'v${info.version} ($build)';
    } catch (_) {
      return '';
    }
  }

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
    // Cargar SIEMPRE el historial de casting ('__cast__') además del de la
    // playlist activa de la TV (si la hay). Antes solo se leía la activa, así que
    // lo casteado — guardado bajo '__cast__' — nunca aparecía en el home.
    final currentId = AppState.currentPlaylist?.id;
    final playlistIds = <String>{
      _castPlaylistId,
      if (currentId != null && currentId != _castPlaylistId) currentId,
    };
    final futures = <Future<List<WatchHistory>>>[];
    for (final id in playlistIds) {
      for (final type in ContentType.values) {
        futures.add(_historyService.getWatchHistoryByContentType(type, id));
      }
    }
    final lists = await Future.wait(futures);
    final merged = [for (final list in lists) ...list]
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    // Deduplicar por (playlistId, streamId) conservando la fila más reciente.
    final seen = <String>{};
    final out = <WatchHistory>[];
    for (final h in merged) {
      if (seen.add('${h.playlistId} ${h.streamId}')) out.add(h);
    }
    return out.take(15).toList();
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
          // Una fila de CASTEO no se puede reconstruir en la TV (no hay catálogo
          // local; llegó por LAN desde el móvil). En vez de un error, guiar al
          // usuario a reenviarla desde el móvil.
          final msg = history.playlistId == _castPlaylistId
              ? context.loc.tv_cast_replay_hint
              : context.loc.tv_replay_failed;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
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
    // A real 1080p/4K Android TV reports ~960×540 LOGICAL dp (dpr 2.0) — a
    // tight height budget. `tvScale` is the same density knob
    // home_redesign.dart / xtream_code_home_screen.dart use to compact fixed
    // TV-only chrome; 1.0 off-TV so this is a no-op on phone/tablet (this
    // screen never renders there anyway).
    final s = ResponsiveHelper.tvScale(context);
    return Scaffold(
      // Warm ramp bg (#0C0A09), not flat black — the "empty / too black"
      // complaint this redesign exists to fix started right here.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RensiSafeColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Marca arriba-izquierda + [ajustes-gear, pill de estado]
              // arriba-derecha: el antiguo botón grande de "Ajustes de
              // reproducción" ya no ocupa un bloque completo aquí, para que
              // el centro quede libre para el reloj/rail/guía.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _brandLockup(context),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _settingsIconButton(context),
                      SizedBox(width: 12 * s),
                      _statusPill(context),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20 * s),
              Expanded(child: _heroSection(context)),
              _statusStrip(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandLockup(BuildContext context) {
    final titleSize = AppThemes.tenFoot(context, AppThemes.h2Size);
    // `titleSize` (from `tenFoot`) is a TEXT size — it only actually shrinks
    // on TV through the app-wide `TextScaler(tvScale)` `MaterialApp.builder`
    // applies to `Text` (see `main.dart`), which the `Text` below gets for
    // free. `Image.asset`/`SizedBox` are not text, so anything sized off
    // `titleSize` for THEM needs `tvScale` applied explicitly, same as the
    // icon/spacer sizes elsewhere on this screen (`_emptyStep`, etc.) —
    // otherwise the logo (and its gap to the wordmark) would stay full-size
    // on a smaller-dp TV panel while the text next to it shrinks.
    final s = ResponsiveHelper.tvScale(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo de la app (la "R"), en vez del emoji de TV genérico.
        Image.asset(
          'assets/logo_foreground.png',
          height: titleSize * 1.35 * s,
          filterQuality: FilterQuality.medium,
        ),
        SizedBox(width: titleSize * 0.28 * s),
        Text(
          'Rensi TV',
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// Discoverable / pairing / error pill fed by [TvReceiverStatusScope] — the
  /// surface for the mDNS failure that `TvReceiverHost._start` used to swallow
  /// silently. Renders nothing if the scope is missing (e.g. widget tests that
  /// mount `TvReceiverHome` directly, without a `TvReceiverHost` ancestor).
  Widget _statusPill(BuildContext context) {
    final scope = TvReceiverStatusScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final r = rensi(context);
    final loc = context.loc;
    final (Color dot, String label) = switch (scope.status) {
      ReceiverStatus.discoverable => (
          r.live,
          loc.tv_status_discoverable(scope.deviceName)
        ),
      ReceiverStatus.pairing => (r.accent, loc.cast_pairing),
      ReceiverStatus.error => (r.gold, loc.tv_status_error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: r.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
              fontWeight: FontWeight.w600,
              color: r.text2,
            ),
          ),
          // Oculto (no solo deshabilitado) mientras `_start()` ya está en
          // curso: un Retry en vuelo no necesita otro objetivo D-pad que lo
          // relance por encima, y así no queda un foco "muerto" en pantalla.
          if (scope.status == ReceiverStatus.error && !scope.starting) ...[
            const SizedBox(width: 12),
            FocusHighlight(
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: scope.onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    loc.cast_retry,
                    style: TextStyle(
                      fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
                      fontWeight: FontWeight.w700,
                      color: r.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Entry point to playback settings, now a small gear ICON button instead
  /// of the old full-width `OutlinedButton.icon` — that button used to sit
  /// alone under the header eating a whole row of vertical space for a
  /// setting most viewers never touch. Lives next to the brand lockup/status
  /// pill instead, same row, so the centre of the screen is free for the
  /// clock/history hero/empty guide. Kept as the autofocus target: it is
  /// always present regardless of history state, so D-pad focus always has
  /// a safe, deterministic landing spot the instant this screen builds.
  Widget _settingsIconButton(BuildContext context) {
    final r = rensi(context);
    final s = ResponsiveHelper.tvScale(context);
    return FocusHighlight(
      shape: const CircleBorder(),
      child: Material(
        color: r.surface2,
        shape: const CircleBorder(),
        child: IconButton(
          autofocus: true,
          tooltip: context.loc.tv_playback_settings,
          onPressed: () => _openDecoderSettings(context),
          icon: Icon(
            Icons.settings,
            size: 24 * s,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// The centre of the screen: either the 3-step empty guide, or — once
  /// there is history — the resume rail as the vertically-CENTERED hero
  /// (replacing the old "anchored at the bottom, void above" layout). Both
  /// branches are wrapped by the same `FutureBuilder` so the history query
  /// only runs once and both states share identical top/bottom chrome.
  Widget _heroSection(BuildContext context) {
    return FutureBuilder<List<WatchHistory>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final items = snapshot.data ?? const [];
        return items.isEmpty
            ? _emptyHistoryState(context)
            : _historyHero(context, items);
      },
    );
  }

  /// Resume rail as the centered hero (shown once there is history): the
  /// ambient clock up top, "History" + a short hint, then a noticeably
  /// LARGER rail than the old bottom-anchored one (poster 260→300, scaled by
  /// `tvScale` like everything else fixed-size on this screen) — filling the
  /// vertical void the old anchored-at-the-bottom layout left above it.
  ///
  /// Not wrapping the rail in `Expanded`: as a plain (non-flex) `Column`
  /// child, `RensiRail`'s own `SizedBox` renders at EXACTLY the height it
  /// declares — nothing forces it taller — which is what keeps the clip-fix
  /// math in `_historyCard` exact (see that method's doc). That is NOT what
  /// prevents this column from overflowing the `Expanded` slot `build()`
  /// gives `_heroSection`: a loose constraint shares the same maximum as a
  /// tight one, it only additionally permits smaller, so looseness alone
  /// can't stop an overflow. Overflow safety instead comes from the height
  /// BUDGET — every fixed size in this column (`posterWidth`, the
  /// `_railFocusPad` cushion, the spacers) is scaled by `tvScale`, and every
  /// `Text`'s glyph size is scaled the same way via the app-wide
  /// `TextScaler(tvScale)` `MaterialApp.builder` applies (see `main.dart`),
  /// so the column's total height shrinks together with the panel and stays
  /// within the slot on a real ~960×540dp TV.
  Widget _historyHero(BuildContext context, List<WatchHistory> items) {
    final r = rensi(context);
    final s = ResponsiveHelper.tvScale(context);
    final posterWidth = 300 * s;
    final cardHeight = posterWidth * 10 / 16;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Same cheap static radial glow as the empty state — no
        // BackdropFilter/ImageFilter (perf risk on low-end TV, deliberately
        // deferred).
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: [
                  r.accentGlow.withValues(alpha: 0.12),
                  r.accentGlow.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(alignment: Alignment.center, child: _AmbientClock()),
            SizedBox(height: 32 * s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.loc.history,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, AppThemes.h3Size),
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(height: 4 * s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.loc.tv_history_hint,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, AppThemes.bodySmallSize),
                  color: r.text3,
                ),
              ),
            ),
            SizedBox(height: 18 * s),
            RensiRail(
              posterWidth: posterWidth,
              // `_railFocusPad` on both sides + the fixed 4dp RensiRail bakes
              // into its own bottom padding = exactly enough clearance for a
              // focused card's ring + 1.06x zoom to render without clipping
              // (see `_historyCard`/`_railFocusPad`) — task C.
              height: cardHeight + _railFocusPad * 2 + 4,
              children: [
                for (final h in items) _historyCard(context, h, posterWidth),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 3-step illustrated guide shown before the viewer has ever cast anything —
  /// replaces the old single grey caption, which is what made an untouched TV
  /// home read as "empty" rather than "waiting".
  ///
  /// Laid out as a HORIZONTAL row of 3 icon+label columns, not 3 stacked
  /// rows: a real 1080p/4K Android TV reports ~960×540 LOGICAL dp, and this
  /// widget sits in the `Expanded` slot below the header + settings button —
  /// stacking three 96dp squircles ate the scarce HEIGHT budget and could
  /// clip on-device even though it fit comfortably in a desktop-sized preview.
  /// Going horizontal spends the plentiful WIDTH instead; every fixed size
  /// below is also run through `tvScale` for the same reason `home_redesign`/
  /// `xtream_code_home_screen` do — a 960dp TV is a smaller canvas than the
  /// numbers were eyeballed against.
  Widget _emptyHistoryState(BuildContext context) {
    final r = rensi(context);
    final s = ResponsiveHelper.tvScale(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Cheap static radial glow for depth — no BackdropFilter/ImageFilter
        // (perf risk on low-end TV boxes; deliberately deferred, see HANDOFF).
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: [
                  r.accentGlow.withValues(alpha: 0.16),
                  r.accentGlow.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        ConstrainedBox(
          // Capped further by RensiSafeColumn/tvMaxContentWidth already; this
          // just keeps the 3 columns from spreading edge-to-edge on a very
          // wide desktop/tablet preview.
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AmbientClock(),
              SizedBox(height: 28 * s),
              Text(
                context.loc.tv_ready_subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Bricolage Grotesque',
                  fontWeight: FontWeight.w700,
                  // NOT multiplied by `s`: fontSize already goes through the
                  // app-wide TextScaler(tvScale) MaterialApp.builder applies
                  // on TV (see main.dart) — doubling it here would shrink
                  // this text twice as much as everything else on screen.
                  fontSize: AppThemes.tenFoot(context, AppThemes.h2Size),
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 28 * s),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _emptyStep(
                    context,
                    icon: Icons.wifi,
                    label: context.loc.tv_empty_step_wifi,
                  ),
                  SizedBox(width: 24 * s),
                  _emptyStep(
                    context,
                    icon: Icons.smartphone,
                    label: context.loc.tv_empty_step_phone,
                  ),
                  SizedBox(width: 24 * s),
                  _emptyStep(
                    context,
                    icon: Icons.cast,
                    label: context.loc.tv_empty_step_cast,
                    iconColor: r.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One column of the 3-step guide: squircle icon above a centred label.
  /// Sized through `tvScale` (see `_emptyHistoryState`) except the label's
  /// `fontSize`, which is left to the app-wide TextScaler for the same reason
  /// the headline above it is.
  Widget _emptyStep(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? iconColor,
  }) {
    final r = rensi(context);
    final s = ResponsiveHelper.tvScale(context);
    return SizedBox(
      width: 210 * s,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96 * s,
            height: 96 * s,
            decoration: BoxDecoration(
              color: r.surface2,
              borderRadius: BorderRadius.circular(16 * s),
            ),
            child: Icon(icon, size: 40 * s, color: iconColor ?? r.text2),
          ),
          SizedBox(height: 14 * s),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppThemes.tenFoot(context, AppThemes.bodySize),
              fontWeight: FontWeight.w600,
              color: r.text2,
            ),
          ),
        ],
      ),
    );
  }

  /// Vertical breathing room (task C fix) reserved above/below every history
  /// card slot inside `RensiRail`'s horizontal `ListView`.
  ///
  /// Root cause of the reported top-clipped focus ring: `RensiRail` bakes in
  /// `padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 4)` — i.e.
  /// ZERO top padding and only 4dp at the bottom — and its `ListView` (like
  /// every `ScrollView`) defaults to `clipBehavior: Clip.hardEdge`. A
  /// focused card is wrapped by `FocusHighlight`, which grows it ~1.06x
  /// (`AnimatedScale`) plus a 3dp ring padding; with the card slot already
  /// forced to fill the rail's exact cross-axis extent (no slack), that
  /// growth has nowhere to paint above the card — the top edge, sitting
  /// flush at the rail's `top: 0` inset, is the first (and worst) thing the
  /// hard-edge clip cuts into.
  ///
  /// `RensiRail` lives in `lib/redesign/rensi_widgets.dart`, out of this
  /// file's scope this round, so the fix is entirely local: give each card
  /// slot `_railFocusPad` extra height on top of what the unfocused card
  /// needs (`_historyHero` adds `_railFocusPad * 2` to the `height` it hands
  /// `RensiRail`), then eat exactly that much of it back here as a
  /// `Padding` wrapping the card. `RensiRail`'s `ListView` gives each slot a
  /// TIGHT cross-axis constraint equal to its own extent (not a loose one),
  /// so this padding carves out real, unoccupied pixels above and below the
  /// card — not just alignment — for the ring/zoom to grow into without
  /// being clipped, while the card's own rendered size (and D-pad focus
  /// behaviour) stays exactly as it was.
  static const _railFocusPad = 14.0;

  Widget _historyCard(BuildContext context, WatchHistory h, double width) {
    final r = rensi(context);
    final total = h.totalDuration?.inSeconds ?? 0;
    final done = h.watchDuration?.inSeconds ?? 0;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _railFocusPad),
      child: SizedBox(
        width: width,
        child: FocusHighlight(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: r.surface2,
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
      ),
    );
  }


  /// Bottom status strip: app version+build (from `package_info_plus`, same
  /// source the old lone version caption used) plus a compact echo of the
  /// receiver's discoverable/pairing/error status the top-right pill already
  /// shows — a short "is this TV reachable" hint even if the viewer's eye
  /// lands at the bottom of the screen first. Renders just the version if
  /// `TvReceiverStatusScope` is absent (e.g. `TvReceiverHome` mounted
  /// directly in a widget test, without a `TvReceiverHost` ancestor).
  Widget _statusStrip(BuildContext context) {
    final r = rensi(context);
    final scope = TvReceiverStatusScope.maybeOf(context);
    final style = TextStyle(color: r.text3, fontSize: AppThemes.tenFoot(context, 11));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<String>(
            future: _versionFuture,
            builder: (context, snap) => Text(snap.data ?? '', style: style),
          ),
          if (scope != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('·', style: style),
            ),
            Text(_statusStripLabel(context, scope), style: style),
          ],
        ],
      ),
    );
  }

  String _statusStripLabel(BuildContext context, TvReceiverStatusScope scope) {
    final loc = context.loc;
    return switch (scope.status) {
      ReceiverStatus.discoverable => loc.tv_status_discoverable(scope.deviceName),
      ReceiverStatus.pairing => loc.cast_pairing,
      ReceiverStatus.error => loc.tv_status_error,
    };
  }
}

/// Ambient standby clock — pure local `DateTime`, no network calls. Shown
/// above BOTH the empty guide and the history hero so the idle screen always
/// has a live, slowly-changing focal point instead of a static void
/// (Google-TV-standby style). Colors intentionally muted (`text2`/`text3`)
/// to read as "discreet", not a competing headline.
///
/// Isolated in its OWN `StatefulWidget` (not a field/Timer on
/// `_TvReceiverHomeState`): a `Timer.periodic` ticking a `setState` on the
/// parent state would rebuild the ENTIRE `TvReceiverHome` subtree every
/// 20s — lockup, status pill, settings gear, the glow gradient, and
/// `RensiRail` with all N history cards — purely to advance a clock this
/// screen doesn't even always show at the top. Scoping the `Timer` and its
/// `DateTime` state to this small widget means each tick only rebuilds
/// these two `Text`s, matching the same "don't repaint what didn't change"
/// discipline `FocusHighlight`'s `RepaintBoundary` already applies to the
/// history cards.
class _AmbientClock extends StatefulWidget {
  const _AmbientClock();

  @override
  State<_AmbientClock> createState() => _AmbientClockState();
}

class _AmbientClockState extends State<_AmbientClock> {
  // 20s, not every second: this clock only shows hour:minute, so a 20s tick
  // is never more than an instant stale — no need for per-second rebuilds on
  // a low-end TV box.
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    // NOT `MaterialLocalizations.of` — this Flutter version doesn't ship a
    // `maybeOf` on it (only `of`, which asserts/throws when there is no
    // ancestor `Localizations`). `Localizations.of<T>` is the exact
    // null-safe primitive `MaterialLocalizations.of` itself wraps with a
    // bang (see its source doc: "just a convenient shorthand for
    // `Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)!`"),
    // so calling it directly here gives the same "maybeOf" behaviour: a
    // widget test that mounts `TvReceiverHome` (or this widget) without a
    // `MaterialApp`/`Localizations` ancestor falls back to a plain "HH:mm"
    // and no date line instead of crashing on this clock alone.
    final materialLoc =
        Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
    final time = materialLoc?.formatTimeOfDay(
          TimeOfDay.fromDateTime(_now),
          alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
        ) ??
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final date = materialLoc?.formatFullDate(_now);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontWeight: FontWeight.w700,
            fontSize: AppThemes.tenFoot(context, 34),
            color: r.text2,
            letterSpacing: 0.5,
          ),
        ),
        if (date != null) ...[
          const SizedBox(height: 4),
          Text(
            date,
            style: TextStyle(
              fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
              fontWeight: FontWeight.w600,
              color: r.text3,
            ),
          ),
        ],
      ],
    );
  }
}
