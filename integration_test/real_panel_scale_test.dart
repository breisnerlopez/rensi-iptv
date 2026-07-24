// Real-scale ingest against a REAL Xtream panel — the market-readiness gap that
// the seeded captures could never cover: does the app fetch, parse and persist a
// tens-of-thousands-item catalogue without falling over?
//
// Runs as an integration_test ON A DEVICE, because `flutter test` on the host
// installs an HttpOverrides that makes every real request return 400 ("no
// network request will be made") — so a host test can never reach a real panel.
// The integration_test binding does real I/O (it is how the player capture
// reached a real live stream), which is exactly what this needs.
//
// Opt-in via --dart-define (nothing is committed):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/real_panel_scale_test.dart -d <device> --profile \
//     --dart-define=PANEL_HOST=host:port --dart-define=PANEL_USER=u \
//     --dart-define=PANEL_PASS=p
// Without the defines the test skips, so a normal run needs no secret.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';

import '../test/integration/harness.dart';

const _host = String.fromEnvironment('PANEL_HOST');
const _user = String.fromEnvironment('PANEL_USER');
const _pass = String.fromEnvironment('PANEL_PASS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('real panel: full catalogue ingests at scale', (tester) async {
    if (_host.isEmpty) {
      markTestSkipped('PANEL_HOST no definido — se omite la prueba de panel real');
      return;
    }
    final repo = IptvRepository(
      ApiConfig(baseUrl: 'http://$_host', username: _user, password: _pass),
      'real-scale',
    );

    // Real Xtream panels throttle bursts with a transient HTTP 400, and the
    // repository returns null on any non-200 with no retry of its own. Retry
    // with backoff here so the scale measurement isn't defeated by throttling.
    Future<T?> withRetry<T>(Future<T?> Function() f, {int tries = 6}) async {
      for (var i = 0; i < tries; i++) {
        final r = await f();
        if (r != null) return r;
        await Future<void>.delayed(Duration(seconds: 6 * (i + 1)));
      }
      return null;
    }

    // Auth first (writes user/server info).
    final info = await withRetry(() => repo.getPlayerInfo(forceRefresh: true));
    expect(info, isNotNull, reason: 'la autenticación real debe funcionar');

    Future<int> timed(String label, Future<List<dynamic>?> Function() f) async {
      final sw = Stopwatch()..start();
      final list = await withRetry(f);
      sw.stop();
      final n = list?.length ?? -1;
      // ignore: avoid_print
      print('SCALE  $label: count=$n  fetch+parse+store=${sw.elapsedMilliseconds}ms');
      return n;
    }

    // Small stagger between catalogue-wide calls: hammering three back-to-back
    // is exactly what trips the panel's burst throttle.
    final live = await timed('live  ', () => repo.getLiveChannelsFromApi());
    await Future<void>.delayed(const Duration(seconds: 4));
    final vod = await timed('vod   ', () => repo.getMoviesFromApi());
    await Future<void>.delayed(const Duration(seconds: 4));
    final series = await timed('series', () => repo.getSeriesFromApi());

    // Sanity: real panels carry thousands; a tiny count means the parse/store
    // silently dropped rows.
    expect(live, greaterThan(500), reason: 'canales en vivo reales');
    expect(vod, greaterThan(5000), reason: 'VOD real a escala');
    expect(series, greaterThan(500), reason: 'series reales');

    // Persistence held: what we stored is what we can read back.
    final storedVod = await harnessDb.getVodStreamsByPlaylistId('real-scale');
    // ignore: avoid_print
    print('SCALE  vod persisted & read-back: ${storedVod.length}');
    expect(storedVod.length, vod,
        reason: 'todo lo insertado debe leerse de vuelta desde Drift');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
