import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_settings_widget.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Panel de ajustes del player: navegable con mando (no atrapado)',
      (tester) async {
    PlayerState.videos = [const VideoTrack('v0', 'auto', 'Auto')];
    PlayerState.audios = [
      const AudioTrack('a0', 'spa', 'Español'),
      const AudioTrack('a1', 'eng', 'English'),
    ];
    PlayerState.subtitles = [
      const SubtitleTrack('s0', 'spa', 'Español'),
      const SubtitleTrack('s1', 'eng', 'English'),
    ];
    PlayerState.selectedVideo = PlayerState.videos.first;
    PlayerState.selectedAudio = PlayerState.audios.first;
    PlayerState.selectedSubtitle = PlayerState.subtitles.first;
    PlayerState.showVideoSettings = false;

    await pumpScreen(
        tester, const Scaffold(body: Center(child: VideoSettingsWidget())));

    // Open the settings panel (the gear).
    await tester.tap(find.byIcon(Icons.settings));
    await settle(tester);
    await shot(tester, 'player_settings_1_open.png');
    debugPrint('panel open focus=${focusedInfo()}');

    // Drive DOWN through the panel: focus must move across items, not be trapped
    // on the full-screen wrapper (the auditor's demonstrated bug/fix).
    final labels = <String>[];
    for (var i = 0; i < 6; i++) {
      await down(tester);
      labels.add(focusedInfo());
    }
    debugPrint('DOWN traversal=$labels');
    await shot(tester, 'player_settings_2_nav.png');
    expect(labels.toSet().length, greaterThan(1),
        reason:
            'el D-pad debe navegar los ítems del panel (audio/subtítulos), no quedar atrapado en el wrapper');

    // BACK closes the panel.
    await back(tester);
    await settle(tester);
    debugPrint('after BACK showVideoSettings=${PlayerState.showVideoSettings}');
    expect(PlayerState.showVideoSettings, isFalse,
        reason: 'BACK debe cerrar el panel de ajustes');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
