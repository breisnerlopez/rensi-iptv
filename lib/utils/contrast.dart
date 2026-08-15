import 'dart:ui';

/// WCAG contrast utilities (runtime). Mirrors the pure logic that until now only
/// lived in `test/utils/contrast_test.dart`, so the accent-selection path (F4)
/// can validate/derive colours at runtime and the test can reuse the SAME math.
///
/// Uses Flutter's native [Color.computeLuminance] (identical WCAG relative
/// luminance) instead of re-deriving it.
class Contrast {
  Contrast._();

  /// WCAG minimum for normal-size text.
  static const double aaNormal = 4.5;

  /// WCAG minimum for large text / icons / meaningful graphical shapes.
  static const double aaLarge = 3.0;

  /// Contrast ratio between two colours, `(L1+0.05)/(L2+0.05)` with L1≥L2.
  /// Range 1.0 (identical) … 21.0 (black vs white).
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Whether [fg] on [bg] clears the normal-text bar.
  static bool passesText(Color fg, Color bg) => ratio(fg, bg) >= aaNormal;

  /// Whether [fg] on [bg] clears the large/graphical bar.
  static bool passesLarge(Color fg, Color bg) => ratio(fg, bg) >= aaLarge;

  /// The higher-contrast ink (black vs white) for text sitting ON [background].
  /// Used to derive `onAccent` deterministically for an arbitrary accent.
  static Color inkFor(Color background) =>
      ratio(const Color(0xFFFFFFFF), background) >=
              ratio(const Color(0xFF000000), background)
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000);
}
