/// Tests for issue #209: `CycleWheel`'s pure geometry/semantics helpers and
/// widget rendering, plus `TodayCard`'s composition, confidence chip, and
/// one-tap "Period started today" action (busy-state guarding a double tap
/// at the widget level -- see `test/domain/logging/quick_log_test.dart` and
/// `test/ui/overview_test.dart` for the no-downgrade/no-duplicate write
/// rule itself).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/cycle_wheel.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/components/today_card.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    // Issue #218: the confidence chip's label resolves through
    // AppLocalizations like every other surfaced string, so this harness
    // carries the delegates the app's own MaterialApps do.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ));
}

void main() {
  group('cycleWheelFraction', () {
    test('a fraction of a normal-length cycle', () {
      expect(cycleWheelFraction(15, 30), 0.5);
      expect(cycleWheelFraction(0, 30), 0);
      expect(cycleWheelFraction(30, 30), 1);
    });

    test('a day count past the cycle length is not itself clamped', () {
      expect(cycleWheelFraction(40, 30), closeTo(1.333, 0.001));
    });

    test('a defensively-unreachable zero/negative length floors at 1 day '
        'so the fraction never divides by zero', () {
      expect(cycleWheelFraction(3, 0), 3);
      expect(cycleWheelFraction(3, -5), 3);
    });
  });

  group('cycleWheelShowsPredictedBand (issue #316 review item 8)', () {
    test('false when meanPeriodLengthDays rounds to 0', () {
      expect(cycleWheelShowsPredictedBand(0), isFalse);
    });

    test('true for any positive day count', () {
      expect(cycleWheelShowsPredictedBand(1), isTrue);
      expect(cycleWheelShowsPredictedBand(5), isTrue);
    });
  });

  group('predictedBandDashes (issue #316 review item 2)', () {
    test('empty for a zero or negative sweep', () {
      expect(predictedBandDashes(0, 0.3, 0.1), isEmpty);
      expect(predictedBandDashes(-1, 0.3, 0.1), isEmpty);
    });

    test('empty for a non-positive dash length', () {
      expect(predictedBandDashes(1, 0, 0.1), isEmpty);
    });

    test('emits full-length dashes with a shortened final dash when the '
        'sweep does not divide evenly', () {
      final dashes = predictedBandDashes(1.0, 0.3, 0.1);
      expect(dashes, hasLength(3));
      expect(dashes[0], closeTo(0.3, 1e-9));
      expect(dashes[1], closeTo(0.3, 1e-9));
      expect(dashes[2], closeTo(0.2, 1e-9),
          reason: 'the final dash is shortened to fit within the sweep, '
              'never omitted or overrun');
    });

    test('a sweep that lands exactly on the end of a dash (not a gap) '
        'emits only full-length dashes', () {
      final dashes = predictedBandDashes(0.7, 0.3, 0.1);
      expect(dashes, hasLength(2));
      for (final dash in dashes) {
        expect(dash, closeTo(0.3, 1e-9));
      }
    });
  });

  group('cycleWheelSemanticsLabel', () {
    test('mid-cycle names the cycle day, not the period', () {
      expect(
        cycleWheelSemanticsLabel(
          cycleDay: 14,
          duringEpisode: false,
          cycleLengthDays: 30,
          periodLengthDays: 4,
        ),
        'Cycle day 14 of about 30 days. Period usually runs about 4 days.',
      );
    });

    test('during an episode the label leads with "Period"', () {
      expect(
        cycleWheelSemanticsLabel(
          cycleDay: 2,
          duringEpisode: true,
          cycleLengthDays: 28,
          periodLengthDays: 5,
        ),
        'Period, day 2 of about 28 days. Period usually runs about 5 days.',
      );
    });

    test('never uses fertility/ovulation vocabulary (R13)', () {
      final label = cycleWheelSemanticsLabel(
        cycleDay: 14,
        duringEpisode: false,
        cycleLengthDays: 30,
        periodLengthDays: 4,
      );
      for (final stem in ['fertil', 'ovul', 'conceiv', 'luteal']) {
        expect(label.toLowerCase().contains(stem), isFalse);
      }
    });
  });

  group('CycleWheel widget', () {
    testWidgets('renders "Cycle day N" mid-cycle', (tester) async {
      await _pump(
        tester,
        const CycleWheel(
          cycleDay: 14,
          duringEpisode: false,
          cycleLengthDays: 30,
          periodLengthDays: 4,
        ),
      );

      expect(find.text('Cycle day 14'), findsOneWidget);
    });

    testWidgets('renders "Period · day N" during an episode', (tester) async {
      await _pump(
        tester,
        const CycleWheel(
          cycleDay: 2,
          duringEpisode: true,
          cycleLengthDays: 28,
          periodLengthDays: 5,
        ),
      );

      expect(find.text('Period · day 2'), findsOneWidget);
    });

    testWidgets('carries a screen-reader semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const CycleWheel(
          cycleDay: 14,
          duringEpisode: false,
          cycleLengthDays: 30,
          periodLengthDays: 4,
        ),
      );

      final node = tester.getSemantics(find.byType(CycleWheel));
      expect(node.label,
          'Cycle day 14 of about 30 days. Period usually runs about 4 days.');
      handle.dispose();
    });

    testWidgets('a periodLengthDays of 0 (issue #316 review item 8) renders '
        'with no crash -- the predicted band is skipped, not drawn as a '
        'zero-sweep arc', (tester) async {
      await _pump(
        tester,
        const CycleWheel(
          cycleDay: 5,
          duringEpisode: false,
          cycleLengthDays: 28,
          periodLengthDays: 0,
        ),
      );

      expect(find.byType(CycleWheel), findsOneWidget);
      expect(find.text('Cycle day 5'), findsOneWidget);
    });
  });

  group('TodayCard widget', () {
    Widget cardFor({
      bool canLog = true,
      bool showConfidenceChip = true,
      CycleConfidence tier = CycleConfidence.learning,
      Future<void> Function()? onLogToday,
    }) {
      return TodayCard(
        cycleDay: 14,
        duringEpisode: false,
        cycleLengthDays: 30,
        periodLengthDays: 4,
        estimateText: 'Next period estimate: September 4, 2026',
        tier: tier,
        showConfidenceChip: showConfidenceChip,
        canLog: canLog,
        onLogToday: onLogToday ?? () async {},
      );
    }

    testWidgets('renders the wheel, estimate, chip, and disclaimer',
        (tester) async {
      await _pump(tester, cardFor());

      expect(find.byKey(const ValueKey('today-card')), findsOneWidget);
      expect(find.text('Cycle day 14'), findsOneWidget);
      expect(find.text('Next period estimate: September 4, 2026'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('today-card-confidence-chip')),
          findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Estimates only — not medical advice.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('today-card-log-action')),
          findsOneWidget);
      expect(find.text('Period started today'), findsOneWidget);
    });

    testWidgets('omits the confidence chip when showConfidenceChip is false',
        (tester) async {
      await _pump(tester, cardFor(showConfidenceChip: false));

      expect(find.byKey(const ValueKey('today-card-confidence-chip')),
          findsNothing);
    });

    testWidgets('omits the log action entirely when canLog is false',
        (tester) async {
      await _pump(tester, cardFor(canLog: false));

      expect(find.byKey(const ValueKey('today-card-log-action')),
          findsNothing);
    });

    testWidgets('tapping the log action calls onLogToday and disables the '
        'button while the write is in flight', (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await _pump(
        tester,
        cardFor(onLogToday: () {
          calls++;
          return gate.future;
        }),
      );

      final button = find.byKey(const ValueKey('today-card-log-action'));
      await tester.tap(button);
      await tester.pump();

      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(button).onPressed,
        isNull,
        reason: 'a second tap while the first write is in flight must not '
            'fire another one',
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('issue #316 blocking finding 1: a throwing onLogToday '
        'surfaces an InlineError with Retry instead of failing silently, '
        'and the button re-enables', (tester) async {
      var calls = 0;
      var shouldThrow = true;
      await _pump(
        tester,
        cardFor(onLogToday: () async {
          calls++;
          if (shouldThrow) throw Exception('write failed');
        }),
      );

      final button = find.byKey(const ValueKey('today-card-log-action'));
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byType(InlineError), findsOneWidget,
          reason: 'a throwing write must surface in-place, not vanish '
              'silently while the button just re-enables');
      expect(
        tester.widget<FilledButton>(button).onPressed,
        isNotNull,
        reason: 'the button stays usable after a failed write, not stuck '
            'disabled',
      );

      shouldThrow = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2, reason: 'Retry re-runs the same write');
      expect(find.byType(InlineError), findsNothing,
          reason: 'a successful retry clears the error');
    });
  });
}
