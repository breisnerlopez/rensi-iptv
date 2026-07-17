// REAL-HARDWARE Android-TV navigation — RUN ON A REAL ANDROID TV DEVICE /
// EMULATOR. Boots the seeded home and drives it with REAL D-pad events: hero
// focus, rail reachability and tab switching. (The app's Android-only plugins
// prevent this from running on the Linux desktop engine; on-device it renders
// and processes the remote for real.)
//
// Run:  flutter test integration_test/tv_nav_test.dart -d <android-device>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import '../test/integration/harness.dart';
import '../test/integration/seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  setUp(() => setUpHarness()); // tv = true
  tearDown(tearDownHarness);

  testWidgets('TV real: onboarding pinta en el engine real', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen());
    await settle(tester);
    // Clean-install onboarding shows the empty state / add-playlist affordance.
    expect(find.byType(AppInitializerScreen), findsOneWidget);
  });

  testWidgets('TV real: home sembrado — foco al hero, rail alcanzable, cambio de pestaña con mando',
      (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);

    // 1) Hero takes initial focus (commercial TV behaviour).
    expect(focusedInfo(), contains('Comenzar a ver'),
        reason: 'el foco inicial debe caer en el hero');

    // 2) The side rail is reachable with LEFT (real DPAD event on the real engine).
    await left(tester);
    bool onRail() => ['Inicio', 'Explorar', 'vivo', 'lista', 'Configuración']
        .any((s) => focusedInfo().contains(s));
    expect(onRail(), isTrue, reason: 'el rail debe alcanzarse con LEFT');

    // 3) Move to "En vivo" and activate it; seeded live channels appear.
    for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
      await up(tester);
    }
    for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
      await down(tester);
    }
    await ok(tester);
    await settle(tester);
    expect(tester.any(find.text('ESPN')), isTrue,
        reason: 'cambiar a En vivo debe mostrar los canales sembrados');
  });
}
