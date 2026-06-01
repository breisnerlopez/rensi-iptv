int safeInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    try {
      return double.parse(trimmed).toInt();
    } catch (e) {
      return 0;
    }
  }
  try {
    return int.parse(value.toString());
  } catch (e) {
    return 0;
  }
}

double? safeDouble(dynamic value) {
  if (value == null) return null;

  if (value is double) return value;
  if (value is int) return value.toDouble();

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    try {
      return double.parse(trimmed);
    } catch (e) {
      print('Double parsing error for value: "$value" - $e');
      return null;
    }
  }

  try {
    return double.parse(value.toString());
  } catch (e) {
    print('Double parsing error for value: "$value" - $e');
    return null;
  }
}

bool safeBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;

  if (value is String) {
    final trimmed = value.trim().toLowerCase();
    return trimmed == 'true' || trimmed == '1' || trimmed == 'yes';
  }

  if (value is int) return value != 0;

  return false;
}

String safeString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

/// Tolerantly parses an Xtream-Codes-style timestamp value into a
/// [DateTime]. Accepts:
///   - a [DateTime] passed through unchanged,
///   - a Unix epoch in seconds as `int` or numeric `String`,
///   - an ISO 8601 / "YYYY-MM-DD HH:mm:ss" string,
///   - a bare `"YYYY"` year string (mapped to Jan 1 of that year).
///
/// Returns null for missing/empty/unparseable values so callers can apply
/// their own fallback (e.g. epoch for sort).
DateTime? safeDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
  }
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    // Pure-digit strings: distinguish a 4-digit year ("2019") from a Unix
    // epoch ("1700000000"). DateTime.tryParse would happily read either
    // as a year, so we route through the integer path here.
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      final n = int.tryParse(raw);
      if (n == null) return null;
      if (raw.length == 4 && n >= 1000 && n <= 9999) {
        return DateTime(n);
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    return DateTime.tryParse(raw);
  }
  return null;
}

String? getFirstBackdropPath(dynamic backdropPath) {
  if (backdropPath == null) return null;

  if (backdropPath is List && backdropPath.isNotEmpty) {
    final first = backdropPath[0];
    final safeFirst = safeString(first);
    return safeFirst.isEmpty ? null : safeFirst;
  }

  if (backdropPath is String) {
    final safe = safeString(backdropPath);
    return safe.isEmpty ? null : safe;
  }

  return null;
}
