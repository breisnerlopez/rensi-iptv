// Integration tests for the GLOBAL "Explorar" (BrowseRedesign): the grid fans
// out over EVERY playlist (not just the active one), de-duplicates LOSSLESSLY
// (movies by definitive tmdbId; series/no-id kept distinct so nothing owned is
// unreachable), default-sorts most-recently-added first, and — when an item is
// opened from a non-active playlist — restores the active playlist on return
// while the watch history saved during playback lands under the ORIGIN.
//
// Local content comes from the in-memory Drift DB (harnessDb). Browse is mounted
// with EMPTY preview categories so the only way a title appears is the global
// full-catalogue load.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import 'harness.dart';

Playlist _pl(String id) => Playlist(
      id: id,
      name: 'PL $id',
      type: PlaylistType.xtream,
      url: 'https://$id.example',
      username: 'u$id',
      password: 'p$id',
      createdAt: DateTime(2026),
    );

VodStream _vod(String playlistId, String name, DateTime added, {int? tmdbId}) =>
    VodStream(
      streamId: 'm-$playlistId-${name.hashCode}',
      name: name,
      streamIcon: '',
      categoryId: 'movies',
      rating: '',
      rating5based: 0,
      containerExtension: 'mp4',
      playlistId: playlistId,
      createdAt: added,
      genre: '',
      tmdbId: tmdbId,
    );

SeriesStream _series(String playlistId, String seriesId, String name) =>
    SeriesStream(
      seriesId: seriesId,
      name: name,
      cover: '',
      categoryId: 'series',
      playlistId: playlistId,
      lastModified: '1700000000',
    );

