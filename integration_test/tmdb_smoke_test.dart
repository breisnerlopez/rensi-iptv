// Opt-in TMDb smoke test — verifies the real TMDb API + our Phase 1/2 wiring
// against a live key. Run on a networked device/emulator:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/tmdb_smoke_test.dart -d <device> --profile \
//     --dart-define-from-file=<path>/tmdb_env.json   # { "TMDB_TOKEN": "..." }
//
// The token is passed at runtime only (never committed). v4 bearer rides in the
// Authorization header, so it never appears in a URL/log. Prints only public
// movie/person data + counts — never the token.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const token = String.fromEnvironment('TMDB_TOKEN');
  const es = Locale('es');

  testWidgets('TMDb live smoke: detail+cast, title match, person search',
      (tester) async {
    expect(token, isNotEmpty,
        reason: 'pass --dart-define-from-file with TMDB_TOKEN');
    await TmdbCredentialsService.saveCredential(token);
    final svc = TmdbService();

    await tester.runAsync(() async {
      // 1) Detail with credits+videos for a known movie (Avengers: Endgame).
      final d = await svc.detail(299534, TmdbMediaType.movie,
          withCredits: true, locale: es);
      // ignore: avoid_print
      print('SMOKE detail: title="${d.title}" overviewLen=${(d.overview ?? "").length} '
          'cast=${d.cast.length} videos=${d.videos.length} '
          'trailer=${d.bestTrailer?.key != null}');

      // 2) The user's failing case: a local title that TMDb lists differently.
      //    "Horizonte Profundo" (es) == "Deepwater Horizon" (en).
      final hits = await svc.searchTitle('Horizonte Profundo',
          mediaType: TmdbMediaType.movie, locale: es);
      // ignore: avoid_print
      print('SMOKE searchTitle("Horizonte Profundo"): ${hits.length} results');
      for (final h in hits.take(3)) {
        // ignore: avoid_print
        print('   -> id=${h.id} title="${h.title}"');
      }
      if (hits.isNotEmpty) {
        final det = await svc.detail(hits.first.id, TmdbMediaType.movie,
            withCredits: true, locale: es);
        // ignore: avoid_print
        print('SMOKE horizonte detail: title="${det.title}" '
            'overviewLen=${(det.overview ?? "").length} cast=${det.cast.length}');
      }

      // 2b) The user's EXACT dirty filename title vs a cleaned one.
      for (final t in const [
        'Horizonte profundo Desastre en el golfo (2016).mp4',
        'Horizonte profundo',
        'Horizonte Profundo Desastre en el golfo',
      ]) {
        final r = await svc.searchTitle(t,
            mediaType: TmdbMediaType.movie, locale: es);
        // ignore: avoid_print
        print('SMOKE dirty "$t": ${r.length} -> '
            '${r.isNotEmpty ? '"${r.first.title}" (${r.first.releaseYear})' : "NONE"}');
      }

      // 3) Person search + filmography (Phase 2).
      final people = await svc.searchPerson('vin diesel', locale: es);
      // ignore: avoid_print
      print('SMOKE person: ${people.length} '
          'first="${people.isNotEmpty ? people.first.name : "-"}"');
      if (people.isNotEmpty) {
        final credits = await svc.getPersonCredits(people.first.id, locale: es);
        // ignore: avoid_print
        print('SMOKE credits: ${credits.length}');
      }
    });

    await TmdbCredentialsService.deleteCredential();
  });
}
