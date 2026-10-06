/// The OS health-store import service (Issues #217/#458, full-history in
/// #992) — the effectful half of the read direction,
/// mirroring `health_flow_write_service.dart`'s split between pure mapping
/// and an injected platform port. One shared pipeline reads Apple Health on
/// iOS and Health Connect on Android; the injected [HealthImportPlatform]
/// picks the provenance stamped on every written row.
///
/// **What it does, in order:**
///
/// 1. Resolves the one profile bound to this device (`HealthSyncBinding`,
///    #153) and pre-checks the same guard every write uses. A denied guard
///    ends the pass with a [HealthImportSummary.blocked], touching no
///    health API.
/// 2. Re-asserts the native binding mirror and requests authorization
///    through [HealthPlatformStore.requestImportAuthorization] — iOS asks
///    for both the write types and the menstrual-flow read type in the one
///    system sheet; Android asks Health Connect for the reads the import
///    performs and its two optional read extras, and for no write
///    permission (Issue #1515), so a user who has only ever imported
///    (never exported) is still prompted, and one who declined the writes
///    is not asked for them again by tapping Import.
/// 3. Reads menstrual-flow and intermenstrual-bleeding samples over the
///    **whole history** (Issue #992 — from [kHealthImportEarliestYear] to
///    tomorrow, ±1 day of slack so a sample in any zone is returned), one
///    *page* at a time. Each page is fetched through
///    [HealthImportSource.readMenstrualFlowPage] with an opaque cursor and
///    [kHealthImportPageSize]; the loop stops on a null cursor, on an
///    exhausted (empty) page, on a repeated cursor, or after
///    [kHealthImportMaxPages] pages — so no adapter bug can make it spin.
///    A page's samples are resolved to desired days (in a background
///    isolate once the page is large enough, see
///    [kHealthImportResolveOffloadThreshold]) and merged into a pass-wide
///    per-date accumulator, so the same day split across two pages still
///    resolves to its highest-intensity sample.
/// 4. Resolves each sample's civil date from the **sample's own** zone —
///    HealthKit's IANA `tzName`, or Health Connect's raw `offset`
///    (`day_boundary.dart`'s #180 import contract) — never the device's
///    current zone. The one bounded exception (Issue #902): when Apple's
///    Health app logs a menstruation sample by hand it carries no
///    `HKMetadataKeyTimeZone`, so the iOS read forwards this phone's own
///    offset at the sample's instant, flagged
///    ([HealthFlowSample.offsetInferred]); those rows are placed and counted
///    as device-zone rows, not skipped. Samples with no zone, no lunarlog
///    equivalent, or a date outside the window are counted, never guessed.
/// 5. Merges the highest-intensity flow per date into the bound profile's
///    day entries, using the additive rule the Clue importer established:
///    a value the user logged by hand is **never** overwritten, an unlogged
///    (`none`) day is upgraded, and an already-imported day is refreshed.
///    An intermenstrual-bleeding record becomes a `spotting` observation
///    (the inverse of the write side's A3-4 rule) unless the day already
///    carries a spotting observation, which is never overwritten. A re-run
///    is idempotent because every row carries its platform sample id as
///    `source_id` (#186's contract); "resumable" means exactly that — an
///    interrupted pass leaves the days it wrote in place and a fresh pass
///    recomputes the rest without duplicating anything.
/// 6. Every written row carries the platform's provenance
///    ([DayEntrySource.healthkit]/[DayEntrySource.healthConnect], and the
///    matching observation source) so the write path never echoes it back
///    into the OS store — the loop the two directions would otherwise form.
///
/// **Bound. Two entry points.** [importNow] is the user-initiated pass —
/// the only thing `lib/ui` calls, from an explicit Settings action, and
/// the only path that stamps a binding's first-import consent marker
/// (Issue #1215). Issue #993 adds [importInBackground]: the same pipeline
/// minus everything a background context must never do (no `bindProfile`
/// re-write, no authorization prompt — and, since Issue #1215, no read at
/// all until one [importNow] pass has completed for the current binding:
/// the first import is the person's to start). The OS permission is
/// *probed* — the read-side `importPermissionStatus` since Issue #1491,
/// not the write-side `permissionStatus` — and anything but `granted`
/// ends the pass before a single read. The platform triggers
/// behind it (an HKObserverQuery on iOS, a WorkManager job on Android —
/// see `health_background_import_service.dart`) are import-only: no
/// write, no UI, counts-only logging at the coordinator.
///
/// **Read-only for computed types.** This service reads menstrual flow and
/// intermenstrual bleeding only. Apple's four computed cycle-deviation
/// types are never read or written here, and nothing this service touches
/// can write any of them (the App Review 5.1.3 rule `health_channel.dart`'s
/// library doc states).
///
/// Pure Dart (R14/R16): repositories and the platform ports are injected
/// interfaces; time and "today" are injectable, so every branch runs under
/// `flutter test`. The one `dart:isolate` use is the pure page-resolution
/// offload; it lives behind the same top-level function a synchronous call
/// would use, so tests exercise the resolution logic directly.
library;

import 'dart:async' show Completer;
import 'dart:isolate' show Isolate;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/util/timezone.dart' show fixedOffsetZoneName;

import 'health_flow_mapping.dart';

// The service takes its collaborators as constructor parameters that are
// not initializing formals (private finals via the initializer list), the
// same declared pattern `health_flow_write_service.dart` uses.
// ignore_for_file: prefer_initializing_formals

