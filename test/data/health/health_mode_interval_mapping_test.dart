/// Issue #246: the pure life-stage-mode → OS-health interval mapping —
/// the pregnancy/lactation interval plans, the `menopausalState` start ==
/// end constraint, and the `bleedingAfterMenopause` reuse of #193's
/// shared flow-value table, every derivation behind the #153 (HS-1)
/// write guard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_mapping.dart';
import 'package:lunarlog/data/health/health_mode_interval_mapping.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';

void main() {
  const allowed = HealthSyncCheck.allowed;
  final start = LocalDate(2026, 3, 10);
  final exit = LocalDate(2026, 11, 20);

  group('#153 (HS-1) write guard', () {
    test('every non-allowed check produces no plan and no sample', () {
      for (final guard in HealthSyncCheck.values) {
        if (guard.isAllowed) continue;
        expect(
          deriveModeIntervalPlans(
            mode: LifecycleMode.pregnancy,
            modeStartedOn: start,
            exitedOn: exit,
            writeGuard: guard,
          ),
          isEmpty,
          reason: guard.name,
        );
        expect(
          lactationIntervalPlan(start: start, end: exit, writeGuard: guard),
          isNull,
          reason: guard.name,
        );
        expect(
          deriveMenopausalStateSample(
            mode: LifecycleMode.perimenopause,
            modeStartedOn: start,
            writeGuard: guard,
          ),
          isNull,
          reason: guard.name,
        );
        expect(
          resolveBleedingAfterMenopause(
            flow: FlowLevel.heavy,
            inPeriodEpisode: true,
            inPerimenopauseMode: true,
            writeGuard: guard,
          ),
          isNull,
          reason: guard.name,
        );
      }
    });

    test('the allowed check is the only gate the mapping needs to pass', () {
      // The mapping's own logic must add no second silent veto: with the
      // guard allowed, every derivation below produces its sample (the
      // per-derivation groups pin the details).
      expect(
        deriveModeIntervalPlans(
          mode: LifecycleMode.pregnancy,
          modeStartedOn: start,
          exitedOn: exit,
          writeGuard: allowed,
        ),
        isNotEmpty,
      );
      expect(
        deriveMenopausalStateSample(
          mode: LifecycleMode.perimenopause,
          modeStartedOn: start,
          writeGuard: allowed,
        ),
        isNotNull,
      );
      expect(
        resolveBleedingAfterMenopause(
          flow: FlowLevel.medium,
          inPeriodEpisode: true,
          inPerimenopauseMode: true,
          writeGuard: allowed,
        ),
        isNotNull,
      );
    });
  });

  group('pregnancy interval plans (issue #246)', () {
    test('an active mode derives one open plan', () {
      final plans = deriveModeIntervalPlans(
        mode: LifecycleMode.pregnancy,
        modeStartedOn: start,
        exitedOn: null,
        writeGuard: allowed,
      );
      expect(plans, hasLength(1));
      final plan = plans.single;
      expect(plan.concept, 'pregnancy');
      expect(plan.start, start);
      expect(plan.end, isNull);
      expect(plan.isClosed, isFalse);
    });

    test('a stamped exit closes the plan at the exit date', () {
      final plan = deriveModeIntervalPlans(
        mode: LifecycleMode.pregnancy,
        modeStartedOn: start,
        exitedOn: exit,
        writeGuard: allowed,
      ).single;
      expect(plan.isClosed, isTrue);
      expect(plan.end, exit);
    });

    test('the plan carries the platform constants (HealthKit-only)', () {
      final plan = deriveModeIntervalPlans(
        mode: LifecycleMode.pregnancy,
        modeStartedOn: start,
        exitedOn: null,
        writeGuard: allowed,
      ).single;
      expect(plan.healthKitIdentifier, kPregnancyHealthKitIdentifier);
      expect(plan.healthKitIdentifier, 'HKCategoryTypeIdentifier.pregnancy');
      // Existence, not a value, is the signal.
      expect(plan.healthKitValue, kIntervalSampleNotApplicableHealthKitValue);
      expect(plan.healthKitValue, 'notApplicable');
      // Health Connect has no analogue — carried explicitly so an adapter
      // cannot "just also write Android" without confronting the absence.
      expect(plan.healthConnectRecord, isNull);
    });

    test('a null modeStartedOn derives nothing (honest empty set)', () {
      expect(
        deriveModeIntervalPlans(
          mode: LifecycleMode.pregnancy,
          modeStartedOn: null,
          exitedOn: exit,
          writeGuard: allowed,
        ),
        isEmpty,
      );
    });

    test('an exit before the start derives nothing (never an inverted span)',
        () {
      expect(
        deriveModeIntervalPlans(
          mode: LifecycleMode.pregnancy,
          modeStartedOn: exit,
          exitedOn: start,
          writeGuard: allowed,
        ),
        isEmpty,
      );
    });

    test('only pregnancy mode derives a plan', () {
      for (final mode in LifecycleMode.values) {
        if (mode == LifecycleMode.pregnancy) continue;
        expect(
          deriveModeIntervalPlans(
            mode: mode,
            modeStartedOn: start,
            exitedOn: exit,
            writeGuard: allowed,
          ),
          isEmpty,
          reason: mode.name,
        );
      }
    });
  });

  group('lactation interval plans (issue #246)', () {
    test('an explicit span produces the same open/closed shape via lactation',
        () {
      final open = lactationIntervalPlan(start: start, writeGuard: allowed);
      expect(open, isNotNull);
      expect(open!.concept, 'lactation');
      expect(open.healthKitIdentifier, kLactationHealthKitIdentifier);
      expect(open.healthKitIdentifier, 'HKCategoryTypeIdentifier.lactation');
      expect(open.healthKitValue, 'notApplicable');
      expect(open.healthConnectRecord, isNull);
      expect(open.isClosed, isFalse);

      final closed = lactationIntervalPlan(
        start: start,
        end: exit,
        writeGuard: allowed,
      );
      expect(closed!.isClosed, isTrue);
      expect(closed.end, exit);
    });

    test('an inverted span produces nothing', () {
      expect(
        lactationIntervalPlan(start: exit, end: start, writeGuard: allowed),
        isNull,
      );
    });

    test('a guard-denied span produces nothing', () {
      expect(
        lactationIntervalPlan(
          start: start,
          end: exit,
          writeGuard: HealthSyncCheck.noBinding,
        ),
        isNull,
      );
    });
  });

  group('menopausalState start == end (the issue AC)', () {
    test('the derived sample always carries identical start and end', () {
      for (final date in [
        start,
        exit,
        LocalDate(2026, 1, 1),
        LocalDate(2026, 12, 31),
      ]) {
        final sample = deriveMenopausalStateSample(
          mode: LifecycleMode.perimenopause,
          modeStartedOn: date,
          writeGuard: allowed,
        );
        expect(sample, isNotNull, reason: date.iso);
        // The hard HealthKit constraint: start == end, or the save errors.
        expect(sample!.start, date, reason: date.iso);
        expect(sample.end, date, reason: date.iso);
        expect(sample.start, sample.end, reason: date.iso);
      }
    });

    test('the constraint is structural: one date field, two same getters',
        () {
      // There is no second field to set wrong — the sample is built from
      // a single LocalDate and both getters return it.
      final sample = deriveMenopausalStateSample(
        mode: LifecycleMode.perimenopause,
        modeStartedOn: start,
        writeGuard: allowed,
      )!;
      expect(sample.date, sample.start);
      expect(sample.date, sample.end);
      expect(identical(sample.start, sample.end), isTrue);
    });

    test('the sample carries the platform constants (HealthKit-only)', () {
      final sample = deriveMenopausalStateSample(
        mode: LifecycleMode.perimenopause,
        modeStartedOn: start,
        writeGuard: allowed,
      )!;
      expect(sample.healthKitIdentifier, kMenopausalStateHealthKitIdentifier);
      expect(
        sample.healthKitIdentifier,
        'HKCategoryTypeIdentifier.menopausalState',
      );
      expect(sample.healthKitValue, kPerimenopauseMenopausalStateHealthKitValue);
      expect(sample.healthConnectRecord, isNull);
    });

    test('only perimenopause mode derives a sample', () {
      for (final mode in LifecycleMode.values) {
        if (mode == LifecycleMode.perimenopause) continue;
        expect(
          deriveMenopausalStateSample(
            mode: mode,
            modeStartedOn: start,
            writeGuard: allowed,
          ),
          isNull,
          reason: mode.name,
        );
      }
      expect(
        deriveMenopausalStateSample(
          mode: null,
          modeStartedOn: start,
          writeGuard: allowed,
        ),
        isNull,
        reason: 'no profile_modes row yet',
      );
    });

    test('a null modeStartedOn produces nothing (no guessed date)', () {
      expect(
        deriveMenopausalStateSample(
          mode: LifecycleMode.perimenopause,
          modeStartedOn: null,
          writeGuard: allowed,
        ),
        isNull,
      );
    });
  });

  group('bleedingAfterMenopause reuses the #193 shared table', () {
    /// The AC's reuse proof: for every flow value, the
    /// bleedingAfterMenopause resolution carries exactly the value the
    /// shipped #193 table resolves — or nothing, when the shared table
    /// resolves no menstrual sample.
    void expectSharedTableOutcome(
      FlowLevel flow, {
      required bool inPeriodEpisode,
    }) {
      final shared = mapFlowToHealthWrite(flow, inPeriodEpisode: inPeriodEpisode);
      final resolved = resolveBleedingAfterMenopause(
        flow: flow,
        inPeriodEpisode: inPeriodEpisode,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      );
      if (shared is HealthFlowMenstrualSample) {
        expect(resolved, isNotNull, reason: flow.name);
        expect(resolved!.value, shared.value, reason: flow.name);
      } else {
        expect(resolved, isNull, reason: flow.name);
      }
    }

    test('every bleed-level flow carries the shared-table value', () {
      for (final flow in FlowLevel.values) {
        expectSharedTableOutcome(flow, inPeriodEpisode: true);
      }
    });

    test('the superHeavy → heavy collapse carries over (documented loss)',
        () {
      final resolved = resolveBleedingAfterMenopause(
        flow: FlowLevel.superHeavy,
        inPeriodEpisode: true,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      );
      expect(resolved!.value, HealthFlowValue.heavy);
    });

    test('in-episode spotting resolves to light via the shared table', () {
      // ignore: deprecated_member_use_from_same_package
      expectSharedTableOutcome(FlowLevel.spotting, inPeriodEpisode: true);
    });

    test('out-of-episode spotting stays intermenstrual (null here)', () {
      // The shipped #193 routing keeps the day's intermenstrualBleeding
      // write, which exists on both platforms; this HealthKit-only type
      // must not swallow it.
      // ignore: deprecated_member_use_from_same_package
      expectSharedTableOutcome(FlowLevel.spotting, inPeriodEpisode: false);
    });

    test('none and notBleeding write nothing', () {
      expectSharedTableOutcome(FlowLevel.none, inPeriodEpisode: true);
      expectSharedTableOutcome(FlowLevel.notBleeding, inPeriodEpisode: true);
    });

    test('outside perimenopause mode nothing is written for the type', () {
      for (final flow in FlowLevel.values) {
        expect(
          resolveBleedingAfterMenopause(
            flow: flow,
            inPeriodEpisode: true,
            inPerimenopauseMode: false,
            writeGuard: allowed,
          ),
          isNull,
          reason: flow.name,
        );
      }
    });

    test('the sample carries the platform constants (HealthKit-only)', () {
      final sample = resolveBleedingAfterMenopause(
        flow: FlowLevel.heavy,
        inPeriodEpisode: true,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      )!;
      expect(
        sample.healthKitIdentifier,
        kBleedingAfterMenopauseHealthKitIdentifier,
      );
      expect(
        sample.healthKitIdentifier,
        'HKCategoryTypeIdentifier.bleedingAfterMenopause',
      );
      expect(sample.healthConnectRecord, isNull);
    });
  });

  group('value semantics', () {
    test('equal spans are equal plans, unequal spans are not', () {
      final a = lactationIntervalPlan(start: start, writeGuard: allowed)!;
      final b = lactationIntervalPlan(start: start, writeGuard: allowed)!;
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      final c = lactationIntervalPlan(
        start: start,
        end: exit,
        writeGuard: allowed,
      )!;
      expect(a, isNot(equals(c)));
    });

    test('menopausal samples are equal exactly by date', () {
      final a = deriveMenopausalStateSample(
        mode: LifecycleMode.perimenopause,
        modeStartedOn: start,
        writeGuard: allowed,
      )!;
      final b = deriveMenopausalStateSample(
        mode: LifecycleMode.perimenopause,
        modeStartedOn: start,
        writeGuard: allowed,
      )!;
      final c = deriveMenopausalStateSample(
        mode: LifecycleMode.perimenopause,
        modeStartedOn: exit,
        writeGuard: allowed,
      )!;
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('bleeding samples are equal exactly by value', () {
      final light = resolveBleedingAfterMenopause(
        flow: FlowLevel.light,
        inPeriodEpisode: true,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      )!;
      final lightAgain = resolveBleedingAfterMenopause(
        flow: FlowLevel.light,
        inPeriodEpisode: true,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      )!;
      final medium = resolveBleedingAfterMenopause(
        flow: FlowLevel.medium,
        inPeriodEpisode: true,
        inPerimenopauseMode: true,
        writeGuard: allowed,
      )!;
      expect(light, equals(lightAgain));
      expect(light.hashCode, lightAgain.hashCode);
      expect(light, isNot(equals(medium)));
    });
  });
}
