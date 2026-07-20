import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';

import '../integration/harness.dart';

// The continue-watching rail.
//
// It shipped with the redesign and has never appeared in the app: the parameter
// existed, defaulted to an empty list, and no screen ever passed anything. The
// screenshot campaign photographed a legacy history screen instead — one that
// no navigation path in the app can reach — so it looked covered from both
// sides at once.
//
// What is asserted here is the part that makes it a resume rail rather than a
// shelf: the progress bar, and which entries are offered at all.
WatchHistory _entry({
  required String title,
  required int watchedSeconds,
  required int totalSeconds,
}) =>
    WatchHistory(
      playlistId: 'p1',
      contentType: ContentType.vod,
      streamId: 'id-$title',
      watchDuration: Duration(seconds: watchedSeconds),
      totalDuration: Duration(seconds: totalSeconds),
      lastWatched: DateTime(2026, 7, 1),
      imagePath: '',
      title: title,
    );

Future<void> _pumpHome(
  WidgetTester tester,
  List<WatchHistory> items, {
  void Function(WatchHistory)? onResume,
  void Function(WatchHistory)? onRemove,
}) =>
    pumpScreen(
      tester,
      RedesignHome(
        movieCategories: const [],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
        continueWatching: items,
        onResume: onResume ?? (_) {},
        onRemove: onRemove ?? (_) {},
      ),
    );

void main() {
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('an unfinished title is offered with its position', (tester) async {
    await _pumpHome(tester, [
      _entry(title: 'Mad Max', watchedSeconds: 1800, totalSeconds: 6000),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Mad Max'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.3, 0.001),
        reason: 'the bar showed ${bar.value} for 30 minutes into 100 — a rail '
            'that cannot say how far in you are is just a row of shortcuts');
  });

  testWidgets('tapping an entry resumes that entry', (tester) async {
    WatchHistory? resumed;
    // Two entries, because with one the assertion cannot tell "handed back the
    // entry that was tapped" from "handed back the first entry in the list".
    await _pumpHome(
      tester,
      [
        _entry(title: 'El Conjuro', watchedSeconds: 300, totalSeconds: 6000),
        _entry(title: 'John Wick', watchedSeconds: 600, totalSeconds: 6000),
      ],
      onResume: (h) => resumed = h,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('John Wick'));
    await tester.pumpAndSettle();
    expect(resumed?.title, 'John Wick',
        reason: 'the rail did not hand back the entry it was showing');
  });

  // Antes de esto, una fila cuyo contenido ya no existe en el catálogo era
  // INDELEBLE: la poda dejó removeHistory sin llamador, así que la tarjeta
  // muerta se quedaba en la cabeza del riel respondiendo "no disponible" a cada
  // pulsación, y la única salida era borrar el historial entero.
  testWidgets('mantener pulsado ofrece retirar la entrada', (tester) async {
    WatchHistory? removed;
    await _pumpHome(
      tester,
      [
        _entry(title: 'El Conjuro', watchedSeconds: 300, totalSeconds: 6000),
        _entry(title: 'John Wick', watchedSeconds: 600, totalSeconds: 6000),
      ],
      onRemove: (h) => removed = h,
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('John Wick'));
    await tester.pumpAndSettle();

    expect(removed, isNull,
        reason: 'no se puede borrar nada antes de confirmar');
    await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
    await tester.pumpAndSettle();

    // Dos entradas otra vez: con una sola, "devolvió la que se pulsó" y
    // "devolvió la primera de la lista" son indistinguibles.
    expect(removed?.title, 'John Wick',
        reason: 'el riel no devolvió la entrada sobre la que se mantuvo pulsado');
  });

  testWidgets('cancelar la retirada no borra nada', (tester) async {
    WatchHistory? removed;
    await _pumpHome(
      tester,
      [_entry(title: 'John Wick', watchedSeconds: 600, totalSeconds: 6000)],
      onRemove: (h) => removed = h,
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('John Wick'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(removed, isNull, reason: 'un diálogo cancelado no borra datos');
  });

  // The "no rail without a resume handler" case is gone: onResume is required
  // now, so the situation it described cannot be built. It was testing that a
  // wiring mistake failed quietly; the fix was to make the mistake impossible.
}
