/// Platform-neutral health-store port (Issue #173) — the one interface
/// every HealthKit / Health Connect data-type write goes through, one
/// method per data-type *concept*, never per platform SDK call.
///
/// ## Design note: first-party channel over the `health` package (the
/// issue's (a) vs (b) decision — recorded here so it is not re-litigated)
///
/// **Decision: option (b), a first-party `MethodChannel` (`lunarlog/health`)
/// with a Swift `HKHealthStore` implementation on iOS and a Kotlin
/// `HealthConnectClient` implementation on Android. The pub.dev `health`
/// package (v13.3.2) is deliberately NOT a dependency and must not be
/// added.**
///
/// Why (b) over (a) (`health` package + a second channel for the rest):
///
///  1. **Type surface.** The `health` package covers only
///     `MENSTRUATION_FLOW` of the cycle-relevant types on either platform
///     — no intermenstrual bleeding, cervical mucus, ovulation test, basal
///     body temperature, sexual activity, or the ~39 HealthKit symptom
///     category types (the package's own README notes both platforms
///     expose more types than it covers). Depending on it means either
///     single-type parity with Clue (defeating the differentiator types
///     of #217/#228/#210/#238) or two competing implementations of the
///     same data-type concept in one app — the exact duplication this
///     port exists to make impossible.
///  2. **One place for the safety invariant.** The #153 (HS-1) guard
///     (profile↔device-owner binding + owner-not-guardian, see
///     `health_sync_policy.dart`) must be enforced identically across
///     *every* type this epic adds. A package-limited surface would force
///     the flow type through the package's own write path — which cannot
///     run lunarlog's native guard at all — while every other type went
///     through ours: two code paths, two (well, one and zero) places to
///     enforce the same load-bearing property. A single first-party
///     channel keeps it in one place, enforced natively before any health
///     API touch (see the adapters' docs and the plan of record).
///  3. **Background/observer support.** The package has no iOS observer
///     query support at all and Android-only permission helpers; the
///     epic's later background work (#217/#186) needs the native handles
///     a first-party channel owns outright.
///
/// The cost of (b) — maintaining two native implementations behind one
/// protocol — is bounded: both sides speak the small, versioned message
/// set in `lib/data/health/health_channel_codec.dart`, and all
/// cross-platform logic (guard evaluation on the Dart side, day/zone
/// conversion via `day_boundary.dart`) stays in pure, tested Dart.
///
/// ## Shape of the port
///
/// * Methods are per data-type concept (`writeMenstrualFlow`,
///   `writeIntermenstrualBleeding`) — the minimum the epic's v1 parity
///   issues (#193/#202) need. Later types (cervical mucus, ovulation
///   test, BBT, sexual activity, symptom categories) extend this
///   interface with one method each and one codec entry each; nothing
///   about the existing surface changes when they do.
/// * Every guarded method takes a [HealthGuardFacts] — the same inputs
///   `HealthSyncBinding.canWrite` evaluates — because **the adapter, not
///   the eventual call site, owns the guard call**: every implementation
///   must invoke `HealthSyncBinding.canWrite` *before* touching the
///   channel, and the native handler re-evaluates the same predicate
///   from its own natively-stored binding before touching
///   `HKHealthStore`/`HealthConnectClient` at all. A bug in Dart-side
///   call ordering therefore cannot bypass the safety property: the
///   native mirror denies (and never touches the health API) even if
///   Dart never checked. The duplication is the safety property — see
///   the native files and the plan of record for why the mirror cannot
///   be factored into one place (the two sides cannot share code).
/// * Results are typed ([HealthPlatformResult]), never bare bools, so a
///   refusal carries its [HealthSyncCheck] reason all the way back to
///   the caller.
///
/// Pure Dart (R14/R16): no Flutter, channel, or platform imports here —
/// `test/architecture/layering_test.dart` enforces the discipline. The
/// implementations live in `lib/data/health/` (`ios_health_channel.dart`,
/// `android_health_channel.dart`, over the shared `health_channel.dart`).
library;

import '../models/local_date.dart';
import '../models/profile.dart';
import 'health_sync_policy.dart';

