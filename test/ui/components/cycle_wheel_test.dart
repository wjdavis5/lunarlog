library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/cycle_wheel.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  group('CycleWheel dynamic font scaling (Issue #475)', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('renders without overflow at ${scale}x text scaler', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Center(
                  child: CycleWheel(
                    cycleDay: 14,
                    duringEpisode: false,
                    cycleLengthDays: 28,
                    periodLengthDays: 5,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('cycle-wheel-center-label')), findsOneWidget);
        expect(find.text('Cycle day 14'), findsOneWidget);
      });

      testWidgets('renders bleed phase without overflow at ${scale}x text scaler', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Center(
                  child: CycleWheel(
                    cycleDay: 3,
                    duringEpisode: true,
                    cycleLengthDays: 28,
                    periodLengthDays: 5,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('cycle-wheel-center-label')), findsOneWidget);
        expect(find.text('Period · day 3'), findsOneWidget);
      });
    }
  });

  group('CycleWheel pure geometry & semantics (Issue #209, #475)', () {
    test('cycleWheelFraction computes proportional lap', () {
      expect(cycleWheelFraction(14, 28), closeTo(0.5, 0.001));
      expect(cycleWheelFraction(28, 28), closeTo(1.0, 0.001));
      expect(cycleWheelFraction(0, 28), closeTo(0.0, 0.001));
      expect(cycleWheelFraction(5, 0), closeTo(5.0, 0.001));
    });

    test('cycleWheelShowsPredictedBand checks periodLengthDays', () {
      expect(cycleWheelShowsPredictedBand(5), isTrue);
      expect(cycleWheelShowsPredictedBand(0), isFalse);
      expect(cycleWheelShowsPredictedBand(-1), isFalse);
    });

    test('predictedBandDashes splits sweep correctly', () {
      final dashes = predictedBandDashes(1.0, 0.2, 0.1);
      expect(dashes, isNotEmpty);
      expect(predictedBandDashes(0, 0.2, 0.1), isEmpty);
      expect(predictedBandDashes(1.0, 0, 0.1), isEmpty);
    });
  });
}
