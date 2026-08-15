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
    required this.accentInk,
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
  /// Relleno oscurecido del acento para superficies que llevan TEXTO normal
  /// (botones/chips): `onAccent` sobre el `accent` crudo mide ~3.9:1 (&lt;4.5),
  /// sobre `accentInk` ≥4.5. Nunca uses `accent` crudo como fondo de texto.
  final Color accentInk;
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
    Color? accentInk,
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
      accentInk: accentInk ?? this.accentInk,
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
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
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

/// F4 — un preset de acento curado (pre-validado WCAG en las 3 rampas). Ver
/// [AppThemes.accents]. Inmutable; cada tupla se elige para que el `accent` pase
/// ≥3:1 sobre cada surface (iconos/formas) y `onAccent` sobre `accentInk` pase
/// ≥4.5:1 (texto de botones/chips). `test/utils/contrast_test.dart` lo verifica.
class AccentSet {
  const AccentSet({
    required this.id,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.accent2,
  });

  /// Clave estable persistida en preferencias (no el índice, que podría cambiar
  /// si se reordena la paleta).
  final String id;
  final Color accent;
  final Color accentInk;
  final Color onAccent;
  final Color accent2;
}

class AppThemes {
  static const String _displayFont = 'Bricolage Grotesque';
  static const String _uiFont = 'Hanken Grotesk';

  // F4 — Acento personalizable por PRESETS curados. Cada preset es una tupla
  // pre-validada (test/utils/contrast_test.dart la verifica en las 3 rampas):
  //  - accent: iconos/bordes/rieles/formas (barra WCAG 3:1 sobre cada surface).
  //  - accentInk: relleno de botones/chips que llevan TEXTO (onAccent encima
  //    ≥4.5:1; el accent crudo daría ~3.8:1, insuficiente para texto normal).
  //  - onAccent: texto sobre accentInk.
  //  - accent2: secundario (degradados/detalles), no crítico para texto.
  // La mayoría de los usos de colorScheme.primary son iconos/bordes/fondos
  // (3:1). Los pocos que llevan TEXTO (CTA "guardar", selector de fuente) usan
  // rensi.accentInk como relleno (onAccent encima ≥4.5), NUNCA el accent crudo.
  static const AccentSet defaultAccent = AccentSet(
    id: 'terracotta',
    accent: Color(0xFFC75F41),
    accentInk: Color(0xFFB04C2E),
    onAccent: Color(0xFFFFF5F0),
    accent2: Color(0xFFDA8A56),
  );

  static const List<AccentSet> accents = [
    defaultAccent,
    AccentSet(
      id: 'teal',
      accent: Color(0xFF2E857C),
      accentInk: Color(0xFF2C7B74),
      onAccent: Color(0xFFF2FFFD),
      accent2: Color(0xFF6FD0C6),
    ),
    AccentSet(
      id: 'violet',
      accent: Color(0xFF8A6AD0),
      accentInk: Color(0xFF5E44A8),
      onAccent: Color(0xFFF7F4FF),
      accent2: Color(0xFFB9A2F2),
    ),
    AccentSet(
      id: 'rose',
      accent: Color(0xFFCB5074),
      accentInk: Color(0xFFB84666),
      onAccent: Color(0xFFFFF4F8),
      accent2: Color(0xFFEE93AE),
    ),
    AccentSet(
      id: 'amber',
      accent: Color(0xFFA9761F),
      accentInk: Color(0xFF7E5713),
      onAccent: Color(0xFFFFFBF2),
      accent2: Color(0xFFE7BE72),
    ),
    AccentSet(
      id: 'ocean',
      accent: Color(0xFF4380D0),
      accentInk: Color(0xFF356FBE),
      onAccent: Color(0xFFF3F8FF),
      accent2: Color(0xFF83B4EF),
    ),
  ];

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
  // Clears AA against the whole light ramp, not just the background: bg 5.28,
  // surface 5.95, surface2 5.19, surface3 4.62. Two earlier values fell short —
  // #908A80 at 3.04:1 on the background, then #726C62 which passed there but
  // measured 4.04:1 on surface3, where this token actually lives (cards, rows).
  // Only found because the test was widened to walk the ramp.
  static const Color _lText3 = Color(0xFF696359);

  static final ThemeData darkTheme = _build(Brightness.dark);
  static final ThemeData lightTheme = _build(Brightness.light);
  // AMOLED: the dark theme with pure-black background and near-black surfaces
  // (true black saves power on OLED and is a common request). Text tokens are
  // unchanged — light text on black is trivially above AA — so no accent/contrast
  // retune is involved. Built once, selected via ThemeProvider.amoled.
  static final ThemeData amoledTheme = _build(Brightness.dark, amoled: true);

  // AMOLED dark surfaces: pure-black background (the OLED power win, most of the
  // screen) with surfaces lifted enough to stay visible as cards. Card-vs-bg
  // separation also rests on the RensiColors hairline borders (surface alone,
  // near-black, would be too subtle) — the surfaces are lifted here so the
  // combination reads, not the surface colour on its own.
  static const Color _aBg = Color(0xFF000000);
  static const Color _aSurface = Color(0xFF181818);
  static const Color _aSurface2 = Color(0xFF202020);
  static const Color _aSurface3 = Color(0xFF2A2A2A);

