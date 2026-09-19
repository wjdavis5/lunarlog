/// The read/import direction of the Health Platform Sync epic (Issues #217
/// and #458) — the pure-Dart vocabulary for one user-initiated import from
/// the device's OS health store (Apple Health on iOS, Health Connect on
/// Android).
///
/// **This file is where the write-only posture documented in
/// `health_platform.dart` ends, deliberately and for one direction only.**
/// The owner's decision in issue #781 reversed the app's write-only
/// commitment: lunarlog is a cycle-tracking app and may read health data.
/// To keep the write surface's safety property ("the only inputs the port
/// ever writes are the user's own logged values", the App Review 5.1.3
/// no-derived-values rule) checkable by inspection, the read capability
/// lives on a *separate* port ([HealthImportSource]) rather than being
/// bolted onto [HealthPlatformStore]. The import service depends on that
/// read port; nothing that constructs the write service can see it.
///
/// ## Invariants this file encodes
///
/// * **User-initiated only.** There is no observer, no background
///   delivery, and no automatic pass anywhere in this file. The only entry
///   point is [HealthImportRunner.importNow] — a settings action the
///   operator triggers.
/// * **Bounded window.** An import reads a fixed, documented number of
///   days back ([kHealthImportWindowDays]); full-history and background
///   reads stay deferred (see `health_channel_codec.dart`'s doc and #186's
///   AC9).
/// * **Resolve each sample's civil date from its own zone.** HealthKit
///   samples carry an IANA zone (`HKMetadataKeyTimeZone`) and Health
///   Connect records carry their own `zoneOffset`; a sample with neither is
///   skipped, never guessed from the device's current zone (see
///   [HealthFlowSample] and `day_boundary.dart`'s #180 contract). **One
///   bounded exception (Issue #902):** a sample entered by hand in Apple's
///   own Health app carries no `HKMetadataKeyTimeZone`, and the iOS read
///   forwards the *device's* offset at the sample's instant as a last
///   resort, flagged via [HealthFlowSample.offsetInferred] so the summary
///   can report those rows honestly as inferred rather than as skipped.
/// * **Opaque read authorization.** HealthKit's
///   `authorizationStatus(for:)` never reveals a denied *read*, and a
///   denied read is indistinguishable from "no samples"; Health Connect
///   can report a `SecurityException`, but [HealthImportSummary]
///   deliberately records no permission-denied-vs-no-data distinction —
///   the UI must not invent one.
/// * **Read-only for computed types.** Apple's four cycle-deviation
///   category types (`irregularMenstrualCycles`,
///   `infrequentMenstrualCycles`, `prolongedMenstrualPeriods`,
///   `persistentIntermenstrualBleeding`) are Apple-computed, not
///   user-logged, and App Review 5.1.3 forbids writing derived data back
///   into HealthKit. This file's import only ever *reads* user-recorded
///   menstrual flow and intermenstrual-bleeding records into lunarlog;
///   there is no read type that can be written, and the write port's
///   surface is unchanged.
///
/// Pure Dart (R14/R16): imports only the domain port vocabulary.
library;

import '../models/local_date.dart';
import 'health_platform.dart';
import 'health_sync_policy.dart';

/// How many civil days back one user-initiated import reads, inclusive of
/// today. The issue's v1 scope is a bounded, user-initiated pass; this
/// matches the 30-day window `health_channel_codec.dart` already documents
/// for Health Connect's v1 read limit and the Settings screen states it
/// plainly rather than silently truncating.
const int kHealthImportWindowDays = 30;

/// Which OS health-store record a [HealthFlowSample] came from. The shared
/// import pipeline handles both of Android's read data types; iOS currently
/// produces only [menstrualFlow] (#217's read set is the single menstrual
/// flow type).
enum HealthSampleKind {
  /// A `MenstruationFlowRecord` / `HKCategoryTypeSample` menstrual-flow
  /// sample, carrying a [HealthFlowSample.flow] intensity.
  menstrualFlow,

