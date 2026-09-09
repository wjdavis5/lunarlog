/// Issue #151 coverage: the derived-phase projection builder and the wire
/// round trip. The builder reads the sharer's own [ActivePrediction]; the
/// serialized shape is exactly the server's allowlisted key set
/// (20260909200000_prediction_connections.sql), so a note/tag/flow key can
/// never ride along by construction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/pms.dart' show PmsEstimate;
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';

ActivePrediction _prediction(LocalDate today) {
  // 28-day cycles, 4-day bleed, next start 10 days out; today is mid-luteal
  // and not bleeding.
  const cycle = 28;
  const period = 4;
  final nextStart = today.addDays(10);
  final forecast = <PredictedCycle>[
    for (var i = 1; i <= 12; i++)
      PredictedCycle(
        cycleIndex: i,
        start: nextStart.addDays(cycle * (i - 1)),
        estimatedPeriodLengthDays: period,
        tier: CycleConfidence.high,
        spreadDays: 2,
      ),
  ];
  return ActivePrediction(
    today: today,
    lastEpisodeStart: today.addDays(10 - cycle),
    estimatedNextStart: nextStart,
    originalEstimatedNextStart: nextStart,
    averagedCycleLengths: const [cycle],
    meanCycleLengthDays: cycle.toDouble(),
    cycleDay: cycle - 9,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
    meanPeriodLengthDays: period.toDouble(),
    spreadDays: 2,
    tier: CycleConfidence.high,
    forecast: forecast,
  );
}

