import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

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
  /// Darker accent for FILLED buttons, which carry text. `#FFF5F0` on [_accent]
  /// measures 3.81:1 — under the 4.5:1 WCAG AA needs for normal text — while on
  /// this it is 4.99:1. [_accent] stays for icons and large shapes, which only
  /// need 3:1. Also used by selected chips, whose labels are normal-size text.
  static const Color _accentInk = Color(0xFFB04C2E);
  static const Color _accent2 = Color(0xFFDA8A56); // accent 72% + warm gold
  static const Color _onAccent = Color(0xFFFFF5F0);
  static const Color _gold = Color(0xFFD8A34A);
  static const Color _live = Color(0xFFE0563E);

  // ---- Dark (default) tokens ----
  // Warm neutrals (hue ~25-30°), not the blue-violet ramp these used to be
  // (~250°). A terracotta brand sitting on slate-blue surfaces is what made the
  // product read as "generic dark mode with an orange on top" instead of the
  // warm, cinematic look the rest of the design is reaching for.
  static const Color _dBg = Color(0xFF0C0A09);
  static const Color _dSurface = Color(0xFF17130F);
  static const Color _dSurface2 = Color(0xFF221D18);
  // Slightly lighter than the first warm retint: that pass dropped the
  // card-vs-background separation from 1.091 to 1.069, flattening borders that
  // were already subtle at 3m. This restores it without going back to cold.
  static const Color _dSurface3 = Color(0xFF332C25);
  static const Color _dText = Color(0xFFF3F1EE);
  static const Color _dText2 = Color(0xFFB9B2A8);
  // Passes AA (4.5:1) against EVERY surface in the ramp, not just the
  // background: bg 6.61, surface 6.18, surface2 5.59, surface3 4.60. Two
  // earlier attempts failed — #76747E was 4.28:1 even on the background, and
  // #968D81 passed only until surface3 was lightened, which is why
  // test/utils/contrast_test.dart checks the whole ramp instead of one pair.
  static const Color _dText3 = Color(0xFF9D9488);

  // ---- Light tokens ----
  static const Color _lBg = Color(0xFFF4F1EC);
  static const Color _lSurface = Color(0xFFFFFFFF);
  static const Color _lSurface2 = Color(0xFFF3EFE8);
  static const Color _lSurface3 = Color(0xFFE8E2D8);
  static const Color _lText = Color(0xFF1B1813);
  static const Color _lText2 = Color(0xFF59534B);
  // Was #908A80 at 3.04:1 on the light background — well under AA. The dark
  // theme's contrast pass had skipped the light one entirely.
  static const Color _lText3 = Color(0xFF726C62);

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
      // Retinted with the rest of the ramp; it was the one step left at the
      // old blue-violet hue.
      surfaceContainerLow: isDark ? const Color(0xFF120F0D) : _lBg,
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
      // Filled buttons carry text, so they need the darker accent: white on
      // _accent measures 3.9:1, below the 4.5:1 WCAG AA needs for normal text.
      // Icons and large shapes keep _accent (they only need 3:1).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accentInk,
          foregroundColor: _onAccent,
          // Without these an explicit backgroundColor makes the disabled state
          // resolve to null, i.e. a transparent button instead of the grey one.
          disabledBackgroundColor: text.withValues(alpha: 0.12),
          disabledForegroundColor: text.withValues(alpha: 0.38),
        ),
      ),
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
        // Chip labels are normal-size text, so they need the AA-safe accent.
        selectedColor: _accentInk,
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
        // Smaller labels so all 5 tabs (incl. "Configuración") fit without
        // truncation on narrow phones.
        selectedLabelStyle: const TextStyle(fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
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

  /// The type scale, in dp. Seven steps, no half points.
  ///
  /// The app renders 22 distinct sizes today — 9, 9.5, 10, 10.5, 11, 11.5, 12,
  /// 12.5, 13, 13.5, 14, 14.5, 15, 16, 18, 19, 20, 22, 24, 26, 36, 64 — against
  /// 22 uses of the textTheme. The half points are the signature of tuning by
  /// eye. Netflix's TV UI runs on six or seven steps; this is that ladder.
  ///
  /// [tvBodyMin] is the floor for anything a viewer is expected to READ at
  /// three metres. Below it text is decoration, and the rail labels sat at 10.
  static const double displaySize = 52;
  static const double h1Size = 36;
  static const double h2Size = 28;
  static const double h3Size = 22;
  static const double bodySize = 18;
  static const double bodySmallSize = 16;
  static const double labelSize = 14;
  static const double tvBodyMin = 14;

  /// Single content gutter for the 10-foot UI. Five different left margins
  /// (16 / 24 / 72 / 120 / 128) across four screens was the most immediate
  /// visual tell that this was a phone layout stretched onto a TV.
  static const double _tvGutter = 48;

  /// The one focus-ring colour for the whole product.
  ///
  /// Before this existed the app had five: white on cards, terracotta on text
  /// fields, terracotta on text/outlined buttons, #FFF5F0 on filled buttons
  /// (contrast 1.03:1 against their white fill — i.e. invisible) and a filled
  /// terracotta background on the nav rail. On a 10-foot UI the user navigates
  /// by tracking a single bright point; five dialects break that contract.
  static Color focusRing(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFFFFFFF) : _accent;

  /// Returns [base] augmented with TV-grade focus visuals: a strong accent
  /// ring + tinted overlay on every interactive Material widget. Applied
  /// from `MaterialApp.builder` only on large screens / Android TV.
  static ThemeData applyTvOverrides(ThemeData base) {
    final scheme = base.colorScheme;
    // Single source of truth, shared with FocusHighlight so the two can never
    // drift into different dialects.
    final ring = focusRing(base.brightness);
    final focusOverlay = ring.withValues(alpha: 0.28);

    return base.copyWith(
      focusColor: focusOverlay,
      // AppBars kept Material's phone defaults: a 16dp titleSpacing puts the
      // title — and the back arrow — inside the 5% a TV crops. One theme entry
      // aligns every screen's header with the body gutter.
      appBarTheme: base.appBarTheme.copyWith(
        titleSpacing: _tvGutter,
        toolbarHeight: 72,
      ),
      // Only on a REAL television. `isDesktopOrTV` also covers tablets and
      // desktop (>=900dp), where the handles are still draggable — hiding them
      // there would leave an invisible-but-live control, which is worse than
      // the artefact it removes.
      textSelectionTheme: ResponsiveHelper.isTelevisionDevice
          ? base.textSelectionTheme
              .copyWith(selectionHandleColor: Colors.transparent)
          : base.textSelectionTheme,
      // Filled / elevated buttons paint a primary fill, so a primary ring
      // would be invisible on them — use onPrimary for contrast there.
      // MERGE, don't replace: `copyWith` swaps the whole theme, and rebuilding
      // it here silently threw away the base style's accessible background —
      // on TV the filled buttons fell back to colorScheme.primary at 3.81:1,
      // i.e. the contrast fix did not exist on the target platform.
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle())
            .merge(_tvButtonStyle(scheme.onPrimary, focusOverlay)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle())
            .merge(_tvButtonStyle(scheme.onPrimary, focusOverlay)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _tvButtonStyle(ring, focusOverlay),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _tvButtonStyle(ring, focusOverlay),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return focusOverlay;
            return null;
          }),
        ),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: ring.withValues(alpha: 0.18),
      ),
      // Real Material chips (ChoiceChip/FilterChip/… in search filters, genre
      // pickers, playback speed) are NOT wrapped in FocusHighlight, so they need
      // their own strong D-pad focus ring. Match the FocusHighlight language:
      // white on dark, brand accent on light. (RensiChip is a custom Container,
      // it doesn't read chipTheme, so there's no double ring.)
      chipTheme: base.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            final ring = scheme.brightness == Brightness.dark
                ? const Color(0xFFFFFFFF)
                : scheme.primary;
            return BorderSide(color: ring, width: 3);
          }
          return BorderSide(color: scheme.outlineVariant, width: 1);
        }),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: ring, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Overlay only. The ring belongs to [FocusHighlight]; painting one here too
  /// produced two concentric-ish rings with a dark gap between them, and on a
  /// StadiumBorder button the theme's rectangular radius did not even match the
  /// pill it was drawn around.
  static ButtonStyle _tvButtonStyle(Color ring, Color overlay) {
    return ButtonStyle(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) return overlay;
        return null;
      }),
    );
  }
}
