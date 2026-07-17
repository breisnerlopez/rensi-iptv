import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import 'harness.dart';
import 'seed.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Home Xtream poblado — navegable con mando', (tester) async {
    late Playlist p;
    await tester.runAsync(() async {
      p = await seedXtreamHome(harnessDb);
    });

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);
    await shot(tester, 'home_1_populated.png');
    debugPrint('HOME entry focus=${focusedInfo()}');

    // The content should be visible: assert a seeded channel/movie is on screen.
    debugPrint('ESPN present=${tester.any(find.text('ESPN'))}');
    debugPrint('Deportes present=${tester.any(find.text('Deportes'))}');

    // 1) Hero takes initial focus (commercial TV behaviour).
    expect(focusedInfo(), contains('Comenzar a ver'),
        reason: 'el foco inicial debe caer en el hero, no en el rail');

    // 2) The side rail is reachable with LEFT.
    await left(tester);
    bool onRail() => ['Inicio', 'Explorar', 'vivo', 'lista', 'Configuración']
        .any((s) => focusedInfo().contains(s));
    expect(onRail(), isTrue, reason: 'el rail debe alcanzarse con LEFT');
    await shot(tester, 'home_2_rail.png');

    // 3) Navigate the rail to "En vivo" and switch tab; live content appears.
    for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
      await up(tester);
    }
    for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
      await down(tester);
    }
    debugPrint('rail focus before OK=${focusedInfo()}');
    await ok(tester);
    await settle(tester);
    await shot(tester, 'home_3_live_tab.png');
    debugPrint('ESPN present after switch=${tester.any(find.text('ESPN'))}');
    expect(tester.any(find.text('ESPN')), isTrue,
        reason: 'cambiar a En vivo debe mostrar canales sembrados');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Cambio de pestaña programático (avatar → Ajustes) no pierde foco',
      (tester) async {
    late Playlist p;
    await tester.runAsync(() async {
      p = await seedXtreamHome(harnessDb);
    });
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);
    expect(focusedInfo(), contains('Comenzar a ver'),
        reason: 'foco inicial en el contenido');

    // El avatar "A" dispara onSettings → onNavigationTap(4) sin pasar por el rail.
    await tester.tap(find.text('A'));
    await settle(tester);
    debugPrint('tras avatar→Ajustes focus=${focusedInfo()}');
    expect(focusedInfo(), contains('Configuración'),
        reason: 'tras el cambio programático el foco debe caer en el rail, no perderse');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
