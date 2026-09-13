/// Design tokens guard and contract test (issue #473).
///
/// Verifies the design tokens contracts in `tokens.dart`:
/// - Space scales and radius scales
/// - Motion durations and reduce-motion accessibility resolution via [LLMotion.resolve]
/// - Source-scan guard verifying that key UI components and screens import and adopt
///   design tokens.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

void main() {
  group('LLSpace contract', () {
    test('spacing scale values match 4dp grid', () {
      expect(LLSpace.space1, 4.0);
      expect(LLSpace.space2, 8.0);
      expect(LLSpace.space3, 12.0);
      expect(LLSpace.space4, 16.0);
      expect(LLSpace.space5, 24.0);
      expect(LLSpace.space6, 32.0);
      expect(LLSpace.space7, 48.0);
    });
  });

  group('LLRadius contract', () {
    test('corner radii scale matches design system', () {
      expect(LLRadius.rSm, 4.0);
      expect(LLRadius.rMd, 8.0);
      expect(LLRadius.rLg, 12.0);
      expect(LLRadius.rXl, 16.0);
      expect(LLRadius.rFull, 999.0);
    });
  });

  group('LLMotion contract and accessibility', () {
    test('motion durations match token specifications', () {
      expect(LLMotion.fast, const Duration(milliseconds: 120));
      expect(LLMotion.base, const Duration(milliseconds: 200));
      expect(LLMotion.slow, const Duration(milliseconds: 320));
    });

    testWidgets('LLMotion.resolve returns requested duration when animations are enabled', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              resolved = LLMotion.resolve(context, LLMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, LLMotion.base);
    });

    testWidgets('LLMotion.resolve returns Duration.zero when reduced motion is requested', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = LLMotion.resolve(context, LLMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });
  });

  group('Design token adoption source guard', () {
    const migratedFiles = [
      'lib/ui/components/app_shell.dart',
      'lib/ui/components/cycle_wheel.dart',
      'lib/ui/components/today_card.dart',
      'lib/ui/insights/analysis_tab.dart',
      'lib/ui/logging/day_sheet.dart',
      'lib/ui/logging/month_calendar.dart',
      'lib/ui/overview/cycle_history_section.dart',
      'lib/ui/overview/late_resolver.dart',
      'lib/ui/overview/overview_panel.dart',
      'lib/ui/profiles/first_run_screen.dart',
      'lib/ui/profiles/profile_dialogs.dart',
    ];

    test('all core UI surfaces import tokens.dart and reference LLSpace or LLRadius', () {
      for (final relativePath in migratedFiles) {
        final file = File(relativePath);
        expect(file.existsSync(), isTrue, reason: 'File should exist: $relativePath');
        final content = file.readAsStringSync();
        expect(
          content.contains('tokens.dart'),
          isTrue,
          reason: '$relativePath should import tokens.dart',
        );
        expect(
          content.contains('LLSpace') || content.contains('LLRadius'),
          isTrue,
          reason: '$relativePath should reference LLSpace or LLRadius tokens',
        );
      }
    });
  });
}
