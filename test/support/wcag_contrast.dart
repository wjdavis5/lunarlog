/// WCAG 2.x contrast-ratio math shared by the theme and lock-screen tests
/// (extracted from `test/ui/theme_test.dart`, issue #886).
///
/// This is deliberately an independent reimplementation rather than a call
/// into `lib/ui/theme/lunarlog_colors.dart`'s `contrastRatio`: the theme
/// test's whole point is to verify the production helper rather than trust
/// it, so both keep using this test-local math.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x relative luminance of an sRGB colour, in `[0, 1]`.
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double wcagRelativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}

/// WCAG 2.x contrast ratio between two colours, in `[1, 21]`.
/// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
double wcagContrastRatio(Color a, Color b) {
  final luminanceA = wcagRelativeLuminance(a);
  final luminanceB = wcagRelativeLuminance(b);
  final lighter = math.max(luminanceA, luminanceB);
  final darker = math.min(luminanceA, luminanceB);
  return (lighter + 0.05) / (darker + 0.05);
}
