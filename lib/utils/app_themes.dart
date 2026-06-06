import 'package:flutter/material.dart';

class AppThemes {
  // Material Red 700 — deep, elegant red that anchors the whole palette
  // (primary, secondary, tertiary, surface, error...) through ColorScheme.fromSeed.
  static const Color _seedColor = Color(0xFFD32F2F);

  /// Stock Material 3 theme for phones — kept intentionally minimal so
  /// touch users see the framework defaults they're used to.
  static final ThemeData lightTheme = _baseTheme(Brightness.light);
  static final ThemeData darkTheme = _baseTheme(Brightness.dark);

  static ThemeData _baseTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
    );
  }

  /// Returns [base] augmented with TV-grade focus visuals: fat coloured
  /// borders + tinted overlays on every interactive Material widget.
  ///
  /// Called from `MaterialApp.builder` for the screens that actually
  /// need it (Android TV, large tablets in landscape, desktop), so a
  /// phone user never sees the heavier strokes.
  static ThemeData applyTvOverrides(ThemeData base) {
    final scheme = base.colorScheme;
    // On dark backgrounds amber 300 pops the most at 3 m viewing
    // distance; on light backgrounds the brand red carries the same
    // contrast against the cream-ish surface.
    final focusRing = scheme.brightness == Brightness.dark
        ? const Color(0xFFFFD54F)
        : scheme.primary;
    final focusOverlay = focusRing.withValues(alpha: 0.32);

    return base.copyWith(
      focusColor: focusOverlay,

      // Filled / elevated buttons paint a *primary* fill, so a primary-coloured
      // focus ring would be red-on-red (invisible) in the light theme. Use the
      // on-primary colour instead so the ring always contrasts the fill.
      filledButtonTheme: FilledButtonThemeData(
        style: _tvButtonStyle(scheme.onPrimary, focusOverlay),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _tvButtonStyle(scheme.onPrimary, focusOverlay),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return focusOverlay;
            return null;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: focusRing, width: 3);
            }
            return null;
          }),
        ),
      ),

      // ThemeData.focusColor already handles ListTile's focus overlay;
      // selectedTileColor anchors the persistent "selected" state for
      // settings groups and the sort sheet.
      listTileTheme: ListTileThemeData(
        selectedTileColor: focusRing.withValues(alpha: 0.18),
      ),

      // Filter / sort chips show a visible ring around the focused one.
      chipTheme: base.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: focusRing, width: 3);
          }
          return BorderSide(color: scheme.outlineVariant, width: 1);
        }),
      ),

      // Thicker focused border so the keyboard target is unmistakable
      // when the user lands on a text input via D-pad.
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: focusRing, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static ButtonStyle _tvButtonStyle(Color ring, Color overlay) {
    return ButtonStyle(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) return overlay;
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: ring, width: 3);
        }
        return null;
      }),
    );
  }
}
