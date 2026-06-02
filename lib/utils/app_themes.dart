import 'package:flutter/material.dart';

class AppThemes {
  // Material Red 700 — deep, elegant red that anchors the whole palette
  // (primary, secondary, tertiary, surface, error...) through ColorScheme.fromSeed.
  static const Color _seedColor = Color(0xFFD32F2F);

  static final ThemeData lightTheme = _buildTheme(Brightness.light);
  static final ThemeData darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    // On TV the user is 3 metres away with a D-pad; the stock Material 3
    // focus indicator is a ~12% overlay that disappears at that distance.
    // We pick a high-contrast accent for the focus ring and let every
    // interactive widget render it as a fat border / overlay.
    final focusRing = brightness == Brightness.dark
        ? const Color(0xFFFFD54F) // amber 300 — pops on dark grey backgrounds
        : scheme.primary;          // brand red — pops on cream backgrounds
    final focusOverlay = focusRing.withValues(alpha: 0.32);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    return base.copyWith(
      focusColor: focusOverlay,

      // Buttons: thick coloured border + visible overlay when focused.
      filledButtonTheme: FilledButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _tvButtonStyle(focusRing, focusOverlay),
      ),

      // IconButton: thick ring (border on the round shape) on focus.
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

      // ListTile (settings, browser, sort sheet…): the focus overlay is
      // supplied by ThemeData.focusColor above. selectedTileColor here
      // adds a tinted background for the "is currently selected" state.
      listTileTheme: ListTileThemeData(
        selectedTileColor: focusRing.withValues(alpha: 0.18),
      ),

      // Cards / InkWell wrappers (content cards, playlist tiles, etc.)
      // share the theme-level focusColor we set above. cardTheme also
      // wins us a focused border for the few places that use `Card`
      // directly with no InkWell inside.
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: focusOverlay, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Filter / sort chips show a visible ring around the active one.
      chipTheme: base.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: focusRing, width: 3);
          }
          return BorderSide(color: scheme.outlineVariant, width: 1);
        }),
      ),

      // Plain text fields the user can land on with the remote get a
      // thick focused border (was the stock 2px primary line).
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: focusRing, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Shared button style: same look across Filled / Elevated / Outlined /
  /// Text buttons — a fat ring + tinted overlay whenever focus lands.
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
