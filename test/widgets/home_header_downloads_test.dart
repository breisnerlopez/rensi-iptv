// Acceso directo a Descargas en el header del Inicio (móvil-only). Verifica lo
// que el gate marcó como no-testeado: (a) el header NO desborda a 320dp con un
// nombre de lista largo, (b) el ícono de Descargas aparece en móvil y NO en el
// ancho de rail (>=600dp), donde Descargas vive en Ajustes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';

import '../integration/harness.dart';

void main() {
  setUpAll(loadFonts);
  // tv:false → layout MÓVIL (el harness por defecto simula TV, que fuerza el
  // rail y ocultaría el ícono de Descargas). currentPlaylist se fija en cada
  // test (setUpHarness la resetea a null).
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);

  void seedPlaylist() => AppState.currentPlaylist = Playlist(
        id: 'pl',
        name: 'PL',
        type: PlaylistType.xtream,
        createdAt: DateTime(2026, 1, 1),
      );

  RedesignHome home() => RedesignHome(
        movieCategories: const [],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
        onResume: (_) {},
        onRemove: (_) {},
        onDownloads: () {},
        // Nombre de lista deliberadamente largo para estresar el header.
        playlistSwitcher: const SizedBox(
          width: 160,
          child: Text(
            'Una lista con un nombre larguísimo para estresar el header',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  testWidgets('móvil angosto (320dp): el header NO desborda y muestra Descargas',
      (tester) async {
    seedPlaylist();
    await pumpScreen(tester, home(), size: const Size(320, 800));
    expect(tester.takeException(), isNull,
        reason: 'el header no debe lanzar RenderFlex overflow a 320dp');
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget,
        reason: 'en móvil (bottom bar) el acceso directo a Descargas se muestra');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('ancho de rail (>=600dp): Descargas NO aparece en el header',
      (tester) async {
    seedPlaylist();
    await pumpScreen(tester, home(), size: const Size(800, 800));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsNothing,
        reason: 'en tablet/TV (rail) no hay ícono de Descargas en el header');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
