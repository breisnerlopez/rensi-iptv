// Widget/integration tests for the global TMDb search UI (the built
// `SearchRedesign` + `SearchDetailSheet`), mounting the REAL screen and
// driving it exactly as a home surface does: `SearchRedesign(onOpen: ...)`.
//
// The screen owns its own GlobalSearchService()/TmdbService(), so we cannot
// hand it a fake. Instead we control TMDb the way the production stack does:
//   - TMDb SUCCESS is injected by pre-seeding the SharedPreferences search
//     cache that TmdbService consults BEFORE any credential/network — a cache
//     hit returns those results with zero network. Key form:
//     'tmdb.search.<lang>.<foldedQuery>' (harness locale es -> 'es-ES').
//   - TMDb FAILURE (noKey) is the default: no credential is ever seeded, so a
//     cache miss makes TmdbService throw noKey, which GlobalSearchService
//     catches into `tmdbFailure` while the local buckets survive.
// Local results come from the in-memory Drift DB (harnessDb).
//
// Assertions use the Spanish strings (harness locale is 'es').
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/widgets/tv/tv_keyboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

// The active playlist a user is browsing when they open global search. Both
// homes push SearchRedesign from within a playlist's home, so AppState has a
// current playlist. Kept here so tests can restore that real launch context.
final _activePlaylist = Playlist(
  id: 'pl1',
  name: 'Mi IPTV',
  type: PlaylistType.xtream,
  url: 'https://x.com',
  username: 'u',
  password: 'p',
  createdAt: DateTime(2026),
);

// --- Spanish strings under test (harness locale) ---------------------------
const _kInLibrary = 'En tu biblioteca';
const _kFromIptv = 'Desde tu IPTV';
const _kDiscover = 'Descubrir en TMDb';
const _kNotInLists = 'No en tus listas';
const _kNotAvailableBody =
    'No está en tus listas. Guárdalo y lo revisamos cuando aparezca.';
const _kGlobalDisabled =
    'Añade tu clave de TMDb para descubrir títulos fuera de tus listas.';
const _kKeepTyping = 'Sigue escribiendo para buscar en TMDb';
const _kWishlistChip = 'Lista de deseos';
const _kWishlistEmpty =
    'Tu lista de deseos está vacía. Toca el marcador en cualquier resultado de TMDb para guardarlo aquí.';
const _kPlayFrom = 'Reproducir desde';

// --- TMDb injection helpers ------------------------------------------------

Map<String, dynamic> _tmdb(int id, String title, {String type = 'movie'}) => {
      'id': id,
      'mediaType': type,
      'title': title,
      'overview': 'Sinopsis de $title',
      'posterPath': null,
      'releaseDate': '2021-01-01',
      'voteAverage': 8.0,
    };

/// A SharedPreferences cache entry that TmdbService will read as a hit for
/// [query] in the es-ES locale, returning [results] without a credential.
MapEntry<String, String> _cache(String query, List<Map<String, dynamic>> results) {
  final key = 'tmdb.search.es-ES.${query.toLowerCase()}';
  final value = jsonEncode({
    'cachedAt': DateTime.now().toIso8601String(),
    'results': results,
  });
  return MapEntry(key, value);
}

MapEntry<String, String> _wishlist(List<Map<String, dynamic>> items) =>
    MapEntry('tmdb.wishlist', jsonEncode(items));

/// Seeds prefs + DB and establishes the active-playlist context before the
/// screen mounts. Prefs are written THROUGH the live SharedPreferences
/// singleton (which TmdbService/TmdbWishlistService share) after a clear(), so
/// injection is deterministic regardless of the cross-test singleton cache —
/// `setMockInitialValues` alone doesn't refresh an already-created instance.
///
/// [activePlaylist] mirrors the real launch context (a user browsing a
/// playlist opens search). Pass false only to exercise the no-active-playlist
/// edge case.
Future<void> _prime(
  WidgetTester tester, {
  List<MapEntry<String, String>> prefs = const [],
  List<(String, String)> movies = const [],
  bool activePlaylist = true,
}) async {
  await tester.runAsync(() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    for (final e in prefs) {
      await sp.setString(e.key, e.value);
    }
    await _seedPlaylist();
    for (final m in movies) {
      await _seedMovie(m.$1, genre: m.$2);
    }
  });
  AppState.currentPlaylist = activePlaylist ? _activePlaylist : null;
}

