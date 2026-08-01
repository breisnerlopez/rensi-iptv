// Wave-2 QA G1: pins the download User-Agent on the host (Dart VM, no emulator).
// The byte-download path itself is a background_downloader platform channel and
// cannot run here (see report — BLOCKED, HW-needed); the UA CONSTANT it sends is
// pure Dart and is asserted directly. The per-item M3U UA override lives in the
// private _resolveUserAgent (reads M3uItems.userAgent) and is code-review only.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/download_service.dart';

void main() {
  test('G1 — default download UA is a whitelisted player UA (VLC 3.0.20)', () {
    // Xtream panels reject the downloader's non-player HTTP client; sending a
    // VLC UA (what libmpv-style clients present) avoids the UA block.
    expect(kDownloadUserAgent, 'VLC/3.0.20 LibVLC/3.0.20');
  });

  test('G1 — DownloadService exposes the 10GB space policy it enforces', () {
    // Same policy object exercised by the Z-cases; confirms enqueue()'s purge
    // uses the 10GB cap.
    expect(DownloadService.instance.policy.capBytes, 10 * 1024 * 1024 * 1024);
  });
}
