import 'package:flutter/material.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';

/// Grouped-rows container for the settings screens.
///
/// Replaces the Material [Card] the legacy settings used (which painted the
/// theme `surface` with a drop shadow / rounded shape). This paints a
/// `surface2` panel — one warm step above the page background — with a
/// `hairline` border instead of elevation, matching the cinematic redesign's
/// flat, bordered surfaces (see [RensiPoster], [RensiEmptyState]).
///
/// It is a [Material] on purpose, not a [Container]: the [ListTile] /
/// [SwitchListTile] rows it wraps look up the nearest [Material] to paint their
/// ink splash and to resolve `tileColor`. A bare coloured box would leave the
/// splash painting on the Scaffold behind the panel, outside the rounded
/// corners. `clipBehavior` keeps the row dividers and splashes inside the
/// radius.
class RensiSettingsCard extends StatelessWidget {
  const RensiSettingsCard({super.key, required this.child, this.margin});

  final Widget child;

  /// Optional outer spacing, for callers that relied on the old [Card]'s margin
  /// to provide their screen gutter. Left null where the host scroll view
  /// already supplies the gutter.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final card = Material(
      color: r.surface2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: r.hairline),
      ),
      child: child,
    );
    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
