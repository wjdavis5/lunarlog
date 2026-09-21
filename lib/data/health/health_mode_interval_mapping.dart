/// The pure life-stage-mode → OS-health-store interval mapping (Issue
/// #246): the four types the issue scopes, as pure plans a future
/// platform adapter consumes. No platform, channel, or I/O dependency —
/// the `health_flow_mapping.dart` / `health_fertility_mapping.dart`
/// pattern — so the mapping logic itself carries full `flutter test`
/// coverage even though no platform adapter exists to call yet.
///
/// ## What exists and what still does not
///
/// The modes this issue was sequenced behind have landed: pregnancy mode
/// (#192) and perimenopause mode (#196) are live on the `profile_modes`
/// axis ([LifecycleMode]). The Health Platform Sync adapter, though, has
/// **no platform plugin** — there is no write path to call today, and all
/// four types stay [HealthTypeMappingStatus.futureCandidate] entries in
/// `health_type_registry.dart`. What this file adds is the mapping
/// itself: the exact sample shapes a future adapter writes, derived from
/// data the app already stores (`profile_modes.mode_started_on` and the
/// exit date a mode switch stamps), so the adapter work is translation
/// rather than rediscovery.
///
/// ## The four mappings
///
/// | type | HealthKit shape | derived from |
/// |---|---|---|
/// | `pregnancy` | open/closed interval sample carrying `HKCategoryValueNotApplicable` | a pregnancy-mode span: `mode_started_on` → exit date |
/// | `lactation` | the same interval shape via `.lactation` | no lunarlog mode derives it today (see [lactationIntervalPlan]) |
/// | `menopausalState` | **point-in-time** sample where start == end (a hard HealthKit constraint) | the perimenopause-mode start date |
/// | `bleedingAfterMenopause` | interval sample carrying `HKCategoryValueVaginalBleeding` | a bleed day logged while perimenopause mode is active |
///
/// Both `pregnancy` and `lactation` carry `HKCategoryValueNotApplicable`:
/// existence of the sample, not a value, is the signal — the mode span
/// *is* the datum. Health Connect has no analogue for any of the four
/// (the registry records this), so all are HealthKit-only — the same
/// registry-level fact that already rules out a cross-platform port
/// method for them.
///
/// ## The `menopausalState` start == end constraint
///
/// `HKCategoryTypeIdentifier.menopausalState` (iOS 26) is a point-in-time
/// category sample: saving one whose start and end dates differ **errors
/// at the API level** — unlike every interval sample this file otherwise
/// names. [MenopausalStateSample] therefore has no way to express a
/// mismatched pair: it is constructed from a single [LocalDate], and its
/// `start` and `end` getters return that one date. The mapping is
/// structurally incapable of producing the rejected shape; the test suite
/// pins the identity anyway (the issue's AC).
///
/// ## Every plan is guarded (#153 HS-1)
///
/// Every public derivation takes the outcome of
/// `HealthSyncBinding.canWrite` as its `writeGuard` parameter and returns
/// nothing unless it is [HealthSyncCheck.allowed] — the same guard every
/// other type in this epic writes behind (`health_flow_write_service.dart`
/// pre-checks it and the port re-checks natively per call). The mapping
/// is deliberately incapable of producing a sample for a write the guard
/// would refuse. A future adapter passes the real check's result — never
/// a hardcoded `allowed` — and re-checks natively, exactly as the
/// existing write paths do.
///
/// All date math is on civil dates ([LocalDate]), matching
/// `mode_intervals.dart`'s convention; the day each plan applies to
/// becomes the write's day envelope via `day_boundary.dart` further down
/// the (future) write path — this file deals in plans, never instants.
library;

import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/perimenopause.dart' show isPerimenopauseMode;

import 'health_flow_mapping.dart';

// ---------------------------------------------------------------------------
// Platform identifiers and value constants
// ---------------------------------------------------------------------------

/// The `HKCategoryTypeIdentifier` case name for the pregnancy interval.
const String kPregnancyHealthKitIdentifier =
    'HKCategoryTypeIdentifier.pregnancy';

