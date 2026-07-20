import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// AppThemes.tenFoot is the single place that decides how a phone-tuned size is
// promoted for a television. Forty-six literals across the player overlay and
// the settings tab now route through it, so a silent change here is a silent
// change to all of them.
Future<double> _resolve(WidgetTester tester,
    {required double phone,
    required Size size,
    bool? directional}) async {
  late double out;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Directional navigation IS the 10-foot signal now, and width is not part of
  // it. Simulating a television by making the window wide used to work and no
  // longer does — on purpose: a large phone in landscape is ~1010dp and is read
  // at arm's length, so type must not key off width the way layout does.
  final tenFoot = directional ?? (size.width >= 900);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (outer) {
      return MediaQuery(
        data: MediaQuery.of(outer).copyWith(
          navigationMode:
              tenFoot ? NavigationMode.directional : NavigationMode.traditional,
        ),
        child: Builder(builder: (context) {
          out = AppThemes.tenFoot(context, phone);
          return const SizedBox.shrink();
        }),
      );
    }),
  ));
  return out;
}

void main() {
  // A 1080p Android TV reports 960x540 LOGICAL dp, not 1920x1080. Thresholds
  // written in pixel-sized numbers never bind, which is how the nav rail shipped
  // 10dp labels behind a 1200dp branch that a television never reaches.
  // A television-sized window. The size itself no longer selects the 10-foot
  // branch — _resolve injects NavigationMode.directional for these cases — so
  // this constant now only shapes the layout, not the decision. Said plainly
  // because the previous comment claimed the 900dp width was what triggered it,
  // which stopped being true the moment type stopped keying off width.
  const tv = Size(960, 540);
  const phone = Size(360, 800);
  // A large handset in landscape — an S23 Ultra reports ~1010dp — and the width
  // at which a foldable opens. The player overlay lives here, and it is still
  // held at arm's length.
  const phoneLandscape = Size(1010, 460);

  testWidgets('a phone keeps every size exactly as authored', (tester) async {
    for (final s in [9.0, 11.0, 12.0, 13.0, 15.0, 18.0, 24.0]) {
      expect(await _resolve(tester, phone: s, size: phone), s,
          reason: 'promoting sizes on a handset would bloat a layout that was '
              'tuned at 30 cm');
    }
  });

  testWidgets('a wide window is not a television', (tester) async {
    // The distinction this whole helper turns on. Keying the promotion off
    // ResponsiveHelper.isDesktopOrTV — which says yes to anything 900dp wide —
    // gave 10-foot type to every large phone in landscape and every desktop
    // window, and no test noticed because the only phone case was 360dp
    // portrait. Layout may key off width; type keys off viewing distance.
    for (final s in [9.0, 12.0, 13.0, 15.0]) {
      expect(
          await _resolve(tester,
              phone: s, size: phoneLandscape, directional: false),
          s,
          reason: '${s}dp was promoted on a 1010dp window with traditional '
              'navigation — that is a phone held sideways, not a panel across '
              'the room');
    }
  });

  testWidgets('a television lifts everything to the readable floor',
      (tester) async {
    for (final s in [9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0]) {
      final got = await _resolve(tester, phone: s, size: tv);
      expect(got, greaterThanOrEqualTo(AppThemes.tvBodyMin),
          reason: '${s}dp resolved to ${got}dp, which is decoration at 3 m');
    }
  });

  testWidgets('the mapping is monotonic and lands on real scale steps',
      (tester) async {
    // A list, not a const Set: doubles have no primitive equality in Dart, so
    // a const Set of them does not compile.
    const scale = <double>[
      AppThemes.labelSize,
      AppThemes.bodySmallSize,
      AppThemes.bodySize,
    ];
    double previous = 0;
    // 15, 16, 17 and 17.5 are in this list deliberately. The earlier version
    // stopped at 16 and the "already on the scale" test started at 18, so the
    // only place the mapping could dip — 16 promoted to 18 while 17 stayed 17 —
    // was the one place nothing looked.
    for (final s in [9.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 17.5]) {
      final got = await _resolve(tester, phone: s, size: tv);
      expect(scale, contains(got),
          reason: '${s}dp resolved to ${got}dp, which is not a step of the '
              'scale — the arbitrary numbers this mapping exists to remove');
      // Monotonic: if a bigger phone size came out smaller, the mapping would
      // invert the hierarchy the original author expressed.
      expect(got, greaterThanOrEqualTo(previous),
          reason: 'the mapping inverted the type hierarchy at ${s}dp');
      previous = got;
    }
  });

  testWidgets('the promotion preserves the hierarchy it was given',
      (tester) async {
    // Without this the mapping can be flattened to a single value and every
    // other test here still passes: a phone is untouched, everything clears the
    // floor, every result is a scale step, and a constant is trivially
    // monotonic. Mutation proved that — `if (phone <= 16) return bodySize`
    // destroys the whole ladder and stays green. What a promotion must actually
    // guarantee is that a caption stays smaller than body text.
    final caption = await _resolve(tester, phone: 11, size: tv);
    final secondary = await _resolve(tester, phone: 13, size: tv);
    final primary = await _resolve(tester, phone: 15, size: tv);
    expect(caption, lessThan(secondary),
        reason: 'a caption and secondary text collapsed to the same size');
    expect(secondary, lessThan(primary),
        reason: 'secondary and primary text collapsed to the same size');
  });

  testWidgets('sizes already on the scale are left untouched', (tester) async {
    for (final s in [18.0, 22.0, 28.0, 36.0, 52.0]) {
      expect(await _resolve(tester, phone: s, size: tv), s,
          reason: 'a heading that already sized itself for the 10-foot scale '
              'must not be rewritten');
    }
  });
}
