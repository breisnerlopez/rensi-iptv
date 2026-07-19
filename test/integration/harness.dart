// Headless integration harness for Rensi IPTV.
//
// Boots REAL app screens inside `flutter test` (no emulator/display/KVM),
// wired with the same MaterialApp shell + providers as main.dart, backed by
// fakes for the platform channels (in-memory Drift DB via get_it, mocked
// SharedPreferences / secure storage / path_provider). Screens are then driven
// with REAL key events that mirror an Android TV remote (D-pad / OK / BACK)
// and captured to PNG.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rensi_iptv/controllers/active_playlist_controller.dart';
import 'package:rensi_iptv/controllers/locale_provider.dart';
import 'package:rensi_iptv/controllers/playlist_controller.dart';
import 'package:rensi_iptv/controllers/theme_provider.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/l10n/supported_languages.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

import '../helpers/test_database.dart';

final GlobalKey harnessBoundaryKey = GlobalKey();

/// TV surface (≥900 dp wide → ResponsiveHelper renders the 10-foot UI).
const Size tvSize = Size(1280, 720);
const Size phoneSize = Size(400, 820);

late AppDatabase _db;

/// Call inside setUp(). Resets get_it, installs an in-memory DB and empty
/// mocked plugin state.
/// [tv] mocks the native TV-detection channel. Pass **null** on a real device
/// to leave the channel unmocked so MainActivity answers for itself — anything
/// else renders the 10-foot UI on a phone, which is exactly how a screenshot
/// campaign can spend six devices photographing the wrong layout.
Future<void> setUpHarness(
    {Map<String, Object> prefs = const {}, bool? tv = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  _mockPathProvider();
  _mockPackageInfo();
  _mockConnectivity();
  // Drive the real native TV-detection path. tv:false → phone (mobile layout);
  // tv:null → no mock at all, so the device decides.
  if (tv != null) {
    _mockChannel('info.breisner.rensi.iptv/pip',
        (call) => call.method == 'isTelevision' ? tv : false);
  }
  await ResponsiveHelper.initTelevisionFlag();

  // Clear static/singleton state that leaks between tests.
  PlaylistService.invalidateCache();
  AppState.currentPlaylist = null;
  AppState.m3uRepository = null;
  AppState.xtreamCodeRepository = null;

  await GetIt.instance.reset();
  _db = createTestDatabase();
  GetIt.instance.registerSingleton<AppDatabase>(_db);
}

Future<void> tearDownHarness() async {
  PlaylistService.invalidateCache();
  AppState.currentPlaylist = null;
  AppState.m3uRepository = null;
  AppState.xtreamCodeRepository = null;
  await GetIt.instance.reset();
  await _db.close();
}

/// Access the in-memory DB to seed data for a test.
AppDatabase get harnessDb => _db;

// ---------------------------------------------------------------------------
// Plugin fakes
// ---------------------------------------------------------------------------
void _mockChannel(String name, Object? Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(name), (call) async {
    return handler(call);
  });
}

void _mockPathProvider() {
  final dir = Directory.systemTemp.createTempSync('rensi_test').path;
  _mockChannel('plugins.flutter.io/path_provider', (call) => dir);
}

void _mockPackageInfo() {
  _mockChannel('dev.fluttercommunity.plus/package_info', (call) {
    return <String, dynamic>{
      'appName': 'Rensi IPTV',
      'packageName': 'info.breisner.rensi.iptv',
      'version': '2.0.3',
      'buildNumber': '7',
    };
  });
}

void _mockConnectivity() {
  _mockChannel('dev.fluttercommunity.plus/connectivity', (call) => 'wifi');
  // EventChannel stream is left unmocked; screens read the one-shot value.
}

// ---------------------------------------------------------------------------
// App shell + pump
// ---------------------------------------------------------------------------
Widget _appShell(Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => ActivePlaylistController()),
      ChangeNotifierProvider(create: (_) => PlaylistController()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales:
          supportedLanguages.map((lang) => Locale(lang['code'])).toList(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        // Wrap the whole app (Navigator + overlays) so screenshots capture
        // pushed routes / dialogs / bottom sheets, not just the home route.
        Widget c = child ?? const SizedBox.shrink();
        if (ResponsiveHelper.isDesktopOrTV(context)) {
          c = Theme(data: AppThemes.applyTvOverrides(Theme.of(context)), child: c);
        }
        return RepaintBoundary(key: harnessBoundaryKey, child: c);
      },
      home: home,
    ),
  );
}

