import 'package:flutter/material.dart';

/// Extra design tokens from the cinematic redesign that don't map onto a
/// standard [ColorScheme] slot (accent ramp, rating gold, live red, the
/// surface-2/3 steps and muted text tints). Read them with
/// `Theme.of(context).extension<RensiColors>()!`.
@immutable
class RensiColors extends ThemeExtension<RensiColors> {
  const RensiColors({
    required this.accent,
    required this.accent2,
    required this.accentSoft,
    required this.accentGlow,
    required this.onAccent,
    required this.gold,
    required this.live,
    required this.surface2,
    required this.surface3,
    required this.text2,
    required this.text3,
    required this.hairline,
    required this.hairline2,
  });

  final Color accent;
  final Color accent2;
  final Color accentSoft;
  final Color accentGlow;
  final Color onAccent;
  final Color gold;
  final Color live;
  final Color surface2;
  final Color surface3;
  final Color text2;
  final Color text3;
  final Color hairline;
  final Color hairline2;

  @override
  RensiColors copyWith({
    Color? accent,
    Color? accent2,
    Color? accentSoft,
    Color? accentGlow,
    Color? onAccent,
    Color? gold,
    Color? live,
    Color? surface2,
    Color? surface3,
    Color? text2,
    Color? text3,
    Color? hairline,
    Color? hairline2,
  }) {
    return RensiColors(
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accentSoft: accentSoft ?? this.accentSoft,
      accentGlow: accentGlow ?? this.accentGlow,
      onAccent: onAccent ?? this.onAccent,
      gold: gold ?? this.gold,
      live: live ?? this.live,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      hairline: hairline ?? this.hairline,
      hairline2: hairline2 ?? this.hairline2,
    );
  }

  @override
  RensiColors lerp(ThemeExtension<RensiColors>? other, double t) {
    if (other is! RensiColors) return this;
    return RensiColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      live: Color.lerp(live, other.live, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairline2: Color.lerp(hairline2, other.hairline2, t)!,
    );
  }
}

class AppThemes {
  static const String _displayFont = 'Bricolage Grotesque';
  static const String _uiFont = 'Hanken Grotesk';

  // Terracotta brand accent — single source the rest derives from.
  static const Color _accent = Color(0xFFC75F41);
  static const Color _accent2 = Color(0xFFDA8A56); // accent 72% + warm gold
  static const Color _onAccent = Color(0xFFFFF5F0);
  static const Color _gold = Color(0xFFD8A34A);
  static const Color _live = Color(0xFFE0563E);

  // ---- Dark (default) tokens ----
  static const Color _dBg = Color(0xFF0B0B0D);
  static const Color _dSurface = Color(0xFF16161B);
  static const Color _dSurface2 = Color(0xFF202027);
  static const Color _dSurface3 = Color(0xFF2A2A32);
  static const Color _dText = Color(0xFFF3F1EE);
  static const Color _dText2 = Color(0xFFB6B4BD);
  static const Color _dText3 = Color(0xFF76747E);

  // ---- Light tokens ----
  static const Color _lBg = Color(0xFFF4F1EC);
  static const Color _lSurface = Color(0xFFFFFFFF);
  static const Color _lSurface2 = Color(0xFFF3EFE8);
  static const Color _lSurface3 = Color(0xFFE8E2D8);
  static const Color _lText = Color(0xFF1B1813);
  static const Color _lText2 = Color(0xFF59534B);
  static const Color _lText3 = Color(0xFF908A80);

  static final ThemeData darkTheme = _build(Brightness.dark);
  static final ThemeData lightTheme = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? _dBg : _lBg;
    final surface = isDark ? _dSurface : _lSurface;
    final surface2 = isDark ? _dSurface2 : _lSurface2;
    final surface3 = isDark ? _dSurface3 : _lSurface3;
    final text = isDark ? _dText : _lText;
    final text2 = isDark ? _dText2 : _lText2;
    final text3 = isDark ? _dText3 : _lText3;
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : const Color(0xFF1C1612).withValues(alpha: 0.10);
    final hairline2 = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFF1C1612).withValues(alpha: 0.16);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: _accent,
      onPrimary: _onAccent,
      primaryContainer: Color.alphaBlend(
        _accent.withValues(alpha: isDark ? 0.22 : 0.16),
        surface,
      ),
      onPrimaryContainer: text,
      secondary: _accent2,
      onSecondary: _onAccent,
      secondaryContainer: surface2,
      onSecondaryContainer: text,
      tertiary: _gold,
      onTertiary: const Color(0xFF1B1813),
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: text2,
      surfaceContainerLowest: bg,
      surfaceContainerLow: isDark ? const Color(0xFF0F0F12) : _lBg,
      surfaceContainer: surface,
      surfaceContainerHigh: surface2,
      surfaceContainerHighest: surface3,
      outline: hairline2,
      outlineVariant: hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: text,
      onInverseSurface: bg,
      inversePrimary: _accent,
    );

    final baseText = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseText
        .apply(
          fontFamily: _uiFont,
          bodyColor: text,
          displayColor: text,
        )
        .copyWith(
          displayLarge: _display(57, FontWeight.w800, text),
          displayMedium: _display(45, FontWeight.w800, text),
          displaySmall: _display(36, FontWeight.w700, text),
          headlineLarge: _display(32, FontWeight.w700, text),
          headlineMedium: _display(28, FontWeight.w700, text),
          headlineSmall: _display(24, FontWeight.w700, text),
          titleLarge: _display(22, FontWeight.w700, text),
        );

    final rensi = RensiColors(
      accent: _accent,
      accent2: _accent2,
      accentSoft: _accent.withValues(alpha: 0.16),
      accentGlow: _accent.withValues(alpha: 0.45),
      onAccent: _onAccent,
      gold: _gold,
      live: _live,
      surface2: surface2,
      surface3: surface3,
      text2: text2,
      text3: text3,
      hairline: hairline,
      hairline2: hairline2,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: _uiFont,
      textTheme: textTheme,
      extensions: [rensi],
      dividerColor: hairline,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _display(22, FontWeight.w700, text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: _accent,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: text2, fontFamily: _uiFont),
        shape: const StadiumBorder(),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: _accent,
        unselectedItemColor: text3,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: _accent.withValues(alpha: 0.18),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _accent,
        thumbColor: _accent,
        inactiveTrackColor: hairline2,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _accent),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _onAccent : text3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _accent : surface3,
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
    );
  }

  static TextStyle _display(double size, FontWeight weight, Color color) {
    return TextStyle(
      fontFamily: _displayFont,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: -0.02 * size,
      color: color,
      height: 1.05,
    );
  }

  /// Returns [base] augmented with TV-grade focus visuals: a strong accent
  /// ring + tinted overlay on every interactive Material widget. Applied
  /// from `MaterialApp.builder` only on large screens / Android TV.
  static ThemeData applyTvOverrides(ThemeData base) {
    final scheme = base.colorScheme;
    final focusRing = scheme.primary; // terracotta reads on dark + light
    final focusOverlay = focusRing.withValues(alpha: 0.32);

    return base.copyWith(
      focusColor: focusOverlay,
      // Filled / elevated buttons paint a primary fill, so a primary ring
      // would be invisible on them — use onPrimary for contrast there.
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
      listTileTheme: ListTileThemeData(
        selectedTileColor: focusRing.withValues(alpha: 0.18),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: focusRing, width: 3);
          }
          return BorderSide(color: scheme.outlineVariant, width: 1);
        }),
      ),
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
