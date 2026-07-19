import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';

import 'harness.dart';

// RENDIMIENTO / escala: "Inicio" con un catálogo grande (40 categorías).
// Prueba la GANANCIA REAL del refactor a ListView.builder + _CategoryRail: la
// construcción de cada rail (SectionHeader + RensiRail + 18 pósters) se DIFIERE
// hasta acercarse al viewport. Se mide con el contador `RedesignHome.debugRailBuilds`
// (nº de _CategoryRail.build ejecutados) — esto SÍ distingue el refactor del
// original (que construía las 40 en cada build); contar Elements montados no lo
// haría, porque el montaje de slivers ya era perezoso en ambas variantes.
CategoryViewModel _cat(String id, int n) => CategoryViewModel(
      category: Category(
        categoryId: id,
        categoryName: 'Categoría $id',
        parentId: 0,
        playlistId: 'pl',
        type: CategoryType.vod,
      ),
      contentItems: List.generate(
        n,
        (i) => ContentItem('${id}_$i', 'Peli $id $i', '', ContentType.vod),
      ),
    );

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Inicio con 40 categorías virtualiza y no crashea',
      (tester) async {
    AppState.currentPlaylist = Playlist(
      id: 'pl',
      name: 'PL',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
    );
    final movieCats = [for (var i = 0; i < 40; i++) _cat('c$i', 12)];

    RedesignHome.debugRailBuilds = 0;
    await pumpScreen(
      tester,
      RedesignHome(
        movieCategories: movieCats,
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull,
        reason: 'un catálogo grande no debe crashear Inicio');

    // Deferral (la ganancia real): solo se CONSTRUYEN los rails cercanos al
    // viewport, no los 40. El original habría construido las 40 aquí.
    final builtAtEntry = RedesignHome.debugRailBuilds;
    debugPrint('SCALE rails construidos al entrar=$builtAtEntry de 40');
    expect(builtAtEntry, lessThan(40),
        reason: 'Inicio debe DIFERIR la construcción de rails, no construir los 40');
    expect(builtAtEntry, greaterThan(0), reason: 'debe construir los primeros rails');
    // Sanity: los mismos rails están montados (virtualización de elementos).
    expect(find.byType(RensiRail), findsWidgets);

    // Navegación con MANDO real (D-pad abajo): baja el foco por Inicio; a medida
    // que entran rails al viewport se construyen bajo demanda (el contador sube).
    await down(tester, times: 12);
    await settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'navegar Inicio grande con el mando no debe lanzar');
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: 'el foco no debe perderse navegando con el mando');
    final builtAfterNav = RedesignHome.debugRailBuilds;
    debugPrint('SCALE rails construidos tras D-pad=$builtAfterNav');
    expect(builtAfterNav, greaterThan(builtAtEntry),
        reason: 'bajar con el mando debe construir más rails bajo demanda (perezoso)');
    expect(builtAfterNav, lessThanOrEqualTo(40),
        reason: 'nunca se construyen más de las 40 categorías');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
