import 'dart:async';

import 'package:rensi_iptv/utils/credential_scrubber.dart';

class PlayerErrorHandler {
  Timer? _errorTimer;
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  static const int _baseDelayMs = 1000; // 1 saniye başlangıç

  /// Advisory (non-fatal) mpv error substrings. mpv reports some conditions on
  /// the same error stream as genuine failures even though playback is fine —
  /// most notably a seek it cannot honour on a live stream ("Cannot seek …
  /// force it with '--force-seekable=yes'"). These are hints, not failures, and
  /// must NEVER trigger a reopen loop or the fatal error screen. Matched
  /// case-insensitively.
  static const List<String> _nonFatalSubstrings = <String>[
    'force-seekable',
    'cannot seek',
  ];

  /// Whether [error] is an advisory hint that should be ignored rather than
  /// retried or surfaced as a fatal error.
  static bool isNonFatal(String error) {
    final lower = error.toLowerCase();
    return _nonFatalSubstrings.any(lower.contains);
  }

  void handleError(String error, Function() onRetry, Function(String) showSnackBar,
      {bool isLive = false}) {
    // Advisory hint (e.g. force-seekable) on a LIVE stream: clean no-op. Return
    // BEFORE cancelling any pending retry so a genuine in-flight "Failed to
    // open" backoff is preserved, and without reopening or setting hasError.
    // Scoped to live ONLY: on VOD/series a "cannot seek" can be a real
    // resume-seek failure that must still surface, not be silently swallowed.
    if (isLive && isNonFatal(error)) return;

    _errorTimer?.cancel();

    // Exponential backoff (1s, 2s, 4s, 8s, 16s)
    int delayMs = (_baseDelayMs * (1 << _retryCount)).clamp(1000, 30000);

    if (error.contains('Failed to open') && _retryCount < _maxRetryCount) {
      _errorTimer = Timer(Duration(milliseconds: delayMs), () {
        _retryCount++;
        onRetry();
      });
    } else {
      // libmpv reports the failing URL verbatim ("Failed to open http://…"),
      // which for Xtream contains the account. Scrub at this boundary so every
      // present and future caller is covered.
      showSnackBar(scrubCredentials(error));
    }
  }

  void reset() {
    _errorTimer?.cancel();
    _retryCount = 0;
  }
}