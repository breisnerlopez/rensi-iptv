// Shared helpers for the end-to-end player tests that run the REAL PlayerWidget
// with a REAL libmpv Player and REAL remote key events.
//
// media_kit keeps global state per process, so a second libmpv player in the
// same isolate can fail to initialize its texture. `flutter test` runs each
// *file* in its own isolate, so these tests live in separate files (playback vs.
// error-recovery) and share this support library rather than a single file.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wl;
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// No-op wakelock so the keep-screen-awake pigeon channel doesn't error headless.
class FakeWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

/// Installs the platform-channel fakes the real PlayerWidget needs headless:
///  - the video-texture channel (no native registrant in `flutter test`),
///  - wakelock_plus (keep-screen-awake pigeon channel),
///  - the connectivity status EventChannel (reconnect watcher),
///  - a filter for media_kit_video's benign controls-initState race.
void installPlayerPluginFakes(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;

  // media_kit_video's controls read MaterialVideoControlsTheme.of() inside their
  // own initState; under the synthetic pump timing here that inherited lookup can
  // fire one frame early. It's a package-internal race (not app code) and benign
  // on device — swallow exactly that assertion, delegate everything else.
  final origOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final s = details.exceptionAsString();
    if (s.contains('MaterialVideoControlsTheme') ||
        (s.contains('dependOnInheritedWidgetOfExactType') &&
            s.contains('initState'))) {
      return;
    }
    origOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = origOnError);

  // --- Video texture channel: swallow outgoing calls and, on Create, deliver a
  // texture id through the incoming Resize callback so create() resolves and the
  // widget leaves `isLoading` exactly as on a device. ---
  const vName = 'com.alexmercerind/media_kit_video';
  const codec = StandardMethodCodec();
  messenger.setMockMethodCallHandler(const MethodChannel(vName), (call) async {
    switch (call.method) {
      case 'VideoOutputManager.Create':
        final handle = int.parse(call.arguments['handle'] as String);
        Future(() async {
          final data = codec.encodeMethodCall(
            MethodCall('VideoOutput.Resize', {
              'handle': handle,
              'rect': {'left': 0, 'top': 0, 'width': 1280, 'height': 720},
              'id': 1,
            }),
          );
          await messenger.handlePlatformMessage(vName, data, (_) {});
        });
        return null;
      case 'Utils.IsEmulator':
        return false;
      default:
        return null;
    }
  });
  addTearDown(() =>
      messenger.setMockMethodCallHandler(const MethodChannel(vName), null));

  // --- wakelock_plus: the facade snapshots the platform impl into a public
  // top-level var at load time, so overriding it there is what actually swaps in
  // our no-op. Leave it installed: dispose() calls disable() during the
  // framework's automatic teardown, which must not hit the real channel. ---
  wl.wakelockPlusPlatformInstance = FakeWakelock();

  // --- connectivity status EventChannel: accept listen/cancel, emit nothing. ---
  const connStatus = 'dev.fluttercommunity.plus/connectivity_status';
  messenger.setMockMethodCallHandler(
      const MethodChannel(connStatus), (call) async => null);
  addTearDown(() =>
      messenger.setMockMethodCallHandler(const MethodChannel(connStatus), null));
}

ContentItem liveItem(String url, String name) => ContentItem(
      url,
      name,
      '',
      ContentType.liveStream,
      liveStream: LiveStream(
        streamId: url,
        name: name,
        streamIcon: '',
        categoryId: 'c',
        epgChannelId: 'e',
        playlistId: 'm',
      ),
    );

/// Interleave frame pumps (fire post-frame callbacks — VideoController.create
/// waits on one) with real time (libmpv + native texture callbacks flow). Doing
/// only one or the other deadlocks: create needs a frame, open() needs real time.
Future<void> pumpReal(WidgetTester tester, {int cycles = 12, int ms = 250}) async {
  for (var i = 0; i < cycles; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
  }
  await tester.pump(const Duration(milliseconds: 16));
}

/// Interleave until [ready] holds (or the budget runs out).
Future<void> pumpUntil(WidgetTester tester, bool Function() ready,
    {int cycles = 40, int ms = 200}) async {
  for (var i = 0; i < cycles && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
  }
  await tester.pump(const Duration(milliseconds: 16));
}

Focus? remoteFocus(WidgetTester tester) => tester
    .widgetList<Focus>(find.byType(Focus))
    .where((f) => f.focusNode?.debugLabel == 'PlayerRemote')
    .firstOrNull;

/// Unmount the player and drain media_kit's internal open() timers so they don't
/// outlive the widget tree (FakeAsync's pending-timer teardown invariant).
Future<void> disposePlayerCleanly(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await pumpReal(tester, cycles: 6, ms: 200); // let dispose()/player.dispose run
  await tester.pump(const Duration(seconds: 6)); // fire lingering FakeAsync timers
}
