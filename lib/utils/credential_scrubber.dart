/// Removes IPTV credentials from any text before it reaches a screen, a log or
/// a crash report.
///
/// Xtream carries the subscription user and password *inside the stream path*
/// (`buildMediaUrl`), so a raw libmpv/http error string such as
/// `Failed to open http://host:8080/live/USER/PASS/1.ts` discloses the whole
/// account. Scrubbing therefore happens at the boundary — every place that
/// renders or logs an error — never at individual call sites.
///
/// The masking is **structural, not pattern-matching**: every URL found in the
/// text is parsed as a [Uri] and rebuilt with everything that could carry a
/// secret replaced. Enumerating the shapes that leak (`/live/`, `/movie/`,
/// `/timeshift/`, `/hlsr/`, `get.php?…`, `user:pass@host`, a stray trailing
/// slash in the saved server URL) is a losing game — one unknown shape, or one
/// extra path segment, and the password walks straight through. So the default
/// is to mask, and only a small allowlist survives.
///
/// Deliberately does **not** depend on the active playlist for its guarantee:
/// `M3uParser` runs inside `compute()`, i.e. a separate isolate where statics
/// like `AppState.currentPlaylist` are reset to null. Anything relying on that
/// would silently be a no-op on exactly the M3U path it is meant to protect.
library;

import 'package:rensi_iptv/services/app_state.dart';

const String _mask = '***';

/// Query parameters whose values are safe to keep — they aid debugging and
/// carry no secret. Everything else (`token`, `auth`, `key`, `sid`, …) is
/// masked, including names we have never seen.
const Set<String> _safeQueryKeys = {
  'type',
  'output',
  'action',
  'category_id',
  'stream_id',
  'series_id',
  'vod_id',
};

/// Path segments that are known Xtream/M3U endpoint names, safe to keep and
/// genuinely useful when reading an error. Anything else — including the first
/// segment — is masked, because a live-stream URL can omit the type segment
/// entirely (`http://host/USER/PASS/1.ts`) and then position 0 *is* the
/// username.
const Set<String> _safePathSegments = {
  'live',
  'movie',
  'series',
  'timeshift',
  'hlsr',
  'get.php',
  'player_api.php',
  'panel_api.php',
  'xmltv.php',
};

/// Any scheme, not just http(s): `M3uParser` treats every non-`#` line as a
/// stream URL without validating the scheme, so `rtmp://USER:PASS@host/live`
/// and `rtsp://…` reach the player, the snackbar and the log exactly like an
/// http one. Matching only http here would have been the same "enumerate the
/// shapes that leak" mistake this file exists to avoid.
///
/// Matches greedily up to whitespace; trailing punctuation is trimmed
/// afterwards rather than excluded from the character class, because excluding
/// `)`/`]`/`"` truncates the match on a password that contains one and leaves
/// its tail in the clear.
final RegExp _urlInText =
    RegExp(r'[a-zA-Z][a-zA-Z0-9+.\-]*://\S+', caseSensitive: false);

/// Punctuation that is almost certainly sentence structure, not part of a URL.
final RegExp _trailingPunctuation = RegExp(r'''[.,;:!?'"\)\]\}>]+$''');

/// Rebuilds [raw] with credentials removed. Keeps the scheme, the host, the
/// first path segment (`live`, `movie`, `get.php` — the useful diagnostic) and
/// the file extension; masks userInfo, every other path segment and every
/// non-allowlisted query value.
String _maskUrlSafely(String raw, {String? username, String? password}) {
  // Fail CLOSED. Anything we cannot fully understand gets masked wholesale:
  // returning the input unchanged would hand over the credentials in exactly
  // the malformed-URL cases an attacker-shaped or unusual error produces. This
  // also runs inside ErrorWidget.builder, where an uncaught throw would be an
  // unrecoverable error loop — so nothing here is allowed to escape.
  final schemeEnd = raw.indexOf('://');
  final safeFallback =
      schemeEnd > 0 ? '${raw.substring(0, schemeEnd)}://$_mask' : _mask;
  try {
    return _maskUrlOrThrow(raw, username: username, password: password) ??
        safeFallback;
  } catch (_) {
    return safeFallback;
  }
}

