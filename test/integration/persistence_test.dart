import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import 'harness.dart';
import 'seed.dart';

void main() {
  setUpAll(loadFonts);
  tearDown(tearDownHarness);

  testWidgets('Persistencia: la última playlist restaura su home al reiniciar',
      (tester) async {
    // Simula un reinicio: prefs ya tienen last_playlist de una sesión previa.
    await setUpHarness(prefs: {'last_playlist': 'test-playlist-1'});
    await tester.runAsync(() async {
      await seedXtreamHome(harnessDb);
    });

    await pumpScreen(tester, const AppInitializerScreen());
    await settle(tester);
    await shot(tester, 'persist_1_restored_home.png');

    expect(find.byType(XtreamCodeHomeScreen), findsOneWidget,
        reason: 'debe restaurar el home de la última playlist, no volver a la pantalla de listas');
    expect(find.byType(PlaylistScreen), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Recuperación: una playlist SIN contenido no crashea el home',
      (tester) async {
    await setUpHarness();
    late Playlist p;
    await tester.runAsync(() async {
      // Solo la playlist, sin categorías/streams.
      p = Playlist(
        id: 'empty-1',
        name: 'Lista Vacía',
        type: PlaylistType.xtream,
        url: 'http://example.test',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026, 1, 1),
      );
      await harnessDb.insertPlaylist(p);
    });

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);
    await shot(tester, 'recover_1_empty_home.png');

    // No debe lanzar excepción; la pantalla se renderiza.
    expect(tester.takeException(), isNull,
        reason: 'el home de una playlist vacía no debe crashear');
    expect(find.byType(XtreamCodeHomeScreen), findsOneWidget);
    // Estado vacío decente (no un "—" en blanco) + foco garantizado.
    expect(find.textContaining('No hay películas'), findsOneWidget,
        reason: 'debe mostrar un estado vacío útil, no un placeholder en blanco');
    expect(focusedInfo(), contains('Buscar'),
        reason: 'el mando debe tener un objetivo de foco en el home vacío');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