  /// An `IntermenstrualBleedingRecord` — bleeding outside a period
  /// episode. The record carries no intensity (the record's existence is
  /// the datum), so [HealthFlowSample.flow] is null. Imported as a
  /// `spotting` observation, the inverse of the write side's A3-4 rule
  /// (`health_flow_mapping.dart`'s `mapSpottingToHealthWrite`).
  intermenstrualBleeding;

  /// Parses the wire string; null when [raw] is not in the closed set. A
  /// null [raw] is the pre-#458 iOS payload (no `kind` key) and means
  /// [menstrualFlow] — only Android emits a kind today. The native sides
  /// build the string; Dart only ever reads it.
  static HealthSampleKind? fromWire(String? raw) => switch (raw) {
        null || 'menstrualFlow' => menstrualFlow,
        'intermenstrualBleeding' => intermenstrualBleeding,
        _ => null,
      };
}

/// One menstrual sample read from the OS health store, before it is
/// resolved to a lunarlog civil date.
///
/// [start]/[end] are absolute instants (the sample's own recorded times).
/// The sample's own zone rides exactly one of [tzName] (HealthKit's
/// `HKMetadataKeyTimeZone` IANA name) or [offset] (Health Connect's raw
/// `zoneOffset`) — never the device's current zone. A sample with neither
/// cannot be placed on a civil date without guessing, so the import service
/// skips and counts it rather than falling back to the device zone. The one
/// exception is [offsetInferred] (Issue #902): when the source recorded no
/// zone at all, the iOS read forwards the device's offset at the sample's
/// instant, flagged so the import summary counts that row as inferred from
/// this phone's zone instead of as its own recorded zone.
///
/// [recordId] is the sample's own store id (HealthKit's stable sample UUID,
/// Health Connect's platform `metadata.id`), used as the imported day
/// entry's `source_id` so re-importing the same sample addresses the same
/// row. [externalUuid] is `HKMetadataKeyExternalUUID` when present — the id
/// lunarlog stamps on its own writes (#186), carried through for
/// diagnostics. Echo prevention itself is [HealthImportSource]'s mandatory
/// implementation duty: each native query excludes any record whose
/// recording source is this app (HealthKit's `sourceRevision.source`, Health
/// Connect's `dataOrigin`), which is what stops a write from being
/// re-imported as new data.
class HealthFlowSample {
  const HealthFlowSample({
    required this.recordId,
    required this.start,
    required this.end,
    this.kind = HealthSampleKind.menstrualFlow,
    this.flow,
    this.tzName,
    this.offset,
    this.offsetInferred = false,
    this.externalUuid,
  }) : assert(
          kind == HealthSampleKind.intermenstrualBleeding || flow != null,
          'a menstrual-flow sample requires a flow value',
        );

  final String recordId;

  /// Which record type this sample is. See [HealthSampleKind].
  final HealthSampleKind kind;

  /// The flow intensity. Non-null for [HealthSampleKind.menstrualFlow]
  /// (asserted); null for [HealthSampleKind.intermenstrualBleeding], which
  /// has no intensity field at all.
  final HealthFlowValue? flow;

  final DateTime start;
  final DateTime end;

  /// The sample's own IANA zone (HealthKit). Exactly one of this or
  /// [offset] is present for a placeable sample.
  final String? tzName;

  /// The record's own recorded UTC offset (Health Connect), or — when
  /// [offsetInferred] is true — the device's offset at [start] used as a
  /// last-resort proxy (Issue #902). Exactly one of this or [tzName] is
  /// present for a placeable sample.
  final Duration? offset;