/// The `HKCategoryTypeIdentifier` case name for the lactation interval.
const String kLactationHealthKitIdentifier =
    'HKCategoryTypeIdentifier.lactation';

/// The `HKCategoryTypeIdentifier` case name for the menopause state
/// point-in-time sample (iOS 26).
const String kMenopausalStateHealthKitIdentifier =
    'HKCategoryTypeIdentifier.menopausalState';

/// The `HKCategoryTypeIdentifier` case name for the post-menopausal
/// bleeding interval (iOS 26).
const String kBleedingAfterMenopauseHealthKitIdentifier =
    'HKCategoryTypeIdentifier.bleedingAfterMenopause';

/// The `HKCategoryValueNotApplicable` case name both mode-span interval
/// types carry: existence of the sample, not a value, is the signal.
const String kIntervalSampleNotApplicableHealthKitValue = 'notApplicable';

/// The `HKCategoryValueMenopausalState` case the mapping writes while
/// perimenopause mode is active. Named here rather than inline so the one
/// decision is reviewable and unit-testable; the adapter confirms the raw
/// SDK spelling when the write path lands (the type is iOS 26 and cannot
/// be compiled against from Dart today).
const String kPerimenopauseMenopausalStateHealthKitValue = 'perimenopause';

// ---------------------------------------------------------------------------
// Mode-span interval plans (pregnancy / lactation)
// ---------------------------------------------------------------------------

/// A resolved open-or-closed interval-sample plan for one of the two
/// mode-span types (`pregnancy` / `lactation`): what a future adapter
/// writes, as platform constants plus a civil-date envelope.
///
/// An open plan ([end] null) is written when the mode is entered; closing
/// it at exit is the same sample with its end date stamped. HealthKit's
/// own `[start, end)` semantics decide how the envelope maps onto
/// instants — that translation belongs to the adapter, not here.
class HealthModeIntervalPlan {
  const HealthModeIntervalPlan._({
    required this.concept,
    required this.healthKitIdentifier,
    required this.start,
    required this.end,
  });

  /// The registry concept this plan writes: `'pregnancy'` or
  /// `'lactation'`.
  final String concept;

  /// The `HKCategoryTypeIdentifier` this plan targets.
  final String healthKitIdentifier;

  /// Health Connect has no analogue for either type (the registry
  /// records this). Carried as an explicit getter so an adapter cannot
  /// "just also write Android" without confronting the absence.
  String? get healthConnectRecord => null;

  /// The `HKCategoryValueNotApplicable` both types carry.
  String get healthKitValue => kIntervalSampleNotApplicableHealthKitValue;

  /// The mode-enter date (`profile_modes.mode_started_on`).
  final LocalDate start;

  /// The mode-exit date, or null while the mode is still active (an open
  /// interval sample). Non-null reads as the closed plan; see [isClosed].
  final LocalDate? end;

  /// Whether the span has its exit date stamped (the mode has ended).
  bool get isClosed => end != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthModeIntervalPlan &&
          other.concept == concept &&
          other.healthKitIdentifier == healthKitIdentifier &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(concept, healthKitIdentifier, start, end);

  @override
  String toString() =>
      'HealthModeIntervalPlan($concept, ${start.iso}..${end?.iso ?? 'open'})';
}

