/// Issue #1517: when the estimate beneath the Today ring is a date range,
/// the ring follows the range. It used to count down to the middle of it:
/// "1 day" above "September 27 – October 1" on a day already inside that
/// range, then "1 day past estimate" through its second half.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/components/cycle_wheel.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

/// Fabricated, uneven cycles (26, 33, 27 and 34 days). With the last
/// period starting 2026-08-29 the estimate is September 28, shown as the
/// range September 24 – October 2.
final _unevenStarts = [
  LocalDate(2026, 5, 1),
  LocalDate(2026, 5, 27),
  LocalDate(2026, 6, 29),
  LocalDate(2026, 7, 26),
  LocalDate(2026, 8, 29),
];

/// Six cycles of exactly 28 days: a one-date, high-confidence estimate.
final _steadyStarts = [
  for (var i = 0; i < 7; i++) LocalDate(2026, 1, 1).addDays(28 * i),
];

ActivePrediction _predictionOn(LocalDate today, List<LocalDate> starts) {
  final result = computePrediction(
    episodes: [for (final s in starts) Episode(s, s.addDays(3))],
    today: today,
  );
  return result as ActivePrediction;
}

Future<void> _pumpWheel(
  WidgetTester tester, {
  required ({int start, int end})? range,
  int? daysUntil,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: CycleWheel(
              cycleDay: 27,
              duringEpisode: false,
              cycleLengthDays: 30,
              periodLengthDays: 4,
              daysUntilNextPeriod: daysUntil,
              rangeDaysAhead: range,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('estimateRangeDaysAhead: which days the ring shows a range', () {
    test('the fixture is what the comments say it is', () {
      final p = _predictionOn(LocalDate(2026, 9, 20), _unevenStarts);
      expect(p.tier, isNot(CycleConfidence.high));
      expect(p.estimatedRangeStart, LocalDate(2026, 9, 24));
      expect(p.estimatedRangeEnd, LocalDate(2026, 10, 2));
      expect(estimateDateText(p, 'en'), contains('–'));
    });

    test('before the range opens: both distances', () {
      final p = _predictionOn(LocalDate(2026, 9, 20), _unevenStarts);
      expect(estimateRangeDaysAhead(p), (start: 4, end: 12));
    });

    test('on every day the range is shown and includes today: start is at '
        'or below zero, and the old count would have gone negative', () {
      for (var day = 24; day <= 30; day++) {
        final today = LocalDate(2026, 9, day);
        final p = _predictionOn(today, _unevenStarts);
        final range = estimateRangeDaysAhead(p);
        expect(range, isNotNull, reason: today.iso);
        expect(range!.start, lessThanOrEqualTo(0), reason: today.iso);
        expect(range.end, greaterThanOrEqualTo(0), reason: today.iso);
        // The line beneath still shows the range that includes today.
        expect(p.estimatedRangeStart, LocalDate(2026, 9, 24));
        expect(p.estimatedRangeEnd, LocalDate(2026, 10, 2));
      }
      // The fault: on these two days the ring's single count was already
      // "past estimate" while that range still included today.
      expect(
        _predictionOn(LocalDate(2026, 9, 29), _unevenStarts)
            .daysUntilNextPeriod,
        -1,
      );
      expect(
        _predictionOn(LocalDate(2026, 9, 30), _unevenStarts)
            .daysUntilNextPeriod,
        -2,
      );
    });

    test('once the estimate has rolled past its date the single count '
        'stands: its "past estimate" wording is then true', () {
      final p = _predictionOn(LocalDate(2026, 10, 1), _unevenStarts);
      expect(p.daysLate, isNotNull);
      expect(estimateRangeDaysAhead(p), isNull);
    });

    test('a one-date estimate keeps the single count', () {
      final p = _predictionOn(LocalDate(2026, 6, 25), _steadyStarts);
      expect(estimateDateText(p, 'en'), isNot(contains('–')));
      expect(estimateRangeDaysAhead(p), isNull);
    });
  });

  group('the ring for a range estimate', () {
    testWidgets('before the range: both distances over "days"',
        (tester) async {
      await _pumpWheel(tester, range: (start: 4, end: 12), daysUntil: 8);
      expect(find.text('4–12'), findsOneWidget);
      expect(find.text('days'), findsOneWidget);
      // Never the count to the middle of the range.
      expect(find.text('8'), findsNothing);
    });

    testWidgets('inside the range: "Any day now", no count, and nothing '
        'about being past the estimate', (tester) async {
      // The day after the middle of the range: the single count is -1.
      await _pumpWheel(tester, range: (start: -5, end: 3), daysUntil: -1);
      expect(find.text('Any day'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(find.textContaining('past estimate'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('the range opening today reads "Any day now" too',
        (tester) async {
      await _pumpWheel(tester, range: (start: 0, end: 8), daysUntil: 4);
      expect(find.text('Any day'), findsOneWidget);
      expect(find.text('4'), findsNothing);
    });

    testWidgets('no range: the single count, as before', (tester) async {
      await _pumpWheel(tester, range: null, daysUntil: 3);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('days'), findsOneWidget);
      expect(find.text('Any day'), findsNothing);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('a wide range fits the ring at ${scale}x text',
          (tester) async {
        await _pumpWheel(
          tester,
          range: (start: 24, end: 32),
          daysUntil: 28,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('24–32'), findsOneWidget);

        await _pumpWheel(
          tester,
          range: (start: -1, end: 7),
          daysUntil: 3,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Any day'), findsOneWidget);
      });
    }
  });

  group('what the ring reads aloud for a range estimate', () {
    String label(({int start, int end})? range, int? daysUntil) =>
        cycleWheelSemanticsLabel(
          cycleDay: 27,
          duringEpisode: false,
          cycleLengthDays: 30,
          periodLengthDays: 4,
          daysUntilNextPeriod: daysUntil,
          rangeDaysAhead: range,
          l10n: _l10n,
        );

    test('before the range: both distances', () {
      expect(
        label((start: 4, end: 12), 8),
        startsWith('About 4 to 12 days until next period.'),
      );
    });

    test('inside the range: any day now, never "past the estimate"', () {
      final spoken = label((start: -5, end: 3), -1);
      expect(spoken, startsWith('Next period may start any day now.'));
      expect(spoken, isNot(contains('past')));
    });

    test('no range: unchanged', () {
      expect(label(null, 3), startsWith('About 3 days until next period.'));
      expect(label(null, -2), startsWith('2 days past the estimate.'));
    });

    test('a logged period still leads, whatever the range says', () {
      expect(
        cycleWheelSemanticsLabel(
          cycleDay: 2,
          duringEpisode: true,
          cycleLengthDays: 30,
          periodLengthDays: 4,
          rangeDaysAhead: (start: -1, end: 3),
          l10n: _l10n,
        ),
        startsWith('Day 2 of period.'),
      );
    });
  });
}