Future<void> _mountAndLoad(
  WidgetTester tester, {
  Future<void> Function(ContentItem)? onOpen,
}) async {
  await pumpScreen(
    tester,
    BrowseRedesign(
      movieCategories: const [],
      seriesCategories: const [],
      onOpen: onOpen ?? (_) async {},
    ),
  );
  final state = tester.state(find.byType(BrowseRedesign)) as dynamic;
  // Let the real DB fan-out complete deterministically, then paint it.
  // ignore: avoid_dynamic_calls
  await tester.runAsync(() async => await state.loadFuture);
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets(
      'Explorar es GLOBAL: muestra títulos de TODAS las playlists, no solo la activa',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      await PlaylistService.savePlaylist(_pl('B'));
      await harnessDb.insertVodStreams([
        _vod('A', 'SoloEnA', DateTime(2020)),
        _vod('B', 'SoloEnB', DateTime(2021)),
      ]);
    });
    // Active playlist is A; the item that lives ONLY in B must still appear.
    AppState.currentPlaylist = _pl('A');

    await _mountAndLoad(tester);

    expect(find.text('SoloEnA'), findsOneWidget,
        reason: 'la playlist activa se incluye');
    expect(find.text('SoloEnB'), findsOneWidget,
        reason: 'una playlist NO activa también se incluye (global)');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
      'Explorar colapsa copias de la MISMA película (mismo tmdbId) entre playlists',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      await PlaylistService.savePlaylist(_pl('B'));
      await harnessDb.insertVodStreams([
        _vod('A', 'Dune', DateTime(2020), tmdbId: 438631),
        _vod('B', 'Dune', DateTime(2026), tmdbId: 438631),
      ]);
    });
    AppState.currentPlaylist = _pl('A');

    await _mountAndLoad(tester);

    expect(find.text('Dune'), findsOneWidget,
        reason: 'un mismo tmdbId en dos playlists colapsa a una tarjeta');
  }, timeout: const Timeout(Duration(seconds: 60)));

  // Point 6b — ZERO LOSS: two DISTINCT works whose titles normalize identically
  // (no tmdbId) must BOTH remain reachable; the old title-normalization dedup
  // dropped one (e.g. "El Rey León" 1994 vs 2019). And two distinct series
  // (The Office US/UK) likewise.
  testWidgets(
      'Explorar NO pierde obras distintas con título que normaliza igual (sin tmdbId)',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      // Two DIFFERENT movies that normalize to the same "el rey leon" (no id).
      await harnessDb.insertVodStreams([
        _vod('A', 'El Rey León (1994)', DateTime(1994)),
        _vod('A', 'El Rey León (2019)', DateTime(2019)),
      ]);
      // Two DIFFERENT shows that normalize to the same "the office" (no id).
      await harnessDb.insertSeriesStreams([
        _series('A', 's-office-us', 'The Office'),
        _series('A', 's-office-uk', 'The Office (UK)'),
      ]);
    });
    AppState.currentPlaylist = _pl('A');

    await _mountAndLoad(tester);

    expect(find.textContaining('El Rey León'), findsNWidgets(2),
        reason: 'ambas películas distintas deben ser alcanzables (cero pérdida)');
    expect(find.textContaining('The Office'), findsNWidgets(2),
        reason: 'ambas series distintas deben ser alcanzables (cero pérdida)');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Explorar ordena por más reciente primero (date-added desc)',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      await harnessDb.insertVodStreams([
        _vod('A', 'Antiguo', DateTime(2015)),
        _vod('A', 'Reciente', DateTime(2026, 6, 1)),
        _vod('A', 'Medio', DateTime(2020)),
      ]);
    });
    AppState.currentPlaylist = _pl('A');

    await _mountAndLoad(tester);

    // Newest sits first in reading order (row-major: top-to-bottom, then
    // left-to-right). A single grid row shares dy, so fold dx in for the rank.
    double rank(String label) {
      final o = tester.getTopLeft(find.text(label));
      return o.dy * 100000 + o.dx;
    }

    expect(rank('Reciente') < rank('Medio'), isTrue,
        reason: 'lo más reciente va antes que lo intermedio');
    expect(rank('Medio') < rank('Antiguo'), isTrue,
        reason: 'lo intermedio va antes que lo más antiguo');
  }, timeout: const Timeout(Duration(seconds: 60)));

  // Point 6c — RESTORE: opening a non-active item repoints AppState to its
  // origin for playback, then restores the previously-active playlist on return.
  testWidgets(
      'Explorar restaura la playlist activa al volver del player (ítem de otra lista)',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      await PlaylistService.savePlaylist(_pl('B'));
      await harnessDb.insertVodStreams([_vod('B', 'PeliDeB', DateTime(2022))]);
    });
    AppState.currentPlaylist = _pl('A');

    // A controllable "navigation": completes only when we say the route popped.
    final routePopped = Completer<void>();
    await _mountAndLoad(tester, onOpen: (_) => routePopped.future);

    await tester.tap(find.text('PeliDeB'));
    await tester.pump();
    // While "in the player", AppState is repointed to the ORIGIN (B).
    expect(AppState.currentPlaylist?.id, 'B',
        reason: 'la reproducción usa la lista de origen');

    // The player route pops → the active playlist is restored to A.
    routePopped.complete();
    await tester.pump();
    expect(AppState.currentPlaylist?.id, 'A',
        reason: 'al volver, la lista activa vuelve a ser la del usuario (A)');
  }, timeout: const Timeout(Duration(seconds: 60)));

  // Point 6a — DATA GUARANTEE: after openLocalMatch of a non-active item, the
  // watch history saved (as the player does, from AppState) lands under ORIGIN.
  testWidgets(
      'un WatchHistory guardado tras openLocalMatch queda bajo la lista de ORIGEN',
      (tester) async {
    await tester.runAsync(() async {
      await PlaylistService.savePlaylist(_pl('A'));
      await PlaylistService.savePlaylist(_pl('B'));

      AppState.currentPlaylist = _pl('A'); // user is on A
      final service = GlobalSearchService();
      final content = ContentItem(
        'sB', 'PeliDeB', '', ContentType.vod,
        vodStream: _vod('B', 'PeliDeB', DateTime(2022)),
      );
      // Play a copy owned in B: repoints AppState to B for the playback tick.
      service.openLocalMatch(
        LocalContentMatch(playlist: _pl('B'), content: content),
      );
      expect(AppState.currentPlaylist?.id, 'B');

      // Save exactly as player_widget does: playlistId from AppState.
      await WatchHistoryService().saveWatchHistory(WatchHistory(
        playlistId: AppState.currentPlaylist!.id,
        contentType: ContentType.vod,
        streamId: 'sB',
        lastWatched: DateTime(2026, 7, 1),
        title: 'PeliDeB',
        imagePath: '',
        totalDuration: const Duration(minutes: 90),
        watchDuration: const Duration(minutes: 10),
      ));

      final svc = WatchHistoryService();
      expect(await svc.getWatchHistory('B', 'sB'), isNotNull,
          reason: 'el historial se guarda bajo la lista de ORIGEN (B)');
      expect(await svc.getWatchHistory('A', 'sB'), isNull,
          reason: 'nunca bajo la lista que el usuario tenía activa (A)');
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
