import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// A poster's title must not move when the tile takes focus, and a tile must
// never be left without one.
//
// The two title anchors are drawn by different widgets: RensiKeyArt centres the
// generated one, RensiPoster's overlay pins the other bottom-left. A tile that
// used both — centred while idle, bottom-left once focused — made the title jump
// on every D-pad hop. On a 10-foot UI, where moving focus across a rail IS the
// interaction, that is motion in the worst possible place.
//
// Two earlier versions of this file were proven vacuous by mutation, and both
// failures were about focus, so it is worth stating what is verified now:
//   * v1 wrapped the poster in a Focus and requested focus on THAT. The wrapper
//     is an ancestor, so the poster's own Focus never became focused.
//   * v2 added a guard against exactly that — using `Focus.of(...).hasFocus`,
//     which ALSO resolves to an ancestor, and on the root scope is true whenever
//     nothing else holds focus. The guard could not fail. Same bug, one level
//     down, inside the assertion written to catch it.
// So focus is now asserted through FocusManager's primary focus node, checking
// it lies inside the poster's subtree.
ContentItem _item({required String image}) => ContentItem(
      'id-1',
      'Título de Prueba',
      image,
      ContentType.vod,
      containerExtension: 'mp4',
    );

Finder get _title => find.text('Título de Prueba');

const kArtUrl = 'https://example.test/poster.jpg';

