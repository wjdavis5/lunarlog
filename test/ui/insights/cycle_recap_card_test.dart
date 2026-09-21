/// Issue #852: the [CycleRecapCard]'s rendering, in isolation — every
/// supported fact, both change directions, the thin-history learning state,
/// `irregular` mode's suppression of range/comparison language, the cramp
/// fallback when no `cramps` symptom pattern met threshold, and the two
/// callbacks. Constructing [CycleRecap] directly keeps each branch narrow
/// and its expected copy exact.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/insights/cycle_recap.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/statistic_change.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/cycle_recap_card.dart';

CycleRecap buildRecap({
  int cycleNumber = 6,
  LocalDate? cycleStart,
  LocalDate? previousCycleStart,
  int cycleLengthDays = 30,
  int? lengthChangeDays = 0,
  bool hasEstimate = true,
  CycleConfidence confidence = CycleConfidence.high,
  double? meanCycleLengthDays = 30,
  double? spreadDays = 0,
  bool statisticChange = false,
  bool tierChanged = false,
  CycleConfidence? previousConfidence,
  int? meanCycleShiftDays,
  List<RecurringSymptom> recurringSymptoms = const [],
  List<int>? crampCycleDays,
}) =>
    CycleRecap(
      cycleNumber: cycleNumber,
      cycleStart: cycleStart ?? LocalDate(2026, 7, 6),
      previousCycleStart: previousCycleStart ?? LocalDate(2026, 6, 6),
      cycleLengthDays: cycleLengthDays,
      previousCycleLengthDays: 30,
      lengthChangeDays: lengthChangeDays,
      bleedDayCountDelta: 0,
      hasEstimate: hasEstimate,
      confidence: confidence,
      meanCycleLengthDays: meanCycleLengthDays,
      meanPeriodLengthDays: hasEstimate ? 4 : null,
      spreadDays: spreadDays,
      usableCycleCount: hasEstimate ? null : 1,
      statisticChange: statisticChange,
      tierChanged: tierChanged,
      previousConfidence: previousConfidence,
      meanCycleShiftDays: meanCycleShiftDays,
      meanPeriodShiftDays: 0,
      recurringSymptoms: recurringSymptoms,
      crampCycleDays: crampCycleDays,
      currentSnapshot: hasEstimate
          ? const CycleStatisticSnapshot(
              meanCycleLengthDays: 30,
              meanPeriodLengthDays: 4,
              tier: CycleConfidence.high,
            )
          : null,
    );

Future<void> pumpCard(
  WidgetTester tester,
  CycleRecap recap, {
  bool irregularFraming = false,
  VoidCallback? onDismiss,
  VoidCallback? onCompare,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CycleRecapCard(
          recap: recap,
          irregularFraming: irregularFraming,
          onDismiss: onDismiss ?? () {},
          onCompare: onCompare,
        ),
      ),
    ),
  );
}

