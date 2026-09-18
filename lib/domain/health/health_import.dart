/// The read/import direction of the Health Platform Sync epic (Issue #217)
/// — the pure-Dart vocabulary for one user-initiated Apple Health import.
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
///   point is [AppleHealthImportRunner.importNow] — a settings action the
///   operator triggers.
/// * **Bounded window.** An import reads a fixed, documented number of
///   days back ([kAppleHealthImportWindowDays]); full-history and
///   background reads stay deferred (see `health_channel_codec.dart`'s
///   doc and #186's AC9).
/// * **Opaque read authorization.** HealthKit's
///   `authorizationStatus(for:)` never reveals a denied *read*, and a
///   denied read is indistinguishable from "no samples". [HealthReadResult]
///   therefore carries no "denied but non-empty" state, and
///   [AppleHealthImportSummary] deliberately records no
///   permission-denied-vs-no-data distinction — the UI must not invent
///   one.
/// * **Read-only for Apple's computed types.** The four cycle-deviation
///   category types (`irregularMenstrualCycles`,
///   `infrequentMenstrualCycles`, `prolongedMenstrualPeriods`,
///   `persistentIntermenstrualBleeding`) are Apple-computed, not
///   user-logged, and App Review 5.1.3 forbids writing derived data back
///   into HealthKit. This file's import only ever *reads* menstrual flow
///   into lunarlog; there is no read type that can be written, and the
///   write port's surface is unchanged.
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
const int kAppleHealthImportWindowDays = 30;

/// One menstrual-flow sample read from the OS health store, before it is
/// resolved to a lunarlog civil date.
///
/// [start]/[end] are absolute instants (the sample's own recorded times).
/// [tzName] is the sample's own IANA zone from HealthKit's
/// `HKMetadataKeyTimeZone` (see `day_boundary.dart`'s #180 import
/// contract) — never the device's current zone. It may be null for a
/// sample written without that metadata; such a sample cannot be placed on
/// a civil date without guessing, so the import service skips and counts
/// it rather than falling back to the device zone.
///
/// [recordId] is the sample's own UUID (HealthKit's stable sample id), used
/// as the imported day entry's `source_id` so re-importing the same sample
/// addresses the same row. [externalUuid] is `HKMetadataKeyExternalUUID`
/// when present — the id lunarlog stamps on its own writes (#186), carried
/// through for diagnostics. Echo prevention itself is [HealthImportSource]'s
/// mandatory implementation duty: the native query excludes any sample whose
/// recording source is this app (HealthKit's `dataOrigin`), which is what
/// stops a write from being re-imported as new data.
class HealthFlowSample {
  const HealthFlowSample({
    required this.recordId,
    required this.flow,
    required this.start,
    required this.end,
    this.tzName,
    this.externalUuid,
  });

  final String recordId;
  final HealthFlowValue flow;
  final DateTime start;
  final DateTime end;
  final String? tzName;
  final String? externalUuid;
}

/// The typed outcome of one read query, mirroring [HealthPlatformResult]'s
/// platform-failure vocabulary but carrying the samples on success.
///
/// A denial of read access is deliberately NOT a distinct state: HealthKit
/// reports it as an empty result, so [HealthReadSamples] with an empty list
/// and any permission state are treated identically by every caller. The
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
  /// HealthKit for a denied read (it returns empty instead); carried so the
  /// port stays total on platforms that do report it.
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

/// The read half of the health-store port (Issue #217) — one method per
/// read data-type concept, mirroring [HealthPlatformStore]'s write shape.
/// The shared `lunarlog/health` adapter implements both; the Dart guard and
/// its native mirror apply exactly as they do to a write, because reading
/// the bound profile's health data is the same device-binding decision.
///
/// **Implementor contract:** evaluate `HealthSyncBinding.canWrite` first
/// (returning a refusal without touching the OS health store on a deny),
/// then forward the same guard facts so the native handler re-evaluates
/// the mirrored predicate against its own stored binding before issuing
/// the query — the same defense-in-depth property [HealthPlatformStore]
/// documents.
abstract interface class HealthImportSource {
  /// Reads menstrual-flow samples whose recorded interval intersects
  /// `[start]`–`[end]` (absolute instants) for the bound profile.
  ///
  /// Samples recorded by this app itself MUST be excluded by the
  /// implementation before they reach the caller (HealthKit's
  /// `dataOrigin`/source filtering): lunarlog's write path (#193) writes
  /// the user's logged flow into Apple Health, and re-importing those
  /// samples would duplicate every entry and loop the two directions.
  Future<HealthReadResult> readMenstrualFlow(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  });
}

/// What one user-initiated import pass did, in counts a summary can render
/// without re-reading anything. Deliberately carries no
/// permission-denied-vs-empty distinction (see the library doc).
class AppleHealthImportSummary {
  const AppleHealthImportSummary({
    this.bound = true,
    this.blocked,
    this.samplesRead = 0,
    this.daysWritten = 0,
    this.daysUnchanged = 0,
    this.daysKeptManual = 0,
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

  /// Samples skipped because they carried no IANA zone to resolve a civil
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
      samplesWithoutZone == 0 &&
      samplesUnsupported == 0;
}

/// The seam `lib/ui` drives for a user-initiated import. Implementations
/// own the binding guard, the bounded window, and the local-store merge;
/// the screen only renders the returned [AppleHealthImportSummary].
abstract interface class AppleHealthImportRunner {
  /// Runs one user-initiated import pass for the currently bound profile.
  Future<AppleHealthImportSummary> importNow();
}

/// The first civil day of the inclusive import window ending at [today]
/// — `today - (kAppleHealthImportWindowDays - 1)`.
LocalDate appleHealthImportWindowStart(LocalDate today) =>
    today.addDays(-(kAppleHealthImportWindowDays - 1));
