/// The pure `FlowLevel` → OS-health-store mapping (Issue #193) — the full
/// flow-enum table from the issue, as a total function with no platform,
/// channel, or I/O dependency, so the mapping logic itself carries full
/// `flutter test` coverage even though the native call sites are excluded
/// per #173 (HS-4).
///
/// The table (issue #193, A3-41, resolved for what #247 did to the flow
/// vocabulary after this issue was written):
///
/// | lunarlog value | HealthKit write target |
/// |---|---|
/// | `none` (nothing logged) | no sample written |
/// | `notBleeding` (#247's explicit assertion) | no sample written |
/// | `spotting` inside a period episode | `menstrualFlow` = `light` |
/// | `spotting` outside a period episode | `intermenstrualBleeding` |
/// | `light` | `light` |
/// | `medium` | `medium` |
/// | `heavy` | `heavy` |
/// | `superHeavy` (#247) | `heavy` — the documented collapse |
///
/// Decisions this table bakes in, each pinned by a test:
///
/// * **`none` writes nothing** (the issue's own stated assumption): a
///   sample for the majority of non-period days would bury the signal.
///   `notBleeding` — which did not exist when #193 was written — follows
///   the same rule: `HealthFlowValue` deliberately has no `none` case (see
///   its doc), and an explicit not-bleeding assertion is expressed to
///   Apple Health, which has such a value, only if a future issue reverses
///   the #193 assumption for both together.
/// * **`superHeavy` collapses to `heavy`**: Apple's
///   `HKCategoryValueVaginalBleeding` has no heavier case. This is the one
///   lossy mapping in the table and mirrors Clue's own documented
///   "heavy"/"super heavy" → `heavy` collapse; the Settings screen's
///   health-sync copy documents it the same way Clue documents its own.
/// * **The spotting branch is the issue's A3-4 rule**, spotted here as
///   `mapSpottingToHealthWrite` since #247 moved spotting out of
///   [FlowLevel] (a stored `flow = 'spotting'` row reads as
///   [FlowLevel.notBleeding] — the deprecated alias survives below only so
///   the mapping stays total over the enum, exactly as the issue's table
///   wrote it). Spotting inside a period episode writes `menstrualFlow`
///   `light` (so it participates in Apple Health's period model, carrying
///   the cycle-start metadata like any other menstrual sample); spotting
///   outside an episode writes `intermenstrualBleeding` — a different
///   HealthKit category type with no intensity — and is *never* written
///   as `menstrualFlow`.
///
/// The `unspecified` transport value is deliberately unreachable from
/// here: lunarlog always knows which value it means, or writes nothing —
/// it never asks Apple Health to guess.
///
/// The day each plan applies to becomes the write's day envelope via
/// `day_boundary.dart` (#180's timezone contract) further down the write
/// path (`health_flow_write_service.dart` → `health_channel_codec.dart`);
/// this file deals in plans, never instants.
library;

import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

/// The `observations.category` value the app logs spotting under since
/// #247 (Clue's own category name; see
/// `lib/data/repositories/drift_observations_repository.dart`'s synthesis
/// note). The write service filters spotting rows on this exact string.
const String kSpottingObservationCategory = 'spotting';

/// One day's resolved write decision: what (if anything) the OS health
/// store should receive for that day's logged bleeding. Sealed so the
/// write service's `switch` is exhaustive — a new [HealthFlowValue] or
/// [FlowLevel] case cannot silently fall through unmapped.
sealed class HealthFlowWritePlan {
  const HealthFlowWritePlan();
}

/// Nothing is written for this day (`none` / `notBleeding`).
final class HealthFlowNoWrite extends HealthFlowWritePlan {
  const HealthFlowNoWrite();
}

/// A `menstrualFlow` sample with this intensity is written for the day.
/// [value] is the platform-intersection transport value (never
/// `unspecified` — see the library doc); the cycle-start metadata flag is
/// computed from the containing episode by the write service, not here.
final class HealthFlowMenstrualSample extends HealthFlowWritePlan {
  const HealthFlowMenstrualSample(this.value);

  final HealthFlowValue value;

  /// Value equality — the plans are pure data, and the mapping tests pin
  /// exact outcomes (`const HealthFlowMenstrualSample(...)`) rather than
  /// mere runtime types.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthFlowMenstrualSample && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An `intermenstrualBleeding` record is written for the day (the
/// spotting-outside-an-episode branch). No intensity exists on this type
/// on either platform — the record's existence is the datum.
final class HealthFlowIntermenstrualMarker extends HealthFlowWritePlan {
  const HealthFlowIntermenstrualMarker();
}

/// Maps one day's [flow] to its write plan per the library-doc table.
/// [inPeriodEpisode] is whether the day lies inside a period episode
/// derived by `lib/domain/episodes/episodes.dart` — it only matters for
/// the spotting branch (a bleed-level day is an episode member by
/// construction) but is total over every input.
HealthFlowWritePlan mapFlowToHealthWrite(
  FlowLevel flow, {
  required bool inPeriodEpisode,
}) =>
    switch (flow) {
      FlowLevel.none => const HealthFlowNoWrite(),
      FlowLevel.notBleeding => const HealthFlowNoWrite(),
      // The deprecated alias: kept so the function is total over the enum
      // and the issue's table verbatim. Repository reads never surface it
      // (a stored `flow = 'spotting'` row reads as notBleeding, and the
      // synthesised spotting observation takes the branch below instead),
      // so this case exists for a legacy direct caller only.
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.spotting =>
        mapSpottingToHealthWrite(inPeriodEpisode: inPeriodEpisode),
      FlowLevel.light =>
        const HealthFlowMenstrualSample(HealthFlowValue.light),
      FlowLevel.medium =>
        const HealthFlowMenstrualSample(HealthFlowValue.medium),
      FlowLevel.heavy => const HealthFlowMenstrualSample(HealthFlowValue.heavy),
      FlowLevel.superHeavy =>
        // The documented collapse: Apple has no heavier case (A3-35's
        // Clue parity — Clue documents the same collapse for its own
        // "super heavy").
        const HealthFlowMenstrualSample(HealthFlowValue.heavy),
    };

/// The A3-4 spotting rule: spotting inside a period episode is written as
/// a `menstrualFlow` `light` sample; spotting outside one is written as
/// `intermenstrualBleeding` — never as `menstrualFlow`. The single most
/// lossy point in the whole mapping, per the issue, which is why it is a
/// named function with its own tests rather than an inline branch.
HealthFlowWritePlan mapSpottingToHealthWrite({
  required bool inPeriodEpisode,
}) =>
    inPeriodEpisode
        ? const HealthFlowMenstrualSample(HealthFlowValue.light)
        : const HealthFlowIntermenstrualMarker();
