// ON-DEVICE credential-leak guard. Runs the real engine on a real Android /
// Android-TV device, where libmpv, the platform channels and the framework's
// error machinery all behave for real — none of which exist under
// `flutter test`.
//
// Why this exists: Xtream puts the subscription user and password *inside the
// stream path*, so every raw error string is a credential disclosure. An audit
// of this app found them reaching the player overlay, the snackbar, the
// full-screen error state and logcat. `credential_scrubber.dart` closes those
// paths; this test proves it on the device rather than in a unit-test harness.
//
// Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/credential_leak_test.dart -d <device> --profile
//
// The host should ALSO grep logcat for the same decoys after this run — the
// widget tree is only one of the two sinks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/utils/player_error_handler.dart';

import '../test/integration/harness.dart';

// Distinctive so a grep over logcat / screenshots cannot produce false hits.
const String decoyUser = 'ZQXDECOYUSER77';
const String decoyPass = 'ZQXDECOYPASS88';

/// Every text node currently on screen, joined. Cheaper and stricter than
/// hunting for a specific widget: if the credential is painted anywhere, it
/// shows up here.
String visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await setUpHarness();
    AppState.currentPlaylist = Playlist(
      id: 'decoy',
      name: 'Decoy',
      type: PlaylistType.xtream,
      url: 'http://nohost.invalid:8080',
      username: decoyUser,
      password: decoyPass,
      createdAt: DateTime(2026, 1, 1),
    );
  });
  tearDown(tearDownHarness);

  void expectNoDecoy(String haystack, String where) {
    expect(haystack, isNot(contains(decoyUser)), reason: where);
    expect(haystack, isNot(contains(decoyPass)), reason: where);
  }

  testWidgets('a raw libmpv error never reaches a pixel', (tester) async {
    // A NON-retryable libmpv error: only this branch surfaces text to the user.
    // (Anything containing 'Failed to open' is retried instead, and the retry
    // counter lives in a Timer that does not fire under test — so asserting on
    // that path would assert on nothing.)
    final raw = 'Cannot open stream '
        'http://nohost.invalid:8080/live/$decoyUser/$decoyPass/1.ts';

    String? shown;
    PlayerErrorHandler().handleError(raw, () {}, (msg) => shown = msg);

    expect(shown, isNotNull, reason: 'the handler must surface something');
    expectNoDecoy(shown!, 'PlayerErrorHandler -> snackbar');
    expect(shown, contains('nohost.invalid'),
        reason: 'the host must survive, or the message is useless');
  });

  testWidgets('an uncaught exception renders a scrubbed error screen',
      (tester) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (_) => throw Exception(
            'Failed to open http://nohost.invalid:8080/live/$decoyUser/$decoyPass/1.ts'),
      ),
      size: null, // device-native surface
    );
    expect(tester.takeException(), isNotNull);
    expectNoDecoy(visibleText(tester), 'ErrorWidget on screen');
  });

  testWidgets('the M3U parse failure path is scrubbed', (tester) async {
    // Same shape M3uParser throws for a bad playlist URL.
    final scrubbed = scrubCredentials(
        'M3uParseException(m3u_url_fetch_failed): '
        'HttpException: host lookup failed, uri = '
        'http://nohost.invalid:8080/get.php?username=$decoyUser&password=$decoyPass');
    expectNoDecoy(scrubbed, 'M3U parse failure');
  });

  testWidgets('an rtmp stream URL is scrubbed too', (tester) async {
    // M3uParser accepts any scheme for item URLs, not just http.
    expectNoDecoy(
      scrubCredentials('Failed to open rtmp://$decoyUser:$decoyPass@h/live'),
      'rtmp item URL',
    );
  });
}
