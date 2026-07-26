// Focused on-device render check for the v2.2.2 home changes (Feature B's
// refresh-line wrapper + the auditor's rail-duplication fix). Seeds the DB and
// photographs the real XtreamCodeHomeScreen at the device's native resolution —
// no network, no credentials, and (unlike capture_test) no MediaKit/libmpv, so
// it can't hang on the player captures.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/homecheck_test.dart -d <device> --profile \
//     --dart-define=CAPTURE_PREFIX=phone_compact
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import '../test/integration/harness.dart';
import '../test/integration/seed.dart';

const String prefix =
    String.fromEnvironment('CAPTURE_PREFIX', defaultValue: 'dev');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await binding.convertFlutterSurfaceToImage();
  });

  // tv: null → let the device answer the TV-detection channel for itself, so a
  // TV run renders the 10-foot UI and a phone run the mobile one.
  setUp(() => setUpHarness(tv: null));
  tearDown(tearDownHarness);

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await binding.takeScreenshot('${prefix}_$name');
  }

  testWidgets('home — populated, hero focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await capture(tester, 'home_hero');
  });

  testWidgets('home — focus down into a rail', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await moveFocus(tester, TraversalDirection.down, times: 2);
    await settle(tester);
    await capture(tester, 'home_rail');
  });

  testWidgets('home — settings tab', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(
      tester,
      XtreamCodeHomeScreen(playlist: p, initialIndex: 4),
      size: null,
    );
    await settle(tester);
    await capture(tester, 'settings');
  });
}
