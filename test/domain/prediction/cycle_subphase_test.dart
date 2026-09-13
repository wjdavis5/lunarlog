import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

void main() {
  group('CycleSubphase enum', () {
    test('all 6 subphases have valid properties', () {
      expect(CycleSubphase.values.length, 6);
      for (final subphase in CycleSubphase.values) {
        expect(subphase.id, isNotEmpty);
        expect(subphase.displayName, isNotEmpty);
        expect(subphase.hormonalSummary, isNotEmpty);
        expect(subphase.primaryArticleId, isNotEmpty);
        expect(subphase.whatToTrack, isNotEmpty);
      }
    });

    test('ids are distinct and stable', () {
      final ids = CycleSubphase.values.map((s) => s.id).toSet();
      expect(ids.length, 6);
    });
  });

  group('deriveSubphase', () {
    // 28-day cycle with 5-day bleed starting on 2026-09-01
    // Ovulation estimate ~ Day 14 (2026-09-14)
    // Next period ~ 2026-09-29
    ActivePrediction buildPrediction({
      required LocalDate today,
      bool duringEpisode = false,
      CycleConfidence tier = CycleConfidence.high,
      int meanCycleLength = 28,
      int meanPeriodLength = 5,
    }) {
      final start = LocalDate(2026, 9, 1);
      final cycleDay = today.difference(start) + 1;
      return ActivePrediction(
        today: today,
        lastEpisodeStart: start,
        estimatedNextStart: start.addDays(meanCycleLength),
        originalEstimatedNextStart: start.addDays(meanCycleLength),
        averagedCycleLengths: [meanCycleLength, meanCycleLength, meanCycleLength],
        meanCycleLengthDays: meanCycleLength.toDouble(),
        meanPeriodLengthDays: meanPeriodLength.toDouble(),
        cycleDay: cycleDay,
        duringEpisode: duringEpisode,
        completedCycleCount: 6,
        validCycleCount: 6,
        tier: tier,
      );
    }

    test('Day 1 during episode -> earlyFollicular', () {
      final today = LocalDate(2026, 9, 1);
      final pred = buildPrediction(today: today, duringEpisode: true);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.earlyFollicular);
      expect(info.cycleDay, 1);
      expect(info.startCycleDay, 1);
      expect(info.isHedged, isFalse);
      expect(info.source, contains('ACOG'));
      expect(info.reviewDate, isNotEmpty);
      expect(info.cycleDayRangeText, contains('Cycle Days 1–'));
    });

    test('Day 4 during episode -> earlyFollicular', () {
      final today = LocalDate(2026, 9, 4);
      final pred = buildPrediction(today: today, duringEpisode: true);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.earlyFollicular);
      expect(info.cycleDay, 4);
    });

    test('Day 8 post-menses -> lateFollicular', () {
      final today = LocalDate(2026, 9, 8);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.lateFollicular);
      expect(info.cycleDay, 8);
      expect(info.biologicalExplainer, contains('Estrogen rises'));
    });

    test('Day 14 near estimated ovulation -> ovulation', () {
      final today = LocalDate(2026, 9, 14);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.ovulation);
      expect(info.cycleDay, 14);
      expect(info.biologicalExplainer, contains('LH'));
    });

    test('Day 18 post-ovulation -> earlyLuteal', () {
      final today = LocalDate(2026, 9, 18);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.earlyLuteal);
      expect(info.cycleDay, 18);
      expect(info.biologicalExplainer, contains('corpus luteum'));
    });

    test('Day 22 mid luteal -> midLuteal', () {
      final today = LocalDate(2026, 9, 22);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.midLuteal);
      expect(info.cycleDay, 22);
      expect(info.biologicalExplainer, contains('Progesterone peaks'));
    });

    test('Day 27 premenstrual -> lateLuteal', () {
      final today = LocalDate(2026, 9, 27);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.lateLuteal);
      expect(info.cycleDay, 27);
      expect(info.biologicalExplainer, contains('decline sharply'));
    });

    test('Overdue cycle (Day 32) -> lateLuteal with honest hedged notice', () {
      final today = LocalDate(2026, 10, 2);
      final pred = buildPrediction(today: today);
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.subphase, CycleSubphase.lateLuteal);
      expect(info.isHedged, isTrue);
      expect(info.hedgedNotice, contains('longer than average'));
      expect(info.endCycleDay, greaterThanOrEqualTo(32));
    });

    test('Learning confidence tier produces hedged notice', () {
      final today = LocalDate(2026, 9, 10);
      final pred = buildPrediction(
        today: today,
        tier: CycleConfidence.learning,
      );
      final info = deriveSubphase(prediction: pred, today: today);

      expect(info.isHedged, isTrue);
      expect(info.hedgedNotice, contains('estimated from your cycle average'));
    });
  });
}
