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
/// Directories scanned recursively, so a file added to a 10-foot surface is
/// covered the day it lands. A hand-written list missed
/// lib/widgets/live/now_playing_line.dart — added in the same branch that
/// claimed this floor was enforced — and an audit proved the gap by planting
/// `fontSize: 9` there and watching the suite stay green.
const _tvSurfaceDirs = <String>[
  'lib/redesign',
  'lib/widgets/tv',
  'lib/widgets/live',
];

const _tvSurfaceFiles = <String>[
  'lib/screens/playlist_type_screen.dart',
];

final _fontSize = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');

void main() {
  test('no 10-foot surface renders text below the readable floor', () {
    final offenders = <String>[];

    final paths = <String>[
      for (final dir in _tvSurfaceDirs)
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => p.endsWith('.dart')),
      ..._tvSurfaceFiles,
    ];
    expect(paths, isNotEmpty, reason: 'the scan found no files to check');

    for (final path in paths) {
      final file = File(path);
      // Fail loudly rather than skip: a rename used to disable the guard in
      // total silence.
      expect(file.existsSync(), isTrue, reason: '$path is listed but missing');
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
