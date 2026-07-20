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

/// Legacy screens that are nonetheless REACHED on Android TV, so their sizes
/// are 10-foot sizes whatever they were written for.
///
/// They were left out of the original scope on the assumption that anything
/// outside lib/redesign/ was phone-only. Tracing the navigation proved
/// otherwise: opening a movie or a series from the TV home lands in these
/// screens, the entire player overlay is built from lib/widgets/player-buttons/,
/// and the settings tab of the TV home is assembled from the tile widgets below.
/// A sleep-timer countdown was rendering at 9dp on a television.
///
/// They read their sizes through [AppThemes.tenFoot], which keeps the phone
/// value and snaps it onto the scale on TV — so a raw literal here is exactly
/// what this guard is looking for.
const _tvSurfaceFiles = <String>[
  'lib/screens/playlist_type_screen.dart',
  'lib/widgets/player_widget.dart',
  'lib/widgets/video_widget.dart',
  'lib/widgets/player-buttons/video_channel_selector_widget.dart',
  'lib/widgets/player-buttons/video_info_widget.dart',
  'lib/widgets/player-buttons/video_settings_widget.dart',
  'lib/widgets/player-buttons/sleep_timer_widget.dart',
  'lib/screens/movies/movie_screen.dart',
  'lib/screens/series/series_screen.dart',
  'lib/screens/m3u/series/m3u_series_screen.dart',
  'lib/screens/m3u/new_m3u_playlist_screen.dart',
  'lib/widgets/playlist_states.dart',
  'lib/widgets/playlist_card.dart',
  'lib/widgets/playlist_info_widget.dart',
  'lib/widgets/info_tile_widget.dart',
  'lib/widgets/dropdown_tile_widget.dart',
];

/// Every size that reaches a `fontSize:`, whichever way it is written.
///
/// Regexes were tried twice here and both leaked. The first only saw
/// `fontSize: 12`, so a size chosen by a ternary — the exact shape of the
/// nav-rail label that shipped at 10dp and started this guard — was invisible.
/// The second matched conditionals too, but the condition pattern was greedy
/// enough to swallow an EARLIER `fontSize: 9` and report the ternary's healthy
/// arms instead; forbidding `fontSize:` inside the condition just moved the
/// swallow one declaration along. A pattern cannot reliably tell where one
/// value expression ends and the next begins.
///
/// So the value expression is extracted first — everything after `fontSize:`
/// up to the comma that closes it, tracking bracket depth so
/// `AppThemes.tenFoot(context, 12)` is not cut in half — and only then
/// examined. Nothing outside that span can contribute a number.
/// Blanks out `//` comments, keeping every offset intact so reported line
/// numbers stay true.
///
/// Needed because a comment sits between `fontSize:` and its value in several
/// places, and prose contains commas — the extractor below stops at the first
/// top-level comma, so "// Distance, not width" truncated the expression and
/// the ternary after it vanished from the scan. Quotes are tracked so a `//`
/// inside a string (a URL, say) is left alone.
String _withoutComments(String source) {
  final out = StringBuffer();
  var quote = '';
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (quote.isEmpty && (c == "'" || c == '"')) {
      quote = c;
    } else if (quote == c && (i == 0 || source[i - 1] != r'\')) {
      quote = '';
    }
    if (quote.isEmpty && c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      out.write('\n');
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

Iterable<_SizeUse> _sizeUses(String raw) sync* {
  final source = _withoutComments(raw);
  const key = 'fontSize:';
  var at = source.indexOf(key);
  while (at != -1) {
    var i = at + key.length;
    var depth = 0;
    final buf = StringBuffer();
    while (i < source.length) {
      final c = source[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) break;
        depth--;
      }
      if (c == ',' && depth == 0) break;
      if (c == ';') break;
      buf.write(c);
      i++;
    }
    yield _SizeUse(at, buf.toString());
    at = source.indexOf(key, at + key.length);
  }
}

class _SizeUse {
  const _SizeUse(this.offset, this.expression);
  final int offset;
  final String expression;
}

final _number = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)\s*$');
final _conditional = RegExp(
    r'^([\s\S]*?)\?\s*([0-9]+(?:\.[0-9]+)?)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*$');

/// True when the FIRST arm of the conditional is the 10-foot one.
///
/// Knowing which arm is which is what makes the real rule expressible. Without
/// it the guard could only ask "are both arms too small?", and the asymmetric
/// form — a small TV arm beside a larger phone arm — sailed through. That form
/// is not hypothetical: it is precisely the defect quoted at the top of this
/// file, a TV branch rendering smaller than the phone branch beside it.
///
/// Substring matching, which means a NEGATED condition —
/// `!isTenFoot(context) ? 12 : 18` — would be read backwards and reported as a
/// 12dp television. There is none in the codebase today; if one appears, this
/// is the line to fix rather than the call site to work around.
bool _tvArmFirst(String condition) =>
    condition.contains('isTenFoot') ||
    condition.contains('isDesktopOrTV') ||
    RegExp(r'\btv\b').hasMatch(condition);

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
      final source = file.readAsStringSync();
      String where(int offset) =>
          '$path:${'\n'.allMatches(source.substring(0, offset)).length + 1}';

      for (final use in _sizeUses(source)) {
        final plain = _number.firstMatch(use.expression);
        if (plain != null) {
          final size = double.parse(plain.group(1)!);
          if (size < AppThemes.tvBodyMin) {
            offenders.add('${where(use.offset)} → ${size}dp');
          }
          continue;
        }
        final cond = _conditional.firstMatch(use.expression);
        if (cond == null) continue; // a call, a constant, a variable
        final tvArm = double.parse(cond.group(2)!);
        final otherArm = double.parse(cond.group(3)!);
        if (_tvArmFirst(cond.group(1)!)) {
          // The real rule, now that the arms can be told apart: the 10-foot arm
          // must clear the floor AND must not be the smaller of the two.
          if (tvArm < AppThemes.tvBodyMin) {
            offenders.add('${where(use.offset)} → ${tvArm}dp on TV');
          } else if (tvArm < otherArm) {
            offenders.add('${where(use.offset)} → TV arm ${tvArm}dp is smaller '
                'than the phone arm ${otherArm}dp');
          }
        } else if (tvArm < AppThemes.tvBodyMin &&
            otherArm < AppThemes.tvBodyMin) {
          // Unknown condition: fall back to "both arms too small". One arm above
          // the floor is presumably the 10-foot branch and the other the handset
          // value it exists to differ from — `x ? 15 : 13` is a correct pair.
          offenders.add('${where(use.offset)} → ${tvArm}dp / ${otherArm}dp');
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
