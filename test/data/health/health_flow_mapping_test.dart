/// Issue #193's flow-enum mapping table, pinned value by value: the
/// function is pure, so this is the whole contract — `none`/`notBleeding`
/// write nothing, bleed levels pass through named, `superHeavy` collapses
/// to `heavy` (the Settings-documented collapse), and the spotting branch
/// follows A3-4 exactly (inside a period episode → menstrual `light`;
/// outside one → intermenstrual, never menstrual).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_mapping.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

void main() {
  group('mapFlowToHealthWrite', () {
    test('none writes no sample (the issue\'s stated assumption)', () {
      expect(
        mapFlowToHealthWrite(FlowLevel.none, inPeriodEpisode: true),
        isA<HealthFlowNoWrite>(),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.none, inPeriodEpisode: false),
        isA<HealthFlowNoWrite>(),
      );
    });

    test('notBleeding (post-#247) writes no sample like none', () {
      expect(
        mapFlowToHealthWrite(FlowLevel.notBleeding, inPeriodEpisode: true),
        isA<HealthFlowNoWrite>(),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.notBleeding, inPeriodEpisode: false),
        isA<HealthFlowNoWrite>(),
      );
    });

    test('light/medium/heavy pass through named, episode membership aside',
        () {
      expect(
        mapFlowToHealthWrite(FlowLevel.light, inPeriodEpisode: true),
        const HealthFlowMenstrualSample(HealthFlowValue.light),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.medium, inPeriodEpisode: true),
        const HealthFlowMenstrualSample(HealthFlowValue.medium),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.heavy, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      );
    });

    test('superHeavy collapses to heavy — the documented lossy mapping',
        () {
      expect(
        mapFlowToHealthWrite(FlowLevel.superHeavy, inPeriodEpisode: true),
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.superHeavy, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      );
    });

    test('the deprecated spotting alias takes the A3-4 branch verbatim',
        () {
      // ignore: deprecated_member_use_from_same_package
      final inside = mapFlowToHealthWrite(
        FlowLevel.spotting,
        inPeriodEpisode: true,
      );
      expect(inside, const HealthFlowMenstrualSample(HealthFlowValue.light));
      // ignore: deprecated_member_use_from_same_package
      final outside = mapFlowToHealthWrite(
        FlowLevel.spotting,
        inPeriodEpisode: false,
      );
      expect(outside, isA<HealthFlowIntermenstrualMarker>());
    });

    test('unspecified is never produced', () {
      for (final flow in FlowLevel.values) {
        final plan = mapFlowToHealthWrite(flow, inPeriodEpisode: false);
        if (plan is HealthFlowMenstrualSample) {
          expect(plan.value, isNot(HealthFlowValue.unspecified));
        }
      }
    });
  });

  group('mapSpottingToHealthWrite (A3-4 — the single most lossy point)',
      () {
    test('spotting inside a period episode is menstrual light', () {
      expect(
        mapSpottingToHealthWrite(inPeriodEpisode: true),
        const HealthFlowMenstrualSample(HealthFlowValue.light),
      );
    });

    test('spotting outside a period episode is intermenstrual, never '
        'menstrual', () {
      final plan = mapSpottingToHealthWrite(inPeriodEpisode: false);
      expect(plan, isA<HealthFlowIntermenstrualMarker>());
      expect(plan, isNot(isA<HealthFlowMenstrualSample>()));
    });
  });

  group('kSpottingObservationCategory', () {
    test("matches the app's spotting observations category", () {
      // #247 stores spotting as its own observations category; the write
      // service filters on this exact string.
      expect(kSpottingObservationCategory, 'spotting');
    });
  });

  group('Health Connect flow-constant correspondence (#202 AC1)', () {
    // #202 reuses #193's pure mapping verbatim for Health Connect — the only
    // delta is the OS constants (MenstruationFlowRecord.FLOW_* vs HealthKit's
    // HKCategoryValueVaginalBleeding), handled by the native adapters. These
    // tests pin that the shared function's outputs map 1:1 onto Health
    // Connect's constants, so the two platforms can never disagree about what
    // intensity a logged bleed level writes.
    test('light/medium/heavy correspond to the FLOW_LIGHT/FLOW_MEDIUM/'
        'FLOW_HEAVY constants the Kotlin adapter stamps', () {
      const hcConstants = <HealthFlowValue, String>{
        HealthFlowValue.light: 'FLOW_LIGHT',
        HealthFlowValue.medium: 'FLOW_MEDIUM',
        HealthFlowValue.heavy: 'FLOW_HEAVY',
      };
      for (final entry in hcConstants.entries) {
        final value = entry.key; // HealthFlowValue
        final constant = entry.value; // e.g. 'FLOW_LIGHT'
        // The transport wire string is the constant without the FLOW_
        // prefix, lowercased — the exact strings the Kotlin handler maps to
        // MenstruationFlowRecord.
        expect(
          value.toWire(),
          constant.substring('FLOW_'.length).toLowerCase(),
          reason: '$constant must match the wire value the native side maps',
        );
      }
    });

    test('bleed levels map through the shared function to their Health '
        'Connect constants', () {
      expect(
        mapFlowToHealthWrite(FlowLevel.light, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.light),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.medium, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.medium),
      );
      expect(
        mapFlowToHealthWrite(FlowLevel.heavy, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      );
      // #247's documented collapse: superHeavy writes the heavy constant.
      expect(
        mapFlowToHealthWrite(FlowLevel.superHeavy, inPeriodEpisode: false),
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      );
    });

    test('spotting inside an episode writes the light constant; outside one '
        'it is intermenstrual — the A3-4 rule shared with #193 verbatim',
        () {
      expect(
        mapSpottingToHealthWrite(inPeriodEpisode: true),
        const HealthFlowMenstrualSample(HealthFlowValue.light),
      );
      expect(
        mapSpottingToHealthWrite(inPeriodEpisode: false),
        isA<HealthFlowIntermenstrualMarker>(),
      );
    });
  });
}
