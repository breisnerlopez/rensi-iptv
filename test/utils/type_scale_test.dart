import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// Guards the 10-foot type floor.
//
// A design review found the TV nav rail rendering its labels at 10dp, because
// the "large screen" branch that would have used 11 was gated behind a 1200dp
// breakpoint an Android TV never reaches. Nobody noticed for a long time: a size
// literal is invisible in review and only shows up when someone sits three
// metres from a panel. So the floor is asserted instead.
//
// Scope is the surfaces that render the 10-foot UI. Phone-only screens are not
// covered — their constraints are different and sweeping them all at once would
// be a rename, not a design decision.
const _tvSurfaces = <String>[
  'lib/redesign/rensi_widgets.dart',
  'lib/redesign/home_redesign.dart',
  'lib/redesign/browse_redesign.dart',
  'lib/redesign/live_redesign.dart',
  'lib/redesign/search_redesign.dart',
  'lib/redesign/list_redesign.dart',
  'lib/widgets/tv/navigation_models.dart',
  'lib/screens/playlist_type_screen.dart',
];

final _fontSize = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');

void main() {
  test('no 10-foot surface renders text below the readable floor', () {
    final offenders = <String>[];

    for (final path in _tvSurfaces) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in _fontSize.allMatches(lines[i])) {
          final size = double.parse(m.group(1)!);
          if (size < AppThemes.tvBodyMin) {
            offenders.add('$path:${i + 1} → ${size}dp');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'text under ${AppThemes.tvBodyMin}dp is decorative at 3 m, not '
          'readable:\n${offenders.join('\n')}',
    );
  });

  test('the scale has no half points', () {
    const scale = <double>[
      AppThemes.displaySize,
      AppThemes.h1Size,
      AppThemes.h2Size,
      AppThemes.h3Size,
      AppThemes.bodySize,
      AppThemes.bodySmallSize,
      AppThemes.labelSize,
    ];
    for (final s in scale) {
      expect(s, s.roundToDouble(),
          reason: '$s is a half point — the tuning-by-eye smell this scale '
              'exists to remove');
    }
    // Strictly descending: a scale with duplicate or out-of-order steps is not
    // a scale.
    for (var i = 1; i < scale.length; i++) {
      expect(scale[i], lessThan(scale[i - 1]));
    }
  });
}
