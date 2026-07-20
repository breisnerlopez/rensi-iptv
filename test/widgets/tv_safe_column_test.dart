import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

// RensiSafeColumn keeps content — and, critically, the focus ring — inside a
// TV's overscan margin.
//
// The sizes are the *logical* ones real hardware reports, which is the whole
// point: a 1080p Android TV is 960x540 dp (dpr 2.0 @320dpi), and a 4K panel
// reports the same 960 dp, so a cap written in pixel-sized numbers never binds.
// On top of that, FocusHighlight scales a focused element by
// ResponsiveHelper.focusZoom, so content that merely fits the safe area grows
// back out of it the moment it takes focus.
void main() {
  const overscan = ResponsiveHelper.overscanFraction;

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    NavigationMode navigationMode = NavigationMode.traditional,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: navigationMode),
          child: widget!,
        ),
        home: Scaffold(body: RensiSafeColumn(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Measures the REAL painted rect of a focused element, not a computed number:
  // an assertion derived from the same formula as the code would only restate it.
  group('a genuinely focused element stays on the picture', () {
    for (final entry in {
      '1080p / 4K TV (960dp)': const Size(960, 540),
      'wide TV surface (1280dp)': const Size(1280, 720),
      'ultra-wide (1920dp)': const Size(1920, 1080),
    }.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpAt(
          tester,
          entry.value,
          FocusHighlight(
            child: Material(
              child: InkWell(
                autofocus: true,
                onTap: () {},
                child: const SizedBox(height: 120, key: Key('tile')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 400));

        final rect = tester.getRect(find.byKey(const Key('tile')));
        final screen = entry.value.width;
        final leftMargin = rect.left;
        final rightMargin = screen - rect.right;

        expect(leftMargin, greaterThanOrEqualTo(screen * overscan),
            reason: 'left edge inside overscan: rect=$rect screen=$screen');
        expect(rightMargin, greaterThanOrEqualTo(screen * overscan),
            reason: 'right edge inside overscan: rect=$rect screen=$screen');
      });
    }
  });

  testWidgets('content narrower than the cap is left alone', (tester) async {
    await pumpAt(
      tester,
      const Size(960, 540),
      const Center(child: SizedBox(width: 200, height: 50, key: Key('small'))),
    );
    expect(tester.getSize(find.byKey(const Key('small'))).width, 200);
  });

  testWidgets('a phone paired with a remote does not get a TV margin',
      (tester) async {
    // navigationMode.directional makes isDesktopOrTV true even on a 360dp
    // phone. Reserving a full TV overscan margin there would throw away a third
    // of the screen for a device that has no overscan at all.
    await pumpAt(
      tester,
      const Size(360, 780),
      Container(key: const Key('content'), color: Colors.red),
      navigationMode: NavigationMode.directional,
    );
    final w = tester.getSize(find.byKey(const Key('content'))).width;
    expect(w, greaterThan(360 * 0.7),
        reason: 'a narrow directional surface must keep most of its width, got $w');
  });

  testWidgets('a plain phone keeps its usual margin', (tester) async {
    await pumpAt(tester, const Size(400, 820),
        Container(key: const Key('content'), color: Colors.red));
    expect(tester.getSize(find.byKey(const Key('content'))).width, 352,
        reason: '400 minus the 24dp phone inset on each side');
  });
}
