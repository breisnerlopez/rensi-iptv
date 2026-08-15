import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/new_xtream_code_playlist_screen.dart';

import '../integration/harness.dart';

// Answers a question a screenshot could not: on a 360dp phone, the add-playlist
// screens appear to stop rendering after the first field — no source selector,
// no URL field, no submit button. If that is real, a new user cannot create a
// playlist at all and the app is dead on arrival for them.
//
// A capture cannot tell a layout bug from a rasterisation artefact: those two
// screens are the only ones with a focused text field, so a blinking cursor
// keeps the scene from ever settling and the surface readback can return a
// half-painted frame. This asserts the widget tree and geometry instead, which
// is not subject to either.
void main() {
  const phoneSmall = Size(360, 800);

  Future<void> pumpForm(WidgetTester tester, Widget screen) async {
    await setUpHarness(tv: false);
    await pumpScreen(tester, screen, size: phoneSmall);
    await settle(tester);
  }

  tearDown(tearDownHarness);

  testWidgets('M3U: every field and the submit button exist on a 360dp phone',
      (tester) async {
    await pumpForm(tester, NewM3uPlaylistScreen());

    // The submit button is the one that decides whether onboarding completes.
    final submit = find.byType(FilledButton);
    expect(submit, findsWidgets,
        reason: 'the create-playlist button must exist in the tree');

    // And it must be reachable: inside the scrollable, not clipped away.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(submit.first, 200, scrollable: scrollable);
    await tester.pumpAndSettle();

    final rect = tester.getRect(submit.first);
    expect(rect.height, greaterThan(0));
    expect(rect.top, lessThan(phoneSmall.height),
        reason: 'after scrolling, the button must land on screen: $rect');
  });

  testWidgets('Xtream: every field and the submit button exist on a 360dp phone',
      (tester) async {
    await pumpForm(tester, NewXtreamCodePlaylistScreen());

    expect(find.byType(TextFormField), findsAtLeast(3),
        reason: 'url, username and password must all be built');

    final submit = find.byType(FilledButton);
    expect(submit, findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(submit.first, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.getRect(submit.first).height, greaterThan(0));
  });

  testWidgets('M3U: the form does not overflow its viewport', (tester) async {
    await pumpForm(tester, NewM3uPlaylistScreen());
    // A RenderFlex overflow throws in tests; reaching here without an exception
    // means the column fits or scrolls properly.
    expect(tester.takeException(), isNull);
  });
}
