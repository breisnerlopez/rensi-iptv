import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_playlist_settings_screen.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/widgets/dropdown_tile_widget.dart';

import '../integration/harness.dart';
import '../integration/seed.dart';

// Guards against the second-order damage of promoting type for the 10-foot UI.
//
// AppThemes.tenFoot raises 46 sizes across the legacy surfaces on TV. Text that
// grows inside a box that did not is how the settings screen ended up rendering
// its language dropdown as "Españ" and its theme dropdown as "Oscur": the
// SizedBox around them was 120dp, sized by eye around a 12dp label.
//
// That was caught by looking at a screenshot, which is not a mechanism. Flutter
// reports overflows as assertion failures, but ONLY where assertions are on:
// the profile-build capture runs report nothing at all, and the debug-build run
// needs a device that survives a JIT app on a software rasteriser — the one
// attempted here took the emulator offline. So the check lives in a widget
// test, where assertions are always on and no emulator is involved.
//
// A widget test fails on its own when a RenderFlex overflows; takeException
// only makes the failure say which surface and which width.
Future<void> _expectNoOverflow(
  WidgetTester tester, {
  required Size size,
  required String label,
  required bool tv,
}) async {
  await setUpHarness(tv: tv);
  late Playlist p;
  await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
  // The settings section reads AppState.currentPlaylist! while building. In the
  // app the home screen sets it on the way in; pumping the screen directly does
  // not, so without this the widget throws before any layout happens and the
  // overflow check would pass by never running.
  AppState.currentPlaylist = p;
  await pumpScreen(
    tester,
    XtreamCodePlaylistSettingsScreen(playlist: p),
    size: size,
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  final error = tester.takeException();
  expect(error, isNull, reason: 'laying out at $label ($size) threw: $error');

  // Then the part nothing throws for. Each settings dropdown must be at least
  // as wide as the value it is displaying; when it is not, the text is simply
  // clipped by the box and the app looks like it is offering "Oscur" as a
  // theme. Measured, because an assertion-based check cannot see this: the
  // first version of this guard tested for RenderFlex overflows, and reverting
  // the fix left it green.
  final boxes = find.byKey(dropdownTileValueBoxKey);
  expect(boxes, findsWidgets,
      reason: 'no settings dropdown was rendered, so this measurement proves '
          'nothing');
  for (var i = 0; i < boxes.evaluate().length; i++) {
    final box = tester.getRect(boxes.at(i));
    // EVERY option, not just the one on screen. A DropdownButton keeps all of
    // its menu items in the tree, so `.first` is the first OPTION — a previous
    // version of this loop measured that and called it "the dropdown value".
    // Measuring all of them is also the stronger check: any of them can be
    // selected, so any of them that does not fit is a clipped value waiting to
    // happen. That is exactly how "Automático (recomendado)" surfaced, three
    // rows below the fold of the screenshot that started this.
    // skipOffstage: false, or this measures one option per dropdown instead of
    // all of them. A DropdownButton keeps its items in an IndexedStack wrapped
    // in Visibility.maintain, so every option except the selected one is
    // offstage — and Flutter's finders skip offstage by default. The loop said
    // "EVERY option" and measured 6 of 37.
    final texts = find.descendant(
        of: boxes.at(i), matching: find.byType(Text, skipOffstage: false),
        skipOffstage: false);
    expect(texts, findsWidgets,
        reason: 'a settings dropdown rendered with no text in it');
    for (var j = 0; j < texts.evaluate().length; j++) {
      final option = tester.widget<Text>(texts.at(j)).data ?? '';
      if (option.isEmpty) continue;
      // INTRINSIC width against the paragraph's OWN constraints — not the
      // outer box. Two separate mistakes were made here and both left the
      // guard green against the bug it exists to catch:
      //   * comparing laid-out rects, which always fit because the paragraph is
      //     constrained to the box and then clipped by it;
      //   * comparing against the box's width, which overstates the room by the
      //     InputDecoration's 24dp of horizontal padding plus the 18dp dropdown
      //     chevron. That 42dp of phantom space is exactly the margin the real
      //     defect fell into.
      // Reading constraints.maxWidth also means nobody has to remember to
      // update two constants when the padding changes.
      final paragraph = tester.renderObject<RenderParagraph>(texts.at(j));
      final needed = paragraph.getMaxIntrinsicWidth(double.infinity);
      final room = paragraph.constraints.maxWidth;
      expect(needed, lessThanOrEqualTo(room),
          reason: 'at $label ($size) the option "$option" needs '
              '${needed.toStringAsFixed(1)}dp but has '
              '${room.toStringAsFixed(1)}dp inside a ${box.width}dp box, '
              'so selecting it renders clipped');
    }
  }

  // There is deliberately no assertion about the label here any more.
  //
  // The check that used to live here — "the value box must not steal the
  // label's room" — was written when the value sat beside the label. It is now
  // stacked underneath on every surface, so the label's room is the row minus
  // its icon and cannot be affected by the value at all: any assertion about it
  // is either tautological or, if it demands a single line, fails on ordinary
  // wrapping ("Decodificación de video" needs 327.8dp at its authored 14dp and
  // has 260 on a 360dp handset, which is a two-line label, not a defect).
  //
  // It is deleted rather than kept because the version before this one had gone
  // silently dead: it looked for a ListTile ancestor that the widget no longer
  // builds, so `continue` fired on every iteration at all five widths while
  // reading like a careful, well-commented check. That is the fourth time in
  // this change a guard outlived the shape it was written against. A deleted
  // check is honest about covering nothing; a dead one is not.
}

void main() {
  tearDown(tearDownHarness);

  testWidgets('the settings screen lays out on a 10-foot surface',
      (tester) async {
    await _expectNoOverflow(tester, size: tvSize, label: 'TV', tv: true);
  });

  testWidgets('a television actually gets the promoted type', (tester) async {
    // Nobody was asserting this. Every check here is a FLOOR — "nothing renders
    // below 14dp" — which 14 and 15 satisfy, so reverting a promoted size back
    // to its authored value left the whole suite green. Three such reversions
    // survived an audit. A floor says the text is not decoration; it does not
    // say the 10-foot surface got bigger text, which is the entire point.
    await setUpHarness(tv: true);
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    AppState.currentPlaylist = p;
    await pumpScreen(
      tester,
      XtreamCodePlaylistSettingsScreen(playlist: p),
      size: tvSize,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final box = find.byKey(dropdownTileValueBoxKey).first;
    final column = find.ancestor(of: box, matching: find.byType(Column)).first;
    final texts = find.descendant(of: column, matching: find.byType(Text));
    double sizeOfNth(int n) =>
        tester.widget<Text>(texts.at(n)).style?.fontSize ?? -1;

    expect(sizeOfNth(0), AppThemes.bodySize,
        reason: 'the settings label rendered at ${sizeOfNth(0)}dp on a '
            'television; it clears the readable floor but was never promoted');
    // The help line too. Checking only the label left the description free to
    // stay at its authored 12dp — one assertion per surface cannot cover two
    // decisions on that surface, which is the shape of every gap this file has
    // had. Found by key rather than by position: the first dropdown on this
    // screen has no description, so "the second Text in the column" was a
    // dropdown option.
    final help = find.byKey(dropdownTileDescriptionKey);
    expect(help, findsWidgets, reason: 'no settings row rendered a help line');
    // bodySmall, not body: a help line is secondary to the label above it, and
    // demanding the same size here would flatten the very hierarchy the rest of
    // this work exists to keep. What matters is that it was promoted at all —
    // left alone it stays at its authored 12dp, below the 10-foot floor.
    expect(tester.widget<Text>(help.first).style?.fontSize,
        AppThemes.bodySmallSize,
        reason: 'the settings description rendered at '
            '${tester.widget<Text>(help.first).style?.fontSize}dp');
  });

  testWidgets('a handset keeps the authored size', (tester) async {
    // The other half of the same decision. Asserting only the TV side let a
    // mutation promote the label UNCONDITIONALLY — 18dp on a 360dp handset —
    // with the suite green: every check was "is it big enough on TV", and none
    // was "is it still small enough in the hand".
    await setUpHarness(tv: false);
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    AppState.currentPlaylist = p;
    await pumpScreen(
      tester,
      XtreamCodePlaylistSettingsScreen(playlist: p),
      size: const Size(360, 780),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final column = find
        .ancestor(
            of: find.byKey(dropdownTileValueBoxKey).first,
            matching: find.byType(Column))
        .first;
    final label =
        find.descendant(of: column, matching: find.byType(Text)).first;
    expect(tester.widget<Text>(label).style?.fontSize, AppThemes.labelSize,
        reason: 'the settings label rendered at '
            '${tester.widget<Text>(label).style?.fontSize}dp on a 360dp phone');
  });

  testWidgets('a television promotes the poster title too', (tester) async {
    // Same class of gap, different widget: RensiPoster picks its overlay size
    // with a conditional rather than through tenFoot, so nothing here was
    // asserting that the 10-foot arm is the one a television gets.
    await setUpHarness(tv: true);
    late Playlist p;
    await tester.runAsync(() async => p = await seedXtreamHome(harnessDb));
    AppState.currentPlaylist = p;
    await pumpScreen(
      tester,
      RensiPoster(
        item: ContentItem('m1', 'Una Película', '', ContentType.vod,
            containerExtension: 'mp4'),
        onTap: () {},
        showMeta: true,
      ),
      size: tvSize,
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Una Película'));
    expect(title.style?.fontSize, greaterThanOrEqualTo(AppThemes.bodySize),
        reason: 'the poster title rendered at ${title.style?.fontSize}dp on a '
            'television, the same size a handset gets');
  });

  testWidgets('the settings screen lays out on a real 1080p television',
      (tester) async {
    // 960x540, not 1280x720. A 1080p Android TV reports 960 LOGICAL dp — the
    // fact this whole workstream keeps turning on.
    //
    // It was added when the value box was derived from the available width, and
    // at that point 1280 genuinely did not stand in for 960: the same code gave
    // 460dp of box at one and ~418dp at the other, on opposite sides of the
    // longest value. The box is a flat cap now, so both measure 560 and the
    // widths differ only in what the type scale does to them — which is still
    // worth a case, just not the one originally written down.
    await _expectNoOverflow(tester,
        size: const Size(960, 540), label: 'TV 1080p', tv: true);
  });

  // 640 and 800: a 7" tablet, an open foldable, any handset in landscape.
  //
  // They were added when the layout still switched between side-by-side and
  // stacked around this range and nothing covered the boundary. That switch no
  // longer exists — the value stacks on every surface — so these are simply two
  // more widths, and they stay because a width that has never been laid out is
  // a width that has never been checked.
  for (final w in [640.0, 800.0]) {
    testWidgets('the settings screen lays out at ${w.toInt()}dp',
        (tester) async {
      await _expectNoOverflow(tester,
          size: Size(w, 960), label: '${w.toInt()}dp', tv: false);
    });
  }

  testWidgets('the settings screen still lays out on a narrow handset',
      (tester) async {
    // The promotion must be a no-op here, and the value must still fit.
    //
    // 360dp used to be exempt from the clipping check, with a written-down
    // excuse: "Automático (recomendado)" needed ~293dp and could not fit beside
    // its label on a screen this narrow at any font size, so asserting it would
    // have pinned a failure with no fix available. Two fixes arrived — the
    // value moved under the label, and the option text lost the advice it was
    // carrying — so the exemption went with them. A declared gap that outlives
    // its cause is just an untested surface with a comment on it.
    await _expectNoOverflow(tester,
        size: const Size(360, 780), label: 'phone 360dp', tv: false);
  });
}
