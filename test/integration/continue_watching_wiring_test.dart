import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/screens/m3u/m3u_home_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import 'harness.dart';
import 'seed.dart';

// The WIRING, not the widget.
//
// The continue-watching rail shipped with the redesign and never once appeared
// in the app: the parameter existed, defaulted to an empty list, and no screen
// ever passed anything. The first tests written for the fix fed RedesignHome by
// hand — so they exercised the widget that already worked, and the mutation
// that left them all green was precisely the original bug: delete
// `continueWatching:`/`onResume:` from the home screens and the feature goes
// back to being inert with the whole suite passing.
//
// This file mounts the real screen over a seeded database instead, so the path
// under test is the one that was broken: rows → controller → filter → rail.
//
// One gap, stated rather than papered over: removing `_history.addListener`
// does NOT fail these tests. The screen rebuilds anyway here because the
// category controller notifies after its own load, so the rail gets painted
// regardless. The listener is what guarantees the rail appears when history
// resolves AFTER everything else has settled — an ordering this harness does
// not produce and a real panel over a slow link does. Asserting "a listener was
// registered" would be a structural check of the kind that has already gone
// quietly dead twice in this codebase, so it is left uncovered and named.
//
// The titles are deliberately absent from the seeded catalogue. The first draft
// reused names the seed already puts in the movie rails, and the negative cases
// failed for the right reason by accident while the POSITIVE one would have
// passed even with the rail disconnected — it would have been finding the
// catalogue poster, not the history entry.
Future<void> _writeHistory(
  String streamId,
  String title, {
  required int watched,
  required int total,
  ContentType type = ContentType.vod,
}) =>
    WatchHistoryService().saveWatchHistory(WatchHistory(
      playlistId: 'test-playlist-1',
      contentType: type,
      streamId: streamId,
      title: title,
      imagePath: '',
      lastWatched: DateTime(2026, 7, 1),
      watchDuration: Duration(seconds: watched),
      totalDuration: Duration(seconds: total),
    ));

void main() {
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  Future<Playlist> seedWith(
      WidgetTester tester, Future<void> Function() rows) async {
    late Playlist p;
    await tester.runAsync(() async {
      p = await seedXtreamHome(harnessDb);
      await rows();
    });
    return p;
  }

  testWidgets('an unfinished title reaches the home screen', (tester) async {
    final p = await seedWith(
        tester,
        () => _writeHistory('vod_1_movie_0', 'Solaris (1972)',
            watched: 2400, total: 7200));

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Solaris (1972)'), findsWidgets,
        reason: 'the row is in the database and the rail is on screen, so the '
            'home is not passing it through — which is exactly how this '
            'feature spent its whole life');
  });

  testWidgets('a finished title is not offered again', (tester) async {
    final p = await seedWith(
        tester,
        () => _writeHistory('vod_1_movie_1', 'Stalker (1979)',
            watched: 7100, total: 7200));

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Stalker (1979)'), findsNothing,
        reason: 'watched to the credits and still being offered to continue: '
            'the query only asks that durations exist, so without the ceiling '
            'the rail fills up with things already seen');
  });

  testWidgets('a title only glanced at (a few seconds) is not offered',
      (tester) async {
    final p = await seedWith(
        tester,
        () => _writeHistory('vod_1_movie_2', 'Andrei Rublev',
            watched: 10, total: 7200));

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Andrei Rublev'), findsNothing,
        reason: 'a title opened for a few seconds by accident (< 30s and < 2%) '
            'is not something you are partway through');
  });

  testWidgets('a movie watched ~30s+ IS offered even if that is under 2%',
      (tester) async {
    // On a 2h movie 2% is ~2.4 min, so the old bare-2% floor hid a real
    // few-minutes-in play. The 30s absolute floor now surfaces it.
    final p = await seedWith(
        tester,
        () => _writeHistory('vod_1_movie_9', 'Stalker (1979)',
            watched: 45, total: 7200));

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Stalker (1979)'), findsWidgets,
        reason: '45s watched clears the ~30s resume floor');
  });

  testWidgets('the M3U home is wired too', (tester) async {
    // The rail was cabled into both homes and the filter was copy-pasted into
    // both, so a guard on one of them left the other free to drift — or to be
    // unwired entirely — with the suite green. The filter now lives in one
    // place; this makes sure the second screen actually calls it.
    final p = await seedWith(
        tester,
        () => _writeHistory('vod_1_movie_3', 'El Espejo (1975)',
            watched: 1800, total: 7200));

    await pumpScreen(tester, M3UHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('El Espejo (1975)'), findsWidgets,
        reason: 'M3U playlists record history the same way, so leaving this '
            'home unwired makes the feature depend on which kind of list you '
            'happened to add');
  });

  testWidgets('a live channel is never offered', (tester) async {
    // getContinueWatching does not filter by type, and a channel with a DVR
    // window reports a real, growing duration — so it would appear behind a
    // progress bar that the player contradicts the moment it opens.
    final p = await seedWith(
        tester,
        () => _writeHistory('live_1_stream_0', 'Canal Piloto 24h',
            watched: 1200, total: 3600, type: ContentType.liveStream));

    await pumpScreen(tester, XtreamCodeHomeScreen(playlist: p));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Canal Piloto 24h'), findsNothing,
        reason: 'a live channel has no position to resume from');
  });

  // A history row can outlive the catalogue entry it points at: an Xtream
  // refresh drops titles, the row stays. playContent caught the resulting
  // StateError into `errorMessage`, which had no reader anywhere in lib/ — so
  // the card was simply inert on tap, indistinguishable from a frozen UI.
  //
  // The streamId below is deliberately absent from the seeded catalogue while
  // the title is present in the rail, which is the exact shape of the bug.
  for (final home in ['Xtream', 'M3U']) {
    testWidgets('$home: a resume that cannot start says so', (tester) async {
      final p = await seedWith(
          tester,
          () => _writeHistory('vod_1_movie_does_not_exist', 'Nostalghia (1983)',
              watched: 1800, total: 7200));

      await pumpScreen(
        tester,
        home == 'Xtream'
            ? XtreamCodeHomeScreen(playlist: p)
            : M3UHomeScreen(playlist: p),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final card = find.text('Nostalghia (1983)');
      expect(card, findsWidgets,
          reason: 'precondition: the dead entry has to reach the rail before '
              'tapping it can prove anything');

      // On the Xtream home the rail lands at y≈715 of a 720px-tall TV surface,
      // so the label is on screen but its centre is not: tap() reports a missed
      // hit test and the assertion below then fails for the wrong reason.
      await tester.ensureVisible(card.first);
      await tester.pumpAndSettle();
      await tester.tap(card.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Harness locale is 'es'.
      expect(find.text('Este título ya no está disponible en esta lista'),
          findsOneWidget,
          reason: 'the tap failed and the viewer was told nothing: revert '
              'playContent to Future<void> and this is the only guard that '
              'goes red');
    });
  }
}
