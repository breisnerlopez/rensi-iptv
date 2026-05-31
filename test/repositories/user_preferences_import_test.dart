import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserPreferences.importSettings', () {
    test('rejects volume values outside [0, 100]', () async {
      await UserPreferences.importSettings({
        'volume': 9001.0,
      });
      expect(await UserPreferences.getVolume(), 100.0);

      await UserPreferences.importSettings({'volume': -5.0});
      expect(await UserPreferences.getVolume(), 0.0);
    });

    test('clamps subtitle font size to a sane range', () async {
      await UserPreferences.importSettings({'subtitle_font_size': 4.0});
      expect(await UserPreferences.getSubtitleFontSize(), 8.0);

      await UserPreferences.importSettings({'subtitle_font_size': 9999.0});
      expect(await UserPreferences.getSubtitleFontSize(), 96.0);
    });

    test('skips invalid theme_mode values', () async {
      // Keep a known initial value.
      await UserPreferences.setLocale('en');

      await UserPreferences.importSettings({
        'theme_mode': 'rogue', // invalid
        'locale': 'es', // valid, should pass
      });

      expect(await UserPreferences.getLocale(), 'es');
    });

    test('accepts list values for hidden_categories', () async {
      await UserPreferences.importSettings({
        'hidden_categories': ['sports', 'kids'],
      });
      expect(
        await UserPreferences.getHiddenCategories(),
        ['sports', 'kids'],
      );
    });

    test('keys outside the backup allowlist are ignored', () async {
      await UserPreferences.importSettings({
        'totally_unknown_key': 'foo',
        'background_play': true,
      });
      expect(await UserPreferences.getBackgroundPlay(), isTrue);
    });
  });
}
