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
    bool onRail() => ['Inicio', 'Explorar', 'vivo', 'lista', 'Ajustes']
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

  testWidgets('Ajustes se alcanza desde el rail y el foco no se pierde',
      (tester) async {
    // Antes esto se probaba tocando un avatar "A" de la barra superior. Ese
    // avatar se eliminó: era una segunda puerta a Ajustes, que el rail ya tiene,
    // y sugería una identidad de usuario que la app no maneja. El destino real
    // es el rail, así que es el rail lo que hay que probar.
    late Playlist p;
    await tester.runAsync(() async {
      p = await seedXtreamHome(harnessDb);
    });
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);
    expect(focusedInfo(), contains('Comenzar a ver'),
        reason: 'foco inicial en el contenido');

    await tester.tap(find.text('Ajustes'), warnIfMissed: false);
    await settle(tester);
    debugPrint('tras rail→Ajustes focus=${focusedInfo()}');
    expect(focusedInfo(), contains('Ajustes'),
        reason: 'tras el cambio el foco debe quedarse en el rail, no perderse');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
