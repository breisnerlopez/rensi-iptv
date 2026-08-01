// Fix #5 — the mid-play re-buffer indicator. Verifies its visibility contract
// (appears when buffering, hidden otherwise) and that it surfaces the buffered
// seconds / speed readout, without needing a real Player.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../integration/harness.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  setUpAll(loadFonts);

  testWidgets('aparece con un texto y spinner cuando visible=true',
      (tester) async {
    await tester.pumpWidget(_host(const PlayerBufferingIndicator(
      visible: true,
      label: 'Cargando…',
      bufferedSecs: 3,
      speedBps: 2 * 1024 * 1024, // 2 MB/s
    )));
    await tester.pump();

    expect(find.text('Cargando…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Readout de segundos en caché + velocidad.
    expect(find.textContaining('3s'), findsOneWidget);
    expect(find.textContaining('2.00 MB/s'), findsOneWidget);
  });

  testWidgets('oculto (SizedBox.shrink) cuando visible=false', (tester) async {
    await tester.pumpWidget(_host(const PlayerBufferingIndicator(
      visible: false,
      label: 'Cargando…',
    )));
    await tester.pump();

    expect(find.text('Cargando…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sin métricas (0/0) muestra solo el texto, sin readout',
      (tester) async {
    await tester.pumpWidget(_host(const PlayerBufferingIndicator(
      visible: true,
      label: 'Cargando…',
    )));
    await tester.pump();

    expect(find.text('Cargando…'), findsOneWidget);
    expect(find.textContaining('MB/s'), findsNothing);
  });
}