/// How many samples a page must hold before its pure date resolution is
/// moved to a background isolate (Issue #992). Below it the isolate
/// spin-up costs more than the work; above it a multi-hundred-sample page
/// is real CPU work and belongs off the UI isolate — the same
/// threshold-shaped seam `import_screen.dart` uses for a large import file
/// (issue #140 review, item 10). Tests keep their pages small so the
/// resolution runs inline and deterministically.
const int kHealthImportResolveOffloadThreshold = 250;

/// The one flow sample chosen for a civil date: the highest-intensity flow
/// among the samples that resolved to it, plus the provenance the imported
/// row records.
class _DesiredSample {
  const _DesiredSample({
    required this.flow,
    required this.value,
    required this.recordId,
    required this.tzName,
    this.modifiedAt,
  });

  final FlowLevel flow;
  final HealthFlowValue value;

  /// When the store last changed the winning sample
  /// ([HealthFlowSample.modifiedAt]); null where it cannot be changed.
  final DateTime? modifiedAt;

  /// The winning sample's store id — the imported row's `source_id`, so a
  /// re-import of the same sample is idempotent.
  final String recordId;

  /// The winning sample's own zone (IANA name, or the fixed-offset
  /// designator a record with no IANA name resolves to — an Android record
  /// with only a raw offset, or an iOS sample placed from this phone's
  /// offset, #902), used as a new day entry's `tz`.
  final String tzName;
}

/// One intermenstrual-bleeding record resolved to a civil date (Issue
/// #458). Imported as a `spotting` observation; no intensity exists.
class _SpottingSample {
  const _SpottingSample({required this.recordId, required this.tz});

  final String recordId;
  final String tz;
}

/// The outcome of one date's merge, counted by [importNow].
enum _MergeOutcome { written, unchanged, keptManual }

/// The full-history read window, resolved once per pass.
class _Window {
  const _Window({required this.from, required this.to});

  /// Inclusive civil-date bounds the import keeps. [from] is
  /// [kHealthImportEarliestYear]'s first day, [to] is today — the whole
  /// history a store can hold.
  final LocalDate from;
  final LocalDate to;

  /// The zone-free absolute query lower bound (~1970), widened by a day so
  /// a sample in any zone is returned. The precise civil filter happens in
  /// the page resolver against each sample's own zone.
  DateTime get queryStart => DateTime.utc(from.year, from.month, from.day)
      .subtract(const Duration(days: 1));

  /// The absolute query upper bound: tomorrow's UTC civil date (today + 2,
  /// so today in any zone is included).
  DateTime get queryEnd =>
      DateTime.utc(to.year, to.month, to.day).add(const Duration(days: 2));
}

/// One page's pure resolution input (a named record so it is a single
/// sendable value for the isolate offload).
typedef _PageResolveRequest = ({
  List<HealthFlowSample> samples,
  LocalDate from,
  LocalDate to,
});

/// One page's pure resolution output: the winning flow day per date, the
/// spotting record per date, and the placement counts.
typedef _PageResolveResult = ({
  Map<LocalDate, _DesiredSample> flowDays,
  Map<LocalDate, _SpottingSample> spottingDays,
  int recordedZone,
  int deviceZone,
  int withoutZone,
  int unsupported,
});

/// The pure half of a page: maps every sample to a civil date using its OWN
/// zone, keeps the highest-intensity flow per in-window date, records one
/// spotting entry per intermenstrual-bleeding date, and counts the ones
/// that could not be placed. Top-level and side-effect-free so it can run
/// in a background isolate unchanged.
_PageResolveResult _resolvePage(_PageResolveRequest request) {
  final byDate = <LocalDate, _DesiredSample>{};
  final spottingByDate = <LocalDate, _SpottingSample>{};
  var withoutZone = 0;
  var unsupported = 0;
  var recordedZone = 0;
  var deviceZone = 0;
  // Counts a usable in-window sample by how its date was resolved (#902):
  // from a zone the source recorded, or from this phone's own offset. Only
  // samples that actually yield a placed row (or a spotting observation)
  // are counted — an unsupported flow is already counted by [unsupported]
  // and is not also reported as placed.
  void countZone(HealthFlowSample sample) {
    if (_usedDeviceZone(sample)) {
      deviceZone++;
    } else {
      recordedZone++;
    }
  }

  for (final sample in request.samples) {
    final date = _dateFor(sample);
    if (date == null) {
      withoutZone++;
      continue;
    }
    if (date.isBefore(request.from) || date.isAfter(request.to)) continue;
    if (sample.kind == HealthSampleKind.intermenstrualBleeding) {
      countZone(sample);
      spottingByDate.putIfAbsent(
        date,
        () => _SpottingSample(
          recordId: sample.recordId,
          // Non-null: _dateFor already proved a zone resolves.
          tz: _zoneNameFor(sample)!,
        ),
      );
      continue;
    }
    final value = sample.flow!;
    final flow = flowLevelFromHealthValue(value);
    if (flow == null) {
      unsupported++;
      continue;
    }
    countZone(sample);
    final current = byDate[date];
    if (current == null ||
        healthFlowValueRank(value) > healthFlowValueRank(current.value)) {
      byDate[date] = _DesiredSample(
        flow: flow,
        value: value,
        recordId: sample.recordId,
        // Non-null: _dateFor already proved a zone resolves.
        tzName: _zoneNameFor(sample)!,
        modifiedAt: sample.modifiedAt,
      );
    }
  }
  return (
    flowDays: byDate,
    spottingDays: spottingByDate,
    recordedZone: recordedZone,
    deviceZone: deviceZone,
    withoutZone: withoutZone,
    unsupported: unsupported,
  );
}