  /// Fábrica pública parametrizada por acento (F4): reconstruye el tema al
  /// cambiar el preset elegido. `darkTheme`/`lightTheme`/`amoledTheme` siguen
  /// siendo el default (terracota) para quien no pasa acento.
  static ThemeData themeFor(Brightness brightness,
          {bool amoled = false, AccentSet accent = defaultAccent}) =>
      _build(brightness, amoled: amoled, accent: accent);

  static ThemeData _build(Brightness brightness,
      {bool amoled = false, AccentSet accent = defaultAccent}) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? (amoled ? _aBg : _dBg) : _lBg;
    final surface = isDark ? (amoled ? _aSurface : _dSurface) : _lSurface;
    final surface2 = isDark ? (amoled ? _aSurface2 : _dSurface2) : _lSurface2;
    final surface3 = isDark ? (amoled ? _aSurface3 : _dSurface3) : _lSurface3;
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
      primary: accent.accent,
      onPrimary: accent.onAccent,
      primaryContainer: Color.alphaBlend(
        accent.accent.withValues(alpha: isDark ? 0.22 : 0.16),
        surface,
      ),
      onPrimaryContainer: text,
      secondary: accent.accent2,
      onSecondary: accent.onAccent,
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
      // old blue-violet hue. AMOLED gets a near-black step too (not the warm one).
      surfaceContainerLow: isDark
          ? (amoled ? const Color(0xFF101010) : const Color(0xFF120F0D))
          : _lBg,
      surfaceContainer: surface,
      surfaceContainerHigh: surface2,
      surfaceContainerHighest: surface3,
      outline: hairline2,
      outlineVariant: hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: text,
      onInverseSurface: bg,
      inversePrimary: accent.accent,
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
      accent: accent.accent,
      accentInk: accent.accentInk,
      accent2: accent.accent2,
      accentSoft: accent.accent.withValues(alpha: 0.16),
      accentGlow: accent.accent.withValues(alpha: 0.45),
      onAccent: accent.onAccent,
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
      // accent.accent measures 3.9:1, below the 4.5:1 WCAG AA needs for normal text.
      // Icons and large shapes keep accent.accent (they only need 3:1).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent.accentInk,
          foregroundColor: accent.onAccent,
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
        selectedColor: accent.accentInk,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: text2, fontFamily: _uiFont),
        shape: const StadiumBorder(),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent.accent,
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
        indicatorColor: accent.accent.withValues(alpha: 0.18),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent.accent,
        thumbColor: accent.accent,
        inactiveTrackColor: hairline2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent.accent),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent.onAccent : text3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent.accent : surface3,
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
  // SYS-M2: token para micro-etiquetas (antes un `11.5` suelto en
  // save_to_list_button) — entero, sin medios-puntos, y snap a la escala.
  static const double microSize = 12;
  static const double tvBodyMin = 14;

  /// Promotes a phone-tuned size onto the 10-foot scale, leaving phones alone.
  ///
  /// The legacy surfaces — the player overlay and the whole settings tab — are
  /// reachable on Android TV and were written at phone sizes: a sleep-timer
  /// countdown at 9dp, an "EN VIVO" badge at 12, a channel position indicator at
  /// 12. Those are correct on a handset held at 30 cm and unreadable on a panel
  /// at three metres.
  ///
  /// Raising them outright would bloat the phone; a blanket multiplier would
  /// just mint a new set of arbitrary numbers. So each phone size SNAPS to the
  /// step of the scale that carries the same role — caption becomes label,
  /// secondary becomes body-small — and there is one place to argue with the
  /// mapping instead of forty-six.
  static double tenFoot(BuildContext context, double phone) {
    // isTenFoot, not isDesktopOrTV: the latter also says yes to any 900dp
    // window, which includes a large phone in landscape — where the player
    // overlay lives, and where the viewer is still 30 cm away.
    if (!ResponsiveHelper.isTenFoot(context)) return phone;
    if (phone <= 11) return labelSize; // captions, badges, counters
    if (phone <= 13) return bodySmallSize; // secondary text
    // Everything below the body step lands ON it. Written as `< bodySize`
    // rather than `<= 16` so the mapping cannot dip: with a 16 cutoff, 16
    // promoted to 18 while 17 stayed 17, and a function that sometimes returns
    // LESS for a larger input silently inverts whatever hierarchy the caller
    // wrote. Nothing in lib/ passes 17 today, which is exactly why it would
    // have gone unnoticed.
    if (phone < bodySize) return bodySize; // primary text
    return phone; // already at or above the scale: leave it alone
  }

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
  /// El anillo de foco en claro es el acento (F4: parametrizado, se pasa el
  /// `colorScheme.primary` del tema activo). En oscuro es blanco (un único punto
  /// brillante en la UI de 10 pies).
  static Color focusRing(Brightness brightness, Color accent) =>
      brightness == Brightness.dark ? const Color(0xFFFFFFFF) : accent;

  /// Returns [base] augmented with TV-grade focus visuals: a strong accent
  /// ring + tinted overlay on every interactive Material widget. Applied
  /// from `MaterialApp.builder` only on large screens / Android TV.
  static ThemeData applyTvOverrides(ThemeData base) {
    final scheme = base.colorScheme;
    // Single source of truth, shared with FocusHighlight so the two can never
    // drift into different dialects.
    final ring = focusRing(base.brightness, scheme.primary);
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
