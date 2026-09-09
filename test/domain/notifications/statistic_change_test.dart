/// Unit tests for the cycle-statistic change detection (Issue #178):
/// snapshot construction from a live prediction, the documented
/// thresholds, and the tolerant store codecs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/statistic_change.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

ActivePrediction _prediction({
  double meanCycleLengthDays = 28,
  double meanPeriodLengthDays = 4,
  CycleConfidence tier = CycleConfidence.learning,
}) {
  final today = LocalDate(2026, 9, 7);
  return ActivePrediction(
    today: today,
    lastEpisodeStart: today.addDays(-10),
    estimatedNextStart: today.addDays(18),
    originalEstimatedNextStart: today.addDays(18),
    averagedCycleLengths: const [28],
    meanCycleLengthDays: meanCycleLengthDays,
    cycleDay: 11,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
    meanPeriodLengthDays: meanPeriodLengthDays,
    spreadDays: 2,
    tier: tier,
  );
}

void main() {
  group('CycleStatisticSnapshot.fromPrediction', () {
    test('carries the rounded displayed values and the tier', () {
      final snapshot = CycleStatisticSnapshot.fromPrediction(_prediction(
        meanCycleLengthDays: 28.4,
        meanPeriodLengthDays: 4.6,
        tier: CycleConfidence.high,
      ));
      expect(snapshot.meanCycleLengthDays, 28,
          reason: '28.4 displays as 28');
      expect(snapshot.meanPeriodLengthDays, 5, reason: '4.6 displays as 5');
      expect(snapshot.tier, CycleConfidence.high);
    });
  });

  group('isMeaningfulStatisticChange', () {
    test('identical snapshots never fire', () {
      final a = CycleStatisticSnapshot.fromPrediction(_prediction());
      final b = CycleStatisticSnapshot.fromPrediction(_prediction());
      expect(isMeaningfulStatisticChange(a, b), isFalse);
    });

    test('a tier change fires (AC3: the documented trigger)', () {
      final before =
          CycleStatisticSnapshot.fromPrediction(_prediction(tier: CycleConfidence.learning));
      final after =
          CycleStatisticSnapshot.fromPrediction(_prediction(tier: CycleConfidence.irregular));
      expect(isMeaningfulStatisticChange(before, after), isTrue);
      // Even when both means stay put.
      expect(
        isMeaningfulStatisticChange(
          const CycleStatisticSnapshot(
              meanCycleLengthDays: 28,
              meanPeriodLengthDays: 4,
              tier: CycleConfidence.provisional),
          const CycleStatisticSnapshot(
              meanCycleLengthDays: 28,
              meanPeriodLengthDays: 4,
              tier: CycleConfidence.learning),
        ),
        isTrue,
        reason: 'the #218 provisional displacement is a displayed change',
      );
    });

    test('the cycle-length average moving by the threshold fires; a '
        'sub-threshold drift does not', () {
      final before = CycleStatisticSnapshot.fromPrediction(_prediction(
          meanCycleLengthDays: 28, tier: CycleConfidence.learning));
      expect(
        isMeaningfulStatisticChange(
          before,
          CycleStatisticSnapshot.fromPrediction(_prediction(
              meanCycleLengthDays: 30, tier: CycleConfidence.learning)),
        ),
        isTrue,
        reason: '28 → 30 is exactly kStatisticChangeMinCycleLengthShiftDays',
      );
      expect(
        isMeaningfulStatisticChange(
          before,
          CycleStatisticSnapshot.fromPrediction(_prediction(
              meanCycleLengthDays: 29, tier: CycleConfidence.learning)),
        ),
        isFalse,
        reason: 'a one-day drift is noise the display barely moves for',
      );
      expect(
        isMeaningfulStatisticChange(
          before,
          CycleStatisticSnapshot.fromPrediction(_prediction(
              meanCycleLengthDays: 26, tier: CycleConfidence.learning)),
        ),
        isTrue,
        reason: 'a shortening past the threshold fires in both directions',
      );
    });

    test('the period-length average moving by one displayed day fires', () {
      final before = CycleStatisticSnapshot.fromPrediction(_prediction(
          meanPeriodLengthDays: 4, tier: CycleConfidence.learning));
      expect(
        isMeaningfulStatisticChange(
          before,
          CycleStatisticSnapshot.fromPrediction(_prediction(
              meanPeriodLengthDays: 5, tier: CycleConfidence.learning)),
        ),
        isTrue,
      );
      expect(
        isMeaningfulStatisticChange(
          before,
          CycleStatisticSnapshot.fromPrediction(_prediction(
              meanPeriodLengthDays: 4.4, tier: CycleConfidence.learning)),
        ),
        isFalse,
        reason: '4 → 4 (rounded from 4.4) is not a displayed change',
      );
    });
  });

  group('baseline codec', () {
    test('encode then decode preserves every profile snapshot', () {
      final baselines = {
        'p1': CycleStatisticSnapshot.fromPrediction(_prediction()),
        'p2': const CycleStatisticSnapshot(
            meanCycleLengthDays: 31,
            meanPeriodLengthDays: 5,
            tier: CycleConfidence.irregular),
      };
      final decoded = decodeStatisticBaselines(encodeStatisticBaselines(baselines));
      expect(decoded, baselines);
    });

    test('malformed values degrade to no baseline', () {
      expect(decodeStatisticBaselines(null), isEmpty);
      expect(decodeStatisticBaselines(''), isEmpty);
      expect(decodeStatisticBaselines('junk'), isEmpty);
      expect(decodeStatisticBaselines('{"v":1}'), isEmpty);
      expect(decodeStatisticBaselines('{"baselines":{"p1":"junk"}}'), isEmpty);
      expect(
        decodeStatisticBaselines(
            '{"baselines":{"p1":{"cycleDays":28,"periodDays":"x","tier":"high"}}}'),
        isEmpty,
        reason: 'a malformed field drops the whole snapshot, never '
            'fabricates a partial one',
      );
      expect(
        decodeStatisticBaselines(
            '{"baselines":{"p1":{"cycleDays":28,"periodDays":4,"tier":"wat"}}}'),
        isEmpty,
        reason: 'an unknown tier drops the snapshot',
      );
    });
  });

  group('signal codec', () {
    test('encode then decode preserves profile ids and dates', () {
      final signals = {
        'p1': LocalDate(2026, 9, 7),
        'p2': LocalDate(2026, 12, 31),
      };
      expect(
        decodeStatisticChangeSignals(encodeStatisticChangeSignals(signals)),
        signals,
      );
    });

    test('malformed values degrade to no signal', () {
      expect(decodeStatisticChangeSignals(null), isEmpty);
      expect(decodeStatisticChangeSignals('junk'), isEmpty);
      expect(decodeStatisticChangeSignals('{"v":1}'), isEmpty);
      expect(decodeStatisticChangeSignals('{"signals":{"p1":"2026-9-7"}}'),
          isEmpty, reason: 'a non-padded date is not an ISO civil date');
    });
  });
}