/// Resolves one page on a background isolate when it is large enough to be
/// worth the spin-up, inline otherwise (Issue #992).
Future<_PageResolveResult> _resolvePageOffThread(_PageResolveRequest request) {
  if (request.samples.length >= kHealthImportResolveOffloadThreshold) {
    return Isolate.run(() => _resolvePage(request));
  }
  return Future.value(_resolvePage(request));
}

/// Whether [sample]'s civil date is resolved from this phone's own zone
/// (Issue #902) rather than from a zone the source recorded. Only the iOS
/// read ever sets [HealthFlowSample.offsetInferred]; a recorded IANA name
/// still wins over the flag (the #180 contract).
bool _usedDeviceZone(HealthFlowSample sample) =>
    sample.offsetInferred && (sample.tzName == null || sample.tzName!.isEmpty);

/// The sample's civil date in its own recorded zone, or null when it has no
/// zone (or one this build cannot resolve) — never the device's current
/// zone. A sample with no IANA name but a non-null [offset] is placed from
/// that offset: for Health Connect that is the record's own zone, and for an
/// iOS sample the read forwarded this phone's offset (Issue #902,
/// [HealthFlowSample.offsetInferred]). Menstrual flow is a whole-day
/// category sample, so if the phone's zone has since changed the inferred
/// date can be off by at most one day, and only near local midnight — a
/// deliberate, bounded tradeoff.
LocalDate? _dateFor(HealthFlowSample sample) {
  final tzName = sample.tzName;
  if (tzName != null && tzName.isNotEmpty) {
    try {
      return localDateForSample(sample.start, tzName: tzName);
    } on TimeZoneResolutionException {
      return null;
    }
  }
  final offset = sample.offset;
  if (offset == null) return null;
  return localDateForSample(sample.start, offset: offset);
}

/// The zone string a written row carries: the sample's own IANA name when it
/// has one (iOS), otherwise a fixed-offset designator derived from its raw
/// offset (Health Connect records, and an iOS sample whose date came from
/// this phone's offset — #902). The fixed-offset form is what keeps an
/// imported `(local_date, tz)` pair internally consistent without inventing
/// a device zone.
String? _zoneNameFor(HealthFlowSample sample) {
  final tzName = sample.tzName;
  if (tzName != null && tzName.isNotEmpty) return tzName;
  final offset = sample.offset;
  if (offset == null) return null;
  return fixedOffsetZoneName(offset);
}