// --- Local (DB) seeding ----------------------------------------------------

Future<void> _seedPlaylist() => PlaylistService.savePlaylist(_activePlaylist);

Future<void> _seedMovie(String name, {String genre = ''}) =>
    harnessDb.insertVodStreams([
      VodStream(
        streamId: 'm-${name.hashCode}',
        name: name,
        streamIcon: '',
        categoryId: 'movies',
        rating: '',
        rating5based: 0,
        containerExtension: 'mp4',
        playlistId: 'pl1',
        createdAt: DateTime(2026),
        genre: genre,
      ),
    ]);

// --- Focus probes (TV) -----------------------------------------------------

bool _focusInside<T extends Widget>() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget is T) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _typeOnTvKeyboard(WidgetTester tester, String word) async {
  for (final ch in word.toUpperCase().split('')) {
    await tester.tap(find.text(ch), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 20));
  }
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);
  tearDown(tearDownHarness);

  // 1) No API key: local results survive AND the no-key banner appears. The
  //    search must degrade, never blank/error.
  testWidgets('sin clave: los resultados locales sobreviven y aparece el aviso',
      (tester) async {
    await setUpHarness(tv: false); // no cache, no credential -> TMDb noKey
    await _prime(tester, movies: [('Dune', '')]);

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: phoneSize);
    await tester.enterText(find.byType(TextField), 'dune');
    await settle(tester);

    // Local survived the TMDb failure.
    expect(find.text(_kFromIptv), findsOneWidget,
        reason: 'la sección local debe seguir presente pese al fallo de TMDb');
    expect(find.text('Dune'), findsWidgets,
        reason: 'el título local debe verse');
    // The no-key banner is shown, above the results (never replacing them).
    expect(find.text(_kGlobalDisabled), findsOneWidget,
        reason: 'debe aparecer el aviso de búsqueda global desactivada');
  });

  // 2) A tmdbOnly result is NOT playable: it carries the neutral badge and a
  //    tap opens the detail sheet, never the player (onOpen must not fire).
  //    Also proves empty sections (library / owned) are hidden.
  testWidgets('tmdbOnly no reproducible: badge neutro + hoja de detalle',
      (tester) async {
    await setUpHarness(tv: false);
    // No local seeded -> Dune is discover-only.
    await _prime(tester, prefs: [_cache('dune', [_tmdb(1, 'Dune')])]);
    var opened = false;
    await pumpScreen(
        tester, SearchRedesign(onOpen: (_) => opened = true), size: phoneSize);
    await tester.enterText(find.byType(TextField), 'dune');
    await settle(tester);

    // Only the discover section renders; the two reproducible ones are hidden.
    expect(find.text(_kDiscover), findsOneWidget);
    expect(find.text(_kInLibrary), findsNothing,
        reason: 'una sección vacía (biblioteca) no debe renderizarse');
    expect(find.text(_kFromIptv), findsNothing,
        reason: 'una sección vacía (IPTV) no debe renderizarse');
    // The neutral "not in your lists" badge marks it as discovery.
    expect(find.text(_kNotInLists), findsOneWidget,
        reason: 'el póster tmdbOnly lleva la marca neutra');

    // Tapping opens the save-only detail sheet, not the player.
    await tester.tap(find.byKey(const ValueKey('tm:1|movie')),
        warnIfMissed: false);
    await settle(tester);
    expect(find.text(_kNotAvailableBody), findsOneWidget,
        reason: 'un tmdbOnly abre la hoja de detalle (guardar), sin reproducir');
    expect(opened, isFalse,
        reason: 'un tmdbOnly NUNCA debe disparar la reproducción (onOpen)');
  });

  // 3) An owned (withLocal) result with a single match plays directly.
  testWidgets('withLocal con un único match reproduce directo', (tester) async {
    await setUpHarness(tv: false);
    await _prime(tester,
        prefs: [_cache('dune', [_tmdb(1, 'Dune')])],
        movies: [('Dune', '')]); // exact match with the TMDb title -> withLocal

    ContentItem? opened;
    await pumpScreen(tester, SearchRedesign(onOpen: (c) => opened = c),
        size: phoneSize);
    await tester.enterText(find.byType(TextField), 'dune');
    await settle(tester);

    expect(find.text(_kInLibrary), findsOneWidget,
        reason: 'un título owned+TMDb va a "En tu biblioteca"');

    await tester.tap(find.byKey(const ValueKey('wl:1|movie')),
        warnIfMissed: false);
    await settle(tester);

    expect(opened, isNotNull,
        reason: 'un único match reproducible dispara onOpen directamente');
    expect(opened!.name, 'Dune');
    // A single match plays directly; it must NOT open the "play from" sheet.
    expect(find.text(_kPlayFrom), findsNothing,
        reason: 'con un solo match no debe abrirse la hoja "Reproducir desde"');
  });

  // 4) The three sections render, reproducible-first, in order.
  testWidgets('las tres secciones se renderizan en orden', (tester) async {
    await setUpHarness(tv: false);
    // Dune matches a local title (withLocal); Inception has no local (tmdbOnly).
    await _prime(tester,
        prefs: [_cache('scifi', [_tmdb(1, 'Dune'), _tmdb(2, 'Inception')])],
        movies: [('Dune', 'scifi'), ('Avatar', 'scifi')]);

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}),
        size: const Size(420, 2200));
    await tester.enterText(find.byType(TextField), 'scifi');
    await settle(tester);

    expect(find.text(_kInLibrary), findsOneWidget);
    expect(find.text(_kFromIptv), findsOneWidget);
    expect(find.text(_kDiscover), findsOneWidget);

    final yLibrary = tester.getTopLeft(find.text(_kInLibrary)).dy;
    final yOwned = tester.getTopLeft(find.text(_kFromIptv)).dy;
    final yDiscover = tester.getTopLeft(find.text(_kDiscover)).dy;
    expect(yLibrary, lessThan(yOwned),
        reason: '"En tu biblioteca" va antes que "Desde tu IPTV"');
    expect(yOwned, lessThan(yDiscover),
        reason: '"Desde tu IPTV" va antes que "Descubrir en TMDb"');
  });

  // 5) Wishlist filter shows saved items; toggling the bookmark updates state.
  testWidgets('lista de deseos muestra guardados y el toggle actualiza estado',
      (tester) async {
    await setUpHarness(tv: false);
    await _prime(tester, prefs: [_wishlist([_tmdb(1, 'Dune')])]);

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: phoneSize);
    // Browse the wishlist (no local seeded -> Dune shows as a saved discovery).
    await tester.tap(find.text(_kWishlistChip), warnIfMissed: false);
    await settle(tester);

    expect(find.text('Dune'), findsWidgets,
        reason: 'el título guardado debe listarse');
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget,
        reason: 'el marcador guardado se muestra activo');

    // Real-device review (blocker): the wishlist must read as YOUR list, not as
    // discovery. Under the wishlist filter the section header is "Lista de
    // deseos" and the card badge is "Guardado" — never "Descubrir en TMDb" /
    // "No en tus listas", which told the user their own saved list was not in
    // their lists.
    expect(find.text(_kDiscover), findsNothing,
        reason: 'la wishlist no debe titularse "Descubrir en TMDb"');
    expect(find.text(_kNotInLists), findsNothing,
        reason: 'un guardado no debe llevar el badge "No en tus listas"');
    expect(find.text('Guardado'), findsWidgets,
        reason: 'el badge de un guardado debe decir "Guardado"');
    expect(find.text(_kWishlistChip), findsWidgets,
        reason: 'la sección de la wishlist se titula "Lista de deseos"');

    // Toggle the bookmark off -> removed -> the browse re-runs empty.
    await tester.tap(find.byIcon(Icons.bookmark_rounded), warnIfMissed: false);
    await settle(tester);

    expect(find.text(_kWishlistEmpty), findsOneWidget,
        reason: 'quitar el último guardado debe dejar la lista vacía (estado actualizado)');
  });

  // 6a) Progressive: at exactly two chars, local shows plus the "keep typing"
  //     hint where Discover would go — never a spinner, never a discover header.
  testWidgets('progresivo: a 2 chars se ve lo local + pista, sin TMDb',
      (tester) async {
    await setUpHarness(tv: false);
    await _prime(tester, movies: [('Dune', '')]);

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: phoneSize);
    await tester.enterText(find.byType(TextField), 'du');
    await settle(tester);

    expect(find.text(_kFromIptv), findsOneWidget,
        reason: 'lo local aparece de inmediato (searchLocalFirst)');
    expect(find.text(_kKeepTyping), findsOneWidget,
        reason: 'a 2 chars se muestra la pista de "sigue escribiendo"');
    expect(find.text(_kDiscover), findsNothing,
        reason: 'a 2 chars TMDb no arma: sin sección Descubrir');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'nunca un spinner a pantalla completa tapando lo local');
  });

  // 6b) TV: typing on the on-screen keyboard must NOT steal focus into the
  //     results (the old autofocus-per-rebuild bug). Focus stays on the keyboard.
  testWidgets('TV: teclear no roba el foco hacia los resultados',
      (tester) async {
    await setUpHarness(tv: true);
    await _prime(tester,
        prefs: [_cache('dune', [_tmdb(1, 'Dune')])],
        movies: [('Dune', '')]);

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: tvSize);
    await _typeOnTvKeyboard(tester, 'dune');

    // Results have painted (withLocal Dune).
    expect(find.text(_kInLibrary), findsOneWidget,
        reason: 'los resultados deben haberse pintado tras teclear');
    // ...but focus is still on the keyboard, never on a results poster.
    expect(_focusInside<TvKeyboard>(), isTrue,
        reason: 'el foco debe permanecer en el teclado mientras se teclea');
    expect(_focusInside<RensiPoster>(), isFalse,
        reason: 'teclear NO debe mover el foco a un póster de resultados');
  });

  // 7) REGRESSION (BUG): a discover (tmdbOnly) card must render even when there
  //    is no active playlist. Rendering one builds a ContentItem via
  //    _tmdbAsContentItem (search_redesign.dart:663); the ContentItem ctor
  //    eagerly evaluates `url = isXtreamCode ? buildMediaUrl(this) : ...`, and
  //    both isXtreamCode (get_playlist_type.dart:5) and buildMediaUrl
  //    (build_media_url.dart:7) dereference AppState.currentPlaylist!. With no
  //    active playlist that threw a null-check error DURING BUILD, which
  //    crashed the WHOLE results view (library + IPTV sections included), not
  //    just the one card. Fixed by making isXtreamCode/isM3u null-safe
  //    (get_playlist_type.dart); this guards that fix.
  testWidgets(
      'BUG: la sección Descubrir no debe crashear sin playlist activa',
      (tester) async {
    await setUpHarness(tv: false);
    await _prime(tester,
        prefs: [_cache('dune', [_tmdb(1, 'Dune')])],
        activePlaylist: false); // no active playlist

    await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: phoneSize);
    await tester.enterText(find.byType(TextField), 'dune');
    await settle(tester);

    expect(tester.takeException(), isNull,
        reason: 'construir una tarjeta de descubrimiento NO debe lanzar '
            '(ContentItem calcula url con AppState.currentPlaylist! ansiosamente)');
    expect(find.text(_kDiscover), findsOneWidget,
        reason: 'la sección Descubrir debe renderizarse igualmente');
  });

  // --- Layout: no overflow at real TV metrics --------------------------------
  //
  // A 1080p Android TV reports 960x540 LOGICAL dp (not 1920x1080) — the trap
  // that caused half a dozen defects earlier in this project. The on-device
  // capture campaign runs in --profile, where RenderFlex overflow assertions
  // are DISABLED, so it cannot catch this. These run in debug, where an
  // overflow throws and surfaces via takeException(). This is the deterministic
  // guard for "no layout breakage on a 10-foot screen" that the screenshots
  // cannot provide.
  group('Layout — no overflow at TV 960x540', () {
    const tvLogical = Size(960, 540);
    const longTitle = 'Dune: Part Two — The Long Extended Special Edition';

    testWidgets('three sections + long titles', (tester) async {
      await setUpHarness(tv: true);
      await _prime(
        tester,
        prefs: [_cache('dun', [_tmdb(1, 'Dune'), _tmdb(2, longTitle)])],
        movies: [('Dune 2021', ''), ('Duna Roja del Desierto Profundo', '')],
      );
      await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: tvLogical);
      await _typeOnTvKeyboard(tester, 'dun');
      expect(find.text(_kInLibrary), findsOneWidget,
          reason: 'precondition: results painted');
      expect(tester.takeException(), isNull,
          reason: 'the three-section results must not overflow at TV metrics');
    });

    // German and Russian section/chip/banner strings are the longest of the 10
    // locales; a fixed-width container that fits Spanish can still overflow here.
    for (final lang in ['de', 'ru']) {
      testWidgets('three sections do not overflow in "$lang"', (tester) async {
        await setUpHarness(tv: true);
        await _prime(
          tester,
          prefs: [_cache('dun', [_tmdb(1, 'Dune'), _tmdb(2, longTitle)])],
          movies: [('Dune 2021', ''), ('Duna Roja del Desierto', '')],
        );
        await pumpScreen(tester, SearchRedesign(onOpen: (_) {}),
            size: tvLogical, locale: Locale(lang));
        await _typeOnTvKeyboard(tester, 'dun');
        expect(tester.takeException(), isNull,
            reason: 'longer $lang strings must not overflow at TV metrics');
      });
    }

    testWidgets('no-key banner + local results', (tester) async {
      await setUpHarness(tv: true);
      await _prime(tester, movies: [('Dune 2021', '')]); // no cache -> noKey
      await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: tvLogical);
      await _typeOnTvKeyboard(tester, 'dune');
      expect(find.text(_kGlobalDisabled), findsOneWidget,
          reason: 'precondition: the no-key banner is shown');
      expect(tester.takeException(), isNull,
          reason: 'the banner + results must not overflow at TV metrics');
    });

    testWidgets('tmdbOnly detail sheet', (tester) async {
      await setUpHarness(tv: true);
      await _prime(tester, prefs: [_cache('dune', [_tmdb(2, longTitle)])]);
      await pumpScreen(tester, SearchRedesign(onOpen: (_) {}), size: tvLogical);
      await _typeOnTvKeyboard(tester, 'dune');
      await tester.tap(find.text(longTitle).first, warnIfMissed: false);
      await settle(tester);
      expect(tester.takeException(), isNull,
          reason: 'the detail sheet (long overview + buttons) must not '
              'overflow at TV metrics');
    });
  });

  // --- RTL (Arabic): the app ships ar; the search must mirror, not overflow ---
  group('RTL — Arabic', () {
    const longTitle = 'Dune: Part Two — The Long Extended Special Edition';

    testWidgets('mobile: populated results render RTL without overflow',
        (tester) async {
      await setUpHarness(tv: false);
      await _prime(
        tester,
        prefs: [_cache('dune', [_tmdb(1, 'Dune'), _tmdb(2, longTitle)])],
        movies: [('Dune 2021', '')],
      );
      await pumpScreen(tester, SearchRedesign(onOpen: (_) {}),
          size: phoneSize, locale: const Locale('ar'));
      await tester.enterText(find.byType(TextField), 'dune');
      await settle(tester);

      expect(Directionality.of(tester.element(find.byType(SearchRedesign))),
          TextDirection.rtl,
          reason: 'the whole search must lay out right-to-left in Arabic');
      expect(tester.takeException(), isNull,
          reason: 'Arabic chrome + results must not overflow');
    });

    testWidgets('TV: two-column layout mirrors without overflow',
        (tester) async {
      await setUpHarness(tv: true);
      await _prime(tester);
      await pumpScreen(tester, SearchRedesign(onOpen: (_) {}),
          size: const Size(960, 540), locale: const Locale('ar'));
      await settle(tester);
      expect(Directionality.of(tester.element(find.byType(SearchRedesign))),
          TextDirection.rtl);
      expect(tester.takeException(), isNull,
          reason: 'the keyboard/results two-column TV layout must mirror '
              'cleanly in Arabic');
    });
  });
}
