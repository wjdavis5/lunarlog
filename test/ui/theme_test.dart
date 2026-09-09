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

/// Circular distance between two hue-circle degrees (`[0, 360)` each), in
/// `[0, 180]` — the short way around the wheel, so e.g. 350 and 10 are 20
/// degrees apart, not 340.
double _hueDistance(double a, double b) {
  final diff = (a - b).abs() % 360;
  return diff > 180 ? 360 - diff : diff;
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
          'fertileBand': c.fertileBand,
          'fertileBorder': c.fertileBorder,
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

      test(
          '$name theme: each flow* clears 3:1 against surfaceContainerLow '
          '(the Card background it actually renders onto)', () {
        final colors = theme.extension<LunarLogColors>()!;
        final tones = <String, Color>{
          'flowSpotting': colors.flowSpotting,
          'flowLight': colors.flowLight,
          'flowMedium': colors.flowMedium,
          'flowHeavy': colors.flowHeavy,
        };
        for (final tone in tones.entries) {
          final ratio = _contrast(
            tone.value,
            theme.colorScheme.surfaceContainerLow,
          );
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '$name ${tone.key}/surfaceContainerLow contrast was $ratio',
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

      // Issue #312 (contrast review of #191 B-2): the spotting-day numeral
      // is drawn `onSurface`-coloured with a `surface`-coloured halo
      // (`_haloedDayNumber` in `month_calendar.dart`) so it stays legible
      // over the flow-spotting centre dot regardless of what colour sits
      // underneath — that only works if `onSurface` itself has strong
      // contrast against the halo colour, `surface`, in both themes.
      test(
          '$name theme: onSurface clears 4.5:1 against surface (spotting-day '
          'numeral halo)', () {
        final ratio = _contrast(
          theme.colorScheme.onSurface,
          theme.colorScheme.surface,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name onSurface/surface contrast was $ratio',
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

      test(
          '$name theme: fertileBorder clears 3:1 against surface, and is a '
          'distinct colour from predictedBorder (issue #143)', () {
        final colors = theme.extension<LunarLogColors>()!;
        final ratio = _contrast(
          colors.fertileBorder,
          theme.colorScheme.surface,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '$name fertileBorder/surface contrast was $ratio',
        );
        expect(
          colors.fertileBorder,
          isNot(colors.predictedBorder),
          reason: 'the two estimates must not share one colour token',
        );
      });

      // Issue #143 review: `fertileBorder` used to sit at the exact same
      // hue as `symptomDot` (both derived from `tertiaryHue`, unlike
      // `isNot` above which only rules out sharing `predictedBorder`'s
      // primary-derived hue) -- a same-hue-different-lightness pair reads
      // as one colour family at a glance. Asserts a real (>=30 degree)
      // circular hue separation from *both* siblings, not just inequality.
      test(
          '$name theme: fertileBorder\'s hue is genuinely distinct '
          '(>=30 degrees) from both predictedBorder and symptomDot '
          '(issue #143)', () {
        final colors = theme.extension<LunarLogColors>()!;
        final fertileHue = HSLColor.fromColor(colors.fertileBorder).hue;
        final predictedHue = HSLColor.fromColor(colors.predictedBorder).hue;
        final symptomHue = HSLColor.fromColor(colors.symptomDot).hue;
        expect(
          _hueDistance(fertileHue, predictedHue),
          greaterThanOrEqualTo(30.0),
          reason:
              '$name fertileBorder/predictedBorder hue distance was '
              '${_hueDistance(fertileHue, predictedHue)}',
        );
        expect(
          _hueDistance(fertileHue, symptomHue),
          greaterThanOrEqualTo(30.0),
          reason:
              '$name fertileBorder/symptomDot hue distance was '
              '${_hueDistance(fertileHue, symptomHue)}',
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

    // issue #176 review: `lightTheme`/`darkTheme` are memoized `static
    // final`s (not rebuilt on every read), and `LunarLogColors` now
    // implements `==`/`hashCode` -- together these are what let two reads
    // of "the same" theme compare `==` (and, since they're memoized, be
    // `identical`), so `AnimatedTheme`/`Theme.of` dependents stop
    // rebuilding on every `setState` for an unchanged theme.
    test('lightTheme is identical and equal across reads', () {
      final first = AppTheme.lightTheme;
      final second = AppTheme.lightTheme;
      expect(identical(first, second), isTrue);
      expect(first == second, isTrue);
    });

    test('darkTheme is identical and equal across reads', () {
      final first = AppTheme.darkTheme;
      final second = AppTheme.darkTheme;
      expect(identical(first, second), isTrue);
      expect(first == second, isTrue);
    });

    // issue #176 review: `inputDecorationTheme`'s idle border is
    // deliberately borderless (`BorderSide.none`), but focus/error states
    // must not inherit that -- otherwise Flutter silently drops the
    // focus/validation-error indicator from every text field (it does not
    // substitute a themed colour when the base border's side is `none`).
    test('inputDecorationTheme declares state-aware focus/error borders',
        () {
      for (final theme in themes.values) {
        final decorationTheme = theme.inputDecorationTheme;
        expect(
          decorationTheme.border?.borderSide,
          BorderSide.none,
          reason: 'idle border should stay borderless for a filled field',
        );
        expect(
          decorationTheme.focusedBorder?.borderSide,
          isNot(BorderSide.none),
          reason: 'focusedBorder must not be BorderSide.none',
        );
        expect(
          decorationTheme.focusedBorder?.borderSide.color,
          theme.colorScheme.primary,
        );
        expect(
          decorationTheme.errorBorder?.borderSide,
          isNot(BorderSide.none),
          reason: 'errorBorder must not be BorderSide.none',
        );
        expect(
          decorationTheme.errorBorder?.borderSide.color,
          theme.colorScheme.error,
        );
        expect(
          decorationTheme.focusedErrorBorder?.borderSide,
          isNot(BorderSide.none),
          reason: 'focusedErrorBorder must not be BorderSide.none',
        );
        expect(
          decorationTheme.focusedErrorBorder?.borderSide.color,
          theme.colorScheme.error,
        );
      }
    });

    testWidgets(
        'a TextFormField with a failing validator paints an '
        'error-coloured border under AppTheme.lightTheme', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Form(
              key: formKey,
              child: TextFormField(
                autovalidateMode: AutovalidateMode.always,
                validator: (_) => 'Required',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);

      final decorator =
          tester.widget<InputDecorator>(find.byType(InputDecorator));
      final effectiveErrorBorder = decorator.decoration.errorBorder;
      expect(effectiveErrorBorder, isNotNull);
      final borderSide =
          (effectiveErrorBorder as OutlineInputBorder).borderSide;
      expect(borderSide, isNot(BorderSide.none));
      expect(borderSide.color, AppTheme.lightTheme.colorScheme.error);
    });
  });

  group('LunarLogColors.copyWith / lerp (#176 review)', () {
    final base = LunarLogColors.forColorScheme(
      AppTheme.lightTheme.colorScheme,
    );

    test('copyWith overrides only the passed field, others unchanged', () {
      const override = Color(0xFF123456);
      final result = base.copyWith(flowMedium: override);

      expect(result.flowMedium, override);
      expect(result.flowSpotting, base.flowSpotting);
      expect(result.onFlowSpotting, base.onFlowSpotting);
      expect(result.flowLight, base.flowLight);
      expect(result.onFlowLight, base.onFlowLight);
      expect(result.onFlowMedium, base.onFlowMedium);
      expect(result.flowHeavy, base.flowHeavy);
      expect(result.onFlowHeavy, base.onFlowHeavy);
      expect(result.symptomDot, base.symptomDot);
      expect(result.predictedBand, base.predictedBand);
      expect(result.predictedBorder, base.predictedBorder);
      expect(result.confidenceHigh, base.confidenceHigh);
      expect(result.confidenceLearning, base.confidenceLearning);
      expect(result.confidenceIrregular, base.confidenceIrregular);
      expect(result.roleOwner, base.roleOwner);
      expect(result.roleCoParent, base.roleCoParent);
      expect(result.roleCaregiver, base.roleCaregiver);
      expect(result.roleViewer, base.roleViewer);
    });

    test('copyWith with no arguments returns an equal instance', () {
      final result = base.copyWith();
      expect(result, base);
    });

    test('lerp at t=0 returns this colour, at t=1 returns other colour',
        () {
      final other = base.copyWith(
        flowMedium: const Color(0xFFFFFFFF),
        onFlowMedium: const Color(0xFF000000),
      );

      final atZero = base.lerp(other, 0);
      expect(atZero.flowMedium, base.flowMedium);

      final atOne = base.lerp(other, 1);
      expect(atOne.flowMedium, other.flowMedium);
    });

    test('lerp at t=0.5 returns the midpoint colour on one field', () {
      const start = Color(0xFF000000);
      const end = Color(0xFFFFFFFF);
      final a = base.copyWith(flowMedium: start);
      final b = base.copyWith(flowMedium: end);

      final midpoint = a.lerp(b, 0.5);
      expect(midpoint.flowMedium, Color.lerp(start, end, 0.5));
    });

    test(
        'lerp against a non-LunarLogColors other (null -- the shape '
        'ThemeData.lerp passes when the other theme has no LunarLogColors '
        'extension) returns this unchanged', () {
      final result = base.lerp(null, 0.5);
      expect(identical(result, base), isTrue);
    });
  });
}
