import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/screens/settings/general_settings_section.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import 'harness.dart';
import 'seed.dart';

// "Limpiar todo el historial" en Ajustes es la ÚNICA forma que le queda al
// usuario de sacar su historial de visionado de la base de datos: la poda se
// llevó la pantalla de historial, que era el único llamador de clearAllHistory.
// En un aparato compartido —un televisor lo es por definición— eso la convierte
// en una superficie de privacidad, y no tenía ni un test: `grep -rl
// "clearAllHistory" test/` no devolvía nada.
//
// Confirmar un borrado que no ocurre es el peor resultado posible aquí, así que
// el guard afirma las dos mitades: que las filas se van, y que lo que se anuncia
// en pantalla es lo que de verdad pasó.
Future<void> _writeHistory(String playlistId, String streamId) =>
    WatchHistoryService().saveWatchHistory(WatchHistory(
      playlistId: playlistId,
      contentType: ContentType.vod,
      streamId: streamId,
      title: 'Título $streamId',
      imagePath: '',
      lastWatched: DateTime(2026, 7, 1),
      watchDuration: const Duration(minutes: 30),
      totalDuration: const Duration(minutes: 120),
    ));

Future<int> _rowCount() async =>
    (await harnessDb.select(harnessDb.watchHistories).get()).length;

void main() {
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Ajustes: confirmar "limpiar todo" vacía el historial y lo dice',
      (tester) async {
    await tester.runAsync(() async {
      final p = await seedXtreamHome(harnessDb);
      AppState.currentPlaylist = p;
      await _writeHistory(p.id, 'vod_1_movie_0');
      await _writeHistory(p.id, 'vod_1_movie_1');
      // Otra lista: "limpiar todo" es global a propósito, así que esta fila
      // también debe irse. Está aquí para que el alcance quede fijado por un
      // test en vez de por una suposición.
      await _writeHistory('otra-lista', 'vod_9_movie_9');
    });
    expect(await _rowCount(), 3,
        reason: 'precondición: tiene que haber algo que borrar');

    // Igual que la pantalla real (m3u_playlist_settings_screen.dart:52): el
    // widget está pensado para vivir dentro de un scrollable. Montarlo desnudo
    // desborda la Column 1625px y el toque en la tarjeta ni llega.
    await pumpScreen(tester, const _SettingsHost());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final tile = find.text('Limpiar todo el historial');
    await tester.ensureVisible(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(tile.first);
    await tester.pumpAndSettle();

    // El diálogo usa la MISMA cadena para el título y para el botón de
    // confirmar, así que buscarla dentro del AlertDialog da dos resultados.
    // Hay que apuntar al botón.
    await tester.tap(
      find.widgetWithText(TextButton, 'Limpiar todo el historial'),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(await _rowCount(), 0,
        reason: 'confirmar el borrado debe vaciar watch_histories');
    expect(find.text('Historial de reproducción borrado'), findsOneWidget,
        reason: 'el usuario tiene que ver confirmado lo que realmente pasó, no '
            'el título de la propia acción');
  });

  testWidgets('Ajustes: cancelar no borra nada', (tester) async {
    await tester.runAsync(() async {
      final p = await seedXtreamHome(harnessDb);
      AppState.currentPlaylist = p;
      await _writeHistory(p.id, 'vod_1_movie_0');
    });

    // Igual que la pantalla real (m3u_playlist_settings_screen.dart:52): el
    // widget está pensado para vivir dentro de un scrollable. Montarlo desnudo
    // desborda la Column 1625px y el toque en la tarjeta ni llega.
    await pumpScreen(tester, const _SettingsHost());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final tile = find.text('Limpiar todo el historial');
    await tester.ensureVisible(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(tile.first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(await _rowCount(), 1,
        reason: 'un diálogo cancelado no puede borrar datos');
  });
}

class _SettingsHost extends StatelessWidget {
  const _SettingsHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          children: const [GeneralSettingsWidget()],
        ),
      );
}
