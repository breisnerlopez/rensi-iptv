import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';

import 'harness.dart';

Future<Playlist> _seedLarge(AppDatabase db,
    {int movieCats = 20, int perCat = 80, int liveCats = 15}) async {
  final p = Playlist(
    id: 'big-1',
    name: 'Catálogo Grande',
    type: PlaylistType.xtream,
    url: 'http://example.test',
    username: 'u',
    password: 'p',
    createdAt: DateTime(2026, 1, 1),
  );
  await db.insertPlaylist(p);

  final cats = <Category>[];
  for (var c = 0; c < movieCats; c++) {
    cats.add(Category(
        categoryId: 'vod_$c',
        categoryName: 'Categoría VOD $c',
        parentId: 0,
        playlistId: p.id,
        type: CategoryType.vod));
  }
  for (var c = 0; c < liveCats; c++) {
    cats.add(Category(
        categoryId: 'live_$c',
        categoryName: 'Canales $c',
        parentId: 0,
        playlistId: p.id,
        type: CategoryType.live));
  }
  await db.insertCategories(cats);

  final movies = <VodStream>[];
  for (var c = 0; c < movieCats; c++) {
    for (var i = 0; i < perCat; i++) {
      movies.add(VodStream(
        streamId: 'vod_${c}_$i',
        name: 'Película $c-$i',
        streamIcon: '',
        categoryId: 'vod_$c',
        rating: '7.5',
        rating5based: 3.8,
        containerExtension: 'mp4',
        playlistId: p.id,
        createdAt: DateTime(2026, 1, 1),
        genre: 'Acción',
      ));
    }
  }
  await db.insertVodStreams(movies); // movieCats*perCat (e.g. 1600) rows

  final live = <LiveStream>[];
  for (var c = 0; c < liveCats; c++) {
    for (var i = 0; i < 40; i++) {
      live.add(LiveStream(
        streamId: 'live_${c}_$i',
        name: 'Canal $c-$i',
        streamIcon: '',
        categoryId: 'live_$c',
        epgChannelId: 'epg_${c}_$i',
        playlistId: p.id,
      ));
    }
  }
  await db.insertLiveStreams(live);
  return p;
}

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Rendimiento: catálogo grande renderiza sin colgarse ni crashear',
      (tester) async {
    late Playlist p;
    var movieCount = 0;
    await tester.runAsync(() async {
      p = await _seedLarge(harnessDb);
      movieCount = 20 * 80;
    });
    debugPrint('seeded $movieCount movies + live channels');

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await settle(tester);
    await shot(tester, 'perf_1_large_home.png');

    expect(tester.takeException(), isNull,
        reason: 'un catálogo grande no debe crashear el home');
    expect(find.byType(XtreamCodeHomeScreen), findsOneWidget);

    // Basic interaction under load: reach the rail and switch a tab.
    await left(tester);
    await down(tester, times: 2);
    await ok(tester);
    await settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'navegar bajo carga no debe crashear');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
