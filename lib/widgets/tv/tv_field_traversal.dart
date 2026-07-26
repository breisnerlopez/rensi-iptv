import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// Lets the D-pad escape a text field on a 10-foot screen.
///
/// Two things trap focus in a text field on an Android TV remote:
///  1. Inside an `EditableText`, up/down arrows are text-editing keys (caret
///     movement) — so the remote appears dead. We re-bind up/down near the
///     field to focus traversal; `DefaultTextEditingShortcuts` sits up at
///     `WidgetsApp`, so the nearer binding wins. Left/right are left alone: they
///     move the caret within a line, which is still what you want editing a URL.
///  2. While the leanback IME is open, every D-pad key drives the IME, not
///     Flutter, so #1 can't fire until the IME is dismissed — and dismissing it
///     (system BACK) leaves the field still focused with a blinking cursor and
///     no obvious way out. So we also make BACK/escape *blur* the field and move
///     focus to a neighbour instead of popping the screen: a `PopScope` catches
///     the hardware BACK that arrives as a route-pop after the IME closes, and
///     an `onKeyEvent` catches escape/goBack delivered as a key (BT keyboards /
///     some remotes). Both only act while the field actually holds focus.
class TvFieldTraversal extends StatefulWidget {
  const TvFieldTraversal({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _tvShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowDown):
        DirectionalFocusIntent(TraversalDirection.down),
    SingleActivator(LogicalKeyboardKey.arrowUp):
        DirectionalFocusIntent(TraversalDirection.up),
  };

  @override
  State<TvFieldTraversal> createState() => _TvFieldTraversalState();
}

class _TvFieldTraversalState extends State<TvFieldTraversal> {
  bool _fieldFocused = false;

  void _onFocusChange(bool focused) {
    if (focused != _fieldFocused) {
      setState(() => _fieldFocused = focused);
    }
  }

  /// Blur the field and land focus on a visible neighbour so the user is never
  /// left staring at a field they can't leave.
  void _escapeField() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).focusInDirection(TraversalDirection.down);
  }

  @override
  Widget build(BuildContext context) {
    // Phones keep stock behaviour: there the caret keys matter and there is no
    // D-pad to rescue.
    if (!ResponsiveHelper.isDesktopOrTV(context)) return widget.child;

    final observed = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            _fieldFocused &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack ||
                event.logicalKey == LogicalKeyboardKey.browserBack)) {
          _escapeField();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TvFieldTraversal._tvShortcuts.isEmpty
          ? widget.child
          : Shortcuts(
              shortcuts: TvFieldTraversal._tvShortcuts,
              child: widget.child,
            ),
    );

    // Only intercept the route pop while the field holds focus, so BACK behaves
    // normally everywhere else on the screen.
    return PopScope(
      canPop: !_fieldFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _escapeField();
      },
      child: observed,
    );
  }
}
