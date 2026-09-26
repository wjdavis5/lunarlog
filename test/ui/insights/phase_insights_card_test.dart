import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/phase_insights_card.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

ActivePrediction _makePrediction({
  required LocalDate today,
  int cycleDay = 1,
  bool duringEpisode = false,
  CycleConfidence tier = CycleConfidence.high,
}) {
  final start = LocalDate(2026, 9, 1);
  return ActivePrediction(
    today: today,
    lastEpisodeStart: start,
    estimatedNextStart: start.addDays(28),
    originalEstimatedNextStart: start.addDays(28),
    averagedCycleLengths: const [28, 28, 28],
    meanCycleLengthDays: 28,
    meanPeriodLengthDays: 5,
    cycleDay: cycleDay,
    duringEpisode: duringEpisode,
    completedCycleCount: 6,
    validCycleCount: 6,
    tier: tier,
  );
}

void main() {
  testWidgets('PhaseInsightsCard renders active subphase details', (tester) async {
    final today = LocalDate(2026, 9, 1);
    final prediction = _makePrediction(today: today, cycleDay: 1, duringEpisode: true);

    await _pump(tester, PhaseInsightsCard(prediction: prediction, today: today));

    expect(find.byKey(const ValueKey('phase-name-text')), findsOneWidget);
    expect(find.text('Early Follicular (Period)'), findsOneWidget);
    expect(find.byKey(const ValueKey('phase-range-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('phase-explainer-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('phase-tracking-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('phase-article-button')), findsOneWidget);
    expect(find.textContaining('Source: ACOG'), findsOneWidget);
    // Issue #1118: the hormone explainer is framed as a typical ovulatory
    // cycle, not a fact about this person's cycle today.
    expect(
      find.textContaining('In a typical cycle where ovulation happens'),
      findsOneWidget,
    );
  });

  testWidgets(
      'pill (regimenSchedule) shows no subphase or ovulation content '
      '(issue #1118)', (tester) async {
    final today = LocalDate(2026, 1, 15);
    // A pill with a recorded start date is exactly what the predictor
    // turns into a pack-driven (regimenSchedule) estimate.
    final prediction = computePrediction(
      episodes: const [],
      today: today,
      birthControl: ActiveBirthControl(
        method: BirthControlMethod.pill,
        startedOn: LocalDate(2026, 1, 1),
      ),
    ) as ActivePrediction;
    expect(prediction.basis, PredictionBasis.regimenSchedule);

    await _pump(
      tester,
      PhaseInsightsCard(prediction: prediction, today: today),
    );

    expect(
      find.byKey(const ValueKey('phase-insights-regimen-schedule')),
      findsOneWidget,
    );
    expect(
      find.textContaining('your estimate follows your pack schedule'),
      findsOneWidget,
    );
    // Issue #1118: the copy must distinguish combined from progestin-only
    // pills, because about 4 in 10 POP users still ovulate (ACOG FAQ186).
    expect(
      find.textContaining('progestin-only (mini) pills'),
      findsOneWidget,
    );
    // No subphase card content renders.
    expect(find.byKey(const ValueKey('phase-name-text')), findsNothing);
    expect(find.byKey(const ValueKey('phase-explainer-text')), findsNothing);
    expect(find.byKey(const ValueKey('phase-tracking-text')), findsNothing);
    expect(find.textContaining('Ovulation'), findsNothing);
  });

  testWidgets(
      'pill with no recorded start date also shows no subphase content '
      '(issue #1118 follow-up)', (tester) async {
    final today = LocalDate(2026, 4, 10);
    // A pre-#183 row / imported older export: the method is a pill but the
    // regimen start was never recorded, so the predictor cannot use the pack
    // branch and tags the statistical estimate as non-ovulatory.
    final prediction = computePrediction(
      episodes: [
        for (final start in [
          LocalDate(2026, 1, 1),
          LocalDate(2026, 1, 29),
          LocalDate(2026, 2, 28),
          LocalDate(2026, 4, 1),
        ])
          Episode(start, start.addDays(3)),
      ],
      today: today,
      birthControl: ActiveBirthControl(
        method: BirthControlMethod.pill,
        startedOn: null,
      ),
    ) as ActivePrediction;
    expect(prediction.basis, PredictionBasis.statisticalOnHormonalMethod);

    await _pump(
      tester,
      PhaseInsightsCard(prediction: prediction, today: today),
    );

    expect(
      find.byKey(const ValueKey('phase-insights-regimen-schedule')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('phase-name-text')), findsNothing);
    expect(find.byKey(const ValueKey('phase-explainer-text')), findsNothing);
    expect(find.textContaining('Ovulation'), findsNothing);
  });

  testWidgets('PhaseInsightsCard renders hedged notice when confidence is learning', (tester) async {
    final today = LocalDate(2026, 9, 8);
    final prediction = _makePrediction(
      today: today,
      cycleDay: 8,
      tier: CycleConfidence.learning,
    );

    await _pump(tester, PhaseInsightsCard(prediction: prediction, today: today));

    expect(find.byKey(const ValueKey('phase-hedged-notice')), findsOneWidget);
    expect(find.textContaining('Subphase timing is estimated'), findsOneWidget);
  });

  testWidgets('tapping article button opens article sheet', (tester) async {
    final today = LocalDate(2026, 9, 1);
    final prediction = _makePrediction(today: today, cycleDay: 1, duringEpisode: true);

    await _pump(tester, PhaseInsightsCard(prediction: prediction, today: today));

    final articleButton = find.byKey(const ValueKey('phase-article-button'));
    expect(articleButton, findsOneWidget);

    await tester.tap(articleButton);
    await tester.pumpAndSettle();

    // The modal bottom sheet opens, displaying the article title
    expect(find.text('The Four Key Phases of the Menstrual Cycle'), findsOneWidget);
  });
}
