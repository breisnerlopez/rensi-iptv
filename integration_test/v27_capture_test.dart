// Opt-in visual proof of the v2.7.0 UI. Modeled exactly on
// integration_test/enrich_capture_test.dart: IntegrationTestWidgetsFlutterBinding,
// convertFlutterSurfaceToImage(), binding.takeScreenshot(name), the TMDb token
// from --dart-define (runtime-only, never committed/logged), and a localized
// dark MaterialApp (locale es). Run on the tv_1080p emulator (960dp logical
// width == the user's real TV):
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/v27_capture_test.dart -d <tv_1080p> --profile \
//     --dart-define-from-file=<path>/tmdb_env.json
//
// where tmdb_env.json is {"TMDB_TOKEN": "<v4 read token>"}.
//
// Screenshots produced (build/screenshots/<name>.png via the driver):
//   continue_watching_seeall, studio_picker, studio_filmography,
//   popular_rail, popular_year, recent_searches, cast_rail,
//   browse_genre, live_selector, live_picker, search_genre,
//   search_genre_results.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/l10n/supported_languages.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/continue_watching_all_screen.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/widgets/tmdb_cast_rail.dart';
import 'package:rensi_iptv/services/recent_searches_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// Localized labels the finders tap. The MaterialApp below is pinned to Spanish
// (matching enrich_capture_test), so these are the es values from app_es.arb;
// they are load-bearing for find.text and must track the arb.
const _esStudios = 'Estudios'; // loc.search_filter_studios
const _esPopularYear = 'Este año'; // loc.popular_window_year
const _esGenres = 'Géneros'; // loc.search_filter_genre

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const token = String.fromEnvironment('TMDB_TOKEN');

  setUpAll(() async {
    await binding.convertFlutterSurfaceToImage();
    // Register an EMPTY in-memory catalogue. This is real infrastructure, not a
    // UI fake: the popular rail and a studio's filmography cross-reference TMDb
    // against the local library (DatabaseService.database == getIt<AppDatabase>),
    // which throws when nothing is registered because `flutter drive` runs the
    // test's own main(), not the app's boot. An empty drift DB lets that code
    // run for real and simply find no owned copies (every result is a Discover
    // card). Guarded so a registration failure only affects the two DB-backed
    // scenarios, never the standalone ones.
    try {
      if (!getIt.isRegistered<AppDatabase>()) {
        getIt.registerSingleton<AppDatabase>(
          AppDatabase(NativeDatabase.memory()),
        );
      }
    } catch (_) {}
  });

  Widget wrap(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales:
            supportedLanguages.map((l) => Locale(l['code'])).toList(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppThemes.darkTheme,
        home: Scaffold(backgroundColor: Colors.black, body: child),
      );

  // Lets a real network Future resolve (same ~9s dwell enrich_capture uses).
  Future<void> settleNetwork(WidgetTester tester,
      {int seconds = 9}) async {
    await tester.runAsync(
        () => Future<void>.delayed(Duration(seconds: seconds)));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  }

  // ---------------------------------------------------------------------------
  // 1) continue_watching_seeall — NO token, NO catalogue. The see-all grid
  //    renders straight from the WatchHistory list it is handed (RensiKeyArt.raw
  //    needs only a picture + name, never a ContentItem/AppState).
  // ---------------------------------------------------------------------------
  testWidgets('continue_watching_seeall', (tester) async {
    // Real TMDb poster art (w342) so the cards look like the shipping rail; if a
    // path 404s the card falls back to typographic key-art and the progress bar
    // + title overlay still render. Durations set to 40-70% so the bar is
    // visibly partial.
    WatchHistory h(String id, String title, String poster, int watchedMin,
            int totalMin, ContentType type) =>
        WatchHistory(
          playlistId: 'demo',
          contentType: type,
          streamId: id,
          watchDuration: Duration(minutes: watchedMin),
          totalDuration: Duration(minutes: totalMin),
          lastWatched: DateTime(2026, 7, 26),
          imagePath: 'https://image.tmdb.org/t/p/w342$poster',
          title: title,
        );
    final items = <WatchHistory>[
      h('157336', 'Interstellar', '/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg', 92, 169,
          ContentType.vod),
      h('155', 'The Dark Knight', '/qJ2tW6WMUDux911r6m7haRef0WH.jpg', 78, 152,
          ContentType.vod),
      h('27205', 'Inception', '/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg', 60, 148,
          ContentType.vod),
      h('438631', 'Dune', '/d5NXSklXo0qyIYkgV94XAgMIckC.jpg', 55, 155,
          ContentType.vod),
      h('872585', 'Oppenheimer', '/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg', 120, 181,
          ContentType.vod),
      h('299534', 'Avengers: Endgame', '/or06FN3Dka5tukK1e9sl16pB3iy.jpg', 95,
          181, ContentType.vod),
      h('1396', 'Breaking Bad', '/ggFHVNu6YYI5L9pCfOacjizRGt.jpg', 22, 47,
          ContentType.series),
    ];
    await tester.pumpWidget(wrap(
      ContinueWatchingAllScreen(
        listenable: ValueNotifier<int>(0),
        itemsBuilder: () => items,
        onResume: (_) {},
      ),
    ));
    // A short real dwell so the network posters have a chance to decode.
    await settleNetwork(tester, seconds: 5);
    await binding.takeScreenshot('continue_watching_seeall');
  });

  // ---------------------------------------------------------------------------
  // 5) cast_rail — token. Same DISCOVER-sheet approach as enrich_capture, plus a
  //    non-null onActorTap so the cast avatars under the synopsis are tappable.
  // ---------------------------------------------------------------------------
  testWidgets('cast_actor_tap renders tappable cast rail', (tester) async {
    await tester.runAsync(() => TmdbCredentialsService.saveCredential(token));
    const result = GlobalSearchResult(
      tmdb: TmdbSearchResult(
        id: 299534, // Avengers: Endgame
        mediaType: TmdbMediaType.movie,
        title: 'Vengadores: Endgame',
        voteAverage: 8.2,
      ),
      localMatches: [],
      isWishlisted: false,
    );
    await tester.pumpWidget(wrap(
      SearchDetailSheet(
        result: result,
        service: GlobalSearchService(),
        onPlayLocal: (_) {},
        onToggleWishlist: () async => false,
        onActorTap: (_) {},
      ),
    ));
    // getDetail(withCredits) can take a moment; give it room so the cast section
    // (TmdbCastRail, rendered only once the detail resolves with cast) mounts.
    await settleNetwork(tester, seconds: 9);
    // The tappable cast rail sits BELOW the synopsis; scroll the sheet down so
    // the avatars are in frame (the whole point of the shot). Fall back to a
    // fixed drag if the rail isn't located, so the shot still moves past the
    // synopsis rather than silently staying at the top.
    final castRail = find.byType(TmdbCastRail);
    final sheetScroll = find.byType(Scrollable).first;
    if (castRail.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(castRail, 280,
          scrollable: sheetScroll, maxScrolls: 20);
    } else {
      await tester.drag(sheetScroll, const Offset(0, -700));
    }
    await tester.pumpAndSettle();
    // Let the avatar network images paint before capturing.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await binding.takeScreenshot('cast_rail');
    await tester.runAsync(() => TmdbCredentialsService.deleteCredential());
  });

  // ---------------------------------------------------------------------------
  // 4) recent_searches — NO token. Seed a few queries, then pump SearchRedesign
  //    with an empty query: the ALL-filter empty state renders the recent-search
  //    chips (SharedPreferences is real on the device). No catalogue touched.
  // ---------------------------------------------------------------------------
  testWidgets('recent_searches empty-state chips', (tester) async {
    await tester.runAsync(() async {
      await RecentSearchesService.clear();
      await RecentSearchesService.record('Interstellar');
      await RecentSearchesService.record('Breaking Bad');
      await RecentSearchesService.record('A24');
      await RecentSearchesService.record('Dune');
      await RecentSearchesService.record('Christopher Nolan');
    });
    await tester.pumpWidget(wrap(const SearchRedesign(onOpen: _noopOpen)));
    // initState._loadRecent reads SharedPreferences via a real platform channel.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await binding.takeScreenshot('recent_searches');
  });

  // ---------------------------------------------------------------------------
  // 2) studio_picker + studio_filmography — token. Drive the real SearchRedesign
  //    on the TV layout: tap the "Estudios" filter, type "A24" on the on-screen
  //    TvKeyboard (there is no TextField at 960dp), screenshot the company
  //    picker, then tap the first company card for its filmography.
  //    The picker is pure TMDb; the filmography cross-references the (empty)
  //    catalogue registered in setUpAll.
  // ---------------------------------------------------------------------------
  testWidgets('studio_search picker and filmography', (tester) async {
    await tester.runAsync(() => TmdbCredentialsService.saveCredential(token));
    await tester.pumpWidget(wrap(const SearchRedesign(onOpen: _noopOpen)));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The "Estudios" chip is the LAST entry in a lazy horizontal ListView, so
    // it is not built (and find.text matches nothing) until the chip row is
    // scrolled. Scroll that specific row to reveal it, then tap.
    final studiosChip = find.text(_esStudios);
    final chipRow = find
        .byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal)
        .first;
    await tester.scrollUntilVisible(
      studiosChip,
      160,
      scrollable: find.descendant(of: chipRow, matching: find.byType(Scrollable)).first,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();
    await tester.tap(studiosChip);
    await tester.pumpAndSettle();

    // Type "A24" on the on-screen keyboard (A-Z0-9 keys). The integration
    // binding uses a REAL clock, so a fast burst (tap+single-frame pump, ~ms
    // apart) leaves only the FINAL keystroke's 300ms debounce pending — each
    // _onChanged cancels the prior timer. Then ONE long real-time settle lets
    // that 'a24' debounce fire and its network search resolve, so the picker
    // shows the true final results (A24) rather than an intermediate 'a2' prefix
    // whose slower search would otherwise be the last to repaint.
    Future<void> tapKey(String k) async {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await tapKey('A');
    await tapKey('2');
    await tapKey('4');
    await settleNetwork(tester, seconds: 6);
    await binding.takeScreenshot('studio_picker');

    // Open the first company (A24) → its filmography. Needs the registered DB;
    // if that failed this tap throws and only studio_filmography is skipped —
    // studio_picker is already captured above.
    final firstCompany = find.byType(RensiPoster);
    if (firstCompany.evaluate().isNotEmpty) {
      try {
        await tester.ensureVisible(firstCompany.first);
        await tester.pumpAndSettle();
        await tester.tap(firstCompany.first);
        await tester.pump();
        await settleNetwork(tester);
        await binding.takeScreenshot('studio_filmography');
      } catch (_) {
        // studio_picker is already captured; a filmography-tap failure (e.g. the
        // card is not a RensiPoster) must not fail the whole capture run.
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 3) popular_rail + popular_year — token. Pump the real RedesignHome with
  //    empty categories/callbacks so its self-contained _PopularRail mounts; it
  //    fetches TMDb popular and cross-references the (empty) catalogue, so every
  //    tile is a Discover card. Then switch the window chip to "Este año".
  //    (RedesignHome shows its empty-state below the rail because no local
  //    catalogue is seeded — the rail itself is the subject of the shot.)
  // ---------------------------------------------------------------------------
  testWidgets('popular_rail with window switch', (tester) async {
    await tester.runAsync(() => TmdbCredentialsService.saveCredential(token));
    await tester.pumpWidget(wrap(
      RedesignHome(
        movieCategories: const [],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
        onResume: (_) {},
        onRemove: (_) {},
      ),
    ));
    // _PopularRail probes the key then fetches popular(month) — real async.
    await settleNetwork(tester);
    await binding.takeScreenshot('popular_rail');

    // Switch to the "this year" window and re-fetch.
    final yearChip = find.text(_esPopularYear);
    if (yearChip.evaluate().isNotEmpty) {
      await tester.ensureVisible(yearChip);
      await tester.pumpAndSettle();
      await tester.tap(yearChip);
      await tester.pump();
      await settleNetwork(tester);
      await binding.takeScreenshot('popular_year');
    }
    await tester.runAsync(() => TmdbCredentialsService.deleteCredential());
  });

  // ---------------------------------------------------------------------------
  // 6) browse_genre — NO token, NO DB. BrowseRedesign derives its genre chip
  //    row from the ContentItems in the CategoryViewModels it is handed. The
  //    full-catalogue load (initState._loadFull) has no real repository here, so
  //    it degrades to preview-only — exactly the guard being exercised — and the
  //    chips/grid render from these synthetic previews. Tapping "Terror" filters
  //    the grid. AppState is untouched (still null), so ContentItem urls fall
  //    back to their id (isXtreamCode == false) and nothing throws.
  // ---------------------------------------------------------------------------
  testWidgets('browse_genre chip filters the grid', (tester) async {
    final movies = _cat('m1', 'Populares', CategoryType.vod, [
      _movieItem('101', 'Sombras', 'Terror'),
      _movieItem('102', 'Ecos', 'Comedia, Drama'),
      _movieItem('103', 'El Salto', 'Acción'),
      _movieItem('104', 'Nébula', 'Ciencia ficción'),
      _movieItem('105', 'Grito', 'Terror'),
      _movieItem('106', 'Duelo', 'Acción, Aventura'),
    ]);
    final series = _cat('s1', 'Series destacadas', CategoryType.series, [
      _seriesItem('201', 'Penumbra', 'Terror / Suspense'),
      _seriesItem('202', 'La Oficina', 'Comedia'),
      _seriesItem('203', 'Fronteras', 'Action & Adventure'),
      _seriesItem('204', 'Laboratorio', 'Ciencia ficción, Drama'),
    ]);
    await tester.pumpWidget(wrap(BrowseRedesign(
      movieCategories: [movies],
      seriesCategories: [series],
      onOpen: _noopOpen,
    )));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The genre chips are a lazy horizontal ListView; "Terror" sorts last and is
    // off-screen at 960dp, so reveal it the same way studio_search reveals the
    // "Estudios" chip, then tap to filter the grid. Guarded so a miss still
    // captures the (unfiltered) chip row rather than failing the run.
    try {
      final terror = find.text('Terror');
      final chipRow = find
          .byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal)
          .first;
      await tester.scrollUntilVisible(
        terror,
        120,
        scrollable: find
            .descendant(of: chipRow, matching: find.byType(Scrollable))
            .first,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      await tester.tap(terror);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    } catch (_) {
      // Chip reveal/tap failed; the chip row itself is still the subject.
    }
    await binding.takeScreenshot('browse_genre');
  });

  // ---------------------------------------------------------------------------
  // 7) live_selector — NO token, NO DB. LiveRedesign builds its category chip
  //    row straight from the CategoryViewModels it is handed. With >8 real
  //    categories it also mounts the "jump to category" button, so we pump 9
  //    synthetic live categories to capture the row + that button, then open the
  //    searchable picker sheet for a second shot when the button is present.
  // ---------------------------------------------------------------------------
  testWidgets('live_selector category row and jump button', (tester) async {
    const names = [
      'Deportes',
      'Noticias',
      'Películas',
      'Infantil',
      'Música',
      'Documentales',
      'Nacionales',
      'Internacionales',
      'Premium',
    ];
    final cats = <CategoryViewModel>[
      for (var i = 0; i < names.length; i++)
        _cat('l$i', names[i], CategoryType.live, [
          _channel('c${i}0', '${names[i]} HD'),
          _channel('c${i}1', '${names[i]} 24h'),
          _channel('c${i}2', '${names[i]} Plus'),
        ], playlistId: 'live-demo'),
    ];
    await tester.pumpWidget(wrap(LiveRedesign(
      liveCategories: cats,
      onPlay: _noopOpen,
    )));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await binding.takeScreenshot('live_selector');

    // 9 real categories (>8) mount the jump-to-category button. Opening its
    // searchable sheet is a bonus shot; guarded so a failure never fails the run
    // and never affects the already-captured row.
    try {
      final pickerBtn = find.byIcon(Icons.category_outlined);
      if (pickerBtn.evaluate().isNotEmpty) {
        await tester.tap(pickerBtn.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        await binding.takeScreenshot('live_picker');
      }
    } catch (_) {
      // Sheet open failed; live_selector is already captured.
    }
  });

  // ---------------------------------------------------------------------------
  // 8) search_genre — NO token, but SEEDED DB + AppState. Unlike the picker
  //    modes above, the "Géneros" filter is LOCAL-ONLY: it calls
  //    GlobalSearchService.enumerateLocalGenres(), which reads
  //    AppState.currentPlaylist (must be Xtream) and the current playlist's VOD +
  //    series rows from the in-memory AppDatabase registered in setUpAll. So we
  //    point AppState at a synthetic Xtream playlist and insert genre-bearing
  //    rows into the SAME db, tap the trailing "Géneros" chip, and capture the
  //    genre picker. All seeding is guarded (degrades to an empty picker) and
  //    AppState is reset in `finally` so the other scenarios stay unaffected.
  // ---------------------------------------------------------------------------
  testWidgets('search_genre picker from seeded catalogue', (tester) async {
    const seedPlaylistId = 'genre-seed';
    try {
      AppState.currentPlaylist = Playlist(
        id: seedPlaylistId,
        name: 'Seed',
        type: PlaylistType.xtream,
        url: 'http://example.test',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026, 1, 1),
      );
      final db = getIt<AppDatabase>();
      await tester.runAsync(() async {
        await db.insertVodStreams([
          _vod('501', 'Sombras', 'Terror', seedPlaylistId),
          _vod('502', 'Grito', 'Terror', seedPlaylistId),
          _vod('503', 'El Salto', 'Acción', seedPlaylistId),
          _vod('504', 'Duelo', 'Acción, Aventura', seedPlaylistId),
          _vod('505', 'Risas', 'Comedia', seedPlaylistId),
          _vod('506', 'Nébula', 'Ciencia ficción', seedPlaylistId),
        ]);
        await db.insertSeriesStreams([
          _ser('601', 'Penumbra', 'Terror / Suspense', seedPlaylistId),
          _ser('602', 'Doble Turno', 'Comedia, Drama', seedPlaylistId),
          _ser('603', 'Cosmos', 'Ciencia ficción', seedPlaylistId),
        ]);
      });
    } catch (_) {
      // Seeding failed (registration/insert): the picker degrades to empty
      // rather than failing the whole capture run.
    }

    await tester.pumpWidget(wrap(const SearchRedesign(onOpen: _noopOpen)));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    try {
      // Reveal + tap the trailing "Géneros" filter chip (mirror studio_search).
      final genreChip = find.text(_esGenres);
      final chipRow = find
          .byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal)
          .first;
      await tester.scrollUntilVisible(
        genreChip,
        160,
        scrollable: find
            .descendant(of: chipRow, matching: find.byType(Scrollable))
            .first,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      await tester.tap(genreChip);
      // enumerateLocalGenres reads the seeded in-memory DB — let it resolve.
      await settleNetwork(tester, seconds: 3);
      await binding.takeScreenshot('search_genre');

      // Pick "Terror" for its owned titles, if the card rendered.
      final terror = find.text('Terror');
      if (terror.evaluate().isNotEmpty) {
        await tester.tap(terror.first);
        await settleNetwork(tester, seconds: 2);
        await binding.takeScreenshot('search_genre_results');
      }
    } catch (_) {
      // Picker interaction failed; any earlier screenshot is already captured.
    } finally {
      // Never let the seeded playlist leak into another scenario.
      AppState.currentPlaylist = null;
    }
  });
}

// A const no-op ContentItem sink so `const SearchRedesign(...)` stays const.
Future<void> _noopOpen(ContentItem _) async {}

// --- Genre-filter capture builders -----------------------------------------
// Poster art is left empty on purpose: the chip rows, grids and pickers are the
// subject of these shots, not network posters (which would just 404 → key-art).

/// A VOD [ContentItem] carrying a packed `genre` string in its [VodStream], the
/// exact shape Browse's full-catalogue filter and GlobalSearchService read.
ContentItem _movieItem(String id, String title, String genre) => ContentItem(
      id,
      title,
      '',
      ContentType.vod,
      containerExtension: 'mp4',
      vodStream: VodStream(
        streamId: id,
        name: title,
        streamIcon: '',
        categoryId: '1',
        rating: '0',
        rating5based: 0,
        containerExtension: 'mp4',
        createdAt: null,
        genre: genre,
      ),
    );

/// A series [ContentItem] carrying a packed `genre` string in its [SeriesStream]
/// (genre_utils reads `seriesStream.genre` for series, `vodStream.genre` else).
ContentItem _seriesItem(String id, String title, String genre) => ContentItem(
      id,
      title,
      '',
      ContentType.series,
      seriesStream: SeriesStream(
        playlistId: 'p',
        seriesId: id,
        name: title,
        genre: genre,
      ),
    );

/// A live channel [ContentItem]. Live rows carry no genre and no stream object —
/// the Live screen only needs a name + (optional) art.
ContentItem _channel(String id, String name) =>
    ContentItem(id, name, '', ContentType.liveStream);

/// A [CategoryViewModel] wrapping [items] under a named [Category] of [type] —
/// how Browse and Live receive their categories.
CategoryViewModel _cat(
  String id,
  String name,
  CategoryType type,
  List<ContentItem> items, {
  String playlistId = 'demo',
}) =>
    CategoryViewModel(
      category: Category(
        categoryId: id,
        categoryName: name,
        parentId: 0,
        playlistId: playlistId,
        type: type,
      ),
      contentItems: items,
    );

/// A [VodStream] row for the seeded DB (search_genre). `createdAt` is required
/// but nullable — null lets the Drift column apply its default.
VodStream _vod(String id, String name, String genre, String playlistId) =>
    VodStream(
      streamId: id,
      name: name,
      streamIcon: '',
      categoryId: '1',
      rating: '0',
      rating5based: 0,
      containerExtension: 'mp4',
      playlistId: playlistId,
      createdAt: null,
      genre: genre,
    );

/// A [SeriesStream] row for the seeded DB (search_genre).
SeriesStream _ser(String id, String name, String genre, String playlistId) =>
    SeriesStream(
      playlistId: playlistId,
      seriesId: id,
      name: name,
      genre: genre,
    );
