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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/redesign/list_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';
import 'package:rensi_iptv/widgets/tv/tv_keyboard.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';
import 'package:rensi_iptv/screens/m3u/new_m3u_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/new_xtream_code_playlist_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/epg_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
// Player capture (round: device) — real PlayerWidget over a pushed clip.
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../test/integration/harness.dart';
import '../test/integration/player_e2e_support.dart';
import '../test/integration/seed.dart';

const String prefix =
    String.fromEnvironment('CAPTURE_PREFIX', defaultValue: 'dev');

/// Render the whole campaign in a given locale (CAPTURE_LOCALE=de|ar|...), so a
/// real-device run can check long-language overflow and RTL mirroring across
/// every screen, not just Spanish.
final Locale _captureLocale =
    Locale(const String.fromEnvironment('CAPTURE_LOCALE', defaultValue: 'es'));

/// Where `scripts/fake_panel.py` is listening, as seen from the device.
/// 10.0.2.2 is the emulator's alias for the host loopback; the panel binds
/// loopback, which the emulator reaches this way; for a real device run the
/// panel with --host 0.0.0.0 and point this at the host's LAN address.
const String epgPanelUrl = String.fromEnvironment(
  'EPG_PANEL_URL',
  defaultValue: 'http://10.0.2.2:8799',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Required on Android before takeScreenshot: swaps the render surface for
    // one that can be read back.
    await binding.convertFlutterSurfaceToImage();
    // The player captures need libmpv up before the first PlayerWidget mounts.
    MediaKit.ensureInitialized();
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

  final demoPlaylist = Playlist(
    id: 'p1',
    name: 'Demo',
    type: PlaylistType.xtream,
    url: 'http://demo.invalid:8080',
    username: 'demo',
    password: 'demo',
    createdAt: DateTime(2026, 1, 1),
  );

  void setActivePlaylist() {
    AppState.currentPlaylist = demoPlaylist;
  }

  // Global search enumerates playlists via PlaylistService.getPlaylists(), so a
  // playlist only set on AppState (not saved) means _searchAllLocal finds no
  // catalogue — which is why the first TV capture showed only the Discover
  // section. Save it so the "in your library" section can populate.
  Future<void> saveActivePlaylist(WidgetTester tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(demoPlaylist);
    });
    AppState.currentPlaylist = demoPlaylist;
  }

  // --- first run -----------------------------------------------------------

  testWidgets('01 onboarding', (tester) async {
    await pumpScreen(tester, const AppInitializerScreen(), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '01_onboarding');
  });

  testWidgets('02 playlist type', (tester) async {
    await pumpScreen(tester, const PlaylistTypeScreen(), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '02_playlist_type');
  });

  // Fictional data only: the add-playlist screens render what is typed, so they
  // must never be captured with a real subscription in the fields.
  testWidgets('03 add xtream form', (tester) async {
    await pumpScreen(tester, NewXtreamCodePlaylistScreen(), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '03_form_xtream');
  });

  testWidgets('04 add m3u form', (tester) async {
    await pumpScreen(tester, NewM3uPlaylistScreen(), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '04_form_m3u');
  });

  // --- populated -----------------------------------------------------------

  testWidgets('05 home — hero focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '05_home_hero');
  });

  testWidgets('06 home — focus in a rail', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null, locale: _captureLocale);
    await settle(tester);
    await moveFocus(tester, TraversalDirection.down, times: 2);
    await settle(tester);
    await capture(tester, '06_home_rail');
  });

  testWidgets('07 navigation rail focused', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p), size: null, locale: _captureLocale);
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
      locale: _captureLocale,
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
      locale: _captureLocale,
    );
    await settle(tester);
    await capture(tester, '09_live');
  });

  // The EPG line was shipped, unit-tested and wired into production, and still
  // nobody had ever seen it paint: capture 09 omits `epgService`, so every
  // screenshot of Live in the campaign showed the channel list WITHOUT a guide
  // and looked correct. This capture closes that hole by running the real
  // repository, the real HTTP client and the real parser against a local panel
  // (scripts/fake_panel.py) — only the provider is faked.
  testWidgets('09b live — with EPG', (tester) async {
    setActivePlaylist();
    final service = EpgService(
      IptvRepository(
        const ApiConfig(
          baseUrl: epgPanelUrl,
          username: 'qa',
          password: 'qa',
        ),
        'test-playlist-1',
      ).getShortEpg,
    );
    await pumpScreen(
      tester,
      LiveRedesign(
        liveCategories: [
          cat('l1', 'Deportes', CategoryType.live, 14),
          cat('l2', 'Noticias', CategoryType.live, 14),
        ],
        onPlay: (_) {},
        epgService: service,
      ),
      size: null,
      locale: _captureLocale,
    );
    // runAsync so the real socket work actually progresses: pumpAndSettle runs
    // in fake-async time, where an outstanding HTTP request never completes.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)));
    await settle(tester);
    // Skip, don't fail, when the panel is not up: this capture needs a helper
    // process the rest of the campaign does not, and taking the whole run down
    // over an optional dependency punishes everyone who just wanted the other
    // twelve screenshots. But do NOT capture instead — photographing an empty
    // guide and filing it as evidence is the exact mistake this test exists to
    // correct.
    if (find.textContaining('Premier League').evaluate().isEmpty) {
      markTestSkipped('no programme painted: start scripts/fake_panel.py and '
          'make sure it is reachable at $epgPanelUrl');
      return;
    }
    await capture(tester, '09b_live_epg');
  });

  testWidgets('10 my list — empty state', (tester) async {
    setActivePlaylist();
    await pumpScreen(tester, ListRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '10_my_list');
  });

  testWidgets('11 search — empty state', (tester) async {
    setActivePlaylist();
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await settle(tester);
    await capture(tester, '11_search');
  });

  // The settings tab is assembled from pre-redesign tile widgets that were
  // written at phone sizes and never photographed, because the campaign stopped
  // at the five redesigned tabs. It is tab 4 of the TV home, so a remote reaches
  // it in two presses — and it was rendering 12dp secondary text on a panel.
  testWidgets('13 settings', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(
      tester,
      XtreamCodeHomeScreen(playlist: p, initialIndex: 4),
      size: null,
      locale: _captureLocale,
    );
    await settle(tester);
    await capture(tester, '13_settings');
  });

  // Continue-watching, on the home screen where the app actually shows it.
  //
  // This capture used to photograph a standalone history screen that no
  // navigation path in the app could reach — so the campaign documented a
  // screen nobody could open while the real rail, which had never been passed
  // any data, went unphotographed and unnoticed. The screen is gone; the rail
  // works; this is the picture of it.
  testWidgets('12 continue watching', (tester) async {
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    await pumpScreen(
      tester,
      RedesignHome(
        movieCategories: const [],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
        continueWatching: [
          WatchHistory(
            playlistId: p.id,
            contentType: ContentType.vod,
            streamId: 'vod_1_movie_0',
            title: 'Mad Max: Fury Road',
            imagePath: '',
            lastWatched: DateTime(2026, 7, 1),
            watchDuration: const Duration(minutes: 41),
            totalDuration: const Duration(minutes: 120),
          ),
          WatchHistory(
            playlistId: p.id,
            contentType: ContentType.series,
            streamId: 'series_1_series_0',
            title: 'Breaking Bad',
            imagePath: '',
            lastWatched: DateTime(2026, 6, 28),
            watchDuration: const Duration(minutes: 12),
            totalDuration: const Duration(minutes: 47),
          ),
        ],
        onResume: (_) {},
        onRemove: (_) {},
      ),
      size: null,
      locale: _captureLocale,
    );
    await settle(tester);
    await capture(tester, '12_continue_watching');
  });

  // --- Global TMDb search (new feature) ------------------------------------
  //
  // TMDb has no key on this machine, so results are injected the way the app
  // resolves them: the SharedPreferences cache TmdbService reads before any
  // credential/network. Cache key for locale 'es' (pumpScreen's locale) is
  // 'tmdb.search.es-ES.<foldedQuery>'.

  Map<String, dynamic> tmdbItem(int id, String title, {String type = 'movie'}) =>
      {
        'id': id,
        'mediaType': type,
        'title': title,
        'overview':
            'Sinopsis de $title. Una historia sobre arena, poder y destino en '
                'un futuro lejano.',
        'posterPath': null,
        'releaseDate': '2021-10-22',
        'voteAverage': 8.2,
      };

  String tmdbCache(List<Map<String, dynamic>> results) => jsonEncode({
        'cachedAt': DateTime(2026, 7, 24).toIso8601String(),
        'results': results,
      });

  Future<void> seedMovie(String name) => harnessDb.insertVodStreams([
        ContentItemSeed(name).stream,
      ]);

  // Drive the search's real async pipeline (mobile field): enterText schedules
  // the 300ms debounce Timer in the test zone; pump fires it; runAsync lets the
  // real Drift/prefs I/O behind _run() complete; then render. Without the
  // runAsync the DB/cache futures never resolve and every capture is the empty
  // state — which is exactly what round 0 produced.
  Future<void> typeSearch(WidgetTester tester, String q) async {
    // TV: the field is readOnly and fed by the on-screen TvKeyboard, and
    // enterText is a no-op on the live integration binding anyway (round 0
    // captured only the empty placeholder). Tapping the keyboard keys sets the
    // controller text synchronously, so the query — and, once the async search
    // resolves, the results — actually appear. Mobile has no on-screen keyboard,
    // so fall back to enterText there.
    final onTv = find.byType(TvKeyboard).evaluate().isNotEmpty;
    if (onTv) {
      for (final ch in q.toUpperCase().split('')) {
        await tester.tap(find.text(ch).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 40));
      }
    } else {
      await tester.tap(find.byType(TextField), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), q);
    }
    await tester.pump(const Duration(milliseconds: 350)); // fire the debounce
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  // GS-02 no key: the most common real path — local survives, banner shows.
  testWidgets('14 search — no key (local + banner)', (tester) async {
    await setUpHarness(tv: null); // no cache, no credential -> noKey
    await saveActivePlaylist(tester);
    await tester.runAsync(() async => seedMovie('Dune 2021'));
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await typeSearch(tester, 'dune');
    await capture(tester, '14_search_nokey');
  });

  // GS-03 three sections + the neutral "not in your lists" badge.
  testWidgets('15 search — sections + neutral badge', (tester) async {
    await setUpHarness(prefs: {
      'tmdb.search.es-ES.dune': tmdbCache([
        tmdbItem(1, 'Dune'),
        tmdbItem(2, 'Dune: Part Two'),
      ]),
    }, tv: null);
    await saveActivePlaylist(tester);
    await tester.runAsync(() async => seedMovie('Dune 2021'));
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await typeSearch(tester, 'dune');
    await capture(tester, '15_search_sections');
  });

  // GS-04 detail sheet on a tmdbOnly card: save-only, no play.
  testWidgets('16 search — tmdbOnly detail sheet', (tester) async {
    await setUpHarness(prefs: {
      'tmdb.search.es-ES.dune': tmdbCache([tmdbItem(2, 'Dune: Part Two')]),
    }, tv: null);
    setActivePlaylist();
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await typeSearch(tester, 'dune');
    if (find.text('Dune: Part Two').evaluate().isNotEmpty) {
      await tester.tap(find.text('Dune: Part Two').first, warnIfMissed: false);
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
    await capture(tester, '16_search_detail');
  });

  // GS-07 two characters: local + "keep typing" hint, no spinner, no gap.
  testWidgets('17 search — 2-char keep-typing hint', (tester) async {
    await setUpHarness(tv: null);
    await saveActivePlaylist(tester);
    await tester.runAsync(() async => seedMovie('Dune 2021'));
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await typeSearch(tester, 'du');
    await capture(tester, '17_search_2char');
  });

  // --- Round 2: interaction flows ------------------------------------------

  // GS-06 wishlist filter, populated. No typing needed (browse mode), so it
  // works on mobile too. Pre-seed a saved TMDb item and tap the chip.
  testWidgets('18 search — wishlist populated', (tester) async {
    await setUpHarness(prefs: {
      'tmdb.wishlist':
          jsonEncode([tmdbItem(2, 'Dune: Part Two'), tmdbItem(3, 'Arrival')]),
    }, tv: null);
    await saveActivePlaylist(tester);
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await tester.tap(find.text('Lista de deseos'), warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await capture(tester, '18_search_wishlist');
  });

  // GS-06b wishlist filter, empty.
  testWidgets('19 search — wishlist empty', (tester) async {
    await setUpHarness(tv: null);
    await saveActivePlaylist(tester);
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await tester.tap(find.text('Lista de deseos'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await capture(tester, '19_wishlist_empty');
  });

  // GS-04b end-to-end (TV only, needs typing): type -> tap discover card ->
  // detail sheet -> tap "Guardar en lista de deseos" -> back to results with the
  // bookmark now saved. Captures the post-save state.
  testWidgets('20 search — save from detail sheet', (tester) async {
    await setUpHarness(prefs: {
      'tmdb.search.es-ES.dune': tmdbCache([tmdbItem(2, 'Dune: Part Two')]),
    }, tv: null);
    await saveActivePlaylist(tester);
    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: null, locale: _captureLocale);
    await typeSearch(tester, 'dune');
    final card = find.text('Dune: Part Two');
    if (card.evaluate().isNotEmpty) {
      await tester.tap(card.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final save = find.text('Guardar en lista de deseos');
      if (save.evaluate().isNotEmpty) {
        await tester.tap(save.first, warnIfMissed: false);
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() async =>
              Future<void>.delayed(const Duration(milliseconds: 120)));
          await tester.pump();
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
      }
    }
    await capture(tester, '20_search_saved');
  });

  // --- player (round: device) ----------------------------------------------
  // The real PlayerWidget over a clip PUSHED to the device (adb push … then
  // RENSI_TESTCLIP=file:///sdcard/testclip.mp4). Only the video-texture channel
  // is faked, so the chrome (top bar, seek/live bar, channel list, audio panel)
  // is photographed over a deterministic black frame with a live libmpv decode
  // behind it — exactly the surfaces a 10-foot audit cares about. Opt-in: with
  // no clip the whole group skips, so a phone/tablet run stays green.
  //
  // pumpAndSettle would hang forever on libmpv's continuous frame timers, so
  // these use pumpReal/pumpUntil and their own takeScreenshot — never capture().
  const String playerClip = String.fromEnvironment('RENSI_TESTCLIP');

  Future<void> capturePlayer(WidgetTester tester, String name) async {
    await pumpReal(tester, cycles: 3, ms: 140);
    await binding.takeScreenshot('${prefix}_$name');
  }

  Future<void> mountPlayer(WidgetTester tester) async {
    // NOTE: no installPlayerPluginFakes here. That fakes the media_kit_video
    // texture channel, which is right headless but WRONG on a device — the real
    // Android plugin is registered and my injected VideoOutput.Resize collides
    // with it ("Null is not int"). On device the real texture channel works;
    // the clip is served over HTTP so libmpv needs no storage permission.
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    PlayerState.showVideoSettings = false;
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    // Headless/emulator: the GPU output stalls open(); software decodes without
    // a surface, and the chrome under audit is identical across decoders.
    await UserPreferences.setVideoDecoder('software');
    final a = liveItem(playerClip, 'Canal A');
    final b = liveItem(playerClip, 'Canal B');
    await tester.pumpWidget(MaterialApp(
      locale: _captureLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PlayerWidget(contentItem: a, queue: [a, b])),
    ));
    // Leave the loading spinner (post-frame → texture create → open resolves).
    await pumpUntil(tester, () {
      final s = tester.state(find.byType(PlayerWidget)) as dynamic;
      // ignore: avoid_dynamic_calls
      return s.isLoading == false;
    });
  }

  testWidgets('21 player — playing, chrome hidden', (tester) async {
    if (playerClip.isEmpty) {
      markTestSkipped('RENSI_TESTCLIP no definido — se omiten capturas de player');
      return;
    }
    await mountPlayer(tester);
    await capturePlayer(tester, '21_player_clean');
    await disposePlayerCleanly(tester);
  });

  testWidgets('22 player — audio/subtitle panel', (tester) async {
    if (playerClip.isEmpty) return;
    await mountPlayer(tester);
    // The clip carries two audio tracks, so this is the real panel with real
    // rows to lay out — where the section titles skip tenFoot() on TV.
    EventBus().emit('toggle_video_settings', true);
    await pumpReal(tester, cycles: 6, ms: 150);
    await capturePlayer(tester, '22_player_audio_panel');
    await disposePlayerCleanly(tester);
  });

  testWidgets('23 player — channel list', (tester) async {
    if (playerClip.isEmpty) return;
    await mountPlayer(tester);
    EventBus().emit('toggle_channel_list', true);
    await pumpReal(tester, cycles: 6, ms: 150);
    await capturePlayer(tester, '23_player_channel_list');
    await disposePlayerCleanly(tester);
  });
}

/// Minimal VodStream builder for the search captures.
class ContentItemSeed {
  ContentItemSeed(this.name);
  final String name;
  VodStream get stream => VodStream(
        streamId: 'm-${name.hashCode}',
        name: name,
        streamIcon: '',
        categoryId: 'movies',
        rating: '',
        rating5based: 0,
        containerExtension: 'mp4',
        playlistId: 'p1',
        createdAt: DateTime(2026),
        genre: '',
      );
}
