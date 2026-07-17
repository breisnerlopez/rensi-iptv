import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

const _urlsPath =
    '/tmp/claude-1000/-workspace-rensi-iptv/aad59248-3ca7-4d7f-93cd-0334958c2000/scratchpad/fixtures/stream_urls.txt';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reproducción REAL + cambio de canal (libmpv + streams Xtream reales)',
      () async {
    // Hits the user's real IPTV server → opt-in only (RENSI_PLAYBACK=1) so it
    // doesn't run on every routine suite pass.
    if (Platform.environment['RENSI_PLAYBACK'] != '1') {
      markTestSkipped('reproducción real desactivada (set RENSI_PLAYBACK=1)');
      return;
    }
    final f = File(_urlsPath);
    if (!f.existsSync()) {
      markTestSkipped('no hay URLs de stream reales');
      return;
    }
    final urls = f
        .readAsStringSync()
        .trim()
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .toList();

    MediaKit.ensureInitialized();
    final player = Player();
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < urls.length; i++) {
      final errors = <String>[];
      final sub = player.stream.error.listen(errors.add);
      await player.open(Media(urls[i]), play: true);
      // Real network + libmpv decode time.
      await Future.delayed(const Duration(seconds: 6));
      final s = player.state;
      results.add({
        'ch': i,
        'playing': s.playing,
        'posMs': s.position.inMilliseconds,
        'buffering': s.buffering,
        'audio': s.tracks.audio.length,
        'video': s.tracks.video.length,
        'errors': errors.length,
      });
      await sub.cancel();
    }
    await player.dispose();

    for (final r in results) {
      // ignore: avoid_print
      print('PLAYBACK $r');
    }

    // Real IPTV: some channels may be down, but at least one must actually play
    // (playing=true or position advanced) with an audio track decoded.
    final anyPlayed = results.any((r) =>
        (r['playing'] == true || (r['posMs'] as int) > 0) &&
        (r['audio'] as int) > 0);
    expect(anyPlayed, isTrue,
        reason:
            'al menos un canal real debe reproducir (playing/posición + pista de audio)');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
