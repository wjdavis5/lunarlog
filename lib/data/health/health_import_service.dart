/// The user-initiated Apple Health import service (Issue #217) — the
/// effectful half of the read direction, mirroring
/// `health_flow_write_service.dart`'s split between pure mapping and an
/// injected platform port.
///
/// **What it does, in order:**
///
/// 1. Resolves the one profile bound to this device (`HealthSyncBinding`,
///    #153) and pre-checks the same guard every write uses. A denied guard
///    ends the pass with a [AppleHealthImportSummary.blocked], touching no
///    health API.
/// 2. Re-asserts the native binding mirror and requests authorization
///    through [HealthPlatformStore] — iOS asks for both the write types and
///    the menstrual-flow read type in the one system sheet, so a user who
///    has only ever imported (never exported) is still prompted.
/// 3. Reads menstrual-flow samples over a bounded, widened query window
///    ([kAppleHealthImportWindowDays] civil days back, ±1 day of slack so a
///    sample in any zone is returned).
/// 4. Resolves each sample's civil date from the **sample's own** IANA zone
///    (`day_boundary.dart`'s #180 import contract) — never the device's
///    current zone. Samples with no zone, no lunarlog flow equivalent, or a
///    date outside the window are counted, never guessed.
/// 5. Merges the highest-intensity flow per date into the bound profile's
///    day entries, using the additive rule the Clue importer established:
///    a value the user logged by hand is **never** overwritten, an unlogged
///    (`none`) day is upgraded, and an already-imported day is refreshed.
///    Every written day carries [`DayEntrySource.healthkit`] provenance so
///    the write path (#193) never echoes it back into Apple Health — the
///    loop the two directions would otherwise form.
///
/// **Bound, never background.** There is no observer here and no timer; the
/// only way this runs is [importNow], which `lib/ui` calls from an explicit
/// Settings action. Background delivery stays deferred (#156/A3-16).
///
/// **Read-only for Apple's computed types.** This service reads menstrual
/// flow only. The four Apple-computed cycle-deviation types are never read
/// or written here, and nothing this service touches can write any of them
/// (the App Review 5.1.3 rule `health_channel.dart`'s library doc states).
///
/// Pure Dart (R14/R16): repositories and the platform ports are injected
/// interfaces; time and "today" are injectable, so every branch runs under
/// `flutter test`.
library;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';

import 'health_flow_mapping.dart';

// The service takes its collaborators as constructor parameters that are
// not initializing formals (private finals via the initializer list), the
// same declared pattern `health_flow_write_service.dart` uses.
// ignore_for_file: prefer_initializing_formals

/// The one sample chosen for a civil date: the highest-intensity flow among
/// the samples that resolved to it, plus the provenance the imported row
/// records.
class _DesiredSample {
  const _DesiredSample({
    required this.flow,
    required this.value,
    required this.recordId,
    required this.tzName,
  });

  final FlowLevel flow;
  final HealthFlowValue value;

  /// The winning sample's UUID — the imported row's `source_id`, so a
  /// re-import of the same sample is idempotent.
  final String recordId;

  /// The winning sample's own IANA zone, used as a new day entry's `tz`.
  final String tzName;
}

/// The outcome of one date's merge, counted by [importNow].
enum _MergeOutcome { written, unchanged, keptManual }

/// The bounded read window, resolved once per pass.
class _Window {
  const _Window({
    required this.from,
    required this.to,
    required this.queryStart,
    required this.queryEnd,
  });

  /// Inclusive civil-date bounds the import keeps.
  final LocalDate from;
  final LocalDate to;

  /// The zone-free absolute query bounds handed to the platform — widened a
  /// day either side of [from]/[to] so a sample in any zone inside the civil
  /// window is returned. The precise civil filter happens in [_resolveSamples]
  /// against each sample's own zone.
  final DateTime queryStart;
  final DateTime queryEnd;
}

/// One pass's sample resolution: the winning sample per in-window date, and
/// the counts of samples that could not be placed.
class _ResolvedSamples {
  const _ResolvedSamples({
    required this.byDate,
    required this.withoutZone,
    required this.unsupported,
  });

  final Map<LocalDate, _DesiredSample> byDate;
  final int withoutZone;
  final int unsupported;
}

