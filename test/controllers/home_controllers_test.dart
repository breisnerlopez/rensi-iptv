import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/controllers/xtream_code_home_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
  });

  tearDown(() async {
    AppState.m3uRepository = null;
    AppState.xtreamCodeRepository = null;
    AppState.currentPlaylist = null;
    await getIt.reset();
    await database.close();
  });

  group('XtreamCodeHomeController default index', () {
    late XtreamCodeHomeController controller;

    setUp(() {
      AppState.currentPlaylist = Playlist(
        id: 'xtream-playlist',
        name: 'Xtream Test',
        type: PlaylistType.xtream,
        url: 'https://example.com',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026),
      );
      AppState.xtreamCodeRepository = IptvRepository(
        ApiConfig(baseUrl: 'https://example.com', username: 'u', password: 'p'),
        'xtream-playlist',
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts at index 4 (TMDb) by default', () {
      controller = XtreamCodeHomeController(false, autoLoad: false);
      expect(controller.currentIndex, 4);
    });

    test('respects explicit initialIndex', () {
      controller = XtreamCodeHomeController(false, autoLoad: false, initialIndex: 0);
      expect(controller.currentIndex, 0);
    });

    test('clamps index to valid range', () {
      controller = XtreamCodeHomeController(false, autoLoad: false, initialIndex: 99);
      expect(controller.currentIndex, 5);
    });
  });
}
