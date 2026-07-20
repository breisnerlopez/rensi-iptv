import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';

import '../integration/harness.dart';

// The privacy notice on "Select playlist type" sits below the fold on a 540dp
// TV surface. It is not interactive, so it used to be no focus target at all:
// pressing DOWN from the last card had nowhere to go, Scrollable.ensureVisible
// never fired, and the notice was unreachable with a remote — a privacy message
// permanently truncated right before the app asks for provider credentials.
//
// 960x540 is what a 1080p Android TV actually reports (dpr 2.0 @320dpi), which
// is why this is pinned at that size and not at some rounder number.
void main() {
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('the privacy notice is reachable with the D-pad on a TV surface',
      (tester) async {
    await pumpScreen(tester, const PlaylistTypeScreen(),
        size: const Size(960, 540));
    await settle(tester);

    final notice = find.textContaining('segura', findRichText: true);
    expect(notice, findsOneWidget, reason: 'the notice must exist in the tree');

    // Walk down the way a remote does.
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await settle(tester);

    final rect = tester.getRect(notice);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(rect.bottom, lessThanOrEqualTo(screen),
        reason: 'after D-pad travel the notice must be on screen, got $rect '
            'on a ${screen}dp-tall surface');
  });
}
