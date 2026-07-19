// Screenshot campaign: drives the REAL app on a real device and captures each
// screen at the device's native resolution.
//
// Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/capture_test.dart -d <device> --profile
//
// Uses the seeded in-memory database, so it produces a populated UI with NO
// credentials anywhere on the machine. Every TV capture is taken with focus
// placed deliberately: on a 10-foot UI the focus state *is* the design, and a
// screenshot without it hides the most failure-prone part of the interface.
//
// The prefix comes from CAPTURE_PREFIX so one run per AVD lands in its own set.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/list_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';
import 'package:rensi_iptv/screens/watch_history_screen.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/new_xtream_code_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';
import 'package:rensi_iptv/services/app_state.dart';

import '../test/integration/harness.dart';
import '../test/integration/seed.dart';

const String prefix =
    String.fromEnvironment('CAPTURE_PREFIX', defaultValue: 'dev');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Required on Android before takeScreenshot: swaps the render surface for
    // one that can be read back.
    await binding.convertFlutterSurfaceToImage();
  });

  // null: let the device answer. Mocking this to `true` — the default — is how
  // the first full campaign photographed the TV layout on three phones and a
  // tablet without anyone noticing.
  setUp(() => setUpHarness(tv: null));
  tearDown(tearDownHarness);

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await binding.takeScreenshot('${prefix}_$name');
  }

  CategoryViewModel cat(String id, String name, CategoryType type, int n) =>
      CategoryViewModel(
        category: Category(
            categoryId: id,
            categoryName: name,
            parentId: 0,
            playlistId: 'p1',
            type: type),
        contentItems: [
          for (var i = 0; i < n; i++)
            ContentItem(
                '$id-$i',
                '$name $i',
                '',
                type == CategoryType.live
                    ? ContentType.liveStream
                    : ContentType.vod,
                containerExtension: 'mp4'),
        ],
      );

  void setActivePlaylist() {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'Demo',
      type: PlaylistType.xtream,
      url: 'http://demo.invalid:8080',
      username: 'demo',
      password: 'demo',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  // --- first run -----------------------------------------------------------

  testWidgets('01 onboarding', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen(), size: null);
    await settle(tester);
    await capture(tester, '01_onboarding');
  });

  testWidgets('02 playlist type', (tester) async {
    await pumpScreen(tester, const PlaylistTypeScreen(), size: null);
    await settle(tester);
    await capture(tester, '02_playlist_type');
  });

  // Fictional data only: the add-playlist screens render what is typed, so they
  // must never be captured with a real subscription in the fields.
  testWidgets('03 add xtream form', (tester) async {
    await pumpScreen(tester, NewXtreamCodePlaylistScreen(), size: null);
    await settle(tester);
    await capture(tester, '03_form_xtream');
  });

  testWidgets('04 add m3u form', (tester) async {
    await pumpScreen(tester, NewM3uPlaylistScreen(), size: null);
    await settle(tester);
    await capture(tester, '04_form_m3u');
  });

  // --- populated -----------------------------------------------------------

  testWidgets('05 home — hero focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await capture(tester, '05_home_hero');
  });

  testWidgets('06 home — focus in a rail', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await moveFocus(tester, TraversalDirection.down, times: 2);
    await settle(tester);
    await capture(tester, '06_home_rail');
  });

  testWidgets('07 navigation rail focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null);
    await settle(tester);
    await moveFocus(tester, TraversalDirection.left);
    await settle(tester);
    await capture(tester, '07_nav_rail');
  });

  testWidgets('08 browse grid', (tester) async {
    setActivePlaylist();
    await pumpScreen(
      tester,
      BrowseRedesign(
        movieCategories: [
          cat('c1', 'Acción', CategoryType.vod, 18),
          cat('c2', 'Drama', CategoryType.vod, 18),
        ],
        seriesCategories: [cat('c3', 'Series', CategoryType.series, 12)],
        onOpen: (_) {},
      ),
      size: null,
    );
    await settle(tester);
    await moveFocus(tester, TraversalDirection.down, times: 2);
    await settle(tester);
    await capture(tester, '08_browse');
  });

  testWidgets('09 live', (tester) async {
    setActivePlaylist();
    await pumpScreen(
      tester,
      LiveRedesign(
        liveCategories: [
          cat('l1', 'Deportes', CategoryType.live, 14),
          cat('l2', 'Noticias', CategoryType.live, 14),
        ],
        onPlay: (_) {},
      ),
      size: null,
    );
    await settle(tester);
    await capture(tester, '09_live');
  });

  testWidgets('10 my list — empty state', (tester) async {
    setActivePlaylist();
    await pumpScreen(tester, ListRedesign(onOpen: (_) {}), size: null);
    await settle(tester);
    await capture(tester, '10_my_list');
  });

  testWidgets('11 search — empty state', (tester) async {
    setActivePlaylist();
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null);
    await settle(tester);
    await capture(tester, '11_search');
  });

  testWidgets('12 watch history', (tester) async {
    setActivePlaylist();
    await pumpScreen(tester,
        const WatchHistoryScreen(playlistId: 'p1'), size: null);
    await settle(tester);
    await capture(tester, '12_history');
  });
}
