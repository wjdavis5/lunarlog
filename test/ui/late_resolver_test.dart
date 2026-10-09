/// Issue #1716: the late resolver's "Skip this cycle" action is hidden for a
/// regimen-schedule (pack) prediction — omission is an editorial signal for
/// the statistical predictor, and the pack branch is deliberately
/// independent of it, so the button could only ever do nothing. The
/// statistical path keeps the action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/late_resolver.dart';

import '../support/fake_settings_store.dart';

final _today = LocalDate(2026, 5, 1);

ActivePrediction _latePrediction(PredictionBasis basis) {
  final lastStart = _today.addDays(-34);
  final estimate = _today.addDays(-6);
  return ActivePrediction(
    today: _today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: estimate,
    originalEstimatedNextStart: estimate,
    averagedCycleLengths: const [28],
    meanCycleLengthDays: 28,
    cycleDay: 35,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
    basis: basis,
  );
}

Future<void> _pumpResolver(
  WidgetTester tester,
  FakeSettingsStore settings,
  PredictionBasis basis,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LateResolver(
          profileId: 'p1',
          prediction: _latePrediction(basis),
          exclusions: CycleExclusionList(settings),
          settings: settings,
          onLogIt: () {},
          todayProvider: () => _today,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'issue #1716: a regimen-schedule prediction offers no "skip this '
      'cycle", but keeps log-it and remind-me', (tester) async {
    final settings = FakeSettingsStore();
    addTearDown(settings.close);

    await _pumpResolver(tester, settings, PredictionBasis.regimenSchedule);

    expect(find.byKey(const ValueKey('resolver-log')), findsOneWidget);
    expect(find.byKey(const ValueKey('resolver-remind')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resolver-skip')),
      findsNothing,
      reason: 'a pack schedule has no cycle to declare skipped; the button '
          'would write an omission the pack branch never reads',
    );
  });

  testWidgets('a statistical prediction keeps the skip action',
      (tester) async {
    final settings = FakeSettingsStore();
    addTearDown(settings.close);

    await _pumpResolver(tester, settings, PredictionBasis.statistical);

    expect(find.byKey(const ValueKey('resolver-skip')), findsOneWidget);
  });
}