void _expectPosterFocused(WidgetTester tester) {
  final primary = FocusManager.instance.primaryFocus;
  expect(primary, isNotNull, reason: 'nothing has focus, so this proves nothing');
  final inside = find
      .descendant(
        of: find.byType(RensiPoster),
        matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode == primary),
      )
      .evaluate()
      .isNotEmpty;
  // Fall back to an ancestry walk: the focused node usually belongs to the
  // InkWell, whose Focus widget is created internally and is not exposed as a
  // `Focus` with a matching focusNode.
  final ctx = primary!.context;
  final byAncestry = ctx != null &&
      find
          .ancestor(of: find.byWidget(ctx.widget), matching: find.byType(RensiPoster))
          .evaluate()
          .isNotEmpty;
  expect(inside || byAncestry, isTrue,
      reason: 'primary focus is $primary, which is not inside the poster — the '
          'test never exercised the focused state');
}

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

  testWidgets('a poster without artwork keeps its title in place on focus',
      (tester) async {
    await _pump(tester, RensiPoster(item: _item(image: ''), onTap: () {}));
    expect(_title, findsOneWidget);
    final idle = tester.getCenter(_title);

    await _pump(
      tester,
      RensiPoster(item: _item(image: ''), onTap: () {}, autofocus: true),
    );
    await tester.pumpAndSettle();
    _expectPosterFocused(tester);

    expect(_title, findsOneWidget,
        reason: 'two widgets are printing the name at once');
    expect(tester.getCenter(_title), idle,
        reason: 'the title moved when the tile took focus: the generated art '
            'and the overlay disagree on where a poster title lives');
  });

  testWidgets('a tile whose cover FAILED still shows its title', (tester) async {
    // The regression this closes: keying the title on "does a URL exist" rather
    // than "did art arrive" left every tile with a dead poster link as a bare
    // gradient.
    //
    // Driven through debugArtLoaded rather than by letting the request fail,
    // because a widget test cannot reach errorWidget deterministically — and
    // the distinction matters: a tile that is still LOADING must NOT print a
    // centred title, or it prints one and then throws it bottom-left the moment
    // the cover lands. That was this fix's own first attempt.
    await _pump(
      tester,
      RensiPoster(
        item: _item(image: kArtUrl),
        onTap: () {},
        debugArtLoaded: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(_title, findsOneWidget,
        reason: 'a tile whose artwork failed must still say what it is');
  });

  testWidgets('a tile that is still loading does not flash a title',
      (tester) async {
    // Nothing resolves here, so this IS the loading state.
    await _pump(
      tester,
      RensiPoster(
        item: _item(image: kArtUrl),
        onTap: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(_title, findsNothing,
        reason: 'a centred title during loading is a title that jumps to the '
            'bottom-left as soon as the cover arrives — the defect this file '
            'exists to prevent, triggered by the network instead of the remote');
  });

  testWidgets('a FOCUSED tile whose cover fails does not slide its title',
      (tester) async {
    // The variant that survived two rounds of fixes. Unfocused, loading painted
    // nothing and failure painted a centred title — an appearance. Focused, the
    // same tile painted a bottom-left title while loading (because "has a URL"
    // was read as "has art") and threw it to the centre when the request
    // failed. Same slide, third trigger.
    await _pump(
      tester,
      RensiPoster(item: _item(image: kArtUrl), onTap: () {}, autofocus: true),
    );
    await tester.pumpAndSettle();
    _expectPosterFocused(tester);
    expect(_title, findsNothing,
        reason: 'a focused tile with no verdict yet must print no title: '
            'whichever anchor it picks now, the verdict will move it');

    await _pump(
      tester,
      RensiPoster(
        item: _item(image: kArtUrl),
        onTap: () {},
        autofocus: true,
        debugArtLoaded: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(_title, findsOneWidget);
    final failed = tester.getCenter(_title);
    final card = tester.getRect(find.byType(RensiPoster));
    expect((failed.dy - card.center.dy).abs(), lessThan(2),
        reason: 'a failed cover shows the generated art, whose title is '
            'centred — it was found at $failed in a card centred on '
            '${card.center}');
  });

  testWidgets('RensiKeyArt reports a verdict for an item with no cover',
      (tester) async {
    // Covers the EMITTER, and it is reachable synchronously — no network
    // needed. Without this, deleting `onArtUnavailable:` from the RensiPoster
    // call site left every other test green (they all reach the has-art branch
    // through debugArtLoaded, which bypasses the wiring entirely) while a 404'd
    // cover went back to rendering an anonymous rectangle in production.
    final seen = <bool>[];
    await _pump(
      tester,
      SizedBox(
        width: 120,
        height: 180,
        child: RensiKeyArt(item: _item(image: ''), onArtUnavailable: seen.add),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen, contains(true),
        reason: 'the art widget never told anyone it had no artwork');
  });

  testWidgets('the poster acts on the verdict, in both directions',
      (tester) async {
    // Drives the REAL closure production installs, straight from the tree — no
    // network, no debugArtLoaded, no seam. That matters twice over: it covers
    // the wiring (delete `onArtUnavailable:` and the `!` below throws), and it
    // covers the way back from `failed`, which nothing else could reach.
    //
    // An earlier version only checked the callback was non-null, on the belief
    // that a behavioural test was impossible here. It was not: what is out of
    // reach is making a real image load, not invoking the verdict.
    await _pump(
      tester,
      RensiPoster(item: _item(image: kArtUrl), onTap: () {}, autofocus: true),
    );
    // Re-read after every pump: the poster rebuilds and hands out a new closure.
    RensiKeyArt art() => tester.widget<RensiKeyArt>(find.descendant(
          of: find.byType(RensiPoster),
          matching: find.byType(RensiKeyArt),
        ));
    final card = tester.getRect(find.byType(RensiPoster));

    art().onArtUnavailable!(true);
    await tester.pump();
    expect(_title, findsOneWidget,
        reason: 'a cover that failed must leave the tile identifiable');
    expect((tester.getCenter(_title).dy - card.center.dy).abs(), lessThan(2),
        reason: 'a failed cover shows generated art, whose title is centred');

    // A retry succeeds. CachedNetworkImage does re-request, so this is the
    // ordinary consequence of a Wi-Fi blip — not an exotic path.
    art().onArtUnavailable!(false);
    await tester.pump();
    expect(_title, findsOneWidget);
    expect(tester.getCenter(_title).dy, greaterThan(card.center.dy),
        reason: 'the tile never came back from `failed`: one transient error '
            'and this poster stops revealing its title for the session');
  });

  testWidgets('a cover that paints turns the tile into the reveal-on-focus one',
      (tester) async {
    // Covers the EMITTER of `loaded`, which is the single line in production
    // that ever produces it: `_report(false)` inside CachedNetworkImage's
    // imageBuilder. An audit deleted that line and all 25 tests stayed green —
    // with it gone, no poster with a working cover ever leaves `unknown`, so
    // reveal-on-focus silently stops existing across the whole app.
    //
    // The trick is the same one used for the failure verdict: a real image
    // cannot load here, but the builder the widget installed can be invoked.
    await _pump(
      tester,
      RensiPoster(item: _item(image: kArtUrl), onTap: () {}, autofocus: true),
    );
    expect(_title, findsNothing, reason: 'no verdict yet: no title');

    final cni = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage, skipOffstage: false));
    final ctx = tester.element(find.byType(CachedNetworkImage, skipOffstage: false));
    cni.imageBuilder!(ctx, const AssetImage('assets/icon/icon.png'));
    await tester.pump();
    await tester.pump();

    expect(_title, findsOneWidget,
        reason: 'the cover painted and the tile is focused, so the title must '
            'be revealed — this is the Google TV pattern the change is for');
    final card = tester.getRect(find.byType(RensiPoster));
    expect(tester.getCenter(_title).dy, greaterThan(card.center.dy),
        reason: 'revealed over artwork, the title belongs at the bottom');
  });

  test('the reveal rule: only over artwork, only on focus', () {
    // Asserted on the rule rather than on pixels, because no cover image can
    // load in a widget test (the framework's HttpClient answers 400 to every
    // request). Without this, deleting reveal-on-focus entirely — `showMeta ??
    // false` — left every rendered assertion in this file green.
    expect(RensiPoster.revealTitle(hasArt: true, focused: true), isTrue,
        reason: 'focusing a tile with cover art must reveal its title');
    expect(RensiPoster.revealTitle(hasArt: true, focused: false), isFalse,
        reason: 'an unfocused cover should be shown, not labelled');
    expect(RensiPoster.revealTitle(hasArt: false, focused: true), isFalse,
        reason: 'without art the generated title already holds the centre; a '
            'second one bottom-left is the jump this file exists to prevent');
    expect(RensiPoster.revealTitle(hasArt: false, focused: false), isFalse);
    expect(RensiPoster.revealTitle(hasArt: false, focused: false, forced: true),
        isTrue,
        reason: 'an explicit showMeta must still win');
  });

  testWidgets('with the cover loaded, focus moves the title to the bottom',
      (tester) async {
    // Covers the CALL, not just the rule. Asserting revealTitle() in isolation
    // left the production line free to stop using it: `showMeta ?? false`
    // deleted reveal-on-focus outright and every other test here stayed green,
    // because none of them could reach the branch where artwork exists. Nothing
    // resolves a network image under flutter_test, hence debugArtLoaded.
    await _pump(
      tester,
      RensiPoster(
        item: _item(image: kArtUrl),
        onTap: () {},
        debugArtLoaded: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(_title, findsNothing,
        reason: 'an unfocused cover should be shown, not labelled');

    await _pump(
      tester,
      RensiPoster(
        item: _item(image: kArtUrl),
        onTap: () {},
        debugArtLoaded: true,
        autofocus: true,
      ),
    );
    await tester.pumpAndSettle();
    _expectPosterFocused(tester);
    expect(_title, findsOneWidget,
        reason: 'focusing a tile with cover art must reveal its title');
    final rect = tester.getRect(_title);
    final card = tester.getRect(find.byType(RensiPoster));
    expect(rect.bottom, greaterThan(card.center.dy),
        reason: 'the revealed title belongs in the lower half of the card');
  });

  testWidgets('a tile does not inherit the previous item verdict on recycle',
      (tester) async {
    // Rails recycle tiles. The art verdict is State, so without a reset it
    // outlives the item it was about.
    await _pump(
      tester,
      RensiPoster(item: _item(image: ''), onTap: () {}),
    );
    expect(_title, findsOneWidget);

    await _pump(
      tester,
      RensiPoster(
        item: ContentItem('id-2', 'Otro Título', 'https://example.test/b.jpg',
            ContentType.vod,
            containerExtension: 'mp4'),
        onTap: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Otro Título'), findsNothing,
        reason: 'the new item has a cover on the way, so it should show the '
            'cover slot — not the art-less treatment the previous item needed');
  });

  testWidgets('over real artwork the title is revealed by focus', (tester) async {
    // The Google TV pattern, asserted so it cannot be deleted silently: an
    // earlier fix could be reduced to `showMeta ?? false` — dropping reveal-on-
    // focus entirely — with every test in this file still green.
    await tester.runAsync(() async {
      await _pump(
        tester,
        RensiPoster(
          item: _item(image: kArtUrl),
          onTap: () {},
          // Forced: no image can actually load here, so the reveal is asserted
          // through the same switch production uses rather than through a
          // network fetch the test framework stubs out to a 400.
          showMeta: true,
        ),
      );
    });
    await tester.pumpAndSettle();
    final rect = tester.getRect(_title);
    final card = tester.getRect(find.byType(RensiPoster));
    expect(rect.bottom, greaterThan(card.center.dy),
        reason: 'the revealed title should sit in the lower half of the card, '
            'not centred over the artwork');
  });
}