String? textAt(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

void main() {
  testWidgets('renders every supported fact with exact copy', (tester) async {
    var compared = false;
    await pumpCard(
      tester,
      buildRecap(
        lengthChangeDays: 3,
        statisticChange: true,
        meanCycleShiftDays: 3,
        recurringSymptoms: const [
          RecurringSymptom(tag: 'headache', cycleDays: [1, 3]),
        ],
      ),
      onCompare: () => compared = true,
    );

    expect(find.text('Cycle 6 wrapped up'), findsOneWidget);
    expect(textAt(tester, 'cycle-recap-length'), 'This cycle lasted 30 days.');
    expect(
      textAt(tester, 'cycle-recap-range'),
      'Your usual range is 30 days.',
    );
    expect(
      textAt(tester, 'cycle-recap-comparison'),
      '3 days longer than the cycle before it.',
    );
    expect(
      textAt(tester, 'cycle-recap-statistic-change'),
      'Your average cycle length moved by 3 days.',
    );
    expect(
      textAt(tester, 'cycle-recap-symptom-headache'),
      'Headache: most often around cycle day 1, 3.',
    );
    expect(find.byKey(const ValueKey('cycle-recap-cramps')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cycle-recap-compare')));
    expect(compared, isTrue);
  });

  testWidgets('renders the cramp forecast when no cramps symptom pattern met '
      'threshold', (tester) async {
    await pumpCard(
      tester,
      buildRecap(meanCycleShiftDays: 0, crampCycleDays: const [1, 2]),
    );

    expect(
      textAt(tester, 'cycle-recap-cramps'),
      'Cramps most often land around cycle day 1\u20132.',
    );
    expect(
      find.byKey(const ValueKey('cycle-recap-symptom-cramps')),
      findsNothing,
    );
  });

  testWidgets('a shorter and an equal comparison read their own copy', (
    tester,
  ) async {
    await pumpCard(tester, buildRecap(lengthChangeDays: -1));
    expect(
      textAt(tester, 'cycle-recap-comparison'),
      'One day shorter than the cycle before it.',
    );

    await pumpCard(tester, buildRecap(lengthChangeDays: 0));
    expect(
      textAt(tester, 'cycle-recap-comparison'),
      'About the same length as the cycle before it.',
    );
  });

  testWidgets('tier transitions name the direction from the stored tier', (
    tester,
  ) async {
    await pumpCard(
      tester,
      buildRecap(
        confidence: CycleConfidence.high,
        previousConfidence: CycleConfidence.learning,
        statisticChange: true,
        tierChanged: true,
      ),
    );
    expect(
      textAt(tester, 'cycle-recap-statistic-change'),
      'Your estimates are now more confident.',
    );

    await pumpCard(
      tester,
      buildRecap(
        confidence: CycleConfidence.irregular,
        previousConfidence: CycleConfidence.high,
        statisticChange: true,
        tierChanged: true,
      ),
    );
    expect(
      textAt(tester, 'cycle-recap-statistic-change'),
      'Your estimates are a little less certain now.',
    );
  });

  testWidgets('an irregular spread still collapses to a single value when '
      'the spread rounds to zero', (tester) async {
    await pumpCard(
      tester,
      buildRecap(meanCycleLengthDays: 29, spreadDays: 2),
    );
    expect(
      textAt(tester, 'cycle-recap-range'),
      'Your usual range is 27\u201331 days.',
    );

    await pumpCard(
      tester,
      buildRecap(meanCycleLengthDays: 30, spreadDays: 0),
    );
    expect(
      textAt(tester, 'cycle-recap-range'),
      'Your usual range is 30 days.',
    );
  });

  testWidgets('the learning state shows only the logged length and the '
      'still-learning line', (tester) async {
    await pumpCard(
      tester,
      buildRecap(
        hasEstimate: false,
        confidence: CycleConfidence.learning,
        meanCycleLengthDays: null,
        spreadDays: null,
        lengthChangeDays: null,
        previousCycleStart: null,
      ),
    );

    expect(find.byKey(const ValueKey('cycle-recap-length')), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-recap-learning')), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-recap-range')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-comparison')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-compare')), findsNothing);
  });

  testWidgets('irregular framing suppresses range, comparison, and the '
      'compare action without dropping the logged length', (tester) async {
    var compared = false;
    await pumpCard(
      tester,
      buildRecap(),
      irregularFraming: true,
      onCompare: () => compared = true,
    );

    expect(textAt(tester, 'cycle-recap-length'), 'This cycle lasted 30 days.');
    expect(find.byKey(const ValueKey('cycle-recap-range')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-comparison')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-compare')), findsNothing);
    expect(compared, isFalse);
  });

  testWidgets('dismiss invokes its callback', (tester) async {
    var dismissed = false;
    await pumpCard(
      tester,
      buildRecap(),
      onDismiss: () => dismissed = true,
    );

    await tester.tap(find.byKey(const ValueKey('cycle-recap-dismiss')));
    expect(dismissed, isTrue);
  });
}
