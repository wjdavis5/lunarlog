import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart'
    show kDefaultLutealPhaseDays;
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

  group('source citation', () {
    test('issue #1133: names the Speroff textbook by its full title', () {
      // The 9th edition's title is "Clinical Gynecologic Endocrinology and
      // Infertility"; the citation previously truncated it after
      // "Endocrinology", so the named source was not a real book title.
      expect(
        CycleSubphaseInfo.kSourceCitation,
        'ACOG Menstrual Cycle infographic (PFSI033); ACOG FAQ024; '
        'Speroff\'s Clinical Gynecologic Endocrinology and Infertility '
        '(9th ed.)',
      );
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
      expect(info.biologicalExplainer, contains('fall if no pregnancy occurs'));
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

  group('deriveSubphase on a rolled or skipped estimate (issue #1424)', () {
    // Every prediction in this group comes out of the production predictor,
    // because the bug lives in the two shapes it really produces: a late
    // estimate that has rolled forward, and "Skip this cycle", which
    // advances the un-rolled estimate as well and clears the late state.
    //
    // 28-day cycles with 5-day periods; the open cycle starts 2026-08-31.
    // Its own length puts the next period on 2026-09-28, so the model lays
    // it out as: period 1-5, late follicular 6-13, ovulation window 14-16
    // (estimated ovulation on day 15, 14 days before 2026-09-28), early
    // luteal 17-20, mid luteal 21-24, late luteal 25-28.
    final openCycleStart = LocalDate(2026, 8, 31);
    final ownEstimate = LocalDate(2026, 9, 28);
    final lateLutealStart = LocalDate(2026, 9, 24);

    LocalDate onCycleDay(int cycleDay) =>
        openCycleStart.addDays(cycleDay - 1);

    // Seven logged periods, so six completed 28-day cycles: the `high`
    // tier, where a long-running cycle is the only thing that hedges the
    // card.
    ActivePrediction computed({
      required LocalDate today,
      bool skipped = false,
    }) =>
        computePrediction(
          episodes: [
            for (var cyclesAgo = 6; cyclesAgo >= 0; cyclesAgo--)
              Episode(
                openCycleStart.addDays(-28 * cyclesAgo),
                openCycleStart.addDays(-28 * cyclesAgo + 4),
              ),
          ],
          today: today,
          omittedCycleStarts: skipped ? {openCycleStart} : const {},
        ) as ActivePrediction;

    // The issue's own reproduction: a new profile with nothing logged,
    // estimated from the onboarding answers alone (`provisional` tier).
    ActivePrediction provisional({
      required LocalDate today,
      bool skipped = false,
    }) =>
        seedProvisionalPrediction(
          facts: CycleFacts(
            lastPeriodStart: openCycleStart,
            typicalCycleLengthDays: 28,
          ),
          today: today,
          omittedCycleStarts: skipped ? {openCycleStart} : const {},
        ) as ActivePrediction;

    void expectLateLutealRunningLong(
      CycleSubphaseInfo info, {
      required int cycleDay,
    }) {
      expect(info.subphase, CycleSubphase.lateLuteal);
      expect(info.cycleDay, cycleDay);
      expect(info.startCycleDay, 25);
      expect(info.endCycleDay, cycleDay);
      expect(info.cycleDayRangeText, 'Cycle Days 25–$cycleDay');
      expect(info.startDate, lateLutealStart);
      expect(info.endDate, onCycleDay(cycleDay));
      expect(info.isHedged, isTrue);
      expect(info.hedgedNotice, contains('running longer than average'));
    }

    test('the fixtures are what the predictor produces for a roll and a skip',
        () {
      final today = onCycleDay(35);

      final rolled = computed(today: today);
      expect(rolled.tier, CycleConfidence.high);
      expect(rolled.cycleDay, 35);
      expect(rolled.originalEstimatedNextStart, ownEstimate);
      expect(rolled.estimatedNextStart, LocalDate(2026, 10, 26));
      expect(rolled.isLate, isTrue);

      // A skip moves the un-rolled estimate too, so neither estimate field
      // names the open cycle's own expected end any more, and the late
      // state is cleared.
      final skipped = computed(today: today, skipped: true);
      expect(skipped.tier, CycleConfidence.high);
      expect(skipped.cycleDay, 35);
      expect(skipped.originalEstimatedNextStart, LocalDate(2026, 10, 26));
      expect(skipped.estimatedNextStart, LocalDate(2026, 10, 26));
      expect(skipped.isLate, isFalse);

      final seeded = provisional(today: today, skipped: true);
      expect(seeded.tier, CycleConfidence.provisional);
      expect(seeded.cycleDay, 35);
      expect(seeded.originalEstimatedNextStart, LocalDate(2026, 10, 26));
      expect(seeded.estimatedNextStart, LocalDate(2026, 10, 26));
      expect(seeded.isLate, isFalse);
    });

    test('a rolled estimate keeps the open cycle\'s own late-luteal range',
        () {
      final today = onCycleDay(35);
      expectLateLutealRunningLong(
        deriveSubphase(prediction: computed(today: today), today: today),
        cycleDay: 35,
      );
      expectLateLutealRunningLong(
        deriveSubphase(prediction: provisional(today: today), today: today),
        cycleDay: 35,
      );
    });

    test('an estimate rolled more than once still does not move the range',
        () {
      // Day 70: the estimate has rolled twice (to 2026-11-23).
      final today = onCycleDay(70);
      final prediction = computed(today: today);
      expect(prediction.estimatedNextStart, LocalDate(2026, 11, 23));

      expectLateLutealRunningLong(
        deriveSubphase(prediction: prediction, today: today),
        cycleDay: 70,
      );
    });

    test(
        'a skipped cycle keeps its own late-luteal range and the '
        'longer-than-average notice', () {
      final today = onCycleDay(35);
      expectLateLutealRunningLong(
        deriveSubphase(
          prediction: computed(today: today, skipped: true),
          today: today,
        ),
        cycleDay: 35,
      );
    });

    test('the issue\'s reproduction: onboarding answers only, then a skip',
        () {
      final today = onCycleDay(35);
      final info = deriveSubphase(
        prediction: provisional(today: today, skipped: true),
        today: today,
      );

      expectLateLutealRunningLong(info, cycleDay: 35);
      // Not the generic low-confidence notice the skip used to swap in.
      expect(
        info.hedgedNotice,
        isNot(contains('estimated from your cycle average')),
      );
    });

    test('a skip changes nothing on the card, on any day of the open cycle',
        () {
      // From day 60 the skipped estimate (2026-10-26) is itself late and
      // has rolled, so this covers a skip followed by a roll as well.
      for (var cycleDay = 1; cycleDay <= 70; cycleDay++) {
        final today = onCycleDay(cycleDay);
        final plain =
            deriveSubphase(prediction: computed(today: today), today: today);
        final skipped = deriveSubphase(
          prediction: computed(today: today, skipped: true),
          today: today,
        );
        final reason = 'cycle day $cycleDay';

        expect(skipped.subphase, plain.subphase, reason: reason);
        expect(skipped.startCycleDay, plain.startCycleDay, reason: reason);
        expect(skipped.endCycleDay, plain.endCycleDay, reason: reason);
        expect(skipped.startDate, plain.startDate, reason: reason);
        expect(skipped.endDate, plain.endDate, reason: reason);
        expect(skipped.isHedged, plain.isHedged, reason: reason);
        expect(skipped.hedgedNotice, plain.hedgedNotice, reason: reason);
      }
    });

    test('the phase layout is the open cycle\'s own on every day, late or not',
        () {
      // (first day, last day, subphase): the layout in this group's header.
      const layout = [
        (1, 5, CycleSubphase.earlyFollicular),
        (6, 13, CycleSubphase.lateFollicular),
        (14, 16, CycleSubphase.ovulation),
        (17, 20, CycleSubphase.earlyLuteal),
        (21, 24, CycleSubphase.midLuteal),
        (25, 28, CycleSubphase.lateLuteal),
      ];
      for (var cycleDay = 1; cycleDay <= 70; cycleDay++) {
        final today = onCycleDay(cycleDay);
        final info =
            deriveSubphase(prediction: computed(today: today), today: today);
        final reason = 'cycle day $cycleDay';
        // Past day 28 the model stays in late luteal and stretches it to
        // today.
        final (start, end, subphase) = layout.firstWhere(
          (row) => cycleDay <= row.$2,
          orElse: () => (25, cycleDay, CycleSubphase.lateLuteal),
        );

        expect(info.subphase, subphase, reason: reason);
        expect(info.startCycleDay, start, reason: reason);
        expect(info.endCycleDay, end, reason: reason);
        expect(info.startDate, onCycleDay(start), reason: reason);
        expect(info.endDate, onCycleDay(end), reason: reason);
      }
    });

    test(
        'the longer-than-average notice keeps the late grace, measured from '
        'the open cycle\'s own expected end', () {
      // The period is expected on cycle day 29; the notice starts once
      // today is more than kLateGraceDays past that, exactly when an
      // un-skipped cycle first reads as late.
      const firstNoticeDay = 29 + kLateGraceDays + 1;
      expect(firstNoticeDay, 32);

      for (final skipped in [false, true]) {
        for (var cycleDay = 1; cycleDay <= 70; cycleDay++) {
          final today = onCycleDay(cycleDay);
          final info = deriveSubphase(
            prediction: computed(today: today, skipped: skipped),
            today: today,
          );
          final reason = 'cycle day $cycleDay, skipped: $skipped';

          if (cycleDay < firstNoticeDay) {
            // `high` tier until day 62 (the long-open-cycle rung), so
            // nothing hedges the card before the notice starts.
            expect(info.isHedged, isFalse, reason: reason);
            expect(info.hedgedNotice, isNull, reason: reason);
          } else {
            expect(info.isHedged, isTrue, reason: reason);
            expect(
              info.hedgedNotice,
              contains('running longer than average'),
              reason: reason,
            );
          }
        }
      }
    });

    test(
        'until a roll or a skip moves the estimate, the phases are measured '
        'from the estimate itself', () {
      // The date the phases are laid out against (last period start plus
      // the rounded mean cycle length) has to be the very date the
      // predictor estimates for an ordinary cycle; otherwise the card and
      // the estimate would describe two different cycles.
      ActivePrediction fromLengths(List<int> lengths, LocalDate today) {
        final starts = [openCycleStart];
        for (final length in lengths.reversed) {
          starts.insert(0, starts.first.addDays(-length));
        }
        return computePrediction(
          episodes: [
            for (final start in starts) Episode(start, start.addDays(4)),
          ],
          today: today,
        ) as ActivePrediction;
      }

      const histories = [
        [28, 28, 28],
        [27, 28, 30], // mean 28.33
        [28, 29, 28, 29], // mean 28.5, which rounds up
        [21, 35, 28, 24, 40, 30], // mean 29.67
      ];
      for (final lengths in histories) {
        final reason = 'cycle lengths $lengths';
        final earlyOn = fromLengths(lengths, onCycleDay(10));
        final estimate = earlyOn.estimatedNextStart;

        expect(earlyOn.averagedCycleLengths, lengths, reason: reason);
        expect(earlyOn.originalEstimatedNextStart, estimate, reason: reason);
        expect(
          earlyOn.lastEpisodeStart
              .addDays(earlyOn.meanCycleLengthDays.round()),
          estimate,
          reason: reason,
        );

        // So estimated ovulation still sits the model's luteal length
        // before the estimate, with the ovulation window a day either
        // side of it.
        final ovulation = estimate.addDays(-kDefaultLutealPhaseDays);
        final info = deriveSubphase(
          prediction: fromLengths(lengths, ovulation),
          today: ovulation,
        );
        expect(info.subphase, CycleSubphase.ovulation, reason: reason);
        expect(info.startDate, ovulation.addDays(-1), reason: reason);
        expect(info.endDate, ovulation.addDays(1), reason: reason);
      }

      // The same holds for an estimate seeded from the onboarding answers.
      final seeded = provisional(today: onCycleDay(10));
      expect(seeded.originalEstimatedNextStart, ownEstimate);
      expect(seeded.estimatedNextStart, ownEstimate);
      expect(
        seeded.lastEpisodeStart.addDays(seeded.meanCycleLengthDays.round()),
        ownEstimate,
      );
    });
  });
}
