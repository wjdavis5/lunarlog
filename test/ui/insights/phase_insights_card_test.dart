import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
