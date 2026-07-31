import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';

import 'harness.dart';

// RENDIMIENTO (stutter de interacción): "Explorar" (BrowseRedesign) vive en un
// IndexedStack bajo un Consumer, así que cada notifyListeners lo reconstruía y
// re-aplanaba+deduplicaba+regex TODO el catálogo, aunque estuviera off-screen —
// un freeze corto al tocar pestañas/filtros en una caja TV débil. Este test
// prueba con render real que ahora el catálogo se memoiza: los rebuilds sin
// cambios (y los cambios de pestaña) NO re-aplanan; solo un cambio real del
// catálogo lo hace.
CategoryViewModel _cat(String id, int n, {String prefix = 'm'}) => CategoryViewModel(
      category: Category(
        categoryId: id,
        categoryName: 'Cat $id',
        parentId: 0,
        playlistId: 'pl',
        type: CategoryType.vod,
      ),
      contentItems: List.generate(
        n,
        (i) => ContentItem('${prefix}_${id}_$i', 'Item $prefix $id $i', '',
            ContentType.vod),
      ),
    );

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets(
      'BrowseRedesign memoiza el catálogo: rebuilds y cambios de pestaña no re-aplanan',
      (tester) async {
    AppState.currentPlaylist = Playlist(
      id: 'pl',
      name: 'PL',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
    );

    final movieCats = [_cat('a', 30), _cat('b', 30)];
    final seriesCats = [_cat('s', 20, prefix: 's')];
    late StateSetter setParent;

    await pumpScreen(
      tester,
      StatefulBuilder(builder: (ctx, setState) {
        setParent = setState;
        return BrowseRedesign(
          movieCategories: movieCats,
          seriesCategories: seriesCats,
          onOpen: (_) async {},
        );
      }),
    );
    await settle(tester);

    final state = tester.state(find.byType(BrowseRedesign)) as dynamic;
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, 1,
        reason: 'la primera construcción aplana el catálogo una vez');
    expect(find.byType(RensiPoster), findsWidgets,
        reason: 'la cuadrícula de Explorar renderiza pósters');

    // 1) Cinco rebuilds del padre con los MISMOS datos (simula notifyListeners
    //    no relacionados) NO deben re-aplanar.
    for (var i = 0; i < 5; i++) {
      setParent(() {});
      await tester.pump();
    }
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, 1,
        reason: 'rebuilds sin cambios del catálogo no deben re-aplanar');

    // 2) Cambiar de pestaña (setState interno) tampoco re-aplana.
    await tester.tap(find.text('Series'));
    await settle(tester);
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, 1,
        reason: 'cambiar de pestaña usa listas memoizadas, no re-aplana');
    await tester.tap(find.text('Todo'));
    await settle(tester);
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, 1,
        reason: 'volver de pestaña sigue usando la memoización');

    // 3) Un cambio REAL del catálogo (llegan más ítems, como en la carga
    //    progresiva) SÍ debe recomputar exactamente una vez más.
    movieCats[0].contentItems.add(
        ContentItem('m_a_new', 'Nuevo', '', ContentType.vod));
    setParent(() {});
    await settle(tester);
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, 2,
        reason: 'un cambio real del catálogo debe recomputar (frescura)');

    // 4) Recarga con el MISMO conteo pero contenido distinto: el controller crea
    //    CategoryViewModel FRESCOS al recargar, así que la firma (que incluye la
    //    identidad del objeto) debe detectarlo aunque los conteos coincidan — el
    //    hueco de caché rancia que una firma solo-por-conteo dejaría abierto.
    final beforeReload = state.recomputes as int; // == 2 tras el paso 3
    movieCats[0] = _cat('a', 31); // nuevo objeto, mismo conteo (31), otros ítems
    setParent(() {});
    await settle(tester);
    // ignore: avoid_dynamic_calls
    expect(state.recomputes, beforeReload + 1,
        reason: 'un CategoryViewModel nuevo (recarga) debe recomputar aunque el conteo no cambie');

    expect(tester.takeException(), isNull,
        reason: 'la memoización no debe romper el render');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