/// Derives the mode-span interval plans for one [LifecycleMode] span —
/// `[modeStartedOn, exitedOn)` in the same terms
/// `mode_intervals.dart`/`pregnancy.dart` already use — as the interval
/// samples a future adapter writes.
///
/// * Only `LifecycleMode.pregnancy` produces plans today (the issue's
///   pregnancy mapping); every other mode — including the postpartum and
///   perimenopause spans — has no mode-span interval type, so produces
///   none. Lactation has no deriving mode at all; see
///   [lactationIntervalPlan].
/// * A null [modeStartedOn] (the mode was entered before the column was
///   stamped) returns empty — an honest empty set the caller can surface,
///   never a guessed interval, matching `intervalExclusionStarts`'s null
///   rule.
/// * A null [exitedOn] is the still-active mode: one **open** plan. A
///   stamped exit closes it.
/// * An exit before the start is a degenerate span (a bad stored date) —
///   empty, never an inverted interval.
/// * [writeGuard] must be the result of a real
///   `HealthSyncBinding.canWrite` call; anything but
///   [HealthSyncCheck.allowed] produces nothing (see the library doc).
List<HealthModeIntervalPlan> deriveModeIntervalPlans({
  required LifecycleMode mode,
  required LocalDate? modeStartedOn,
  required LocalDate? exitedOn,
  required HealthSyncCheck writeGuard,
}) {
  if (!writeGuard.isAllowed) return const [];
  if (mode != LifecycleMode.pregnancy) return const [];
  final plan = _modeSpanPlan(
    concept: 'pregnancy',
    healthKitIdentifier: kPregnancyHealthKitIdentifier,
    modeStartedOn: modeStartedOn,
    exitedOn: exitedOn,
  );
  return plan == null ? const [] : [plan];
}

/// The lactation interval plan for an explicitly supplied span — the same
/// open/closed `HKCategoryValueNotApplicable` shape pregnancy uses, via
/// `.lactation`.
///
/// **No lunarlog mode derives lactation today**: [LifecycleMode] has no
/// lactation case, and #246's dependencies (#192 pregnancy, #196
/// perimenopause) did not add one. The construction exists so the shape
/// is pinned and a future mode (or postpartum-lactation signal) wires the
/// same plan type rather than reinventing it; until such a source exists
/// no production caller derives it, and the registry entry records that
/// honestly. Null when the write guard refuses, or when [end] precedes
/// [start] (a degenerate span — never an inverted interval).
HealthModeIntervalPlan? lactationIntervalPlan({
  required LocalDate start,
  LocalDate? end,
  required HealthSyncCheck writeGuard,
}) {
  if (!writeGuard.isAllowed) return null;
  return _modeSpanPlan(
    concept: 'lactation',
    healthKitIdentifier: kLactationHealthKitIdentifier,
    modeStartedOn: start,
    exitedOn: end,
  );
}

/// The shared open/closed construction behind both mode-span types: null
/// start → null (an honest empty set), inverted span → null, otherwise
/// exactly one plan with `end` null (open) or stamped (closed).
HealthModeIntervalPlan? _modeSpanPlan({
  required String concept,
  required String healthKitIdentifier,
  required LocalDate? modeStartedOn,
  required LocalDate? exitedOn,
}) {
  final start = modeStartedOn;
  if (start == null) return null;
  if (exitedOn != null && exitedOn.isBefore(start)) return null;
  return HealthModeIntervalPlan._(
    concept: concept,
    healthKitIdentifier: healthKitIdentifier,
    start: start,
    end: exitedOn,
  );
}

// ---------------------------------------------------------------------------
// Menopausal state (point-in-time, start == end)
// ---------------------------------------------------------------------------

/// A `menopausalState` point-in-time sample (iOS 26), stamped with one
/// [LocalDate].
///
/// HealthKit rejects a save whose start and end dates differ, so this
/// class is built from a single date: [start] and [end] return the same
/// value *by construction*, and there is no second field to set wrong.
/// The mapping therefore cannot produce the mismatched pair the API
/// rejects — the guarantee the issue's acceptance criterion asks a unit
/// test to assert is structural here, and the test pins it anyway.
class MenopausalStateSample {
  const MenopausalStateSample._(this.date);

  /// The single date the sample is stamped with: `start == end == date`.
  final LocalDate date;

  /// The sample's start date — always [date] (the hard API constraint).
  LocalDate get start => date;

  /// The sample's end date — always [date] (the hard API constraint).
  LocalDate get end => date;

  /// The `HKCategoryTypeIdentifier` this sample targets.
  String get healthKitIdentifier => kMenopausalStateHealthKitIdentifier;

  /// The `HKCategoryValueMenopausalState` case written while
  /// perimenopause mode is active.
  String get healthKitValue => kPerimenopauseMenopausalStateHealthKitValue;

