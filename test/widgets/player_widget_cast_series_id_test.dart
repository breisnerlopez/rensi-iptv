// REGRESSION (v2.19.x) — the phone must send the SERIES id in the cast LOAD so
// the TV's `__cast__` history row carries `seriesId`, which is what the TV's
// standalone auto-advance (feature H) needs to rebuild the full episode queue
// and chain episode→episode without the phone.
//
// The bug: an episode ContentItem built by series_screen / episode_screen carries
// NO `seriesStream`, so `PlayerWidget._castMedia.seriesId` was
// `contentItem.seriesStream?.seriesId` == null → the wire `sid` was omitted → the
// TV row had `series_id` NULL → `_standaloneSeriesQueue` bailed → NO auto-advance.
// This was masked by fake-panel tests that seeded the queue/row directly.
//
// The fix resolves the seriesId from the DB (`findEpisodesById`, the same source
// `_reliableCastInfo` already used) when the item lacks it, and folds it into the
// LOAD. This mounts a REAL PlayerWidget with a series episode that has NO
// seriesStream, seeds the episode row, drives the cast gate → send → PIN, and
// asserts the captured LOAD carries the DB seriesId.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../integration/harness.dart';

class _CapturingSender extends PhoneSenderService {
  _CapturingSender({this.devices = const [], this.correctPin = '123456'});
  final List<CastDevice> devices;
  final String correctPin;
  String? lastSeriesId;
  bool sawLoad = false;

  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      devices;
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {}
  @override
  Future<bool> pair(String pin) async => pin == correctPin;
  @override
  Future<void> sendLoad({
    required String channelId,
    String contentType = 'live',
    required String url,
    required String username,
    required String password,
    String title = '',
    String ext = '',
    CastMeta? meta,
    int startPositionMs = 0,
    bool standalone = false,
    String pid = '',
    String deviceId = '',
    String? seriesId,
  }) async {
    sawLoad = true;
    lastSeriesId = seriesId;
  }

  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness(tv: false)); // phone layer: the cast gate applies
  tearDown(tearDownHarness);

  testWidgets(
      'cast LOAD of a series episode WITHOUT seriesStream carries the DB seriesId',
      (tester) async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    // Xtream playlist with a dead host → the built series URL is dead so the cast
    // gate fires fast (no real network), and isXtreamCode is true so the fix's
    // DB resolution runs.
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.xtream,
      url: 'http://127.0.0.1:1',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026, 1, 1),
    );

    // Seed the episode row the way opening the series (getSeriesInfo) would — with
    // its parent seriesId. This is what the fix reads back via findEpisodesById.
    await harnessDb.insertEpisode(EpisodesCompanion.insert(
      seriesId: 'SER-42',
      episodeId: 'ep1',
      episodeNum: 1,
      title: 'S01E01',
      season: 1,
      playlistId: 'm',
    ));

    // Episode ContentItem EXACTLY as series_screen/episode_screen build it: NO
    // seriesStream. contentItem.seriesStream?.seriesId is therefore null.
    final episode = ContentItem(
      'ep1',
      'S01E01',
      '',
      ContentType.series,
      containerExtension: 'mp4',
      season: 1,
    );
    expect(episode.seriesStream, isNull,
        reason: 'the real episode ContentItem carries no seriesStream');

    final oneTv = CastDevice(name: 'Sala', host: '10.0.0.5', port: 5000);
    final fake = _CapturingSender(devices: [oneTv], correctPin: '123456');
    final cast = CastSenderController(senderFactory: () => fake);
    addTearDown(() async {
      if (cast.isCasting) await cast.stopCasting();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: AppThemes.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<CastSenderController>.value(
          value: cast,
          child: Scaffold(
            body: PlayerWidget(contentItem: episode, queue: [episode]),
          ),
        ),
      ),
    );
    await tester.pump();

    // Dead stream → the cast gate appears.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      if (tester.any(find.text('¿Enviar esto a tu TV?'))) break;
    }
    expect(find.text('¿Enviar esto a tu TV?'), findsOneWidget,
        reason: 'streamed content shows the gate');

    await tester.tap(find.text('Enviar a la TV'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(TextField), findsOneWidget,
        reason: 'a single fake TV goes straight to the PIN');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Emparejar'));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(cast.isCasting, isTrue, reason: 'correct PIN → casting');
    expect(fake.sawLoad, isTrue, reason: 'a LOAD was sent');
    // THE REGRESSION: the LOAD carries the seriesId resolved from the DB, even
    // though the ContentItem had no seriesStream. Before the fix this was null.
    expect(fake.lastSeriesId, 'SER-42',
        reason: 'the cast LOAD must carry the series id so the TV can auto-advance');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
