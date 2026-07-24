import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// An on-screen keyboard for 10-foot search.
///
/// Netflix, Prime Video, Plex and Google TV all draw their own keyboard beside
/// the results and none of them hand off to the system IME. The reason is not
/// aesthetic: leanback's IME is a full-screen overlay that hides the results, so
/// you cannot see what your typing is finding. Without one, Rensi's search was a
/// text field on an otherwise black screen with no visible way to type at all —
/// the single widest gap against every competitor.
///
/// Deliberately not a QWERTY: alphabetical order is what the same four apps use,
/// because scanning for a letter beats recalling a layout when every hop costs a
/// D-pad press.
class TvKeyboard extends StatelessWidget {
  const TvKeyboard({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    this.keyExtent = 56,
    this.columns = 6,
  });

  /// Appends one character.
  final void Function(String) onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Side of a key. 56dp keeps a comfortable D-pad target at 3 m.
  final double keyExtent;
  final int columns;

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final keys = <Widget>[
      for (final c in _letters.split(''))
        _Key(
          label: c,
          onTap: () => onKey(c),
          // The first key takes focus so arriving at the keyboard always lands
          // somewhere; a grid with no focused cell is unusable with a remote.
          autofocus: c == 'A',
        ),
      // Localized: TalkBack was announcing these three keys in Spanish in
      // every locale (incl. Arabic RTL).
      _Key(label: '␣', onTap: () => onKey(' '), semantic: context.loc.key_space),
      _Key(label: '⌫', onTap: onBackspace, semantic: context.loc.key_backspace),
      _Key(label: '✕', onTap: onClear, semantic: context.loc.clear),
    ];

    return SizedBox(
      width: columns * (keyExtent + 8),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: keys
            .map((k) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.hairline),
                  ),
                  child: k,
                ))
            .toList(),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.semantic,
  });

  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          button: true,
          label: semantic ?? label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            autofocus: autofocus,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppThemes.bodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
