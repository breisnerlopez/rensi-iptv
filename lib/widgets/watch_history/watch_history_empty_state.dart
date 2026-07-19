import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';

/// Empty history.
///
/// This used to be a bare grey icon with a regular-weight title in the body
/// font — a third grammar for "there is nothing here", alongside My List's
/// rounded card and onboarding's tinted squircle, none derived from the others.
/// It was also a dead end: nothing on the screen could take focus, so on a
/// 10-foot UI a remote user arrived and had nothing to press.
class WatchHistoryEmptyState extends StatelessWidget {
  const WatchHistoryEmptyState({super.key, this.onBrowse});

  /// Where the primary action goes. Defaults to going back, which is at least a
  /// way out; a screen that can offer the catalogue should pass its own.
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    return RensiEmptyState(
      icon: Icons.history_rounded,
      title: context.loc.empty_history_title,
      body: context.loc.empty_history_body,
      actionLabel: context.loc.action_browse_catalogue,
      onAction: onBrowse ?? () => Navigator.of(context).maybePop(),
    );
  }
}