  /// Health Connect has no analogue (the registry records this).
  String? get healthConnectRecord => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenopausalStateSample && other.date == date;

  @override
  int get hashCode => date.hashCode;

  @override
  String toString() => 'MenopausalStateSample(${date.iso})';
}

/// The `menopausalState` sample for the transition into perimenopause
/// mode: one point-in-time sample stamped at [modeStartedOn] with
/// start == end (the hard HealthKit constraint [MenopausalStateSample]
/// enforces structurally).
///
/// Null when [writeGuard] is not [HealthSyncCheck.allowed], the [mode] is
/// not perimenopause (routed through the one shared
/// [isPerimenopauseMode] predicate), or no `mode_started_on` is stamped —
/// a mode entered before the column existed gets no guessed date,
/// matching `intervalExclusionStarts`'s null rule.
MenopausalStateSample? deriveMenopausalStateSample({
  required LifecycleMode? mode,
  required LocalDate? modeStartedOn,
  required HealthSyncCheck writeGuard,
}) {
  if (!writeGuard.isAllowed) return null;
  if (!isPerimenopauseMode(mode)) return null;
  if (modeStartedOn == null) return null;
  return MenopausalStateSample._(modeStartedOn);
}

// ---------------------------------------------------------------------------
// Bleeding after menopause (interval, shared #193 value table)
// ---------------------------------------------------------------------------

/// One resolved `bleedingAfterMenopause` sample (iOS 26): an interval
/// sample whose value comes from the **same** `HKCategoryValueVaginalBleeding`
/// mapping table #193 (HS-5) uses — [HealthFlowValue] as resolved by
/// [mapFlowToHealthWrite] — never a separate ad hoc mapping (the issue's
/// AC).
class BleedingAfterMenopauseSample {
  const BleedingAfterMenopauseSample._(this.value);

  /// The shared-table value for the day's bleeding.
  final HealthFlowValue value;

  /// The `HKCategoryTypeIdentifier` this sample targets.
  String get healthKitIdentifier => kBleedingAfterMenopauseHealthKitIdentifier;

  /// Health Connect has no analogue (the registry records this).
  String? get healthConnectRecord => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleedingAfterMenopauseSample && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BleedingAfterMenopauseSample(${value.name})';
}

/// Resolves one bleed day into its `bleedingAfterMenopause` sample, or
/// null when nothing is written for the type:
///
/// * [writeGuard] is not [HealthSyncCheck.allowed] (see the library doc);
/// * perimenopause mode is **not** active — the day's routing stays
///   exactly the shipped #193 mapping ([mapFlowToHealthWrite]); this type
///   is simply not written outside the mode;
/// * the shared table resolves no menstrual sample for the day
///   (`none`/`notBleeding` write nothing — a sample for the common empty
///   day would bury the signal, the same rule `health_flow_mapping.dart`
///   applies);
/// * the day resolves to the spotting-outside-an-episode branch — that
///   keeps writing `intermenstrualBleeding`, which exists on **both**
///   platforms; retargeting it to this HealthKit-only type would drop the
///   day's Android write entirely.
///
/// What remains — a bleed-level day (or in-episode spotting, which the
/// shared table resolves to a `light` menstrual sample) inside active
/// perimenopause mode — carries the same [HealthFlowValue] the #193 table
/// resolved, including the documented `superHeavy` → `heavy` collapse.
BleedingAfterMenopauseSample? resolveBleedingAfterMenopause({
  required FlowLevel flow,
  required bool inPeriodEpisode,
  required bool inPerimenopauseMode,
  required HealthSyncCheck writeGuard,
}) {
  if (!writeGuard.isAllowed) return null;
  if (!inPerimenopauseMode) return null;
  final plan = mapFlowToHealthWrite(flow, inPeriodEpisode: inPeriodEpisode);
  if (plan is! HealthFlowMenstrualSample) return null;
  return BleedingAfterMenopauseSample._(plan.value);
}
