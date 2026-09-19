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
        expect(find.text('14'), findsOneWidget);
        expect(find.text('days'), findsOneWidget);
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
        expect(find.text('Day 3'), findsOneWidget);
        expect(find.text('of period'), findsOneWidget);
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

  group('Issue #809: quick-log motion reward', () {
    Widget wheel(int day, {bool disableAnimations = false}) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: CycleWheel(
              cycleDay: day,
              duringEpisode: false,
              cycleLengthDays: 30,
              periodLengthDays: 4,
              daysUntilNextPeriod: 30 - day,
            ),
          ),
        ),
      );
    }

    testWidgets('the centre label cross-fades on a cycle-day change',
        (tester) async {
      await tester.pumpWidget(wheel(14));
      await tester.pumpAndSettle();
      expect(find.text('16'), findsOneWidget);

      await tester.pumpWidget(wheel(15));
      // One frame in: the outgoing and incoming labels coexist while the
      // AnimatedSwitcher cross-fades them.
      await tester.pump();
      expect(find.text('days'), findsNWidgets(2),
          reason: 'the centre label must cross-fade, not snap');
      expect(find.text('16'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('15'), findsOneWidget);
      expect(find.text('16'), findsNothing);
    });

    testWidgets('reduced motion collapses the wheel animation to zero',
        (tester) async {
      await tester.pumpWidget(wheel(14, disableAnimations: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(wheel(20, disableAnimations: true));
      await tester.pump();

      // cycleDay 20 of 30 shows 10 days until the next period.
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'disableAnimations must resolve LLMotion to Duration.zero '
              'so no wheel animation is scheduled');
      expect(find.text('10'), findsOneWidget);
      expect(find.text('16'), findsNothing,
          reason: 'the label swap is immediate under reduced motion');
    });
  });
}