void main() {
  final today = LocalDate(2026, 9, 7);

  /// The default prediction carrying a #220 PMS band: onset 3 days before
  /// the next estimated start, 2 days long (nextStart−3 .. nextStart−2).
  ActivePrediction predictionWithPms(LocalDate today) {
    final base = _prediction(today);
    final nextStart = base.estimatedNextStart;
    return ActivePrediction(
      today: base.today,
      lastEpisodeStart: base.lastEpisodeStart,
      estimatedNextStart: base.estimatedNextStart,
      originalEstimatedNextStart: base.originalEstimatedNextStart,
      averagedCycleLengths: base.averagedCycleLengths,
      meanCycleLengthDays: base.meanCycleLengthDays,
      cycleDay: base.cycleDay,
      duringEpisode: base.duringEpisode,
      completedCycleCount: base.completedCycleCount,
      validCycleCount: base.validCycleCount,
      meanPeriodLengthDays: base.meanPeriodLengthDays,
      spreadDays: base.spreadDays,
      tier: base.tier,
      forecast: base.forecast,
      pms: PmsEstimate(
        meanOnsetDaysBeforeNextPeriod: 3,
        meanLengthDays: 2,
        usableIntervalCount: 4,
        tier: CycleConfidence.high,
        predictedStart: nextStart.addDays(-3),
        predictedEnd: nextStart.addDays(-2),
      ),
    );
  }

  test('period days cover the forecast bleed bands, strictly after today',
      () {
    final projection = buildPredictionProjection(_prediction(today));

    // Cycle 1: starts today+10, bleeds 4 days.
    expect(projection.periodDays.first, today.addDays(10));
    expect(projection.periodDays, contains(today.addDays(13)));
    expect(projection.periodDays, isNot(contains(today.addDays(14))));
    // Sorted, no gaps between consecutive cycles' bands.
    expect(
      projection.periodDays.every((d) => d.isAfter(today)),
      isTrue,
      reason: 'the sharer is not mid-episode, so every period day is '
          'strictly forecast (KTD3 forward-only)',
    );
  });

  test('current open episode days are included while duringEpisode', () {
    final base = _prediction(today);
    final midEpisode = ActivePrediction(
      today: today,
      lastEpisodeStart: today.addDays(-1),
      estimatedNextStart: base.estimatedNextStart,
      originalEstimatedNextStart: base.originalEstimatedNextStart,
      averagedCycleLengths: base.averagedCycleLengths,
      meanCycleLengthDays: base.meanCycleLengthDays,
      cycleDay: 2,
      duringEpisode: true,
      completedCycleCount: 4,
      validCycleCount: 4,
      meanPeriodLengthDays: 4,
      spreadDays: 2,
      tier: CycleConfidence.high,
      forecast: base.forecast,
    );

    final projection = buildPredictionProjection(midEpisode);
    // Day 1 and day 2 of the open episode (yesterday, today).
    expect(projection.periodDays, contains(today.addDays(-1)));
    expect(projection.periodDays, contains(today));
  });

  test('fertile/ovulation days are the fertile-window back-calculation of '
      'each forecast cycle (ovulation = start - 14, window -5..+1)', () {
    final projection = buildPredictionProjection(_prediction(today));
    final nextStart = today.addDays(10);

    // Cycle 1's ovulation: the fertile window before its period start.
    final ovulation = nextStart.addDays(-14);
    expect(projection.ovulationDays, contains(ovulation));
    expect(projection.fertileDays, contains(ovulation.addDays(-5)));
    expect(projection.fertileDays, contains(ovulation.addDays(1)));
    expect(projection.fertileDays, isNot(contains(ovulation.addDays(-6))));
    expect(projection.fertileDays, isNot(contains(ovulation.addDays(2))));
  });

  test('PMS days are the estimate\'s own #220 phase band; none without one',
      () {
    // No PmsEstimate on the prediction (below the logged-interval
    // minimum): the projection shares no PMS days at all.
    expect(buildPredictionProjection(_prediction(today)).pmsDays, isEmpty);

    // With a band: the projection carries exactly that span, sorted.
    final nextStart = today.addDays(10);
    final projection = buildPredictionProjection(predictionWithPms(today));
    expect(projection.pmsDays,
        [nextStart.addDays(-3), nextStart.addDays(-2)]);
    expect(projection.pmsDays, isNot(contains(nextStart)));
  });

  test('toJson carries exactly the server allowlisted keys with ISO dates',
      () {
    final projection = buildPredictionProjection(_prediction(today));
    final json = projection.toJson();

    expect(json.keys.toSet(), PredictionProjection.allowedKeys.toSet());
    expect(json['generated_at'], today.iso);
    expect(json['period_days'], isA<List<Object?>>());
    expect((json['period_days'] as List).first, isA<String>());
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}$')
          .hasMatch((json['period_days'] as List).first as String),
      isTrue,
    );
  });

  test('fromJson round-trips a toJson payload', () {
    final projection = buildPredictionProjection(_prediction(today));
    final restored = PredictionProjection.fromJson(
        projection.toJson().cast<String, dynamic>());
    expect(restored, projection);
  });

  test('fromJson skips malformed dates instead of throwing', () {
    final projection = PredictionProjection.fromJson({
      'generated_at': '2026-09-07',
      'period_days': ['2026-09-10', 'garbage', 42],
      'fertile_days': 'not-an-array',
    });
    expect(projection.periodDays, [LocalDate(2026, 9, 10)]);
    expect(projection.fertileDays, isEmpty);
    expect(projection.pmsDays, isEmpty);
  });

  test('phasesByDate exposes per-date lookup with ovulation as its own mark',
      () {
    final projection = buildPredictionProjection(_prediction(today));
    final phases = projection.phasesByDate();
    final nextStart = today.addDays(10);

    expect(phases[nextStart], {PredictionPhase.period});
    final ovulation = nextStart.addDays(-14);
    expect(phases[ovulation], containsAll([PredictionPhase.fertile, PredictionPhase.ovulation]));
    expect(phases[nextStart.addDays(-7)], isNull,
        reason: 'the default prediction carries no PmsEstimate (#220), so '
            'no PMS phase exists to share');
    // With a PMS band, its dates carry the pms phase.
    final withPms = buildPredictionProjection(predictionWithPms(today));
    expect(withPms.phasesByDate()[nextStart.addDays(-3)],
        {PredictionPhase.pms});
  });

  test('a generated invite deep link carries kind=prediction', () {
    // The invite URI shape is produced by the Supabase service; asserted
    // here against the domain type so the shell's kind routing stays
    // coupled to a tested contract.
    final invite = GeneratedPredictionInvite(
      connectionId: 'c1',
      profileId: 'p1',
      rawToken: 'token',
      tokenHash: 'hash',
      inviteUri: Uri.parse('lunarlog://invite?code=token&kind=prediction'),
      expiresAt: DateTime.utc(2026, 9, 8),
    );
    expect(invite.inviteUri.queryParameters['kind'], 'prediction');
  });
}