/// The concrete [AppleHealthImportRunner]. Never throws on an expected
/// failure mode — every one becomes a [AppleHealthImportSummary.blocked];
/// unexpected storage errors propagate, matching the write service's
/// contract. Decomposed into one private method per stage so each stays
/// under the quality gate's CRAP ceiling.
class LocalAppleHealthImportService implements AppleHealthImportRunner {
  LocalAppleHealthImportService({
    required HealthPlatformStore platform,
    required HealthImportSource source,
    required HealthSyncBinding binding,
    required bool minorBindingAllowed,
    required ProfilesRepository profiles,
    required DayEntriesRepository dayEntries,
    required GuardiansForProfile guardiansForProfile,
    required String? Function() signedInUserId,
    LocalDate Function()? today,
    DateTime Function()? now,
  }) : _platform = platform,
       _source = source,
       _binding = binding,
       _minorBindingAllowed = minorBindingAllowed,
       _profiles = profiles,
       _dayEntries = dayEntries,
       _guardiansForProfile = guardiansForProfile,
       _signedInUserId = signedInUserId,
       _today = today ?? LocalDate.today,
       _now = now ?? (() => DateTime.now().toUtc());

  final HealthPlatformStore _platform;
  final HealthImportSource _source;
  final HealthSyncBinding _binding;
  final bool _minorBindingAllowed;
  final ProfilesRepository _profiles;
  final DayEntriesRepository _dayEntries;
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;
  final LocalDate Function() _today;
  final DateTime Function() _now;

  @override
  Future<AppleHealthImportSummary> importNow() async {
    final bound = await _resolveBound();
    if (bound == null) return const AppleHealthImportSummary(bound: false);

    final check = await _binding.canWrite(
      profile: bound.profile,
      signedInUserId: bound.facts.signedInUserId,
      ownerUserId: bound.facts.ownerUserId,
      minorBindingAllowed: _minorBindingAllowed,
    );
    if (!check.isAllowed) {
      return AppleHealthImportSummary(
        blocked: HealthPlatformResult.refused(check),
      );
    }

    // Keep the native-side binding mirror in step and prompt through the one
    // authorization path (which now requests the read type too) — a user who
    // has never enabled the write direction still gets the system sheet.
    final blocked =
        _notAllowed(await _platform.bindProfile(bound.facts)) ??
        _notAllowed(await _platform.requestWriteAuthorization(bound.facts));
    if (blocked != null) return AppleHealthImportSummary(blocked: blocked);

    final window = _window();
    final read = await _source.readMenstrualFlow(
      bound.facts,
      start: window.queryStart,
      end: window.queryEnd,
    );
    return _summaryForRead(bound.profile.id, window, read);
  }

  /// Maps one [HealthReadResult] to the summary: samples go through
  /// [_apply]; every platform outcome becomes the matching blocked summary,
  /// with a denied read coalesced into the neutral empty one (see the
  /// switch's note). Split out of [importNow] purely to keep each method's
  /// CRAP score under the quality gate.
  Future<AppleHealthImportSummary> _summaryForRead(
    String profileId,
    _Window window,
    HealthReadResult read,
  ) async => switch (read) {
    HealthReadSamples(:final samples) => await _apply(
      profileId,
      window,
      samples,
    ),
    HealthReadRefused(:final check) => AppleHealthImportSummary(
      blocked: HealthPlatformResult.refused(check),
    ),
    HealthReadUnavailable() => const AppleHealthImportSummary(
      blocked: HealthPlatformUnavailable(),
    ),
    // HealthKit never reports a denied read — it returns an empty sample
    // list — but if a platform ever did report it, it is deliberately
    // coalesced into the same neutral "nothing came back" summary as an
    // empty result. The app must not distinguish the two.
    HealthReadPermissionDenied() => const AppleHealthImportSummary(),
    HealthReadFailed(:final message) => AppleHealthImportSummary(
      blocked: HealthPlatformResult.failed(message),
    ),
  };

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

