import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/insights/cramp_prediction.dart';
import 'package:lunarlog/domain/insights/symptom_trends.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/symptom_trends_section.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  testWidgets('renders empty state when not enough data', (tester) async {
    const report = CycleInsightsReport.empty;
    await _pump(tester, const SymptomTrendsSection(report: report));

    expect(find.byKey(const ValueKey('symptom-trends-heading')), findsOneWidget);
    expect(find.byKey(const ValueKey('symptom-trends-empty-text')), findsOneWidget);
    expect(find.textContaining('Log symptoms across at least 3 completed cycles'), findsOneWidget);
  });

  testWidgets('renders symptom patterns, cramp forecasts, and flow info when available', (tester) async {
    final report = CycleInsightsReport(
      symptomPatterns: const [
        SymptomPattern(
          tag: 'cramps',
          totalOccurrences: 6,
          cycleCount: 3,
          frequencyByCycleDay: {1: 3, 2: 3},
          peakCycleDays: [1, 2],
          trend: TrendDirection.stable,
          meetsThreshold: true,
        ),
      ],
      flowPattern: const FlowPattern(
        flowByCycleDay: {1: {FlowLevel.heavy: 3}},
        typicalPeakFlow: FlowLevel.heavy,
        typicalPeakDay: 1,
      ),
      crampPrediction: CrampPrediction(
        predictedCycleDays: const [1, 2],
        predictedDates: [LocalDate(2026, 10, 1), LocalDate(2026, 10, 2)],
        observedCycleCount: 3,
        totalCyclesAnalyzed: 3,
        disclaimer: CrampPrediction.kStandardDisclaimer,
      ),
      analyzedCycleCount: 3,
      hasEnoughData: true,
    );

    await _pump(tester, SymptomTrendsSection(report: report));

    // Cramp forecast card
    expect(find.byKey(const ValueKey('cramp-prediction-card')), findsOneWidget);
    expect(find.text('Anticipated Cramp Window'), findsOneWidget);
    expect(find.textContaining('Cramp estimates are based on your past logged tags'), findsOneWidget);

    // Symptom patterns
    expect(find.text('Cramps'), findsOneWidget);
    expect(find.textContaining('Most common on Cycle Days 1, 2'), findsOneWidget);
    expect(find.text('Consistent'), findsOneWidget);

    // Flow pattern
    expect(find.byKey(const ValueKey('flow-pattern-card')), findsOneWidget);
    expect(find.textContaining('Peak flow typically falls on Cycle Day 1 (heavy)'), findsOneWidget);

    // Library link button
    final libraryButton = find.byKey(const ValueKey('browse-cycle-library-button'));
    expect(libraryButton, findsOneWidget);

    await tester.tap(libraryButton);
    await tester.pumpAndSettle();

    // Verify navigating to library screen
    expect(find.text('Cycle Literacy Library'), findsOneWidget);
  });
}
