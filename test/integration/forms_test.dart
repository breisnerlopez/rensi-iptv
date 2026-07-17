import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/new_xtream_code_playlist_screen.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Form M3U — navegable con mando', (tester) async {
    await pumpScreen(tester, const NewM3uPlaylistScreen());
    await shot(tester, 'form_m3u_1.png');
    debugPrint('M3U entry focus=${focusedInfo()}');
    await tab(tester);
    debugPrint('M3U after tab focus=${focusedInfo()}');
    final labels = <String?>[];
    for (var i = 0; i < 8; i++) {
      await down(tester);
      labels.add(focusedInfo());
    }
    debugPrint('M3U ↓ traversal: $labels');
    await shot(tester, 'form_m3u_2.png');
  });

  testWidgets('Form Xtream — navegable con mando', (tester) async {
    await pumpScreen(tester, const NewXtreamCodePlaylistScreen());
    await shot(tester, 'form_xtream_1.png');
    debugPrint('Xtream entry focus=${focusedInfo()}');
    await tab(tester);
    debugPrint('Xtream after tab focus=${focusedInfo()}');
    final labels = <String?>[];
    for (var i = 0; i < 10; i++) {
      await down(tester);
      labels.add(focusedInfo());
    }
    debugPrint('Xtream ↓ traversal: $labels');
    await shot(tester, 'form_xtream_2.png');
  });
}