  /// The bounded window this pass reads. The query bounds are plain UTC
  /// civil dates padded a day either side — never a zone conversion, so
  /// nothing about the device's current zone leaks into the read.
  _Window _window() {
    final to = _today();
    final from = appleHealthImportWindowStart(to);
    return _Window(
      from: from,
      to: to,
      queryStart: DateTime.utc(
        from.year,
        from.month,
        from.day,
      ).subtract(const Duration(days: 1)),
      queryEnd: DateTime.utc(
        to.year,
        to.month,
        to.day,
      ).add(const Duration(days: 2)),
    );
  }

  /// Resolves the pass's samples, merges each in-window date, and assembles
  /// the summary.
  Future<AppleHealthImportSummary> _apply(
    String profileId,
    _Window window,
    List<HealthFlowSample> samples,
  ) async {
    final resolved = _resolveSamples(samples, window);
    var written = 0;
    var unchanged = 0;
    var keptManual = 0;
    for (final entry in resolved.byDate.entries) {
      switch (await _mergeDay(profileId, entry.key, entry.value)) {
        case _MergeOutcome.written:
          written++;
        case _MergeOutcome.unchanged:
          unchanged++;
        case _MergeOutcome.keptManual:
          keptManual++;
      }
    }
    return AppleHealthImportSummary(
      samplesRead: samples.length,
      daysWritten: written,
      daysUnchanged: unchanged,
      daysKeptManual: keptManual,
      samplesWithoutZone: resolved.withoutZone,
      samplesUnsupported: resolved.unsupported,
    );
  }

  /// Maps every sample to a civil date using its OWN zone, keeps the
  /// highest-intensity flow per in-window date, and counts the ones that
  /// could not be placed.
  _ResolvedSamples _resolveSamples(
    List<HealthFlowSample> samples,
    _Window window,
  ) {
    final byDate = <LocalDate, _DesiredSample>{};
    var withoutZone = 0;
    var unsupported = 0;
    for (final sample in samples) {
      final flow = flowLevelFromHealthValue(sample.flow);
      if (flow == null) {
        unsupported++;
        continue;
      }
      final date = _dateFor(sample);
      if (date == null) {
        withoutZone++;
        continue;
      }
      if (date.isBefore(window.from) || date.isAfter(window.to)) continue;
      final current = byDate[date];
      if (current == null ||
          healthFlowValueRank(sample.flow) >
              healthFlowValueRank(current.value)) {
        byDate[date] = _DesiredSample(
          flow: flow,
          value: sample.flow,
          recordId: sample.recordId,
          // Non-null: _dateFor already proved it resolves.
          tzName: sample.tzName!,
        );
      }
    }
    return _ResolvedSamples(
      byDate: byDate,
      withoutZone: withoutZone,
      unsupported: unsupported,
    );
  }

  /// The sample's civil date in its own recorded zone, or null when it has
  /// no zone (or one this build cannot resolve) — never the device's zone.
  LocalDate? _dateFor(HealthFlowSample sample) {
    final tzName = sample.tzName;
    if (tzName == null || tzName.isEmpty) return null;
    try {
      return localDateForSample(sample.start, tzName: tzName);
    } on TimeZoneResolutionException {
      return null;
    }
  }

  /// Merges one date's imported flow into the bound profile's live entry:
  ///
  /// * no live row → insert with `healthkit` provenance;
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
          source: DayEntrySource.healthkit,
          sourceId: desired.recordId,
          updatedAt: _now(),
        ),
      );
      return _MergeOutcome.written;
    }
    if (existing.flow == desired.flow) return _MergeOutcome.unchanged;

    final canAdopt =
        existing.flow == FlowLevel.none ||
        existing.source == DayEntrySource.healthkit;
    if (!canAdopt) return _MergeOutcome.keptManual;

    // `copyWith` preserves tags/note/PMS; provenance flips to healthkit so
    // the write path never echoes this value back into Apple Health.
    await _dayEntries.save(
      existing.copyWith(
        flow: desired.flow,
        source: DayEntrySource.healthkit,
        sourceId: desired.recordId,
      ),
    );
    return _MergeOutcome.written;
  }

  /// The pass-blocking outcome of [result], or null when it was allowed.
  static HealthPlatformResult? _notAllowed(HealthPlatformResult result) =>
      result is HealthPlatformAllowed ? null : result;
}
