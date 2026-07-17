import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Onboarding con mando: autofocus → tipo → explorar', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen());
    await shot(tester, 'onb_1_empty.png');
    final entry = focusedLabel();
    debugPrint('ENTRY focus=$entry');
    expect(entry, contains('Crear'),
        reason: 'la pantalla vacía debe autoenfocar "Crear" en TV');

    // OK on the auto-focused create button.
    await ok(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await shot(tester, 'onb_2_type.png');
    final onType = tester.any(find.byType(PlaylistTypeScreen));
    debugPrint('after OK: PlaylistType=$onType focus=${focusedLabel()}');
    expect(onType, isTrue,
        reason: 'OK en Crear debe navegar a PlaylistTypeScreen');

    // Explore the type screen with the remote.
    await tab(tester);
    debugPrint('type after tab focus=${focusedLabel()}');
    await right(tester);
    debugPrint('type after right focus=${focusedLabel()}');
    await down(tester);
    debugPrint('type after down focus=${focusedLabel()}');
    await shot(tester, 'onb_3_type_focus.png');
  });
}
