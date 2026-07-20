import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/widgets/category_detail/content_grid.dart';

import 'harness.dart';

// RENDIMIENTO (jank de scroll): la fuente #1 de tirones en una caja de Android TV
// es construir cientos de celdas de golpe. Este test prueba con render real que
// la cuadrícula de contenido VIRTUALIZA: con 240 ítems solo construye un puñado
// (viewport + cacheExtent), y al hacer scroll con eventos reales recicla las
// celdas sin excepciones ni overflow. Es la evidencia headless de que el catálogo
// grande se desplaza fluido (los píxeles/raster reales siguen necesitando GPU).
List<ContentItem> _items(int n) => List.generate(
      n,
      (i) => ContentItem('id_$i', 'Item $i', '', ContentType.vod),
    );

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness()); // tv:true → layout 10-foot
  tearDown(tearDownHarness);

  testWidgets('La cuadrícula virtualiza 240 ítems y recicla al hacer scroll',
      (tester) async {
    // ContentItem's constructor reads the active playlist type.
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
    );
    const total = 240;
    final items = _items(total);
    var tapped = '';

    await pumpScreen(
      tester,
      Scaffold(
        body: ContentGrid(
          items: items,
          onItemTap: (it) => tapped = it.name,
        ),
      ),
    );
    await settle(tester);

    // 1) Virtualización: NO se construyen las 240 celdas, solo las visibles +
    //    cacheExtent. Un número acotado prueba que GridView.builder recicla.
    final built = find.byType(RensiPoster).evaluate().length;
    debugPrint('VIRT posters construidos al entrar=$built de $total');
    expect(built, lessThan(100),
        reason: 'la cuadrícula debe virtualizar (no construir los 240 a la vez)');
    expect(built, greaterThan(0), reason: 'debe renderizar la primera pantalla');
    expect(find.text('Item 0'), findsWidgets,
        reason: 'el primer ítem es visible al entrar');
    expect(find.text('Item 230'), findsNothing,
        reason: 'un ítem lejano NO se construye al entrar (virtualización)');

    // 2) Scroll con gesto real: bajar mucho. Debe reciclar sin excepción y traer
    //    ítems lejanos a la vez que descarta los de arriba.
    await tester.drag(find.byType(GridView), const Offset(0, -4000));
    await settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'hacer scroll de un catálogo grande no debe lanzar excepción');

    final builtAfter = find.byType(RensiPoster).evaluate().length;
    debugPrint('VIRT posters construidos tras scroll=$builtAfter');
    expect(builtAfter, lessThan(100),
        reason: 'tras scroll el conteo sigue acotado (siguió virtualizando)');
    expect(find.text('Item 0'), findsNothing,
        reason: 'el primer ítem se recicló al desplazarse fuera de vista');
    expect(find.byType(RensiPoster), findsWidgets,
        reason: 'sigue habiendo celdas renderizadas tras el scroll');

    // 3) Interacción con mando: OK sobre una celda enfocada dispara el tap.
    // ensureVisible primero: el número de columnas depende del ancho, así que
    // "el primer póster del árbol" puede estar parcialmente fuera del viewport
    // y el toque caería fuera de él.
    final cell = find.byType(RensiPoster).first;
    await tester.ensureVisible(cell);
    await settle(tester);
    await tester.tap(cell);
    await settle(tester);
    expect(tapped, isNotEmpty, reason: 'tocar una celda debe invocar onItemTap');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
