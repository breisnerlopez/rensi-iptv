import 'package:xml/xml.dart';

/// One parsed XMLTV programme (a guide entry for a channel over a time window).
class XmltvProgramme {
  final String channelId;
  final DateTime start; // UTC
  final DateTime stop; // UTC
  final String title;
  final String? description;

  const XmltvProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });
}

/// Parses an XMLTV document (the standard external EPG format) into programmes.
/// Lenient by design — a real-world XMLTV feed is large and often has partial
/// entries, so anything missing a channel/start/stop/title is skipped rather
/// than aborting the whole guide.
class XmltvParser {
  static List<XmltvProgramme> parse(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    final out = <XmltvProgramme>[];
    for (final p in doc.findAllElements('programme')) {
      final channel = p.getAttribute('channel');
      final startStr = p.getAttribute('start');
      final stopStr = p.getAttribute('stop');
      if (channel == null || startStr == null || stopStr == null) continue;
      final start = parseXmltvTime(startStr);
      final stop = parseXmltvTime(stopStr);
      if (start == null || stop == null || !stop.isAfter(start)) continue;
      final title = p.getElement('title')?.innerText.trim() ?? '';
      if (title.isEmpty) continue;
      final descRaw = p.getElement('desc')?.innerText.trim();
      out.add(XmltvProgramme(
        channelId: channel,
        start: start,
        stop: stop,
        title: title,
        description: (descRaw == null || descRaw.isEmpty) ? null : descRaw,
      ));
    }
    return out;
  }

  /// XMLTV time: `YYYYMMDDHHMMSS` optionally followed by a ` +ZZZZ`/`-ZZZZ`
  /// offset. Returns the instant in UTC (offset applied), or null if malformed.
  static DateTime? parseXmltvTime(String s) {
    final m = RegExp(r'^\s*(\d{14})(?:\s*([+-]\d{4}))?').firstMatch(s);
    if (m == null) return null;
    final d = m.group(1)!;
    final base = DateTime.utc(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
      int.parse(d.substring(8, 10)),
      int.parse(d.substring(10, 12)),
      int.parse(d.substring(12, 14)),
    );
    final off = m.group(2);
    if (off == null) return base;
    final sign = off[0] == '-' ? -1 : 1;
    final oh = int.parse(off.substring(1, 3));
    final om = int.parse(off.substring(3, 5));
    // The wall-clock had the given offset; subtract it to reach UTC.
    return base.subtract(Duration(hours: sign * oh, minutes: sign * om));
  }
}
