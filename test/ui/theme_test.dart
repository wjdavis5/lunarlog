/// Theme-walking test (issue #176's acceptance criteria): walks both
/// `AppTheme.lightTheme` and `AppTheme.darkTheme`, asserts every
/// `LunarLogColors` role is present, and independently recomputes WCAG
/// contrast (rather than trusting `lunarlog_colors.dart`'s own
/// `contrastRatio` helper to test itself) for the documented pairs:
/// `onSurfaceVariant` on `surface`, and each `onFlow*` on its `flow*`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';

/// WCAG 2.x relative luminance of an sRGB colour, in `[0, 1]`.
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double _luminance(Color color) {
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
double _contrast(Color a, Color b) {
  final luminanceA = _luminance(a);
  final luminanceB = _luminance(b);
  final lighter = math.max(luminanceA, luminanceB);
  final darker = math.min(luminanceA, luminanceB);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  };

  group('AppTheme / LunarLogColors (#176)', () {
    for (final themeEntry in themes.entries) {
      final name = themeEntry.key;
      final theme = themeEntry.value;

      test('$name theme carries a complete LunarLogColors extension', () {
        final colors = theme.extension<LunarLogColors>();
        expect(
          colors,
          isNotNull,
          reason: '$name theme has no LunarLogColors extension',
        );
        final c = colors!;
        // Every role, walked explicitly (Color fields are non-nullable, so
        // this is the "assert every role is non-null" the acceptance
        // criteria asks for -- a missing role would fail to compile before
        // it could fail this test, which is the point).
        final roles = <String, Color>{
          'flowSpotting': c.flowSpotting,
          'onFlowSpotting': c.onFlowSpotting,
          'flowLight': c.flowLight,
          'onFlowLight': c.onFlowLight,
          'flowMedium': c.flowMedium,
          'onFlowMedium': c.onFlowMedium,
          'flowHeavy': c.flowHeavy,
          'onFlowHeavy': c.onFlowHeavy,
          'symptomDot': c.symptomDot,
          'predictedBand': c.predictedBand,
          'predictedBorder': c.predictedBorder,
          'confidenceHigh': c.confidenceHigh,
          'confidenceLearning': c.confidenceLearning,
          'confidenceIrregular': c.confidenceIrregular,
          'roleOwner': c.roleOwner,
          'roleCoParent': c.roleCoParent,
          'roleCaregiver': c.roleCaregiver,
          'roleViewer': c.roleViewer,
        };
        for (final role in roles.entries) {
          expect(role.value, isNotNull, reason: '$name.${role.key} is null');
        }
      });

      test('$name theme: onSurfaceVariant on surface clears 4.5:1', () {
        final ratio = _contrast(
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surface,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name onSurfaceVariant/surface contrast was $ratio',
        );
      });

      test('$name theme: each onFlow* clears 4.5:1 against its flow*', () {
        final colors = theme.extension<LunarLogColors>()!;
        final pairs = <String, List<Color>>{
          'flowSpotting': [colors.onFlowSpotting, colors.flowSpotting],
          'flowLight': [colors.onFlowLight, colors.flowLight],
          'flowMedium': [colors.onFlowMedium, colors.flowMedium],
          'flowHeavy': [colors.onFlowHeavy, colors.flowHeavy],
        };
        for (final pair in pairs.entries) {
          final on = pair.value[0];
          final tone = pair.value[1];
          final ratio = _contrast(on, tone);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name on${pair.key} contrast was $ratio',
          );
        }
      });

      test('$name theme: each flow* clears 3:1 against surface', () {
        final colors = theme.extension<LunarLogColors>()!;
        final tones = <String, Color>{
          'flowSpotting': colors.flowSpotting,
          'flowLight': colors.flowLight,
          'flowMedium': colors.flowMedium,
          'flowHeavy': colors.flowHeavy,
        };
        for (final tone in tones.entries) {
          final ratio = _contrast(tone.value, theme.colorScheme.surface);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '$name ${tone.key}/surface contrast was $ratio',
          );
        }
      });

      test('$name theme: symptomDot clears 3:1 against surface', () {
        final colors = theme.extension<LunarLogColors>()!;
        final ratio = _contrast(colors.symptomDot, theme.colorScheme.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '$name symptomDot/surface contrast was $ratio',
        );
      });

      test('$name theme: predictedBorder clears 3:1 against surface', () {
        final colors = theme.extension<LunarLogColors>()!;
        final ratio = _contrast(
          colors.predictedBorder,
          theme.colorScheme.surface,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '$name predictedBorder/surface contrast was $ratio',
        );
      });
    }

    test('lightTheme and darkTheme have the matching brightness', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
    });

    test('textTheme matches the documented type ramp sizes', () {
      final textTheme = AppTheme.lightTheme.textTheme;
      expect(textTheme.headlineMedium?.fontSize, 28);
      expect(textTheme.headlineSmall?.fontSize, 24);
      expect(textTheme.titleLarge?.fontSize, 22);
      expect(textTheme.titleMedium?.fontSize, 16);
      expect(textTheme.titleSmall?.fontSize, 14);
      expect(textTheme.bodyLarge?.fontSize, 16);
      expect(textTheme.bodyMedium?.fontSize, 14);
      expect(textTheme.bodySmall?.fontSize, 12);
      expect(textTheme.labelLarge?.fontSize, 14);
      expect(textTheme.labelMedium?.fontSize, 12);
      expect(textTheme.labelSmall?.fontSize, 11);
    });

    test('chipTheme/cardTheme/inputDecorationTheme/listTileTheme are set',
        () {
      for (final theme in themes.values) {
        expect(theme.chipTheme.backgroundColor, isNotNull);
        expect(theme.cardTheme.shape, isNotNull);
        expect(theme.inputDecorationTheme.border, isNotNull);
        expect(theme.listTileTheme.shape, isNotNull);
      }
    });
  });
}