/// The closed, platform-intersection set of menstrual-flow intensities
/// this port can write. Mirrors the common ground of HealthKit's
/// `HKCategoryValueVaginalBleeding` (`unspecified`/`light`/`medium`/
/// `heavy`; `none` exists there but is deliberately absent here — a
/// "no sample" day is expressed by *not writing*, per #193's mapping
/// table) and Health Connect's `MenstruationFlowRecord` flow constants
/// (`FLOW_UNKNOWN`/`FLOW_LIGHT`/`FLOW_MEDIUM`/`FLOW_HEAVY`).
///
/// This is a *transport* vocabulary, not a domain one: mapping lunarlog's
/// [FlowLevel] (plus episode membership for the spotting rule) onto these
/// values is #193/#202's pure mapping function, which lives beside the
/// adapters in `lib/data/health/` — it does not belong in the domain.
enum HealthFlowValue {
  unspecified,
  light,
  medium,
  heavy;

  /// The wire string used on the `lunarlog/health` channel. Both native
  /// implementations and `health_channel_codec.dart` recognize exactly
  /// this closed set.
  String toWire() => switch (this) {
        unspecified => 'unspecified',
        light => 'light',
        medium => 'medium',
        heavy => 'heavy',
      };

  /// Parses the wire string; null when [raw] is not in the closed set (a
  /// newer native side than this Dart side, or corruption) — callers
  /// treat null as a protocol error, never a silent fallback.
  static HealthFlowValue? fromWire(String? raw) => switch (raw) {
        'unspecified' => unspecified,
        'light' => light,
        'medium' => medium,
        'heavy' => heavy,
        _ => null,
      };
}

/// The transport vocabulary for a HealthKit symptom sample's severity
/// (Issue #238): the closed subset of `HKCategoryValueSeverity` this port
/// can write. Health Connect has **no** symptom category types at all, so
/// this vocabulary is only ever used by the iOS half — an asymmetry the
/// Android adapter documents permanently rather than working around (see
/// `HealthConnectAdapter.kt`).
///
/// `HKCategoryValue.notApplicable` (0) is deliberately absent, exactly as
/// it is for [HealthFlowValue]: "no severity" is expressed by the
/// dedicated [unspecified] value (raw 4 in Apple's SDK), never by the
/// shared not-applicable zero.
enum HealthSymptomSeverity {
  unspecified,
  mild,
  moderate,
  severe;

  /// The wire string used on the `lunarlog/health` channel. Both the
  /// native half and `health_channel_codec.dart` recognize exactly this
  /// closed set.
  String toWire() => switch (this) {
        unspecified => 'unspecified',
        mild => 'mild',
        moderate => 'moderate',
        severe => 'severe',
      };

  /// Parses the wire string; null when [raw] is not in the closed set (a
  /// newer native side than this Dart side, or corruption) — callers
  /// treat null as a protocol error, never a silent fallback.
  static HealthSymptomSeverity? fromWire(String? raw) => switch (raw) {
        'unspecified' => unspecified,
        'mild' => mild,
        'moderate' => moderate,
        'severe' => severe,
        _ => null,
      };
}

/// The guard inputs every guarded port method carries: which [profile]'s
/// data is about to be written to this device's OS health store, and the
/// ownership facts `HealthSyncBinding.canWrite` evaluates (see
/// `health_sync_policy.dart` — [ownerUserId] is resolved via
/// [ownerUserIdFor] from the profile's guardian rows; [signedInUserId]
/// is the signed-in account's user id, null when signed out).
///
/// [minorBindingAllowed] is deliberately NOT a field here: it must be
/// sourced from `AppConfig.healthSyncMinorBindingAllowed` and nowhere
/// else, so the adapters take it as a constructor parameter from their
/// production wiring rather than accepting it per call — no call site can
/// invent its own per-call bypass.
class HealthGuardFacts {
  const HealthGuardFacts({
    required this.profile,
    required this.signedInUserId,
    required this.ownerUserId,
  });

  final Profile profile;

  /// The signed-in account's user id, or null when signed out.
  final String? signedInUserId;