String? _maskUrlOrThrow(String raw, {String? username, String? password}) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.isEmpty) return null;

  final known = <String>{
    if (username != null && username.isNotEmpty) username,
    if (password != null && password.isNotEmpty) password,
  };

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final masked = <String>[];
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    // A segment is only "safe" if it is an endpoint name AND is not the user's
    // actual credential: a subscription whose username is literally `live`
    // would otherwise be waved through by its own allowlist.
    if (_safePathSegments.contains(segment.toLowerCase()) &&
        !known.contains(segment)) {
      masked.add(segment);
      continue;
    }
    // Keep the extension: "***.ts" still tells you it was a live stream. Only
    // when it really looks like an extension, though — blindly keeping
    // everything after the last dot published the tail of a password shaped
    // `/USER/Abc.Def12345`, and matrix params (`1.ts;jsessionid=SECRET`) rode
    // along with it.
    final isLast = i == segments.length - 1;
    final dot = segment.lastIndexOf('.');
    final ext = dot > 0 ? segment.substring(dot + 1) : '';
    final looksLikeExtension =
        ext.isNotEmpty && ext.length <= 5 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(ext);
    masked.add(isLast && looksLikeExtension ? '$_mask.$ext' : _mask);
  }

  // Parsed by hand rather than via `queryParameters`, which collapses repeated
  // keys ("an arbitrary choice of possible value") — so `?type=m3u&type=SECRET`
  // could keep the secret. Keys are masked too: a query with no `=` would
  // otherwise surface the whole secret as a key name.
  final query = <String>[];
  if (uri.query.isNotEmpty) {
    final pairs = uri.query.split('&');
    // A legitimate URL does not repeat `type` or `action`. A repeat is how a
    // secret rides in behind an allowlisted name (`?type=m3u&type=SECRET`), so
    // a duplicated key forfeits its allowlist status entirely.
    final seen = <String>{};
    final duplicated = <String>{};
    for (final pair in pairs) {
      final eq = pair.indexOf('=');
      final key = (eq < 0 ? pair : pair.substring(0, eq)).toLowerCase();
      if (!seen.add(key)) duplicated.add(key);
    }
    for (final pair in pairs) {
      final eq = pair.indexOf('=');
      if (eq < 0) {
        query.add(_mask);
        continue;
      }
      final key = pair.substring(0, eq);
      final safe = _safeQueryKeys.contains(key.toLowerCase()) &&
          !duplicated.contains(key.toLowerCase());
      // The key is masked too when it is not allowlisted: a parameter *name*
      // can carry the secret just as easily as its value.
      query.add(safe ? '$key=${pair.substring(eq + 1)}' : '$_mask=$_mask');
    }
  }

  final buffer = StringBuffer()
    ..write(uri.scheme)
    ..write('://');
  if (uri.userInfo.isNotEmpty) buffer.write('$_mask@');
  // `Uri.host` strips the brackets off an IPv6 literal; without them the
  // rebuilt string is not a valid URL.
  buffer.write(uri.host.contains(':') ? '[${uri.host}]' : uri.host);
  if (uri.hasPort) buffer.write(':${uri.port}');
  if (masked.isNotEmpty) buffer.write('/${masked.join('/')}');
  if (query.isNotEmpty) buffer.write('?${query.join('&')}');
  // A fragment can carry anything; keep the marker, drop the content.
  if (uri.hasFragment) buffer.write('#$_mask');
  return buffer.toString();
}

/// Scrubs [input] of any credential material. Safe to call on anything,
/// including null. Pass [username]/[password] when the caller knows them (e.g.
/// a repository holding its own config) so literals are caught even when they
/// appear outside a URL.
/// Longest input we will scan. `_urlInText` backtracks quadratically over a
/// long run of alphanumerics with no `://` (measured: 100k chars = 19 s, 400k =
/// 256 s), and this runs on the UI thread from `FlutterError.onError` and
/// `ErrorWidget.builder` — a degenerate HTTP body quoted inside an exception
/// would freeze the app. No real error message needs more than this.
const int _maxScanLength = 8192;

String scrubCredentials(Object? input, {String? username, String? password}) {
  var text = input?.toString() ?? '';
  if (text.isEmpty) return text;
  if (text.length > _maxScanLength) {
    text = '${text.substring(0, _maxScanLength)}… [truncado]';
  }

  // Structural pass — the load-bearing one. Works with no playlist context and
  // across isolates.
  final playlist = AppState.currentPlaylist;
  final user = username ?? playlist?.username;
  final pass = password ?? playlist?.password;
  text = text.replaceAllMapped(_urlInText, (m) {
    final match = m[0]!;
    // Trim sentence punctuation that the greedy match swallowed, and put it
    // back after masking so "Failed to open http://…/1.ts." keeps its period.
    final tail = _trailingPunctuation.firstMatch(match)?.group(0) ?? '';
    final url = match.substring(0, match.length - tail.length);
    return _maskUrlSafely(url, username: user, password: pass) + tail;
  });

  // Literal pass — catches credentials quoted outside a URL. Only for secrets
  // long enough that replacing them cannot shred an unrelated message; a short
  // password is already covered by the structural pass inside URLs.
  for (final secret in <String?>[user, pass]) {
    if (secret != null && secret.length >= 6) {
      text = text.replaceAll(secret, _mask);
    }
  }

  return text;
}

/// Masks a URL for display: shows *where* without showing *who*.
String scrubUrlForDisplay(String? url) {
  if (url == null || url.isEmpty) return '';
  return scrubCredentials(url);
}
