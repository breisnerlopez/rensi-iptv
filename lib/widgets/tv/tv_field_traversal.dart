import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// Lets the D-pad escape a text field on a 10-foot screen.
///
/// Inside an `EditableText`, up/down arrows are text-editing keys: Flutter's
/// `DefaultTextEditingShortcuts` binds them to caret movement, so on a TV the
/// remote appears to do nothing and focus is trapped in the field — the user
/// cannot reach the next input or the submit button without a physical
/// keyboard. Shortcuts resolve from the focused widget outwards, and
/// `DefaultTextEditingShortcuts` sits way up at `WidgetsApp`, so re-binding the
/// two keys nearer to the field wins and turns them back into navigation.
///
/// Left/right are deliberately left alone: they are how you move the caret
/// within a line, which is still what you want when editing a URL.
class TvFieldTraversal extends StatelessWidget {
  const TvFieldTraversal({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _tvShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowDown):
        DirectionalFocusIntent(TraversalDirection.down),
    SingleActivator(LogicalKeyboardKey.arrowUp):
        DirectionalFocusIntent(TraversalDirection.up),
  };

  @override
  Widget build(BuildContext context) {
    // Phones keep stock behaviour: there the caret keys matter and there is no
    // D-pad to rescue.
    if (!ResponsiveHelper.isDesktopOrTV(context)) return child;
    return Shortcuts(shortcuts: _tvShortcuts, child: child);
  }
}
