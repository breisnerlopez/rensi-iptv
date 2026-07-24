import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// The neutral badge exists so a "not in your lists" discovery poster reads as a
// normal, inviting card — NOT a dimmed/disabled one. The legibility scrim used
// to fire on any badge, which darkened the whole poster; that was the exact
// contradiction an adversarial review caught. This pins three things:
//   1. a badge-less poster (every Home/Browse/List card) paints no scrim — proof
//      the shared widget is unchanged for its existing callers;
//   2. a NEUTRAL badge shows its label WITHOUT darkening the poster;
//   3. an ACCENT badge still pulls the scrim (the documented behaviour kept for
//      any caller that wants it).
ContentItem _item() => ContentItem(
      'id-1',
      'Título',
      '',
      ContentType.vod,
      containerExtension: 'mp4',
    );

int _scrimCount(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .where((d) =>
        d.decoration is BoxDecoration &&
        (d.decoration as BoxDecoration).gradient == RensiPoster.scrimGradient)
    .length;

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(
      theme: AppThemes.darkTheme,
      home: Scaffold(body: Center(child: child)),
    ));

void main() {
  setUp(() {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'Demo',
      type: PlaylistType.xtream,
      url: 'http://demo.invalid:8080',
      username: 'demo',
      password: 'demo',
      createdAt: DateTime(2026, 1, 1),
    );
  });

  testWidgets('a badge-less poster paints no scrim (Home/Browse unchanged)',
      (tester) async {
    await _pump(tester, RensiPoster(item: _item(), onTap: () {}));
    expect(_scrimCount(tester), 0,
        reason: 'the default poster must not be darkened — this is what every '
            'Home and Browse card is');
  });

  testWidgets('a neutral badge shows its label without darkening the poster',
      (tester) async {
    await _pump(
      tester,
      RensiPoster(
        item: _item(),
        onTap: () {},
        badge: 'No en tus listas',
        badgeTone: RensiBadgeTone.neutral,
      ),
    );
    // Not uppercased (a translated label would be long and shouty otherwise).
    expect(find.text('No en tus listas'), findsOneWidget);
    expect(_scrimCount(tester), 0,
        reason: 'the neutral marker must read as a normal poster, not a dimmed '
            'or disabled one');
  });

  testWidgets('an accent badge still pulls the scrim', (tester) async {
    await _pump(
      tester,
      RensiPoster(
        item: _item(),
        onTap: () {},
        badge: 'Nuevo',
        badgeTone: RensiBadgeTone.accent,
      ),
    );
    expect(find.text('NUEVO'), findsOneWidget); // accent uppercases
    expect(_scrimCount(tester), 1,
        reason: 'the accent badge keeps its legibility scrim');
  });
}
