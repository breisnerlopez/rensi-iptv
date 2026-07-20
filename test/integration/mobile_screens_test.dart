import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import 'harness.dart';
import 'seed.dart';

// Renders the main MOBILE screens (phone viewport, touch UI) for a competitive
// design review.
void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness(tv: false)); // real mobile layout, not TV
  tearDown(tearDownHarness);

  const phone = Size(412, 915); // Pixel-class phone (dp).

  testWidgets('Móvil: onboarding (instalación limpia)', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen(), size: phone);
    await shot(tester, 'mobile_1_onboarding.png');
  });

  testWidgets('Móvil: lista de playlists (tarjetas migradas al design system)',
      (tester) async {
    await tester.runAsync(() async {
      await harnessDb.insertPlaylist(Playlist(
          id: 'p1',
          name: 'Mi Servidor IPTV',
          type: PlaylistType.xtream,
          url: 'http://ejemplo.tv:8080',
          username: 'u',
          password: 'p',
          createdAt: DateTime(2026, 1, 1)));
      await harnessDb.insertPlaylist(Playlist(
          id: 'p2',
          name: 'Lista M3U Casa',
          type: PlaylistType.m3u,
          url: 'http://ejemplo.tv/list.m3u',
          createdAt: DateTime(2026, 1, 1)));
    });
    await pumpScreen(tester, const PlaylistScreen(), size: phone);
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, 'mobile_6_playlists.png');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Móvil: home poblado', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: phone);
    await settle(tester);
    await shot(tester, 'mobile_2_home.png');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Móvil: home → detalle de película (tap en póster)', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: phone);
    await settle(tester);
    // Tap a visible movie poster in the rail.
    final poster = find.text('Mad Max: Fury Road');
    if (tester.any(poster)) {
      await tester.tap(poster.first, warnIfMissed: false);
      await settle(tester);
    }
    await shot(tester, 'mobile_3_detail.png');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Móvil: pestaña En vivo (tap bottom nav)', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: phone);
    await settle(tester);
    final live = find.text('En vivo');
    if (tester.any(live)) {
      await tester.tap(live.first, warnIfMissed: false);
      await settle(tester);
    }
    await shot(tester, 'mobile_4_live.png');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Móvil: pestaña Ajustes', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: phone);
    await settle(tester);
    final cfg = find.textContaining('Ajustes');
    if (tester.any(cfg)) {
      await tester.tap(cfg.first, warnIfMissed: false);
      await settle(tester);
    }
    await shot(tester, 'mobile_5_settings.png');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
