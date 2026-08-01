import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// Visual container the toggle renders in. [plain] is a bare tappable icon
/// (or icon+label) with no background — used on detail-screen headers and
/// in the player controls bar. [glass] wraps the icon in the same
/// translucent rounded box the home hero uses for its other overlay
/// buttons (info, share), so the favourite toggle keeps matching its
/// siblings there.
enum SaveToListButtonStyle { plain, glass }

/// THE single "save to My List" affordance for the whole app.
///
/// Every surface that lets a user save/unsave an item (movie & series detail
/// screens, the M3U series screen, the home hero card, the in-player
/// controls) must render this widget instead of rolling its own icon +
/// [FavoritesRepository] call. Before this existed, five surfaces had drifted
/// onto three different icon languages (check/+, a bare red heart, and this
/// bookmark) with inconsistent feedback (some showed a snackbar, some
/// didn't) and one still had an untranslated Turkish tooltip — see the
/// "unify save-to-list affordance" changelog entry. Adding a sixth surface
/// with its own copy of this logic is exactly the drift this widget exists
/// to prevent.
///
/// Design: `Icons.bookmark_border_rounded` unsaved / `Icons.bookmark_rounded`
/// saved, coloured with the theme's [RensiColors] (accent when saved, text2
/// on a themed surface or white over artwork when not), toggled through
/// [FavoritesRepository.toggleFavorite] and confirmed with the shared
/// localized snackbar. Every instance listens to the `favorites_changed`
/// event so the button stays in sync when the same item is saved/unsaved
/// from another surface (e.g. the home hero — which lives in a mounted
/// IndexedStack and never rebuilds on its own — reflects a save made on the
/// detail screen).
class SaveToListButton extends StatefulWidget {
  const SaveToListButton({
    super.key,
    required this.item,
    this.showLabel = false,
    this.overArtwork = false,
    this.iconSize = 24,
    this.style = SaveToListButtonStyle.plain,
    this.showSnackBar = true,
  });

  /// The item being saved/unsaved. Passed straight to
  /// [FavoritesRepository.toggleFavorite] and [FavoritesRepository.isFavorite].
  final ContentItem item;

  /// Show the localized "Mi lista" / "Guardado" text under the icon. Off by
  /// default for icon-only placements (headers, in-player controls).
  final bool showLabel;

  /// True when the button sits directly over poster/backdrop art rather
  /// than a themed surface — the unsaved icon then uses white so it stays
  /// legible over an image instead of blending into it.
  final bool overArtwork;

  final double iconSize;

  final SaveToListButtonStyle style;

  /// Set to false to suppress the confirmation snackbar, e.g. if the
  /// surface already gives its own feedback for this action elsewhere.
  final bool showSnackBar;

  @override
  State<SaveToListButton> createState() => _SaveToListButtonState();
}

class _SaveToListButtonState extends State<SaveToListButton> {
  final _repo = FavoritesRepository();
  StreamSubscription<dynamic>? _favoritesSub;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Stay in sync when the same item is saved/unsaved from another surface:
    // the home hero lives in a mounted IndexedStack and would otherwise show a
    // stale bookmark forever after a save made on the detail screen.
    _favoritesSub =
        EventBus().on('favorites_changed').listen((_) => _checkStatus());
  }

  @override
  void didUpdateWidget(covariant SaveToListButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.contentType != widget.item.contentType) {
      _checkStatus();
    }
  }

  @override
  void dispose() {
    _favoritesSub?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final saved = await _repo.isFavorite(
      widget.item.id,
      widget.item.contentType,
    );
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _toggle() async {
    final result = await _repo.toggleFavorite(widget.item);
    if (!mounted) return;
    setState(() => _saved = result);
    if (widget.showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result
                ? context.loc.added_to_favorites
                : context.loc.removed_from_favorites,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final color =
        _saved ? r.accent : (widget.overArtwork ? Colors.white : r.text2);
    final label =
        _saved ? context.loc.action_saved : context.loc.action_save_to_list;

    final icon = Icon(
      _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      size: widget.iconSize,
      color: color,
    );

    Widget content = icon;
    if (widget.showLabel) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppThemes.tenFoot(context, 11.5),
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );
    }

    final borderRadius = BorderRadius.circular(widget.style ==
            SaveToListButtonStyle.glass
        ? 14
        : widget.iconSize);

    Widget button = Material(
      color: widget.style == SaveToListButtonStyle.glass
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: widget.style == SaveToListButtonStyle.glass
            ? BorderSide(color: Colors.white.withValues(alpha: 0.25))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: _toggle,
        child: Padding(
          padding: widget.style == SaveToListButtonStyle.glass
              ? const EdgeInsets.all(14)
              : const EdgeInsets.all(10),
          child: content,
        ),
      ),
    );

    button = Tooltip(message: label, child: button);

    return FocusHighlight(borderRadius: borderRadius, child: button);
  }
}