/// Settle animations but never hang: bounded timeout, then a few plain pumps
/// if something animates forever (e.g. a spinner).
Future<void> settle(WidgetTester tester,
    [Duration timeout = const Duration(seconds: 6)]) async {
  try {
    await tester.pumpAndSettle(
        const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, timeout);
  } catch (_) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// Pump a real screen inside the app shell at the given surface size.
///
/// Pass `size: null` when running on a real device/emulator: overriding the
/// surface would render at the harness's synthetic size instead of the screen's
/// own, and every capture would come out at the wrong resolution.
Future<void> pumpScreen(WidgetTester tester, Widget home,
    {Size? size = tvSize}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(_appShell(home));
  await settle(tester);
}

// ---------------------------------------------------------------------------
// Remote (D-pad) events
// ---------------------------------------------------------------------------
/// Key-simulation platform. On the host `flutter_test` infers it, but in an
/// on-device integration run KeyEventSimulator cannot resolve the physical-key
/// map on its own and throws "Null check operator used on a null value" from
/// _findPhysicalKey — so every D-pad press failed the moment these helpers were
/// first exercised on real hardware.
/// Null on the host so flutter_test keeps its own default — forcing 'linux'
/// there broke four suites that pass with the inferred one.
final String? _keyPlatform = Platform.isAndroid ? 'android' : null;

Future<void> dpad(WidgetTester tester, LogicalKeyboardKey key,
    {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    if (_keyPlatform != null) {
      await tester.sendKeyEvent(key, platform: _keyPlatform);
    } else {
      await tester.sendKeyEvent(key);
    }
    await tester.pump(const Duration(milliseconds: 120));
  }
  await settle(tester);
}

/// Moves focus the way the D-pad does, without KeyEventSimulator.
///
/// On device the simulator cannot resolve a physical-key map and throws from
/// _findPhysicalKey, so every press fails — which is why the D-pad steps of the
/// screenshot campaign produced nothing. This drives the same code path a real
/// press ends up in (DirectionalFocusIntent -> focusInDirection), so traversal,
/// focus order and any onFocusChange side effects are exercised for real. It is
/// NOT a substitute for [dpad] in behavioural tests: it skips the key handling
/// layer, so a screen that swallows arrow keys would still look navigable here.
Future<void> moveFocus(WidgetTester tester, TraversalDirection dir,
    {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    FocusManager.instance.primaryFocus?.focusInDirection(dir);
    await tester.pump(const Duration(milliseconds: 120));
  }
  await settle(tester);
}

Future<void> right(WidgetTester t, {int times = 1}) =>
    dpad(t, LogicalKeyboardKey.arrowRight, times: times);
Future<void> left(WidgetTester t, {int times = 1}) =>
    dpad(t, LogicalKeyboardKey.arrowLeft, times: times);
Future<void> down(WidgetTester t, {int times = 1}) =>
    dpad(t, LogicalKeyboardKey.arrowDown, times: times);
Future<void> up(WidgetTester t, {int times = 1}) =>
    dpad(t, LogicalKeyboardKey.arrowUp, times: times);
Future<void> ok(WidgetTester t) => dpad(t, LogicalKeyboardKey.select);
Future<void> enter(WidgetTester t) => dpad(t, LogicalKeyboardKey.enter);
// The Android TV remote BACK maps to logical `goBack`, but that key has no
// physical mapping in flutter_test; `escape` is the testable equivalent and the
// app treats both the same (overlays / ConfirmExitScope check escape+goBack).
Future<void> back(WidgetTester t) => dpad(t, LogicalKeyboardKey.escape);
Future<void> tab(WidgetTester t) => dpad(t, LogicalKeyboardKey.tab);

/// The label of the widget currently holding primary focus (best-effort:
/// nearest Text inside the focused subtree), for asserting where focus landed.
String? focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  String? found;
  void visit(Element el) {
    if (found != null) return;
    final w = el.widget;
    if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
      found = w.data;
      return;
    }
    el.visitChildren(visit);
  }
  ctx.visitChildElements(visit);
  return found;
}

/// Richer focus probe: reports the focused widget's kind + nearest label, so
/// text fields (which have no inner Text) don't read as "no focus".
String focusedInfo() {
  final node = FocusManager.instance.primaryFocus;
  final ctx = node?.context;
  if (ctx == null) return 'none';
  String kind = 'focus';
  String? label;
  void visit(Element el) {
    final w = el.widget;
    if (w is EditableText) kind = 'TextField';
    if (w is ButtonStyleButton) kind = w.runtimeType.toString();
    if (w is FloatingActionButton) kind = 'FAB';
    if (w is InkWell && kind == 'focus') kind = 'InkWell';
    if (label == null && w is Text && (w.data?.trim().isNotEmpty ?? false)) {
      label = w.data;
    }
    el.visitChildren(visit);
  }
  ctx.visitChildElements(visit);
  return label != null ? '$kind:$label' : kind;
}

// ---------------------------------------------------------------------------
// Screenshots
// ---------------------------------------------------------------------------
bool _fontsLoaded = false;
Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  }

  await load('Bricolage Grotesque', 'assets/fonts/BricolageGrotesque.ttf');
  await load('Hanken Grotesk', 'assets/fonts/HankenGrotesk.ttf');
  final root = Platform.environment['FLUTTER_ROOT'] ??
      '/tmp/claude-1000/-workspace-rensi-iptv/aad59248-3ca7-4d7f-93cd-0334958c2000/scratchpad/flutter-sdk';
  final icons =
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(icons).existsSync()) await load('MaterialIcons', icons);
}

/// Best-effort screenshot: a capture failure (e.g. a boundary still repainting
/// due to a spinner) must never fail the functional test.
Future<void> shot(WidgetTester tester, String file) async {
  await settle(tester);
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final boundary = harnessBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) return;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final out = File('build/screenshots/$file')..createSync(recursive: true);
      out.writeAsBytesSync(data.buffer.asUint8List());
    });
  } catch (e) {
    // ignore: avoid_print
    print('shot($file) skipped: $e');
  }
}
