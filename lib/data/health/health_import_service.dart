/// The user-initiated OS health-store import service (Issues #217/#458,
/// full-history in #992) — the effectful half of the read direction,
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
///    through [HealthPlatformStore] — iOS asks for both the write types and
///    the menstrual-flow read type in the one system sheet, Android's
///    Health Connect sheet carries the write and read permission sets, so a
///    user who has only ever imported (never exported) is still prompted.
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
/// **Bound, never background.** There is no observer here and no timer; the
/// only way this runs is [importNow], which `lib/ui` calls from an explicit
/// Settings action. Background delivery stays deferred (#156/A3-16).
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

import 'dart:isolate' show Isolate;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_import.dart';
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
  });

  final FlowLevel flow;
  final HealthFlowValue value;

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
class LocalHealthImportService implements HealthImportRunner {
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

    // Keep the native-side binding mirror in step and prompt through the one
    // authorization path (which now requests the read types too) — a user
    // who has never enabled the write direction still gets the system sheet.
    final blocked =
        _notAllowed(await _platform.bindProfile(bound.facts)) ??
        _notAllowed(await _platform.requestWriteAuthorization(bound.facts));
    if (blocked != null) return HealthImportSummary(blocked: blocked);

    final window = _window();
    final run = await _readPages(bound.facts, window, onProgress);
    final early = run.earlySummary;
    if (early != null) return early;
    return _apply(bound.profile.id, run.accumulator, run.lateBlocked);
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
      accumulator.addPage(
        await _resolvePageOffThread(
          (samples: read.samples, from: window.from, to: window.to),
        ),
      );
      onProgress?.call(accumulator.progress);
      final next = read.nextCursor;
      if (next == null) break;
      if (next == cursor || seenCursors.contains(next)) {
        accumulator.repeatedCursor = true;
        break;
      }
      seenCursors.add(next);
      cursor = next;
    }
    return _PageRun(accumulator: accumulator);
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
  /// * no live row → insert with this platform's provenance;
  /// * same flow → no-op;
  /// * unlogged (`none`) day, or a day this importer previously wrote →
  ///   adopt the imported flow, preserving the row's tags/note/PMS;
  /// * a different human-logged flow → keep the human value
  ///   ([_MergeOutcome.keptManual]); the import never overwrites what the
  ///   user typed.
  Future<_MergeOutcome> _mergeDay(
    String profileId,
    LocalDate date,
    _DesiredSample desired,
  ) async {
    final existing = await _dayEntries.find(profileId, date);
    if (existing == null) {
      await _dayEntries.save(
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: date,
          tz: desired.tzName,
          flow: desired.flow,
          source: _daySource,
          sourceId: desired.recordId,
          updatedAt: _now(),
        ),
      );
      return _MergeOutcome.written;
    }
    if (existing.flow == desired.flow) return _MergeOutcome.unchanged;

    final canAdopt =
        existing.flow == FlowLevel.none || existing.source == _daySource;
    if (!canAdopt) return _MergeOutcome.keptManual;

    // `copyWith` preserves tags/note/PMS; provenance flips to this platform
    // so the write path never echoes this value back into the OS store.
    await _dayEntries.save(
      existing.copyWith(
        flow: desired.flow,
        source: _daySource,
        sourceId: desired.recordId,
      ),
    );
    return _MergeOutcome.written;
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
    final day = await _dayEntries.find(profileId, date) ??
        await _dayEntries.save(
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
    final existing = await _observations.listForDayEntryWithLegacyAlias(
      day.id,
    );
    final spotting = [
      for (final observation in existing)
        if (observation.category == ObservationCategory.spotting) observation,
    ];
    if (spotting.isNotEmpty) {
      return spotting.any((o) => o.source == _observationSource)
          ? _MergeOutcome.unchanged
          : _MergeOutcome.keptManual;
    }
    await _observations.save(
      Observation(
        id: '',
        dayEntryId: day.id,
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
  _PageRun({required this.accumulator, this.earlySummary, this.lateBlocked});

  final _Accumulator accumulator;
  final HealthImportSummary? earlySummary;
  final HealthPlatformResult? lateBlocked;
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