  /// The profile's resolved owner (`ownerUserIdFor` over its accepted
  /// guardian rows), or null when ownership has not resolved.
  final String? ownerUserId;
}

/// The typed outcome of every guarded port method. A refusal carries its
/// [HealthSyncCheck] reason; platform failures are distinguished so the
/// caller (and, later, Settings copy) can tell "the guard said no" from
/// "HealthKit isn't on this device" from "the OS rejected the write".
sealed class HealthPlatformResult {
  const HealthPlatformResult();

  /// The guard (Dart- or native-side) allowed the operation and the
  /// platform performed it (for `requestWriteAuthorization`: the prompt
  /// completed).
  const factory HealthPlatformResult.allowed() = HealthPlatformAllowed;

  /// The guard refused; [check] is the deny reason, never
  /// [HealthSyncCheck.allowed]. No health API was touched.
  const factory HealthPlatformResult.refused(HealthSyncCheck check) =
      HealthPlatformRefused;

  /// No health store exists on this device (no HealthKit — e.g. iPad
  /// before iOS 17 — or Health Connect not installed/enabled).
  const factory HealthPlatformResult.unavailable() = HealthPlatformUnavailable;

  /// The OS denied the required permissions for this operation.
  const factory HealthPlatformResult.permissionDenied() =
      HealthPlatformPermissionDenied;

  /// The platform threw or answered with something this Dart side does
  /// not understand (including an unresolvable time zone — the write is
  /// refused rather than written at a wrong instant). [message] is
  /// diagnostic, never user-facing.
  const factory HealthPlatformResult.failed(String message) =
      HealthPlatformFailed;
}

final class HealthPlatformAllowed extends HealthPlatformResult {
  const HealthPlatformAllowed();
}

final class HealthPlatformRefused extends HealthPlatformResult {
  const HealthPlatformRefused(this.check) : assert(check != HealthSyncCheck.allowed);

  final HealthSyncCheck check;
}

final class HealthPlatformUnavailable extends HealthPlatformResult {
  const HealthPlatformUnavailable();
}

final class HealthPlatformPermissionDenied extends HealthPlatformResult {
  const HealthPlatformPermissionDenied();
}

final class HealthPlatformFailed extends HealthPlatformResult {
  const HealthPlatformFailed(this.message);

  final String message;
}

/// A `writeMenstrualFlow` payload: one logged day's bleed intensity for
/// the bound profile, plus the HealthKit cycle-start flag (#193:
/// `HKMetadataKeyMenstrualCycleStart` must be set on every menstrual
/// flow sample — true on the first day of a cycle, false otherwise,
/// sourced from `lib/domain/episodes/episodes.dart` by the caller).
///
/// [date]/[tzName] are the entry's own civil date and IANA zone (never
/// the device's current zone): the adapter converts them to platform
/// instants through `day_boundary.dart` — the #180 timezone contract —
/// so no native side ever does timezone arithmetic of its own.
class HealthMenstrualFlowWrite {
  const HealthMenstrualFlowWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.flow,
    required this.cycleStart,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;
  final HealthFlowValue flow;
  final bool cycleStart;

  /// The lunarlog record id this sample came from (Issue #186 sync
  /// mechanics): the `day_entry_id` ULID. Becomes Health Connect's
  /// `clientRecordId` and HealthKit's `HKMetadataKeyExternalUUID`, so the
  /// write is idempotent (re-writes replace rather than duplicate) and a
  /// tombstone can delete the exact sample.
  final String recordId;

  /// `updatedAt.millisecondsSinceEpoch` of the source row — Health
  /// Connect's `clientRecordVersion` (a higher version replaces on
  /// re-write).
  final int recordVersionMs;
}

/// A `writeIntermenstrualBleeding` payload: one logged day of bleeding
/// outside a period episode (#193/A3-4's spotting rule — this type has
/// no intensity on either platform; HealthKit's
/// `intermenstrualBleeding` carries `HKCategoryValueNotApplicable` and
/// Health Connect's `IntermenstrualBleedingRecord` has no value field
/// at all: the record's existence is the datum). [date]/[tzName] as in
/// [HealthMenstrualFlowWrite].
class HealthIntermenstrualBleedingWrite {
  const HealthIntermenstrualBleedingWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;

