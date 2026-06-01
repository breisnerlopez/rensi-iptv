import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/type_convertions.dart';

void main() {
  group('safeDateTime', () {
    test('returns null for null and empty inputs', () {
      expect(safeDateTime(null), isNull);
      expect(safeDateTime(''), isNull);
      expect(safeDateTime('   '), isNull);
    });

    test('passes through a DateTime unchanged', () {
      final dt = DateTime.utc(2024, 6, 1);
      expect(safeDateTime(dt), same(dt));
    });

    test('parses an int as Unix seconds', () {
      expect(
        safeDateTime(1700000000),
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('parses a long digit string as Unix seconds, not as year', () {
      expect(
        safeDateTime('1700000000'),
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('parses a 4-digit year string', () {
      expect(safeDateTime('2019'), DateTime(2019));
      expect(safeDateTime('1995'), DateTime(1995));
    });

    test('parses ISO 8601', () {
      expect(
        safeDateTime('2024-06-01T12:30:00Z'),
        DateTime.utc(2024, 6, 1, 12, 30),
      );
    });

    test('parses "YYYY-MM-DD HH:mm:ss"', () {
      final parsed = safeDateTime('2024-06-01 12:30:00');
      expect(parsed?.year, 2024);
      expect(parsed?.month, 6);
      expect(parsed?.day, 1);
    });

    test('returns null on garbage input', () {
      expect(safeDateTime('not a date'), isNull);
      expect(safeDateTime('123abc'), isNull);
    });

    test('handles a double as Unix seconds (decimal)', () {
      final parsed = safeDateTime(1700000000.5);
      expect(parsed, DateTime.fromMillisecondsSinceEpoch(1700000000500));
    });
  });
}
