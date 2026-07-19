import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

// Pins the colour pairings that a design review measured as failing WCAG AA.
//
// These are not opinions, they are ratios, so they belong in a test rather than
// in a reviewer's judgement of a screenshot. Two of them regressed silently
// before: a "large screen" theme branch that a TV never reached, and a
// `copyWith` in the TV overrides that replaced the accessible button theme
// wholesale instead of merging it — so the fix existed everywhere except the
// platform it was written for.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG AA for normal-size text.
const double aaNormal = 4.5;

/// WCAG AA for large text (>=18pt, or >=14pt bold) and for UI components.
const double aaLarge = 3.0;

void main() {
  final dark = AppThemes.darkTheme;
  final light = AppThemes.lightTheme;
  final tv = AppThemes.applyTvOverrides(dark);

  void expectAA(String what, Color fg, Color bg, {double min = aaNormal}) {
    final r = contrast(fg, bg);
    expect(r, greaterThanOrEqualTo(min),
        reason: '$what measured ${r.toStringAsFixed(2)}:1, needs $min:1');
  }

  group('dark theme', () {
    final scheme = dark.colorScheme;

    test('muted text clears AA on every surface in the ramp', () {
      // text3 lives on cards and list rows, not just on the background — the
      // first fix only checked the background and still failed on surface2/3.
      final text3 = dark.extension<RensiColors>()!.text3;
      expectAA('text3 on background', text3, scheme.surfaceContainerLowest);
      expectAA('text3 on surface', text3, scheme.surface);
      expectAA('text3 on surface2', text3,
          dark.extension<RensiColors>()!.surface2);
      expectAA('text3 on surface3', text3,
          dark.extension<RensiColors>()!.surface3);
    });

    test('body text clears AA on the background', () {
      expectAA('onSurface on background', scheme.onSurface,
          scheme.surfaceContainerLowest);
    });
  });

  group('light theme', () {
    // The same ramp as dark, not just the background. An audit darkened the
    // light surface2/surface3 until they broke AA against text3 and the suite
    // stayed green — the exact regression this file claims to prevent, unseen
    // in the theme most likely to be edited without a TV to check it on.
    test('muted text clears AA on every surface in the ramp', () {
      final scheme = light.colorScheme;
      final rensi = light.extension<RensiColors>()!;
      expectAA('light text3 on background', rensi.text3,
          scheme.surfaceContainerLowest);
      expectAA('light text3 on surface', rensi.text3, scheme.surface);
      expectAA('light text3 on surface2', rensi.text3, rensi.surface2);
      expectAA('light text3 on surface3', rensi.text3, rensi.surface3);
    });

    test('the focus ring is unmistakable on light surfaces too', () {
      expectAA('light focus ring', AppThemes.focusRing(Brightness.light),
          light.colorScheme.surface,
          min: aaLarge);
    });
  });

  group('filled buttons', () {
    // The label sits on the button's fill, so this is normal-size text.
    Color? fillOf(ThemeData t) => t.filledButtonTheme.style?.backgroundColor
        ?.resolve(<WidgetState>{});
    Color? inkOf(ThemeData t) => t.filledButtonTheme.style?.foregroundColor
        ?.resolve(<WidgetState>{});

    test('dark theme', () {
      expectAA('filled button label', inkOf(dark)!, fillOf(dark)!);
    });

    test('light theme', () {
      expectAA('filled button label', inkOf(light)!, fillOf(light)!);
    });

    test('SURVIVES the TV overrides', () {
      // applyTvOverrides used to rebuild filledButtonTheme from scratch, which
      // dropped the accessible background and fell back to colorScheme.primary
      // at 3.81:1 — on the one platform the fix was written for.
      expect(fillOf(tv), isNotNull,
          reason: 'the TV overrides must not drop the button background');
      expectAA('filled button label on TV', inkOf(tv)!, fillOf(tv)!);
    });
  });

  test('the focus ring is unmistakable against the dark background', () {
    expectAA(
      'focus ring',
      AppThemes.focusRing(Brightness.dark),
      dark.colorScheme.surfaceContainerLowest,
      min: aaLarge,
    );
  });
}
