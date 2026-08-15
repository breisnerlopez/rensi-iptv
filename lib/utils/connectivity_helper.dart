import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Small helpers to reason about the active network interface for features that
/// only make sense on a LAN (casting to a TV on the same network) or that are
/// costly on a metered link (large offline downloads).
///
/// Conservative by design: any ambiguous or multi-interface state, and any
/// platform/plugin error, resolves to "not cellular-only" so we never hide a
/// usable feature (cast) or nag a user who is actually on Wi‑Fi.
class ConnectivityHelper {
  /// Pure predicate over a connectivity result set: true ONLY when the set is
  /// non-empty and every interface is cellular. Extracted so the decision can
  /// be unit-tested without the platform plugin.
  @visibleForTesting
  static bool cellularOnly(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.every((r) => r == ConnectivityResult.mobile);
  }

  /// Test seam: when set, [isCellularOnly] returns this instead of querying the
  /// platform. Null in production. Reset it in tearDown.
  @visibleForTesting
  static Future<bool> Function()? debugIsCellularOnly;

  /// True ONLY when the active connectivity is exclusively cellular data — no
  /// Wi‑Fi, Ethernet or VPN interface present. In that state there is no LAN a
  /// cast receiver could live on, so casting cannot possibly work.
  ///
  /// Returns false on any ambiguity (Wi‑Fi+VPN, Ethernet, empty result) or on
  /// error, so a false positive never wrongly hides cast from someone who could
  /// use it. The same predicate drives the "you're on mobile data" download
  /// prompt.
  static Future<bool> isCellularOnly() async {
    final override = debugIsCellularOnly;
    if (override != null) return override();
    try {
      // timeout: el canal de plataforma NO debe poder colgar al llamador (el
      // gate de cast está en el hot path de abrir reproducción). Si tarda o
      // lanza, se degrada a "no celular" = comportamiento de hoy.
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      return cellularOnly(results);
    } catch (_) {
      return false;
    }
  }
}