  /// Whether [offset] is the iPhone's own zone at [start] rather than a zone
  /// the source sample recorded (Issue #902). False for every Health Connect
  /// record, whose `zoneOffset` is the record's own; true only for an iOS
  /// sample the source recorded no `HKMetadataKeyTimeZone` for, where the
  /// date is nonetheless placed from this device's offset. Menstrual flow is
  /// a whole-day category sample, so an inferred offset can only shift the
  /// resolved civil date by at most one day, and only when this phone is in
  /// a different zone now than when the sample was logged.
  final bool offsetInferred;

  final String? externalUuid;
}

/// The typed outcome of one read query, mirroring [HealthPlatformResult]'s
/// platform-failure vocabulary but carrying the samples on success.
///
/// A denial of read access is deliberately NOT a distinct state: HealthKit
/// reports it as an empty result, and the import summary coalesces every
/// platform's denial signal into the same neutral state. The
/// [HealthReadRefused] case is a *device-binding* refusal (the Dart or
/// native guard denied the read), which is a different thing from the OS
/// withholding read permission.
sealed class HealthReadResult {
  const HealthReadResult();

  /// The query ran; [samples] is what the store returned (possibly empty).
  const factory HealthReadResult.samples(List<HealthFlowSample> samples) =
      HealthReadSamples;

  /// No health store exists on this device.
  const factory HealthReadResult.unavailable() = HealthReadUnavailable;

  /// The OS threw a permission error for the read. Never produced by
  /// HealthKit for a denied read (it returns empty instead); Health Connect
  /// does surface it as a `SecurityException`, but the import service
  /// coalesces it with the empty case deliberately.
  const factory HealthReadResult.permissionDenied() =
      HealthReadPermissionDenied;

  /// The device-binding guard refused the read; no health API was touched.
  const factory HealthReadResult.refused(HealthSyncCheck check) =
      HealthReadRefused;

  /// The platform threw or answered with something this Dart side does not
  /// understand. [message] is diagnostic, never user-facing.
  const factory HealthReadResult.failed(String message) = HealthReadFailed;
}

final class HealthReadSamples extends HealthReadResult {
  const HealthReadSamples(this.samples);

  final List<HealthFlowSample> samples;
}

final class HealthReadUnavailable extends HealthReadResult {
  const HealthReadUnavailable();
}

final class HealthReadPermissionDenied extends HealthReadResult {
  const HealthReadPermissionDenied();
}

final class HealthReadRefused extends HealthReadResult {
  const HealthReadRefused(this.check);

  final HealthSyncCheck check;
}

final class HealthReadFailed extends HealthReadResult {
  const HealthReadFailed(this.message);

  final String message;
}

/// Which OS health platform an import pass is reading from. Carried by the
/// runner so the Settings UI can name the right store ("Apple Health" /
/// "Health Connect") and the import service can stamp the right provenance
/// ([DayEntrySource.healthkit] / [DayEntrySource.healthConnect]) — one
/// shared pipeline, not two.
enum HealthImportPlatform {
  appleHealth,
  healthConnect;
}

/// The read half of the health-store port (Issues #217/#458) — one method
/// per read data-type concept, mirroring [HealthPlatformStore]'s write
/// shape. The shared `lunarlog/health` adapter implements both; the Dart
/// guard and its native mirror apply exactly as they do to a write, because
/// reading the bound profile's health data is the same device-binding
/// decision.
///
/// **Implementor contract:** evaluate `HealthSyncBinding.canWrite` first
/// (returning a refusal without touching the OS health store on a deny),
/// then forward the same guard facts so the native handler re-evaluates
/// the mirrored predicate against its own stored binding before issuing
/// the query — the same defense-in-depth property [HealthPlatformStore]
/// documents.
abstract interface class HealthImportSource {
  /// Reads menstrual-flow and intermenstrual-bleeding samples whose
  /// recorded interval intersects `[start]`–`[end]` (absolute instants)
  /// for the bound profile.
  ///
  /// Samples recorded by this app itself MUST be excluded by the
  /// implementation before they reach the caller (HealthKit's
  /// `sourceRevision.source.bundleIdentifier` / Health Connect's
  /// `dataOrigin` filtering): lunarlog's write path (#193/#202) writes the
  /// user's logged flow into the OS store, and re-importing those samples
  /// would duplicate every entry and loop the two directions.
  Future<HealthReadResult> readMenstrualFlow(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  });
}

