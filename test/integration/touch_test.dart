import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Móvil (táctil): onboarding con tap real → tipo → form M3U',
      (tester) async {
    // Phone viewport → mobile layout, touch UI (no TV overrides).
    await pumpScreen(tester, const AppInitializerScreen(), size: phoneSize);
    await shot(tester, 'touch_1_empty.png');

    // The onboarding empty-state renders after REAL async init (SharedPreferences
    // + DB playlist lookup) that FakeAsync pump() can't advance; interleave
    // runAsync so it makes progress. On slower CI runners this matters.
    Future<bool> waitFor(Finder f) async {
      for (var i = 0; i < 40; i++) {
        if (tester.any(f)) return true;
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
      }
      return tester.any(f);
    }

    final createBtn = find.widgetWithIcon(FilledButton, Icons.add);
    expect(await waitFor(createBtn), isTrue,
        reason: 'el estado vacío del onboarding debe mostrar el botón Crear');
    // Tap the "create" button (has Icons.add) with a real tap gesture.
    await tester.tap(createBtn.first);
    await settle(tester);
    await shot(tester, 'touch_2_type.png');
    expect(find.byType(PlaylistTypeScreen), findsOneWidget,
        reason: 'tap en Crear debe abrir el selector de tipo');

    // Tap the M3U card (wait for the type screen to settle in first).
    final m3uCard = find.text('M3U Playlist');
    expect(await waitFor(m3uCard), isTrue,
        reason: 'la tarjeta M3U debe renderizarse');
    await tester.tap(m3uCard.first);
    await settle(tester);
    expect(find.byType(NewM3uPlaylistScreen), findsOneWidget,
        reason: 'tap en la tarjeta M3U debe abrir el formulario');

    // Tap the URL/File toggle (the fix must remain tappable on mobile).
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
