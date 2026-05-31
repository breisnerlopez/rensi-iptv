import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryType', () {
    test('parses valid persisted values', () {
      expect(CategoryType.fromString('live'), CategoryType.live);
      expect(CategoryType.fromString('vod'), CategoryType.vod);
      expect(CategoryType.fromString('series'), CategoryType.series);
    });

    test('throws on invalid persisted values', () {
      expect(() => CategoryType.fromString('invalid'), throwsArgumentError);
    });
  });

  group('ContentType', () {
    test('maps content type to category type', () {
      expect(
        ContentType.toCategoryType(ContentType.liveStream),
        CategoryType.live,
      );
      expect(ContentType.toCategoryType(ContentType.vod), CategoryType.vod);
      expect(
        ContentType.toCategoryType(ContentType.series),
        CategoryType.series,
      );
    });
  });
}