/// What one user-initiated import pass did, in counts a summary can render
/// without re-reading anything. Deliberately carries no
/// permission-denied-vs-empty distinction (see the library doc).
class HealthImportSummary {
  const HealthImportSummary({
    this.bound = true,
    this.blocked,
    this.samplesRead = 0,
    this.daysWritten = 0,
    this.daysUnchanged = 0,
    this.daysKeptManual = 0,
    this.spottingDaysWritten = 0,
    this.samplesFromRecordedZone = 0,
    this.samplesFromDeviceZone = 0,
    this.samplesWithoutZone = 0,
    this.samplesUnsupported = 0,
  });

  /// False when no profile is bound to this device — the import action is
  /// a no-op rather than an error.
  final bool bound;

  /// The guard/platform refusal that ended the pass, or null when it ran.
  /// For a denial of read permission the platform returns an empty sample
  /// list instead (HealthKit's opacity), not this field.
  final HealthPlatformResult? blocked;

  /// How many samples the store returned for the window (after the
  /// implementation's own-source filtering).
  final int samplesRead;

  /// Days that gained or refreshed an imported flow value.
  final int daysWritten;

  /// Days already at the same imported value (a true no-op).
  final int daysUnchanged;

  /// Days whose human-logged flow differed and was deliberately kept.
  final int daysKeptManual;

  /// Days that gained an imported `spotting` observation from an
  /// intermenstrual-bleeding record (Issue #458).
  final int spottingDaysWritten;

  /// Samples placed on a civil date from the zone the source sample itself
  /// recorded (HealthKit's IANA `tzName`, or a Health Connect record's own
  /// `zoneOffset`) — the #180 contract's normal path.
  final int samplesFromRecordedZone;

  /// Samples placed on a civil date from this phone's own UTC offset at the
  /// sample's instant, because the source sample recorded no zone at all
  /// (Issue #902). Reported separately from [samplesFromRecordedZone] so the
  /// summary never presents an inferred date as a recorded one.
  final int samplesFromDeviceZone;

  /// Samples skipped because they carried no zone/offset to resolve a civil
  /// date from (never guessed from the device zone).
  final int samplesWithoutZone;

  /// Samples skipped because their flow value has no lunarlog equivalent
  /// (HealthKit's `unspecified`).
  final int samplesUnsupported;

  /// Whether the pass ended before any read could run.
  bool get isBlocked => blocked != null;

  /// Whether the store returned no usable samples at all — the neutral
  /// "nothing came back" state. Never phrased as "nothing was tracked" or
  /// "permission denied".
  bool get isEmpty =>
      !isBlocked &&
      samplesRead == 0 &&
      daysWritten == 0 &&
      daysUnchanged == 0 &&
      daysKeptManual == 0 &&
      spottingDaysWritten == 0 &&
      samplesFromRecordedZone == 0 &&
      samplesFromDeviceZone == 0 &&
      samplesWithoutZone == 0 &&
      samplesUnsupported == 0;
}

/// The seam `lib/ui` drives for a user-initiated import. Implementations
/// own the binding guard, the bounded window, and the local-store merge;
/// the screen only renders the returned [HealthImportSummary].
abstract interface class HealthImportRunner {
  /// Which OS health store this runner reads from — drives the Settings
  /// copy's data-source name.
  HealthImportPlatform get platform;

  /// Runs one user-initiated import pass for the currently bound profile.
  Future<HealthImportSummary> importNow();
}

/// The first civil day of the inclusive import window ending at [today]
/// — `today - (kHealthImportWindowDays - 1)`.
LocalDate healthImportWindowStart(LocalDate today) =>
    today.addDays(-(kHealthImportWindowDays - 1));
