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
/// * **Full history, paged.** An import reads *everything the store will
///   return* for the bound profile (Issue #992 — the previous fixed 30-day
///   window was a sequencing choice, not a product rule), from
///   [kHealthImportEarliestYear] forward, one *page* at a time so no single
///   channel call or DB write grows with the whole history. Each page is
///   bounded by [kHealthImportPageSize], and a pass stops after at most
///   [kHealthImportMaxPages] pages so a misbehaving adapter cannot spin.
///   Background reads stay deferred (#156/A3-16).
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

import 'health_platform.dart';
import 'health_sync_policy.dart';

/// How many samples one *page* of a platform read asks for (Issue #992).
/// Sent across the `lunarlog/health` channel as `pageSize` so the native
/// halves use exactly this value rather than their own guess — a Dart test
/// pins the number actually sent, and both native halves read it from the
/// wire (a value that never crosses the boundary cannot drift).
const int kHealthImportPageSize = 500;

/// A hard upper bound on the number of pages one import pass will fetch
/// (Issue #992). With [kHealthImportPageSize] this caps a single pass at
/// 500,000 samples. A well-behaved adapter finishes when a page returns a
/// null cursor, so this bound only fires on a buggy or hostile one, which
/// is exactly why it exists: it makes "the import loop can never spin" a
/// property of this service rather than a property of the adapter.
const int kHealthImportMaxPages = 1000;

/// The first calendar year an import will consider. HealthKit and Health
/// Connect samples cannot predate the Unix epoch, and no real cycle history
/// does; the import's lower bound is the start of [kHealthImportEarliestYear]
/// rather than the epoch itself so the query window stays a readable civil
/// date.
const int kHealthImportEarliestYear = 1970;

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
  /// [nextCursor] is the opaque page cursor for the *next* page, or null
  /// when this was the last page.
  const factory HealthReadResult.samples(
    List<HealthFlowSample> samples, {
    String? nextCursor,
  }) = HealthReadSamples;

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
  const HealthReadSamples(this.samples, {this.nextCursor});

  final List<HealthFlowSample> samples;

  /// The opaque cursor the platform returned for the next page, or null
  /// when the read is exhausted. Opaque to Dart by design: an iOS anchor,
  /// a Health Connect page token, or a changes-stream token all ride the
  /// same field, and this service only ever compares one cursor to the
  /// next to prove progress (see [HealthImportRunner]).
  final String? nextCursor;
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

/// The read half of the health-store port (Issues #217/#458, paged in
/// #992) — one method per read data-type concept, mirroring
/// [HealthPlatformStore]'s write shape. The shared `lunarlog/health`
/// adapter implements both; the Dart guard and its native mirror apply
/// exactly as they do to a write, because reading the bound profile's
/// health data is the same device-binding decision.
///
/// **Implementor contract:** evaluate `HealthSyncBinding.canWrite` first
/// (returning a refusal without touching the OS health store on a deny),
/// then forward the same guard facts so the native handler re-evaluates
/// the mirrored predicate against its own stored binding before issuing
/// the query — the same defense-in-depth property [HealthPlatformStore]
/// documents.
abstract interface class HealthImportSource {
  /// Reads one page of menstrual-flow and intermenstrual-bleeding samples
  /// whose recorded interval intersects `[start]`–`[end]` (absolute
  /// instants) for the bound profile.
  ///
  /// **Paging contract (Issue #992), mandatory for every implementor:**
///
///  * A read is one *page* of at most `pageSize` samples. `cursor` is null
///    on the first call of a pass and opaque on every later one; the
///    implementation must return the cursor for the next page as
///    [HealthReadSamples.nextCursor], or null to mean "no more pages".
///  * An exhausted store MUST return an empty sample list with a null
///    cursor — never a repeated cursor, never a non-null cursor forever.
///  * A page whose raw results were all this app's own writes may be empty
///    *with* a non-null cursor (the page advanced, it just held nothing
///    importable); the service continues on a non-null cursor rather than
///    treating "no samples" as termination.
///  * The same cursor MUST never be returned twice for two different
///    pages; a well-behaved implementation advances or terminates. The
///    service additionally guards against a repeated cursor so a buggy
///    adapter cannot spin.
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
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
    this.pagesRead = 0,
    this.pageLimitReached = false,
    this.repeatedCursor = false,
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

  /// How many pages the pass fetched before it terminated (Issue #992).
  final int pagesRead;

  /// True when the pass stopped because it reached
  /// [kHealthImportMaxPages] rather than because a page ended the stream —
  /// a buggy adapter, not a normal completion. The days already resolved
  /// before the cap are still merged; the summary says so.
  final bool pageLimitReached;

  /// True when a page returned the same cursor it was given (or a cursor
  /// already seen this pass), so the service stopped rather than spin —
  /// a buggy adapter, not a normal completion.
  final bool repeatedCursor;

  /// Whether the pass ended before any read could run.
  bool get isBlocked => blocked != null;

  /// The headline count for the completion summary: days that gained a new
  /// or refreshed imported value ("Imported N days").
  int get importedDays => daysWritten;

  /// The headline count for the completion summary: days the import
  /// deliberately skipped because a value was already there — a hand-logged
  /// flow it must not overwrite, or an already-imported value it matched
  /// ("skipped M already logged").
  int get skippedAlreadyLoggedDays => daysUnchanged + daysKeptManual;

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

/// A mid-pass progress tick (Issue #992): how far a running import has
/// got, so a long full-history pass can show something other than a
/// spinner. Carries counts only, never sample content.
class HealthImportProgress {
  const HealthImportProgress({
    required this.pagesRead,
    required this.samplesRead,
    required this.daysWritten,
  });

  /// Pages fetched so far.
  final int pagesRead;

  /// Samples read so far (after own-source filtering).
  final int samplesRead;

  /// Days newly written or refreshed so far.
  final int daysWritten;
}

/// The seam `lib/ui` drives for a user-initiated import. Implementations
/// own the binding guard, the full-history window, and the local-store
/// merge; the screen only renders the returned [HealthImportSummary] and
/// whatever [HealthImportRunner.importNow]'s optional progress callback
/// reports.
abstract interface class HealthImportRunner {
  /// Which OS health store this runner reads from — drives the Settings
  /// copy's data-source name.
  HealthImportPlatform get platform;

  /// Runs one user-initiated import pass for the currently bound profile.
  ///
  /// [onProgress], when supplied, is invoked after each page with the
  /// running counts. It must never be assumed to fire (a one-page or empty
  /// import may finish before the first tick) and must never be awaited by
  /// the implementation.
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  });
}