/// The concrete [HealthImportRunner]. Never throws on an expected failure
/// mode — every one becomes a [HealthImportSummary.blocked]; unexpected
/// storage errors propagate, matching the write service's contract.
/// Decomposed into one private method per stage so each stays under the
/// quality gate's CRAP ceiling.
class LocalHealthImportService
    implements HealthImportRunner, HealthBackgroundImportRunner {
  LocalHealthImportService({
    required HealthImportPlatform importPlatform,
    required HealthPlatformStore platform,
    required HealthImportSource source,
    required HealthSyncBinding binding,
    required bool minorBindingAllowed,
    required ProfilesRepository profiles,
    required DayEntriesRepository dayEntries,
    required ObservationsRepository observations,
    required GuardiansForProfile guardiansForProfile,
    required String? Function() signedInUserId,
    LocalDate Function()? today,
    DateTime Function()? now,
  }) : _importPlatform = importPlatform,
       _platform = platform,
       _source = source,
       _binding = binding,
       _minorBindingAllowed = minorBindingAllowed,
       _profiles = profiles,
       _dayEntries = dayEntries,
       _observations = observations,
       _deletedDays = dayEntries is DeletedDayEntryReader
           ? dayEntries as DeletedDayEntryReader
           : null,
       _guardiansForProfile = guardiansForProfile,
       _signedInUserId = signedInUserId,
       _today = today ?? LocalDate.today,
       _now = now ?? (() => DateTime.now().toUtc());

  final HealthImportPlatform _importPlatform;
  final HealthPlatformStore _platform;
  final HealthImportSource _source;
  final HealthSyncBinding _binding;
  final bool _minorBindingAllowed;
  final ProfilesRepository _profiles;
  final DayEntriesRepository _dayEntries;
  final ObservationsRepository _observations;

  /// Issue #1561: what she deleted, where the repository can say. Null
  /// for one that cannot (a test double), and the import then inserts as
  /// it always did.
  final DeletedDayEntryReader? _deletedDays;

  /// The health-store records she deleted, named
  /// `healthImportDeletionId(source, sourceId)`, each with the moment of
  /// its deletion. Read when a pass's merge starts ([_apply]) and again
  /// before anything new is written ([_loadDeleted]).
  Map<String, DateTime> _deleted = {};

  /// Records this pass found on a live row although [_deleted] named
  /// them, with the moment that was read for each: the deletion was
  /// undone. Forgotten when the pass ends ([_forgetUndone]).
  final Map<String, DateTime> _undone = {};
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;
  final LocalDate Function() _today;
  final DateTime Function() _now;

  @override
  HealthImportPlatform get platform => _importPlatform;

  /// The `day_entries.source` this platform's imports carry.
  DayEntrySource get _daySource =>
      _importPlatform == HealthImportPlatform.healthConnect
          ? DayEntrySource.healthConnect
          : DayEntrySource.healthkit;

  /// The `observations.source` this platform's imports carry.
  ObservationSource get _observationSource =>
      _importPlatform == HealthImportPlatform.healthConnect
          ? ObservationSource.healthConnect
          : ObservationSource.appleHealth;

  @override
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  }) async {
    final bound = await _resolveBound();
    if (bound == null) return const HealthImportSummary(bound: false);

    final check = await _binding.canWrite(
      profile: bound.profile,
      signedInUserId: bound.facts.signedInUserId,
      ownerUserId: bound.facts.ownerUserId,
      minorBindingAllowed: _minorBindingAllowed,
    );
    if (!check.isAllowed) {
      return HealthImportSummary(
        blocked: HealthPlatformResult.refused(check),
      );
    }

    // Keep the native-side binding mirror in step, then prompt through the
    // import's own request (Issue #1515): what the import reads, and on
    // Android no write permission. It used to prompt through the write
    // path's request, which carries everything, so someone who had allowed
    // reading and declined writing was asked for the writes again on every
    // tap of Import. On iOS it is still that one sheet (see the port's doc).
    final blocked =
        _notAllowed(await _platform.bindProfile(bound.facts)) ??
        _notAllowed(await _platform.requestImportAuthorization(bound.facts));
    if (blocked != null) return HealthImportSummary(blocked: blocked);

    final summary = await _runPass(bound, onProgress);
    // Issue #1215: a completed pass is the consent the background gate
    // reads — the person started this import themselves. A pass blocked
    // before its read (guard, authorization, platform) stamps nothing, so
    // a first import that never actually ran never opens the gate; a
    // late-page failure ends in a blocked summary too, and the screen
    // already asks for a re-run in exactly that case.
    if (!summary.isBlocked) await _binding.markFirstImportCompleted();
    return summary;
  }

  @override
  Future<bool> pastDataSwitchOffered() => _source.pastDataSwitchOffered();

  /// Issue #1573. The port's own guard decides whether anything may be
  /// asked; what it answers is not used, because it does not say what was
  /// granted (see [HealthImportSource.requestPastDataAccess]). What counts
  /// is whether a read reaches the older data once the prompt has gone,
  /// and that is asked whether or not anything could be raised.
  @override
  Future<bool> requestPastDataAccess() async {
    final bound = await _resolveBound();
    if (bound != null) await _source.requestPastDataAccess(bound.facts);
    return _platform.importReachesPastData();
  }

  @override
  Future<HealthImportSummary> importInBackground() async {
    final bound = await _resolveBound();
    if (bound == null) return const HealthImportSummary(bound: false);

    final check = await _binding.canWrite(
      profile: bound.profile,
      signedInUserId: bound.facts.signedInUserId,
      ownerUserId: bound.facts.ownerUserId,
      minorBindingAllowed: _minorBindingAllowed,
    );
    if (!check.isAllowed) {
      return HealthImportSummary(
        blocked: HealthPlatformResult.refused(check),
      );
    }

    // Issue #1215: the first import is the person's to start. Until one
    // user-initiated pass has completed for this binding, any trigger —
    // HealthKit's own first fire on a fresh observer, a launch-time
    // delivery, a WorkManager tick — is a silent no-op: no probe, no read,
    // no write. Without this gate the store's whole history would land in
    // the profile on the next launch after binding, before the person ever
    // tapped Import. Unbinding or re-binding clears the marker with the
    // binding, so consent always belongs to the current one.
    if (!await _binding.hasCompletedFirstImport()) {
      return const HealthImportSummary(firstImportNotStarted: true);
    }

    // Issue #993: a background pass probes the OS permission and stops
    // before any read unless it is granted. It must never prompt — no
    // `bindProfile` re-write, no authorization request of either kind — so
    // a trigger on a device that never granted the reads (`notAsked`) or
    // that had them removed (`denied`) is a silent no-op.
    //
    // Issue #1491: the probe is the READ-side one. This used to be the
    // write-side `permissionStatus`, so someone who let lunarlog read from
    // Health Connect but not write to it had a working Import button and a
    // background import that never ran. On Android the read-side probe
    // answers for the two record reads this pass performs. On iOS it
    // cannot — HealthKit never discloses read access — so there it is
    // still the write (share) types, and an iPhone that may read but not
    // write skips background passes; the Health sync screen says so.
    if (await _platform.importPermissionStatus() !=
        HealthPermissionStatus.granted) {
      return const HealthImportSummary(
        blocked: HealthPlatformPermissionDenied(),
      );
    }

    return _runPass(bound, null);
  }

  /// The tail of the last pass that ran on this service (issue #1212).
  /// Both entry points — the Settings tap and the background coordinator —
  /// ride this one shared instance (see `buildHealthImportSeams`), and
  /// both funnel through [_runPass], so this chain is the one place their
  /// passes can be kept from interleaving: each pass awaits the previous
  /// pass's FULL completion (including every `_mergeSpotting` read-then-
  /// save window) before its own first read starts. The coordinator's own
  /// overlapping-trigger drop only sees background-vs-background; a
  /// trigger that lands while the user's `importNow` pass is mid-flight
  /// would otherwise interleave with it. The tail never completes with an
  /// error: a failed pass releases it through `whenComplete`, and its
  /// error goes only to its own caller.
  Future<void> _passTail = Future<void>.value();

  /// The pass body both entry points share, serialized on [_passTail]:
  /// one pass at a time on this service. Everything prompt-shaped stays
  /// in the entry points (which run before the queue is joined — the
  /// guard, the binding mirror, and the permission probe are read-free
  /// and race-free).
  Future<HealthImportSummary> _runPass(
    ({Profile profile, HealthGuardFacts facts}) bound,
    void Function(HealthImportProgress progress)? onProgress,
  ) {
    final previous = _passTail;
    final released = Completer<void>();
    _passTail = released.future;
    return previous
        .then((_) => _runPassSteps(bound, onProgress))
        .whenComplete(released.complete);
  }

  /// The unsynchronized pipeline steps [_runPass] serializes: the
  /// full-history window, the paged read, and the never-overwrite merge.
  Future<HealthImportSummary> _runPassSteps(
    ({Profile profile, HealthGuardFacts facts}) bound,
    void Function(HealthImportProgress progress)? onProgress,
  ) async {
    final window = _window();
    final run = await _readPages(bound.facts, window, onProgress);
    final early = run.earlySummary;
    if (early != null) return early;
    final summary = await _apply(
      bound.profile.id,
      run.accumulator,
      run.lateBlocked,
    );
    // Issue #1560: commit the read position only after days are stored.
    if (!summary.isBlocked && run.commitToken != null) {
      await _source.commitImport(bound.facts, run.commitToken!);
    }
    return summary;
  }

  /// Fetches pages until the cursor is exhausted, a page cannot advance, or
  /// [kHealthImportMaxPages] is reached, accumulating resolved days as it
  /// goes. A platform outcome ends the pass: on the first page it is
  /// returned whole ([_PageRun.earlySummary]); after earlier pages were read
  /// those days are still merged and only the outcome rides along
  /// ([_PageRun.lateBlocked]).
  Future<_PageRun> _readPages(
    HealthGuardFacts facts,
    _Window window,
    void Function(HealthImportProgress progress)? onProgress,
  ) async {
    final accumulator = _Accumulator();
    String? cursor;
    String? commitToken;
    final seenCursors = <String>{};
    while (true) {
      if (accumulator.pagesRead >= kHealthImportMaxPages) {
        accumulator.pageLimitReached = true;
        break;
      }
      final read = await _source.readMenstrualFlowPage(
        facts,
        start: window.queryStart,
        end: window.queryEnd,
        pageSize: kHealthImportPageSize,
        cursor: cursor,
      );
      if (read is! HealthReadSamples) {
        return _outcomeRun(accumulator, read);
      }
      accumulator.pagesRead++;
      accumulator.samplesRead += read.samples.length;
      accumulator.incremental |= read.incremental;
      accumulator.addPage(
        await _resolvePageOffThread(
          (samples: read.samples, from: window.from, to: window.to),
        ),
      );
      onProgress?.call(accumulator.progress);
      final next = read.nextCursor;
      if (next == null) {
        commitToken = read.commitToken;
        break;
      }
      if (next == cursor || seenCursors.contains(next)) {
        accumulator.repeatedCursor = true;
        break;
      }
      seenCursors.add(next);
      cursor = next;
    }
    return _PageRun(accumulator: accumulator, commitToken: commitToken);
  }

  /// Wraps a platform outcome per the first-page rule described on
  /// [_readPages].
  _PageRun _outcomeRun(_Accumulator accumulator, HealthReadResult read) {
    if (accumulator.pagesRead == 0) {
      return _PageRun(accumulator: accumulator, earlySummary: _blockedFor(read));
    }
    return _PageRun(
      accumulator: accumulator,
      lateBlocked: _blockedFor(read).blocked,
    );
  }

  /// The full-history window: 1970-01-01 through today. Not a fixed day
  /// count any more (Issue #992); the loop's page cap, not the window, is
  /// what bounds the pass.
  _Window _window() =>
      _Window(from: LocalDate(kHealthImportEarliestYear, 1, 1), to: _today());

  /// The bound profile plus its guard facts, or null when health sync is
  /// off for this device or the bound profile no longer resolves.
  Future<({Profile profile, HealthGuardFacts facts})?> _resolveBound() async {
    final profileId = await _binding.boundProfileId();
    if (profileId == null) return null;
    final profile = await _profiles.findById(profileId);
    if (profile == null) return null;
    final facts = HealthGuardFacts(
      profile: profile,
      signedInUserId: _signedInUserId(),
      ownerUserId: ownerUserIdFor(await _guardiansForProfile(profileId)),
    );
    return (profile: profile, facts: facts);
  }

  /// Merges the accumulated per-date desired rows into the bound profile's
  /// live entries and assembles the summary. [blocked] rides along when a
  /// later page returned a platform outcome after earlier pages had already
  /// been read.
  Future<HealthImportSummary> _apply(
    String profileId,
    _Accumulator accumulator,
    HealthPlatformResult? blocked,
  ) async {
    // A pass that failed part-way leaves nothing behind for this one.
    _undone.clear();
    await _loadDeleted(profileId);
    // Day-level sets, so a date whose flow merge and spotting merge land in
    // different outcomes is counted once per outcome rather than twice.
    final writtenDays = <LocalDate>{};
    final unchangedDays = <LocalDate>{};
    final keptManualDays = <LocalDate>{};
    final spottingDays = <LocalDate>{};
    for (final entry in accumulator.flowDays.entries) {
      switch (await _mergeDay(profileId, entry.key, entry.value)) {
        case _MergeOutcome.written:
          writtenDays.add(entry.key);
        case _MergeOutcome.unchanged:
          unchangedDays.add(entry.key);
        case _MergeOutcome.keptManual:
          keptManualDays.add(entry.key);
      }
    }
    for (final entry in accumulator.spottingDays.entries) {
      switch (await _mergeSpotting(profileId, entry.key, entry.value)) {
        case _MergeOutcome.written:
          spottingDays.add(entry.key);
        case _MergeOutcome.unchanged:
          unchangedDays.add(entry.key);
        case _MergeOutcome.keptManual:
          keptManualDays.add(entry.key);
      }
    }
    await _forgetUndone(profileId);
    return HealthImportSummary(
      blocked: blocked,
      samplesRead: accumulator.samplesRead,
      daysWritten: writtenDays.length,
      daysUnchanged: unchangedDays.length,
      daysKeptManual: keptManualDays.length,
      spottingDaysWritten: spottingDays.length,
      samplesFromRecordedZone: accumulator.recordedZone,
      samplesFromDeviceZone: accumulator.deviceZone,
      samplesWithoutZone: accumulator.withoutZone,
      samplesUnsupported: accumulator.unsupported,
      pagesRead: accumulator.pagesRead,
      pageLimitReached: accumulator.pageLimitReached,
      repeatedCursor: accumulator.repeatedCursor,
      incremental: accumulator.incremental,
    );
  }

  /// Maps a non-sample [read] to the matching blocked summary, with a
  /// denied read coalesced into the neutral empty one (HealthKit never
  /// reports a denied read — it returns an empty sample list — and Health
  /// Connect's denial is deliberately treated the same way).
  HealthImportSummary _blockedFor(HealthReadResult read) => switch (read) {
    HealthReadSamples() => const HealthImportSummary(),
    HealthReadRefused(:final check) => HealthImportSummary(
      blocked: HealthPlatformResult.refused(check),
    ),
    HealthReadUnavailable() => const HealthImportSummary(
      blocked: HealthPlatformUnavailable(),
    ),
    HealthReadPermissionDenied() => const HealthImportSummary(),
    HealthReadFailed(:final message) => HealthImportSummary(
      blocked: HealthPlatformResult.failed(message),
    ),
  };

  /// Merges one date's imported flow into the bound profile's live entry:
  ///
  /// * the store's record is one she deleted, unchanged since → nothing
  ///   is written ([_deletedUnchanged], Issue #1561);
  /// * no live row → insert with this platform's provenance
  ///   ([_insertDay]);
  /// * same flow → no-op;
  /// * a day whose flow did not come from this store, with no flow
  ///   (`none`) → adopt the imported flow, preserving the row's
  ///   tags/note/PMS;
  /// * a day this importer wrote, when the store's record for the day is
  ///   not the one the row was written from ([_storeChangedSince]) →
  ///   adopt the new value;
  /// * anything else → keep what is there ([_MergeOutcome.keptManual]):
  ///   the import never overwrites what the user typed, and that
  ///   includes a correction she made to a day it imported.
  ///
  /// Every row it writes carries a [_recordKey]: which record it saw.
  Future<_MergeOutcome> _mergeDay(
    String profileId,
    LocalDate date,
    _DesiredSample desired,
  ) async {
    final existing = await _dayEntries.find(profileId, date);
    if (existing != null) {
      _seenLive(existing.source.toDb(), existing.sourceId);
    }
    if (_deletedUnchanged(desired)) {
      // Nothing is written: not the day, and not this record's key onto
      // a row logged there since. It is asked for a day with a live row
      // too: she may have deleted the imported day and then logged only
      // a symptom on it, and the import must not fill that day's empty
      // flow from the record she deleted.
      return existing != null && existing.flow == desired.flow
          ? _MergeOutcome.unchanged
          : _MergeOutcome.keptManual;
    }
    if (existing == null) return _insertDay(profileId, date, desired);
    final key = _recordKey(desired);
    if (existing.flow == desired.flow) {
      await _remember(existing, desired, kept: false);
      return _MergeOutcome.unchanged;
    }
    if (!_mayAdopt(existing, desired)) {
      await _remember(existing, desired, kept: true);
      return _MergeOutcome.keptManual;
    }

    // `copyWith` preserves tags/note/PMS; provenance flips to this platform
    // so the write path never echoes this value back into the OS store.
    await _dayEntries.save(
      existing.copyWith(
        flow: desired.flow,
        source: _daySource,
        sourceId: key,
      ),
    );
    return _MergeOutcome.written;
  }

  /// Writes the day for a record that has no live row.
  ///
  /// What she deleted is read again first (Issue #1561). She may have
  /// deleted this very day since the pass began, in which case it has no
  /// live row for that reason, and writing it would undo a deletion made
  /// a moment ago.
  Future<_MergeOutcome> _insertDay(
    String profileId,
    LocalDate date,
    _DesiredSample desired,
  ) async {
    await _loadDeleted(profileId);
    if (_deletedUnchanged(desired)) return _MergeOutcome.keptManual;
    await _dayEntries.save(
      DayEntry(
        id: '',
        profileId: profileId,
        localDate: date,
        tz: desired.tzName,
        flow: desired.flow,
        source: _daySource,
        sourceId: _recordKey(desired),
        updatedAt: _now(),
      ),
    );
    return _MergeOutcome.written;
  }

  /// Reads what she deleted afresh, less the records this pass has found
  /// live again: each of those has had its turn in this pass.
  Future<void> _loadDeleted(String profileId) async {
    final read = await _deletedDays?.deletedHealthRecords(profileId);
    _deleted = {...?read}..removeWhere((id, _) => _undone.containsKey(id));
  }

  /// Forgets the deletions this pass found undone ([_seenLive]).
  Future<void> _forgetUndone(String profileId) async {
    if (_undone.isEmpty) return;
    await _deletedDays?.forgetDeletedHealthRecords(profileId, {..._undone});
    _undone.clear();
  }

  /// A live row carries this record. If she had deleted it, the deletion
  /// has been undone: the day sheet's Undo saves the same row again, with
  /// the record it came from. From here on the record does not count as
  /// deleted, so a later change in the store is not held back by a
  /// deletion she took back.
  void _seenLive(String source, String? sourceId) {
    if (sourceId == null) return;
    final id = healthImportDeletionId(source, sourceId);
    final at = _deleted.remove(id);
    if (at != null) _undone[id] = at;
  }

  /// Whether the store is offering a record she deleted, unchanged since
  /// (Issue #1561). Her deletion holds for as long as the store keeps
  /// that record; a different record for the day, or the same one changed
  /// since, is the store's news and is imported: the rule a hand
  /// correction follows ([_storeChangedSince]).
  ///
  /// Found by its full key, the record is the same version. Found by the
  /// bare id a Health Connect row carried before the key held a time, it
  /// is unchanged unless the store says it changed after she deleted it.
  bool _deletedUnchanged(_DesiredSample desired) {
    final source = _daySource.toDb();
    final key = _recordKey(desired);
    if (_deleted.containsKey(healthImportDeletionId(source, key))) {
      return true;
    }
    if (key == desired.recordId) return false;
    final deletedAt =
        _deleted[healthImportDeletionId(source, desired.recordId)];
    if (deletedAt == null) return false;
    final modifiedAt = desired.modifiedAt;
    return modifiedAt == null || !modifiedAt.isAfter(deletedAt);
  }

  /// What an imported row's `sourceId` holds (Issue #1559): which of the
  /// store's records the row was written from. For HealthKit that is the
  /// sample's id, since a sample cannot be edited: a correction made in
  /// another app is a new sample. Health Connect changes a record in place
  /// and keeps its id, so there the key is the id, `@`, and the time the
  /// store last changed the record.
  ///
  /// It is deliberately not the flow. `sourceId` outlives the row's
  /// content: deleting a day clears its flow and leaves this column, on
  /// the phone, on the server and in every guardian's copy, so nothing
  /// about what was logged may be written into it.
  static String _recordKey(_DesiredSample desired) {
    final modifiedAt = desired.modifiedAt;
    if (modifiedAt == null) return desired.recordId;
    return '${desired.recordId}@${modifiedAt.millisecondsSinceEpoch}';
  }

  /// Whether the store's flow may replace [existing]'s.
  ///
  /// A row whose flow this store never supplied is hers: hand-logged,
  /// from another import, or a row the spotting import created to hang an
  /// observation on (this store's `source`, no `sourceId`). The import
  /// fills such a day in only when it has no flow.
  bool _mayAdopt(DayEntry existing, _DesiredSample desired) {
    final imported =
        existing.source == _daySource && existing.sourceId != null;
    if (!imported) return existing.flow == FlowLevel.none;
    return _storeChangedSince(existing, desired);
  }

  /// Whether the store's value for a day differs from [existing], a row
  /// this importer wrote, because the store changed, and not because she
  /// corrected the day in lunarlog (Issue #1559).
  ///
  /// The day sheet keeps an imported row's provenance through a hand edit,
  /// so `source` alone cannot tell the two apart, and adopting on it put
  /// the store's value back over her correction on every whole-history
  /// read: every Apple Health pass, and a Health Connect pass that is not
  /// changes-only. A day she cleared to `none` was refilled the same way.
  ///
  /// The store changed when the day's record is not the one the row was
  /// written from ([_recordKey]). The same record means the difference is
  /// her edit. The row's own `updatedAt` is no part of it: any edit moves
  /// that, a tag as much as a flow.
  ///
  /// One case has only `updatedAt` to go on: a Health Connect row from
  /// before the key carried the record's time. With the same record id,
  /// it is her edit unless the store says the record changed after the
  /// row did. The row gets its full key on that pass ([_remember]), so
  /// this runs once per row.
  static bool _storeChangedSince(DayEntry existing, _DesiredSample desired) {
    final stored = existing.sourceId;
    if (stored == _recordKey(desired)) return false;
    if (stored != desired.recordId) return true;
    final modifiedAt = desired.modifiedAt;
    return modifiedAt != null && modifiedAt.isAfter(existing.updatedAt);
  }

  /// Brings the [_recordKey] on a row this importer wrote up to date when
  /// its flow is left as it is, so the next pass compares against the
  /// record the store holds now.
  ///
  /// Without it, a day whose record was replaced by one with the same
  /// value would keep the old key, and a correction she made afterwards
  /// would look like the store's news on the next pass.
  ///
  /// [kept] is true when her flow was kept over a different one in the
  /// store. When the flows agree, a Health Connect row from before the key
  /// carried a time is left alone while its record id still matches:
  /// rewriting every imported day on the first whole-history pass after
  /// an update would be a burst of writes, and of sync traffic, that
  /// changes nothing.
  Future<void> _remember(
    DayEntry existing,
    _DesiredSample desired, {
    required bool kept,
  }) async {
    final stored = existing.sourceId;
    if (existing.source != _daySource || stored == null) return;
    final key = _recordKey(desired);
    if (stored == key) return;
    if (!kept && stored == desired.recordId) return;
    await _dayEntries.save(existing.copyWith(sourceId: key));
  }

  /// Merges one date's intermenstrual-bleeding record as a `spotting`
  /// observation (Issue #458) attached to that date's live day entry —
  /// created if absent. A day that already carries a spotting observation
  /// (a hand-logged one, or one this importer previously wrote) is never
  /// given a second: the datum is the observation's existence, so presence
  /// wins and the import reports unchanged/kept-manual.
  Future<_MergeOutcome> _mergeSpotting(
    String profileId,
    LocalDate date,
    _SpottingSample sample,
  ) async {
    final day = await _dayEntries.find(profileId, date);
    final spotting = await _liveSpotting(day);
    if (spotting.isNotEmpty) return _spottingAlreadyThere(spotting);
    // Issue #1561: a spotting entry she removed stays removed while the
    // store still holds the record it came from. Asked before anything is
    // written, so no empty day is made to hang it on, and read afresh,
    // since she may have removed it after the pass began.
    await _loadDeleted(profileId);
    final recordId = healthImportDeletionId(
      _observationSource.toDb(),
      sample.recordId,
    );
    if (_deleted.containsKey(recordId)) return _MergeOutcome.keptManual;
    final host = day ?? await _spottingHost(profileId, date, sample);
    await _observations.save(
      Observation(
        id: '',
        dayEntryId: host.id,
        profileId: profileId,
        localDate: date,
        tz: sample.tz,
        category: ObservationCategory.spotting,
        code: ObservationCategory.spotting.wireCode,
        source: _observationSource,
        sourceId: sample.recordId,
        updatedAt: _now(),
      ),
    );
    return _MergeOutcome.written;
  }

  /// The live spotting observations on [day]; none when there is no day.
  Future<List<Observation>> _liveSpotting(DayEntry? day) async {
    if (day == null) return const [];
    final existing = await _observations.listForDayEntryWithLegacyAlias(
      day.id,
    );
    return [
      for (final observation in existing)
        if (observation.category == ObservationCategory.spotting) observation,
    ];
  }

  /// The outcome for a day that already carries spotting: unchanged when
  /// this importer wrote it, kept when she logged it. One this importer
  /// wrote is live, whatever was remembered about its record
  /// ([_seenLive]).
  _MergeOutcome _spottingAlreadyThere(List<Observation> spotting) {
    var imported = false;
    for (final observation in spotting) {
      if (observation.source != _observationSource) continue;
      imported = true;
      _seenLive(observation.source.toDb(), observation.sourceId);
    }
    return imported ? _MergeOutcome.unchanged : _MergeOutcome.keptManual;
  }

  /// The day an imported spotting entry hangs on when the date has none:
  /// this platform's provenance, no flow, and no record of its own.
  Future<DayEntry> _spottingHost(
    String profileId,
    LocalDate date,
    _SpottingSample sample,
  ) =>
      _dayEntries.save(
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: date,
          tz: sample.tz,
          flow: FlowLevel.none,
          source: _daySource,
          updatedAt: _now(),
        ),
      );

  /// The pass-blocking outcome of [result], or null when it was allowed.
  static HealthPlatformResult? _notAllowed(HealthPlatformResult result) =>
      result is HealthPlatformAllowed ? null : result;
}