  /// As [HealthMenstrualFlowWrite.recordId] — the source observation's
  /// ULID (for spotting markers this is the observation row id).
  final String recordId;

  /// As [HealthMenstrualFlowWrite.recordVersionMs].
  final int recordVersionMs;
}

/// A `writeMenstrualPeriod` payload (Issue #202): one period episode's
/// interval boundaries for the bound profile. This is Health Connect's
/// `MenstruationPeriodRecord` — the interval record HealthKit has no
/// analogue of (HealthKit encodes episode boundaries via the menstrual-flow
/// cycle-start metadata instead, #193).
///
/// [start]/[end] are the episode's inclusive civil dates from
/// `lib/domain/episodes/episodes.dart` (a write pass derives episodes from
/// the bound profile's bleed-day set). The adapter converts them to the
/// record's instants/offsets through `day_boundary.dart` — `startTime` at
/// local midnight of [start], `endTime` at the *exclusive* local midnight
/// after [end], and the matching `zoneOffset`/`endZoneOffset` — the #180
/// timezone contract, never the device's current zone.
///
/// [recordId] is the episode's stable id (the same for the same episode
/// across re-writes as it extends — Issue #186/HS-11 `clientRecordId`, which
/// Health Connect upserts by, so an in-progress episode is *updated*, not
/// duplicated) and [recordVersionMs] a per-write increasing version
/// (`clientRecordVersion`) so a re-write replaces the prior record.
class HealthMenstrualPeriodWrite {
  const HealthMenstrualPeriodWrite({
    required this.facts,
    required this.start,
    required this.end,
    required this.tzName,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;

  /// The episode's first bleed day (inclusive).
  final LocalDate start;

  /// The episode's last bleed day (inclusive); the record's `endTime` is
  /// the exclusive local midnight after this date.
  final LocalDate end;

  /// The episode's IANA zone — from the entries' own `tz` (#180), never the
  /// device's current zone.
  final String tzName;

  /// The episode's stable `clientRecordId` (unchanged across re-writes of
  /// the same episode; see the class doc).
  final String recordId;

  /// As [HealthMenstrualFlowWrite.recordVersionMs].
  final int recordVersionMs;
}

/// One resolved symptom sample inside a [HealthSymptomSamplesWrite]
/// (Issue #238): the HealthKit `HKCategoryTypeIdentifier` symptom string
/// and severity are already decided in Dart (see
/// `lib/data/health/health_symptom_mapping.dart` — the mapping table and
/// every decision live there, never in Swift), so the native half only
/// translates the wire value into an `HKCategorySample`.
///
/// [healthKitTypeIdentifier] is the raw case name of an
/// `HKCategoryTypeIdentifier` (e.g. `abdominalCramps`, `moodChanges`);
/// Swift resolves it via `HKCategoryTypeIdentifier(rawValue:)` with no
/// tag knowledge of its own. [recordId] is the stable lunarlog id for
/// this (day entry, symptom type) pair — HealthKit's
/// `HKMetadataKeyExternalUUID`/`HKMetadataKeySyncIdentifier`, the same
/// idempotence/deletability contract [HealthMenstrualFlowWrite.recordId]
/// documents.
class HealthSymptomSample {
  const HealthSymptomSample({
    required this.healthKitTypeIdentifier,
    required this.severity,
    required this.recordId,
    required this.recordVersionMs,
  });

  final String healthKitTypeIdentifier;
  final HealthSymptomSeverity severity;
  final String recordId;
  final int recordVersionMs;
}

/// A `writeSymptomSamples` payload (Issue #238): every symptom sample
/// resolved for one logged day, in one channel call. [date]/[tzName] are
/// the source day entry's own civil date and IANA zone (never the
/// device's current zone); the adapter converts them to the sample
/// instants through `day_boundary.dart` — the #180 timezone contract, so
/// no native side does zone math.
class HealthSymptomSamplesWrite {
  const HealthSymptomSamplesWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.samples,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;

  /// At least one, always — the write service never sends an empty batch
  /// (nothing to write means no channel call at all).
  final List<HealthSymptomSample> samples;
}

/// A `writeCervicalMucus` payload (Issue #228): one logged day's
/// cervical-mucus appearance for the bound profile. HealthKit writes a
/// single `HKCategoryValueCervicalMucusQuality`; Health Connect needs both
/// an `appearance` and a `sensation`. The domain has no sensation concept,
/// so the native half always writes `SENSATION_UNKNOWN` — only the
/// appearance is carried here. Both platform identifiers are resolved in
/// Dart (`lib/data/health/health_fertility_mapping.dart`); the native half
/// translates the one its platform uses and adds no mapping decision of its
/// own.
class HealthCervicalMucusWrite {
  const HealthCervicalMucusWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.healthKitValue,
    required this.healthConnectAppearance,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;

  /// The `HKCategoryValueCervicalMucusQuality` case name (`sticky`,
  /// `creamy`, `eggWhite`).
  final String healthKitValue;

  /// The `CervicalMucusRecord` appearance constant name
  /// (`APPEARANCE_STICKY`, …).
  final String healthConnectAppearance;

  /// As [HealthMenstrualFlowWrite.recordId] — the source day entry's ULID
  /// paired with the concept, so a re-write replaces and a tombstone can
  /// address the sample.
  final String recordId;

  final int recordVersionMs;
}

/// A `writeOvulationTest` payload (Issue #228): one logged day's resolved
/// ovulation-test result. The two platforms' vocabularies differ
/// (`luteinizingHormoneSurge` vs `RESULT_POSITIVE`), and `positive`/`peak`
/// collapse onto one platform value; those decisions live in Dart, so the
/// payload carries both already-resolved identifiers and the native half
/// only translates.
class HealthOvulationTestWrite {
  const HealthOvulationTestWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.healthKitResult,
    required this.healthConnectResult,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;

  /// The `HKCategoryValueOvulationTestResult` case name (`negative`,
  /// `luteinizingHormoneSurge`).
  final String healthKitResult;

  /// The `OvulationTestRecord` result constant name (`RESULT_NEGATIVE`,
  /// `RESULT_POSITIVE`).
  final String healthConnectResult;

  final String recordId;
  final int recordVersionMs;
}

/// A `writeBasalBodyTemperature` payload (Issue #228): the first non-enum
/// (quantity) type. [celsius] is already converted to Celsius by Dart, so
/// neither native half does unit math — HealthKit writes it in
/// `HKUnit.degreeCelsius()`, Health Connect as `Temperature.celsius`.
///
/// [healthConnectMeasurementLocation] is the resolved Health Connect
/// `measurementLocation` constant; the live domain has no location field,
/// so it is always the honest unknown. HealthKit has no such field.
class HealthBasalBodyTemperatureWrite {
  const HealthBasalBodyTemperatureWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.celsius,
    required this.healthConnectMeasurementLocation,
    required this.recordId,
    required this.recordVersionMs,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;

  /// The value in °C.
  final double celsius;

  /// The `BasalBodyTemperatureRecord.measurementLocation` constant name.
  final String healthConnectMeasurementLocation;

  final String recordId;
  final int recordVersionMs;
}

/// The platform-neutral health-store port (see the library doc for the
/// (a)-vs-(b) design decision). Implementations: `lib/data/health/`
/// (`MethodChannelHealthPlatform` shared, `IOSHealthChannel` and
/// `AndroidHealthChannel` pinning it to each platform's native
/// counterpart; `UnsupportedHealthPlatform` for web/desktop).
///
/// **Implementor contract:** every guarded method MUST (1) evaluate
/// `HealthSyncBinding.canWrite` with [HealthGuardFacts.profile] /
/// `signedInUserId` / `ownerUserId` and the adapter's
/// `minorBindingAllowed` *first*, returning `refused(check)` without any
/// channel invocation on a deny, and (2) forward the same facts so the
/// native handler re-evaluates the mirrored predicate against its own
/// natively-stored binding before touching any health API. `isAvailable`
/// is the one deliberately unguarded method: it is a static capability
/// probe (no health store access, no user data), and the Settings UI
/// needs it before any binding exists.
abstract interface class HealthPlatformStore {
  /// Whether this device has a health store at all (HealthKit present /
  /// Health Connect installed and available). Never touches user data.
  Future<bool> isAvailable();

  /// Records the native-side copy of the device-owner binding after the
  /// Dart-side `HealthSyncBinding.bind` succeeded — the value the
  /// native guard compares every write against, stored natively
  /// (UserDefaults / SharedPreferences) precisely so a Dart-side bug
  /// cannot rewrite it per call. Natively validates the same predicate
  /// `canBind` evaluates before storing; a refusal stores nothing.
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts);

  /// Clears the native-side binding copy (call alongside
  /// `HealthSyncBinding.unbind`).
  Future<void> unbindProfile();

  /// Prompts for write authorization for the types this port covers,
  /// behind the same guard (requesting HealthKit / Health Connect
  /// authorization is itself a health-API touch, so it is gated like a
  /// write). iOS's sheet has no programmatic denial answer — the OS
  /// reports completion, not the user's choice — so [allowed] there
  /// means "the prompt completed"; a denied permission surfaces on the
  /// first actual write as `permissionDenied`.
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  );

