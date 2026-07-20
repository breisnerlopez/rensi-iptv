// Headless screenshot harness: renders the real widget tree to PNG files
// under build/screenshots/. No emulator / display / KVM needed — flutter_test
// paints the widgets and RenderRepaintBoundary.toImage rasterizes them.
//
// Run: flutter test test/screenshots/tv_capture_test.dart --update-goldens
// (the --update-goldens flag just lets golden machinery run; we write PNGs
//  ourselves via the boundary below.)
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';

final GlobalKey _boundaryKey = GlobalKey();

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

// Best-effort: load the framework icon font so Icon() glyphs render (not tofu).
Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      '/tmp/claude-1000/-workspace-rensi-iptv/aad59248-3ca7-4d7f-93cd-0334958c2000/scratchpad/flutter-sdk';
  final candidates = [
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) {
      await _loadFont('MaterialIcons', p);
      return;
    }
  }
}

ContentItem _item(String name, ContentType type) =>
    ContentItem('id_$name', name, '', type);

// onTap MUST be non-null: an InkWell with onTap==null is disabled and can't
// take focus, so the TV focus ring would never appear.
Widget _poster(String name, ContentType type, double w) =>
    RensiPoster(item: _item(name, type), width: w, onTap: () {});

const _titles = [
  ['Duna: Parte Dos', 'vod'],
  ['The Last of Us', 'series'],
  ['ESPN Deportes', 'live'],
  ['Oppenheimer', 'vod'],
  ['La Casa del Dragón', 'series'],
  ['CNN en Español', 'live'],
];

ContentType _t(String s) => s == 'vod'
    ? ContentType.vod
    : s == 'series'
        ? ContentType.series
        : ContentType.liveStream;

Widget _rail() => Center(
      child: RensiRail(
        posterWidth: 210,
        sidePadding: 48,
        children: [
          for (final e in _titles) _poster(e[0], _t(e[1]), 210),
        ],
      ),
    );

Widget _phoneRail() => Center(
      child: RensiRail(
        posterWidth: 138,
        children: [
          for (final e in _titles.take(4)) _poster(e[0], _t(e[1]), 138),
        ],
      ),
    );

/// The continue-watching rail, via the home screen that now feeds it.
///
/// This used to shoot a standalone WatchHistoryCard from a screen no navigation
/// path in the app could reach. The card and its screen are gone; what a viewer
/// can actually get to is this rail, so that is what gets photographed.
Widget _historyCard() => RedesignHome(
      movieCategories: const [],
      seriesCategories: const [],
      onOpen: (_) {},
      onPlay: (_) {},
      continueWatching: [
        WatchHistory(
          playlistId: 'p',
          contentType: ContentType.vod,
          streamId: 's',
          title: 'Duna: Parte Dos',
          imagePath: '',
          lastWatched: DateTime(2026, 1, 1),
          watchDuration: const Duration(minutes: 40),
          totalDuration: const Duration(minutes: 120),
        ),
      ],
      onResume: (_) {},
      onRemove: (_) {},
    );

Future<void> _shoot(
    WidgetTester tester, Size size, Widget child, String file,
    {bool focusFirst = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemes.darkTheme,
      // Localisations, because the fixtures now include a real screen rather
      // than isolated widgets: `context.loc` is null without them, and the
      // failure surfaces as a null-check deep inside the widget under test.
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: RepaintBoundary(key: _boundaryKey, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  if (focusFirst) {
    // Move D-pad/keyboard focus onto the first focusable so the TV focus ring
    // (FocusHighlight) renders.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  await _capture(tester, file);
}

Future<void> _capture(WidgetTester tester, String file) async {
  await tester.runAsync(() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screenshots/$file')..createSync(recursive: true);
    out.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    // ContentItem's constructor reads AppState.currentPlaylist; use an M3U
    // playlist so it takes the simple url path (no Xtream repo needed).
    AppState.currentPlaylist = Playlist(
      id: 'test',
      name: 'Test',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    await _loadFont('Bricolage Grotesque', 'assets/fonts/BricolageGrotesque.ttf');
    await _loadFont('Hanken Grotesk', 'assets/fonts/HankenGrotesk.ttf');
    await _loadMaterialIcons();
  });

  testWidgets('TV rail — foco + texto escalado', (tester) async {
    await _shoot(tester, const Size(1600, 380), _rail(), 'tv_rail_focused.png', focusFirst: true);
  });

  testWidgets('Phone rail — para comparar', (tester) async {
    await _shoot(tester, const Size(430, 320), _phoneRail(), 'phone_rail.png');
  });

  // Renamed with the widget. The old name promised "botón quitar focusable" —
  // the remove button on the deleted history card — and the rail that replaced
  // it has no such control, so the name was asserting something that no longer
  // exists. focusFirst is off for the same reason: the first focusable in this
  // fixture is the home's top bar, not the card, so the Tab documented a focus
  // ring landing somewhere other than the subject.
  testWidgets('TV continue-watching rail', (tester) async {
    await _shoot(tester, const Size(1000, 380), _historyCard(),
        'tv_continue_watching.png');
  });

  // Emula el mando de Android TV: inyecta eventos de teclas reales (Tab para
  // entrar el foco, y flechas = D-pad) y captura cómo se mueve el foco.
  testWidgets('D-pad — navegar el riel con el mando', (tester) async {
    tester.view.physicalSize = const Size(1600, 380);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemes.darkTheme,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: RepaintBoundary(key: _boundaryKey, child: _rail()),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // foco al 1er póster
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _capture(tester, 'dpad_1_primer_poster.png');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // → mando derecha
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // → otra vez
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _capture(tester, 'dpad_2_tras_dos_derechas.png');
  });
}
