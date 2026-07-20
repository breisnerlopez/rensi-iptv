import 'dart:async';

import 'package:rensi_iptv/utils/credential_scrubber.dart';

class PlayerErrorHandler {
  Timer? _errorTimer;
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  static const int _baseDelayMs = 1000; // 1 saniye başlangıç

  void handleError(String error, Function() onRetry, Function(String) showSnackBar) {
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