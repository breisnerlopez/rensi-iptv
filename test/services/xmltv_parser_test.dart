import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/xmltv_parser.dart';

void main() {
  group('XmltvParser', () {
    test('parses programmes with title, desc and UTC-normalized times', () {
      const xml = '''
<tv>
  <channel id="c1"><display-name>One</display-name></channel>
  <programme start="20250815120000 +0000" stop="20250815130000 +0000" channel="c1">
    <title>Noon Show</title>
    <desc>A show at noon</desc>
  </programme>
  <programme start="20250815140000 +0200" stop="20250815150000 +0200" channel="c1">
    <title>Two PM (CEST)</title>
  </programme>
</tv>''';
      final progs = XmltvParser.parse(xml);
      expect(progs, hasLength(2));
      expect(progs[0].channelId, 'c1');
      expect(progs[0].title, 'Noon Show');
      expect(progs[0].description, 'A show at noon');
      expect(progs[0].start, DateTime.utc(2025, 8, 15, 12));
      expect(progs[0].stop, DateTime.utc(2025, 8, 15, 13));
      // +0200 wall clock 14:00 → 12:00 UTC.
      expect(progs[1].start, DateTime.utc(2025, 8, 15, 12));
      expect(progs[1].description, isNull, reason: 'no <desc> → null');
    });

    test('skips partial/malformed programmes instead of aborting', () {
      const xml = '''
<tv>
  <programme start="20250815120000" stop="20250815130000" channel="c1"><title>Good</title></programme>
  <programme stop="20250815130000" channel="c1"><title>NoStart</title></programme>
  <programme start="20250815120000" stop="20250815130000"><title>NoChannel</title></programme>
  <programme start="BADTIME" stop="20250815130000" channel="c1"><title>BadTime</title></programme>
  <programme start="20250815120000" stop="20250815130000" channel="c1"></programme>
  <programme start="20250815130000" stop="20250815120000" channel="c1"><title>StopBeforeStart</title></programme>
</tv>''';
      final progs = XmltvParser.parse(xml);
      expect(progs, hasLength(1),
          reason: 'only the well-formed programme survives');
      expect(progs.single.title, 'Good');
      // No offset → parsed as UTC as-is.
      expect(progs.single.start, DateTime.utc(2025, 8, 15, 12));
    });

    test('parseXmltvTime handles negative offsets', () {
      // 08:00 at -0500 → 13:00 UTC.
      expect(XmltvParser.parseXmltvTime('20250815080000 -0500'),
          DateTime.utc(2025, 8, 15, 13));
    });
  });
}