  /// Writes one day's menstrual flow sample for the bound profile.
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  );

  /// Writes one day's intermenstrual-bleeding record for the bound
  /// profile.
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  );

  /// Writes one period episode's interval record for the bound profile
  /// (Issue #202's `MenstruationPeriodRecord`). A platform with no
  /// period-record type — HealthKit encodes episode boundaries via
  /// menstrual-flow cycle-start metadata instead (#193) — answers
  /// `unavailable`, which the caller treats as a graceful skip, never a
  /// pass-blocking failure.
  Future<HealthPlatformResult> writeMenstrualPeriod(
    HealthMenstrualPeriodWrite write,
  );

  /// Writes one logged day's resolved symptom samples for the bound
  /// profile (Issue #238). The [HealthSymptomSamplesWrite.samples] carry
  /// already-resolved HealthKit type identifiers and severities — this
  /// port never contains the tag table. A platform with no symptom
  /// category types (Health Connect, permanently) answers `unavailable`,
  /// which the caller treats as a graceful skip, never a pass-blocking
  /// failure, exactly as it does for `writeMenstrualPeriod` on iOS.
  Future<HealthPlatformResult> writeSymptomSamples(
    HealthSymptomSamplesWrite write,
  );

  /// Writes one logged day's cervical-mucus appearance for the bound
  /// profile (Issue #228). Both platforms have a type here, so this is not
  /// the iOS-only asymmetry `writeSymptomSamples` is.
  Future<HealthPlatformResult> writeCervicalMucus(
    HealthCervicalMucusWrite write,
  );

  /// Writes one logged day's ovulation-test result for the bound profile
  /// (Issue #228). Both platforms have a type here.
  Future<HealthPlatformResult> writeOvulationTest(
    HealthOvulationTestWrite write,
  );

  /// Writes one logged day's basal body temperature for the bound profile
  /// (Issue #228). A quantity type on HealthKit, an instantaneous record on
  /// Health Connect. A value sourced from a wearable or a health platform
  /// never reaches this method — `resolveBasalBodyTemperature` filters by
  /// source before the write service ever builds the payload.
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  );

  /// Deletes the health-store samples whose recorded external id (Health
  /// Connect `clientRecordId` / HealthKit `HKMetadataKeyExternalUUID`)
  /// matches one of [recordIds] — the tombstone-propagation half of issue
  /// #186's sync mechanics: when a lunarlog entry is tombstoned, the
  /// corresponding health-store sample is removed rather than orphaned.
  ///
  /// Only samples this app itself saved can be deleted (HealthKit's
  /// `delete(_:withCompletion:)` constraint); a record that never made it to
  /// the store, or that the platform refuses to delete, reports
  /// [HealthPlatformResult.allowed] or [HealthPlatformResult.failed] like
  /// any other write — never throws. Behind the same guard as every write
  /// (a deletion is a health-API touch, so it is gated identically).
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  );
}
