import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/tv_keyboard.dart';

import '../integration/harness.dart';

// Accessibility guards from the round-5 review: a screen reader had almost
// nothing to announce (icon-only buttons, no selected/toggled state), and the
// TV keyboard's special keys were hard-coded Spanish in every locale.
void main() {
  ContentItem item() => ContentItem('id1', 'Dune', '', ContentType.vod,
      containerExtension: 'mp4');

  Future<void> pump(WidgetTester tester, Widget child,
          {Locale locale = const Locale('es')}) =>
      pumpScreen(tester, Scaffold(body: Center(child: child)),
          size: const Size(400, 800), locale: locale);

  setUp(() {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'X',
      type: PlaylistType.xtream,
      url: 'http://x.invalid:8080',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026),
    );
  });

  testWidgets('RensiChip exposes selected state to the screen reader',
      (tester) async {
    await pump(tester, const RensiChip(label: 'Todo', active: true));
    final s = tester.getSemantics(find.byType(RensiChip));
    expect(s.hasFlag(SemanticsFlag.isSelected), isTrue,
        reason: 'an active filter chip must announce "selected"');
    expect(s.label, 'Todo');
  });

  testWidgets('RensiPoster has an accessible name including its badge',
      (tester) async {
    await pump(
      tester,
      RensiPoster(item: item(), badge: 'No en tus listas', onTap: () {}),
    );
    final s = tester.getSemantics(find.byType(RensiPoster));
    expect(s.label, 'Dune, No en tus listas',
        reason: 'title + badge spoken together, not a nameless "button"');
    expect(s.hasFlag(SemanticsFlag.isButton), isTrue);
  });

  testWidgets('TV keyboard special keys are localized, not hard-coded Spanish',
      (tester) async {
    // German locale: the space/backspace/clear semantic labels must be German.
    await pump(
      tester,
      TvKeyboard(onKey: (_) {}, onBackspace: () {}, onClear: () {}),
      locale: const Locale('de'),
    );
    expect(find.bySemanticsLabel('Leertaste'), findsOneWidget,
        reason: 'space key announced in German');
    expect(find.bySemanticsLabel('Espacio'), findsNothing,
        reason: 'no hard-coded Spanish label');
  });
}