/// One pass's page-fetch result (Issue #992): the accumulated days, plus
/// the platform outcome that ended the pass — [earlySummary] when it
/// happened on the very first page (nothing was merged, so the whole
/// blocked summary is returned), [lateBlocked] when earlier pages had
/// already merged days (those are still applied and the outcome rides
/// along).
class _PageRun {
  _PageRun({
    required this.accumulator,
    this.earlySummary,
    this.lateBlocked,
    this.commitToken,
  });

  final _Accumulator accumulator;
  final HealthImportSummary? earlySummary;
  final HealthPlatformResult? lateBlocked;
  final String? commitToken;
}

/// The running per-date accumulator across pages (Issue #992). A page's
/// winning day per date merges in without a later page downgrading an
/// earlier one: flow keeps the highest intensity, spotting keeps the first
/// record seen.
class _Accumulator {
  final Map<LocalDate, _DesiredSample> flowDays = {};
  final Map<LocalDate, _SpottingSample> spottingDays = {};
  int recordedZone = 0;
  int deviceZone = 0;
  int withoutZone = 0;
  int unsupported = 0;
  int samplesRead = 0;
  int pagesRead = 0;
  bool pageLimitReached = false;
  bool repeatedCursor = false;

  /// Whether the pass read only what changed since the last import (Issue
  /// #1523). A pass is one or the other for all its pages.
  bool incremental = false;

  void addPage(_PageResolveResult page) {
    for (final entry in page.flowDays.entries) {
      final current = flowDays[entry.key];
      if (current == null ||
          healthFlowValueRank(entry.value.value) >
              healthFlowValueRank(current.value)) {
        flowDays[entry.key] = entry.value;
      }
    }
    for (final entry in page.spottingDays.entries) {
      spottingDays.putIfAbsent(entry.key, () => entry.value);
    }
    recordedZone += page.recordedZone;
    deviceZone += page.deviceZone;
    withoutZone += page.withoutZone;
    unsupported += page.unsupported;
  }

  HealthImportProgress get progress => HealthImportProgress(
    pagesRead: pagesRead,
    samplesRead: samplesRead,
    daysWritten: flowDays.length + spottingDays.length,
  );
}
