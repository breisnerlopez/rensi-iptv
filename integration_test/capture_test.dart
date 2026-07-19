// Screenshot campaign: drives the REAL app on a real device and captures each
// screen at the device's native resolution.
//
// Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/capture_test.dart -d <device> --profile
//
// Uses the seeded in-memory database, so it produces a populated UI with NO
// credentials anywhere on the machine. Every capture is taken with focus placed
// deliberately — on a 10-foot UI the focus state *is* the design, and a
// screenshot without it hides the most failure-prone part of the interface.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import '../test/integration/harness.dart';
import '../test/integration/seed.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Required on Android before takeScreenshot: swaps the render surface for
    // one that can be read back.
    await binding.convertFlutterSurfaceToImage();
  });

  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await binding.takeScreenshot(name);
  }

  testWidgets('01 onboarding', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen(), size: null);
    await settle(tester);
    await capture(tester, 'tv_01_onboarding');
  });

  testWidgets('02 playlist type', (tester) async {
    await pumpScreen(tester, const PlaylistTypeScreen(), size: null);
    await settle(tester);
    await capture(tester, 'tv_02_playlist_type');
  });

  testWidgets('03 home — hero focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await capture(tester, 'tv_03_home_hero');
  });

  testWidgets('04 home — focus moved into a rail', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await down(tester, times: 2);
    await settle(tester);
    await capture(tester, 'tv_04_home_rail');
  });

  testWidgets('05 side rail focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await left(tester);
    await settle(tester);
    await capture(tester, 'tv_05_side_rail');
  });

  testWidgets('06 live tab', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await left(tester);
    for (var i = 0; i < 6 && !focusedInfo().toLowerCase().contains('vivo'); i++) {
      await down(tester);
    }
    await ok(tester);
    await settle(tester);
    await capture(tester, 'tv_06_live');
  });
}
