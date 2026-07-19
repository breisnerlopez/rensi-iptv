import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';

// Guards the boundary that keeps subscription credentials off the screen and
// out of the logs. Xtream embeds user+password in the stream path, so a raw
// libmpv/http error string is a credential disclosure.
//
// The cases below are adversarial on purpose: an earlier pattern-matching
// implementation passed the three obvious ones and leaked on timeshift/hlsr
// URLs, on a server URL saved with a trailing slash, on `user:pass@host`, and
// on any auth token not literally named `password`.
void main() {
  const user = 'juanitolargo';
  const pass = 's3cr3tpassword';

  Playlist xtream({String url = 'http://panel.example:8080'}) => Playlist(
        id: 'p1',
        name: 'P',
        type: PlaylistType.xtream,
        url: url,
        username: user,
        password: pass,
        createdAt: DateTime(2026, 1, 1),
      );

  tearDown(() => AppState.currentPlaylist = null);

  void expectClean(String out, String original) {
    expect(out, isNot(contains(user)), reason: original);
    expect(out, isNot(contains(pass)), reason: original);
  }

  group('structural masking — works with NO playlist loaded (isolate case)', () {
    // M3uParser runs under compute(), where AppState statics are null. The
    // structural pass must carry the whole guarantee on its own.
    setUp(() => AppState.currentPlaylist = null);

    final urls = <String>[
      'http://h:8080/live/$user/$pass/1.ts',
      'http://h:8080/movie/$user/$pass/9.mp4',
      'http://h:8080/series/$user/$pass/9.mkv',
      'http://h:8080/$user/$pass/1.ts', // live with no type segment
      'http://h:8080/timeshift/$user/$pass/60/2026-01-01:00-00/123.ts',
      'http://h:8080/hlsr/TOKEN/$user/$pass/1/2/3.m3u8',
      'http://h:8080//$user/$pass/1.ts', // server URL saved with trailing slash
      'http://$user:$pass@h:8080/playlist.m3u', // credentials in userInfo
      'https://h/get.php?username=$user&password=$pass&type=m3u',
      'https://h/portal/$user/$pass/list.m3u8',
      'http://h/list/$user/$pass.m3u', // secret inside the LAST segment
      'https://h:8080/player_api.php?username=$user&password=$pass',
    ];

    for (final url in urls) {
      test('masks: $url', () {
        expectClean(scrubCredentials('Failed to open $url'), url);
      });
    }

    test('masks auth tokens that are not named "password"', () {
      for (final key in ['token', 'auth', 'key', 'sid', 'stream_token']) {
        final out = scrubCredentials('GET https://h/x.m3u8?$key=SUPERSECRETVALUE');
        expect(out, isNot(contains('SUPERSECRETVALUE')), reason: key);
      }
    });
  });

  group('usefulness — masking must not destroy diagnostics', () {
    test('host, scheme, reason and extension survive', () {
      final out = scrubCredentials(
          'Failed to open http://panel.example:8080/live/$user/$pass/1.ts');
      expect(out, contains('panel.example'));
      expect(out, contains('8080'));
      expect(out, contains('Failed to open'));
      expect(out, contains('live'));
      expect(out, contains('.ts'), reason: 'extension is the useful bit');
    });

    test('a non-URL message is left completely alone', () {
      const msg = 'Connection refused by peer after 3 retries';
      expect(scrubCredentials(msg), msg);
    });

    test('allowlisted query params keep their values', () {
      final out = scrubCredentials('https://h/get.php?type=m3u&output=ts');
      expect(out, contains('type=m3u'));
      expect(out, contains('output=ts'));
    });
  });

  group('literal pass', () {
    test('catches credentials quoted outside a URL', () {
      AppState.currentPlaylist = xtream();
      final out = scrubCredentials('Auth failed for user $user with $pass');
      expectClean(out, 'bare literals');
    });

    test('a short password does not shred an unrelated message', () {
      AppState.currentPlaylist = Playlist(
        id: 'p1',
        name: 'P',
        type: PlaylistType.xtream,
        url: 'http://h',
        username: 'ab',
        password: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(scrubCredentials('Connection refused'), 'Connection refused');
    });

    test('a password shorter than the threshold leaves the host intact', () {
      AppState.currentPlaylist = Playlist(
        id: 'p1',
        name: 'P',
        type: PlaylistType.xtream,
        url: 'http://panel.example',
        username: 'ab',
        password: 'exam', // below the 6-char literal threshold
        createdAt: DateTime(2026, 1, 1),
      );
      final out =
          scrubCredentials('Failed to open http://panel.example/live/a/b/1.ts');
      // Exact, not `contains('panel.')` — that weaker form passed even when the
      // host had been mangled to "panel.***e".
      expect(out, 'Failed to open http://panel.example/live/***/***/***.ts');
    });
  });

  group('exact output — negative assertions alone would pass on empty output',
      () {
    setUp(() => AppState.currentPlaylist = null);

    test('canonical Xtream live URL', () {
      expect(
        scrubCredentials('Failed to open http://h:8080/live/$user/$pass/1.ts'),
        'Failed to open http://h:8080/live/***/***/***.ts',
      );
    });

    test('get.php keeps allowlisted params, masks the rest', () {
      expect(
        scrubCredentials('https://h/get.php?username=$user&type=m3u'),
        // The key is masked too: a parameter name can carry a secret.
        'https://h/get.php?***=***&type=m3u',
      );
    });

    test('trailing sentence punctuation is preserved outside the URL', () {
      expect(
        scrubCredentials('Failed: http://h/live/$user/$pass/1.ts.'),
        'Failed: http://h/live/***/***/***.ts.',
      );
    });
  });

  group('adversarial shapes', () {
    setUp(() => AppState.currentPlaylist = null);

    test('non-http schemes are masked too (M3U accepts any scheme)', () {
      for (final scheme in ['rtmp', 'rtsp', 'rtmps', 'mms', 'udp']) {
        final out = scrubCredentials('open $scheme://$user:$pass@h/live');
        expectClean(out, scheme);
        expect(out, contains('$scheme://'), reason: 'scheme kept: $scheme');
      }
    });

    test('fails CLOSED on an unparseable URL', () {
      // A bare "[" is an invalid gen-delim; Uri parsing throws. The old code
      // returned the input untouched, i.e. handed over the credentials.
      final out = scrubCredentials('open http://h:8080/live/$user/$pass/[1.ts');
      expectClean(out, 'unparseable');
    });

    test('a username colliding with the allowlist is still masked', () {
      AppState.currentPlaylist = Playlist(
        id: 'p1',
        name: 'P',
        type: PlaylistType.xtream,
        url: 'http://h',
        username: 'live',
        password: 'movie',
        createdAt: DateTime(2026, 1, 1),
      );
      // Note the FIRST `live` is masked too: it is indistinguishable from the
      // username, so the safe reading wins over the pretty one.
      final out = scrubCredentials('Failed to open http://h/live/live/movie/1.ts');
      expect(out, 'Failed to open http://h/***/***/***/***.ts');
    });

    test('a repeated query key cannot smuggle a secret through the allowlist',
        () {
      final out = scrubCredentials('https://h/get.php?type=m3u&type=$pass');
      expect(out, isNot(contains(pass)));
    });

    test('query with no "=" does not surface as a key name', () {
      final out = scrubCredentials('https://h/get.php?$pass');
      expect(out, isNot(contains(pass)));
    });

    test('IPv6 host keeps its brackets', () {
      final out = scrubCredentials('open http://[::1]:8080/live/$user/$pass/1.ts');
      expect(out, contains('[::1]'));
      expectClean(out, 'ipv6');
    });

    test('fragment content is dropped', () {
      final out = scrubCredentials('https://h/live/a/b/1.ts#$pass');
      expect(out, isNot(contains(pass)));
    });

    test('does not leak the tail after the last dot of the final segment', () {
      // Regression: keeping everything after the last dot published part of a
      // password shaped `/USER/Abc.Def12345`.
      final out = scrubCredentials('open http://h:8080/list/juanito/Abc.Def12345');
      expect(out, isNot(contains('Def12345')));
    });

    test('matrix parameters do not ride along with the extension', () {
      final out =
          scrubCredentials('open http://h/live/u/p/1.ts;jsessionid=$pass');
      expect(out, isNot(contains(pass)));
    });

    test('a secret used as a query KEY is masked', () {
      final out = scrubCredentials('http://h/get.php?$pass=1&type=m3u');
      expect(out, isNot(contains(pass)));
      expect(out, contains('type=m3u'), reason: 'allowlisted pair survives');
    });

    test('a huge alphanumeric blob does not hang the UI thread', () {
      // Regression: the URL regex backtracks quadratically with no "://" in
      // sight — 100k chars measured at 19 s on the UI thread.
      final blob = 'a' * 200000;
      final sw = Stopwatch()..start();
      scrubCredentials('Error: $blob');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('output is still a parseable Uri', () {
      final out = scrubCredentials('http://h:8080/live/$user/$pass/1.ts');
      expect(Uri.tryParse(out), isNotNull);
    });
  });

  test('handles null and empty without throwing', () {
    expect(scrubCredentials(null), '');
    expect(scrubUrlForDisplay(null), '');
    expect(scrubUrlForDisplay(''), '');
  });
}
