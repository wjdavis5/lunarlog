/// The one-way, opt-in, forward-only menstrual-flow write path (Issue
/// #193): turns the bound profile's day entries and spotting observations
/// into `writeMenstrualFlow` / `writeIntermenstrualBleeding` calls on the
/// #173 platform port, in the order the issue's acceptance criteria pin:
///
/// * **Opt-in** — nothing runs until the operator binds a profile in
///   Settings (`SettingsKeys.healthStoreProfileId`), and nothing is
///   requested from the OS health store until the first sync pass asks for
///   write authorization (stamping the grant instant). Off is the default.
/// * **One-way** — this file only ever calls write (or, since Issue #619's
///   LLA-024, delete-by-own-record-id reconciliation) methods on
///   [HealthPlatformStore]; no read/query API exists on the port in this
///   issue, and no entry is ever created or modified from health-store
///   data. Entries the app itself imported *from* a health store
///   ([DayEntrySource.healthkit]/[DayEntrySource.healthConnect]) are never
///   echoed back — writing them would duplicate rows Apple Health already
///   holds and could become a loop once #217's import direction exists.
/// * **Forward-only** — the first successful authorization stamps
///   [SettingsKeys.healthSyncWrittenThroughMs] with the grant instant; a
///   day is eligible only when its row's `updatedAt` is strictly after the
///   cursor, so pre-grant history is never backfilled (Clue's own
///   documented behavior, A3-35). A fully successful pass advances the
///   cursor to the newest processed row's `updatedAt`; any failure leaves
///   it (and the whole batch) to be retried by the next pass rather than
///   half-skipping.
///
/// **The guard is not re-implemented here.** Every write goes through the
/// port, whose implementations evaluate `HealthSyncBinding.canWrite` first
/// (Dart side) and whose native halves re-evaluate the mirrored predicate
/// from their own stored binding (see `health_channel.dart`'s library
/// doc). This service additionally pre-checks [HealthSyncBinding.canWrite]
/// once per pass purely to avoid building a batch the guard would refuse —
/// the load-bearing checks stay in the adapter, where #173 put them.
///
/// **Store-compliance note (issue #254):** this service is also why the
/// written 5.1.3 no-derived-values rule (see `health_channel.dart`'s
/// library doc) holds in practice — the only inputs it ever feeds the
/// port are the bound profile's own logged day entries and spotting
/// observations; the app's on-device predictions (next-period,
/// fertile-window, ovulation) are computed in `lib/domain/prediction/`
/// and never touch this path.
///
/// Pure Dart (R14/R16): repositories and the platform port are injected
/// interfaces; time comes from the injectable [now] clock, so every branch
/// runs under `flutter test`. The debounced trigger that calls [syncNow]
/// lives in `health_flow_write_coordinator.dart`; this file is the whole
/// policy.
library;

// The service takes its collaborators as constructor parameters that are
// not initializing formals (private finals via the initializer list), the
// same declared pattern `prediction_projection_publisher.dart` uses.
// ignore_for_file: prefer_initializing_formals

import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/logging/day_sheet_reconciliation.dart'
    show gradedPainIntensitiesFrom;
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
import 'package:lunarlog/domain/repositories/settings_store.dart';

import 'health_fertility_mapping.dart';
import 'health_flow_mapping.dart';
import 'health_record_ids.dart';
import 'health_symptom_mapping.dart';

/// One eligible day's resolved write, before it is sent to the port.
class _PendingWrite {
  const _PendingWrite({
    required this.date,
    required this.tzName,
    required this.plan,
    required this.cycleStart,
    required this.recordId,
    required this.updatedAt,
  });

  final LocalDate date;
  final String tzName;
  final HealthFlowWritePlan plan;

  /// Whether [date] is the first day of its period episode — the
  /// `HKMetadataKeyMenstrualCycleStart` flag every `menstrualFlow` sample
  /// must carry (true on the cycle's first day, false otherwise). Always
  /// false for intermenstrual markers (that type carries no metadata).
  final bool cycleStart;

  /// The source row's ULID (day-entry id for flow, observation id for
  /// spotting) — Issue #186 sync mechanics: becomes Health Connect's
  /// `clientRecordId` / HealthKit's `HKMetadataKeyExternalUUID` so the
  /// write is idempotent and a tombstone can delete the exact sample.
  final String recordId;
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// An eligible bleed day's zone + timestamp, used to derive a period
/// episode's interval write (Issue #202): the newest eligible member day's
/// `updatedAt` becomes the record's clientRecordVersion, and its `tz` the
/// episode's zone (#180 — the entry's own zone, never the device's).
class _EligibleBleed {
  const _EligibleBleed(this.tzName, this.updatedAt);

  final String tzName;
  final DateTime updatedAt;
}

/// One period episode's resolved interval write (Issue #202's
/// `MenstruationPeriodRecord`), before it is sent to the port.
class _PendingPeriodWrite {
  const _PendingPeriodWrite({
    required this.start,
    required this.end,
    required this.tzName,
    required this.recordId,
    required this.updatedAt,
  });

  /// The episode's inclusive first bleed day.
  final LocalDate start;

  /// The episode's inclusive last bleed day; the record's `endTime` is the
  /// exclusive local midnight after this date.
  final LocalDate end;

  /// The episode's IANA zone (from its eligible member entries — #180).
  final String tzName;

  /// The episode's stable clientRecordId: derived from the episode start
  /// (Issue #186/HS-11) so the SAME in-progress episode keeps the SAME id
  /// as it extends — Health Connect upserts by clientRecordId, so a
  /// re-write *updates* rather than duplicates; a closed episode simply
  /// stops re-writing once it has no new eligible member days.
  final String recordId;

  /// The newest eligible member day's `updatedAt` — clientRecordVersion,
  /// higher than any prior write of this episode.
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// One day's resolved symptom writes (Issue #238): every HealthKit
/// symptom sample the day entry's tags resolve to, in one channel call.
class _PendingSymptomWrite {
  const _PendingSymptomWrite({
    required this.date,
    required this.tzName,
    required this.samples,
    required this.updatedAt,
  });

  final LocalDate date;
  final String tzName;

  /// Already-resolved samples, each carrying its own stable `recordId`
  /// (`symptom-<entryId>-<typeIdentifier>`) and the source entry's
  /// `updatedAt` as `recordVersionMs`.
  final List<HealthSymptomSample> samples;

  final DateTime updatedAt;
}

/// One day's resolved cervical-mucus write (Issue #228), before the port
/// payload's guard facts are attached.
class _PendingCervicalMucusWrite {
  const _PendingCervicalMucusWrite({
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
  });

  final LocalDate date;
  final String tzName;
  final ResolvedCervicalMucus resolved;
  final String recordId;
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// One day's resolved ovulation-test write (Issue #228).
class _PendingOvulationWrite {
  const _PendingOvulationWrite({
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
  });

  final LocalDate date;
  final String tzName;
  final ResolvedOvulationTest resolved;
  final String recordId;
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// One resolved BBT observation write (Issue #228).
class _PendingBbtWrite {
  const _PendingBbtWrite({
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
    this.observedAt,
  });

  final LocalDate date;
  final String tzName;
  final ResolvedBasalBodyTemperature resolved;
  final String recordId;
  final DateTime updatedAt;
  final DateTime? observedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// Accumulates one pass's write plan: every day (whatever it maps to,
/// [HealthFlowNoWrite] included since Issue #619's LLA-024 — see [add])
/// joins [pending], days mapped to no sample are additionally counted in
/// [withoutSample], period episodes join [pendingPeriods], and the Issue
/// #228 fertility/measurement signals join their own lists.
class _Batch {
  final List<_PendingWrite> pending = [];
  final List<_PendingPeriodWrite> pendingPeriods = [];
  final List<_PendingSymptomWrite> pendingSymptoms = [];
  final List<_PendingCervicalMucusWrite> pendingCervicalMucus = [];
  final List<_PendingOvulationWrite> pendingOvulation = [];
  final List<_PendingBbtWrite> pendingBbt = [];
  int withoutSample = 0;

  /// Every record id each eligible day entry produces this pass (Issue
  /// #930), keyed by day-entry id — the "now" side of the removed-record
  /// diff. Built from [healthRecordIdsForEntry], never by parsing the
  /// pending writes' ids.
  final Map<String, Set<String>> entryRecordIds = {};

  /// Every live, exportable BBT observation's record id this pass,
  /// regardless of the forward-only cursor — the "still present" side of
  /// the BBT diff. A remembered id absent from this set is a reading the
  /// operator cleared (its row is tombstoned or no longer resolves).
  final Set<String> liveBbtRecordIds = {};

  void add(LocalDate date, String tzName, DateTime updatedAt, String recordId,
      HealthFlowWritePlan plan, Episode? containing) {
    switch (plan) {
      case HealthFlowNoWrite():
        withoutSample++;
        // Issue #619, LLA-024: also queued as a write-loop item so a day
        // edited FROM an exportable value TO no sample reconciles away
        // whatever sample a prior pass wrote under this same recordId —
        // see _writeFlowRecords's HealthFlowNoWrite branch.
        pending.add(_PendingWrite(
          date: date,
          tzName: tzName,
          plan: plan,
          cycleStart: false,
          recordId: recordId,
          updatedAt: updatedAt,
        ));
      case HealthFlowMenstrualSample():
        pending.add(_PendingWrite(
          date: date,
          tzName: tzName,
          plan: plan,
          // #193 AC: the cycle-start flag is true exactly on the first
          // day of the containing episode (per episodes.dart), false on
          // every other written sample.
          cycleStart: containing != null && containing.start == date,
          recordId: recordId,
          updatedAt: updatedAt,
        ));
      case HealthFlowIntermenstrualMarker():
        pending.add(_PendingWrite(
          date: date,
          tzName: tzName,
          plan: plan,
          cycleStart: false,
          recordId: recordId,
          updatedAt: updatedAt,
        ));
    }
  }
}

/// One pass's aggregate write outcome, across every type (flow, period,
/// symptom, and Issue #228's fertility/measurement signals).
class _BatchOutcome {
  const _BatchOutcome({
    required this.written,
    required this.reconciled,
    required this.periodRecordsWritten,
    required this.symptomSamplesWritten,
    required this.cervicalMucusSamplesWritten,
    required this.ovulationTestSamplesWritten,
    required this.basalBodyTemperatureSamplesWritten,
    required this.failure,
    required this.newest,
  });

  final int written;
  final int reconciled;
  final int periodRecordsWritten;
  final int symptomSamplesWritten;
  final int cervicalMucusSamplesWritten;
  final int ovulationTestSamplesWritten;
  final int basalBodyTemperatureSamplesWritten;
  final HealthPlatformResult? failure;
  final DateTime? newest;
}

class LocalHealthFlowWriteService implements HealthFlowWriteService {
  LocalHealthFlowWriteService({
    required HealthPlatformStore platform,
    required HealthSyncBinding binding,
    required bool minorBindingAllowed,
    required ProfilesRepository profiles,
    required DayEntriesRepository dayEntries,
    required ObservationsRepository observations,
    required SettingsStore settings,
    required GuardiansForProfile guardiansForProfile,
    required String? Function() signedInUserId,
    DateTime Function()? now,
  })  : _platform = platform,
        _binding = binding,
        _minorBindingAllowed = minorBindingAllowed,
        _profiles = profiles,
        _dayEntries = dayEntries,
        _observations = observations,
        _settings = settings,
        _guardiansForProfile = guardiansForProfile,
        _signedInUserId = signedInUserId,
        _now = now ?? (() => DateTime.now().toUtc());

  final HealthPlatformStore _platform;
  final HealthSyncBinding _binding;
  final bool _minorBindingAllowed;
  final ProfilesRepository _profiles;
  final DayEntriesRepository _dayEntries;
  final ObservationsRepository _observations;
  final SettingsStore _settings;
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;
  final DateTime Function() _now;

  /// The record ids the previous pass recorded for each day entry (Issue
  /// #930) — the "previously exported" side of the removed-record diff.
  /// Keyed by day-entry id; populated from [healthRecordIdsForEntry], the
  /// same derivation the tombstone coordinator remembers and the write path
  /// writes, so a delete can never address an id a write did not use.
  ///
  /// Deliberately this service's own memory rather than the tombstone
  /// coordinator's: only the write path knows which record was actually
  /// exported (the coordinator's set is seeded by live stream emissions,
  /// including rows the forward-only cursor never wrote). See
  /// [_reconcileRemovedRecords].
  final Map<String, Set<String>> _exportedEntryRecordIds = {};

  /// The BBT record ids a previous export wrote (Issue #930), compared
  /// against the live BBT set on every pass so a reading cleared from a day
  /// that itself still exists is reconciled away.
  final Set<String> _exportedBbtRecordIds = {};

  /// Runs one sync pass for the currently bound profile. Never throws —
  /// every expected failure mode is a [HealthFlowSyncReport.blocked];
  /// unexpected storage errors propagate (the coordinator's job to
  /// tolerate), matching the port adapters' own contract of surfacing
  /// rather than swallowing protocol errors. Decomposed into one private
  /// method per stage (resolve → guard → grant → collect → write) so each
  /// stays under the quality gate's CRAP ceiling.
  @override
  Future<HealthFlowSyncReport> syncNow() async {
    final bound = await _resolveBound();
    if (bound == null) {
      return const HealthFlowSyncReport(bound: false);
    }

    // Pre-flight only (the port re-checks per call, natively mirrored):
    // refuses the pass before any channel traffic when the guard would
    // deny every write anyway.
    final check = await _binding.canWrite(
      profile: bound.profile,
      signedInUserId: bound.facts.signedInUserId,
      ownerUserId: bound.facts.ownerUserId,
      minorBindingAllowed: _minorBindingAllowed,
    );
    if (!check.isAllowed) {
      return HealthFlowSyncReport(
        bound: true,
        blocked: HealthPlatformResult.refused(check),
      );
    }

    // Keep the native-side binding mirror in step (idempotent natively).
    // #173 left this unwired ("the flag-flip PR must wire bind/unbind
    // through the port"); storing it here means every pass re-asserts the
    // same binding, so a native side that lost its copy (fresh install
    // restored from backup, or a pre-#193 native half) heals on the next
    // pass instead of silently denying forever.
    final bindBlocked = _notAllowed(await _platform.bindProfile(bound.facts));
    if (bindBlocked != null) {
      return HealthFlowSyncReport(bound: true, blocked: bindBlocked);
    }

    final grant = await _ensureForwardOnlyCursor(bound.facts);
    if (grant.blocked != null) {
      // A refused/denied authorization — or `unavailable` (consent was
      // stamped but there is nothing to write to) — ends the pass.
      return HealthFlowSyncReport(
        bound: true,
        authorizationRequested: grant.grantedNow,
        blocked: grant.blocked,
      );
    }

    final batch = await _collectBatch(bound.profile.id, grant.cursor!);
    final outcome = await _writeBatch(batch, bound.facts);
    if (outcome.failure == null && outcome.newest != null) {
      await _settings.set(
        SettingsKeys.healthSyncWrittenThroughMs,
        '${outcome.newest!.millisecondsSinceEpoch}',
      );
    }

    return HealthFlowSyncReport(
      bound: true,
      authorizationRequested: grant.grantedNow,
      blocked: outcome.failure,
      samplesWritten: outcome.written,
      periodRecordsWritten: outcome.periodRecordsWritten,
      symptomSamplesWritten: outcome.symptomSamplesWritten,
      cervicalMucusSamplesWritten: outcome.cervicalMucusSamplesWritten,
      ovulationTestSamplesWritten: outcome.ovulationTestSamplesWritten,
      basalBodyTemperatureSamplesWritten:
          outcome.basalBodyTemperatureSamplesWritten,
      daysWithoutSample: batch.withoutSample,
      samplesReconciled: outcome.reconciled,
    );
  }

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

  /// Forward-only grant stage: the cursor's first stamp is the
  /// authorization moment. `unavailable` also stamps — a device with no
  /// health store can never be written to, and re-prompting on every pass
  /// would churn; any other outcome leaves the cursor unset so the next
  /// pass retries. A non-null [GrantOutcome.blocked] always ends the pass.
  Future<({DateTime? cursor, HealthPlatformResult? blocked, bool grantedNow})>
      _ensureForwardOnlyCursor(HealthGuardFacts facts) async {
    final existing = await _readCursor();
    if (existing != null) {
      return (cursor: existing, blocked: null, grantedNow: false);
    }
    final auth = await _platform.requestWriteAuthorization(facts);
    final blocked = _notAllowed(auth);
    final unavailable = blocked != null && auth is HealthPlatformUnavailable;
    if (blocked != null && !unavailable) {
      return (cursor: null, blocked: blocked, grantedNow: true);
    }
    final stamped = _now();
    await _settings.set(
      SettingsKeys.healthSyncWrittenThroughMs,
      '${stamped.millisecondsSinceEpoch}',
    );
    return (cursor: stamped, blocked: blocked, grantedNow: true);
  }

  /// Builds the pass's write batch from the bound profile's day entries
  /// and observations: everything strictly newer than [cursor]
  /// (forward-only), mapped through `health_flow_mapping.dart`,
  /// `health_symptom_mapping.dart`, and — Issue #228 —
  /// `health_fertility_mapping.dart`, plus one `MenstruationPeriodRecord`
  /// per period episode that contains an eligible bleed day (Issue #202 —
  /// see [_periodWritesFor]).
  Future<_Batch> _collectBatch(String profileId, DateTime cursor) async {
    final entries = await _dayEntries.listForProfile(profileId);
    final observationRows = await _observations.listForProfile(profileId);
    final spottingRows = [
      for (final observation in observationRows)
        if (observation.category == ObservationCategory.spotting) observation,
    ];
    // Issue #238 / Issue #934: index pain observations by entry id and date
    // so each entry resolves its own graded pain severity rather than
    // inheriting the profile's lifetime maximum.
    final painByEntryId = <String, List<Observation>>{};
    final painByDate = <LocalDate, List<Observation>>{};
    for (final observation in observationRows) {
      if (observation.category != ObservationCategory.pain) continue;
      painByEntryId
          .putIfAbsent(observation.dayEntryId, () => [])
          .add(observation);
      painByDate
          .putIfAbsent(observation.localDate, () => [])
          .add(observation);
    }
    final episodes = deriveEpisodes(bleedDatesOf(entries));
    final bleedDays = bleedDatesOf(entries);
    final batch = _Batch();

    // Eligible bleed days keyed by date, for period-record derivation.
    final eligibleBleed = <LocalDate, _EligibleBleed>{};

    for (final entry in entries) {
      if (!_isEligible(entry.updatedAt, entry.source, cursor)) continue;
      if (isBleed(entry.flow)) {
        eligibleBleed[entry.localDate] =
            _EligibleBleed(entry.tz, entry.updatedAt);
      }
      final containing = _containing(episodes, entry.localDate);
      batch.add(
        entry.localDate,
        entry.tz,
        entry.updatedAt,
        healthFlowRecordId(entry.id),
        mapFlowToHealthWrite(
          entry.flow,
          inPeriodEpisode: containing != null,
        ),
        containing,
      );
      final gradedPain = _gradedPainForEntry(
        entry,
        painByEntryId,
        painByDate,
      );
      final symptomWrite = _symptomWriteFor(entry, gradedPain);
      if (symptomWrite != null) batch.pendingSymptoms.add(symptomWrite);
      final fertility = _fertilityWritesFor(entry);
      final cervical = fertility.cervicalMucus;
      if (cervical != null) batch.pendingCervicalMucus.add(cervical);
      batch.pendingOvulation.addAll(fertility.ovulation);
      // Issue #930: the ids this entry asserts *now*, for the reconcile
      // diff against what the previous export wrote for it.
      batch.entryRecordIds[entry.id] = healthRecordIdsForEntry(entry);
    }

    _collectObservationWrites(
      observationRows: observationRows,
      spottingRows: spottingRows,
      bleedDays: bleedDays,
      episodes: episodes,
      batch: batch,
      cursor: cursor,
    );

    batch.pendingPeriods
        .addAll(_periodWritesFor(profileId, episodes, eligibleBleed));
    return batch;
  }

  /// The two observation-row loops of [_collectBatch] (spotting markers and
  /// Issue #228's BBT values), extracted so [_collectBatch]'s own
  /// cyclomatic complexity stays under the quality gate's CRAP ceiling.
  void _collectObservationWrites({
    required List<Observation> observationRows,
    required List<Observation> spottingRows,
    required Set<LocalDate> bleedDays,
    required List<Episode> episodes,
    required _Batch batch,
    required DateTime cursor,
  }) {
    for (final row in spottingRows) {
      if (!_isEligible(row.updatedAt, row.source, cursor)) continue;
      if (bleedDays.contains(row.localDate)) {
        // The day's own flow sample already carries the intensity — a
        // spotting record alongside it would write a second, contradictory
        // menstrual sample for the same day.
        batch.withoutSample++;
        continue;
      }
      final containing = _containing(episodes, row.localDate);
      batch.add(
        row.localDate,
        row.tz,
        row.updatedAt,
        healthSpottingRecordId(row.id),
        mapSpottingToHealthWrite(inPeriodEpisode: containing != null),
        containing,
      );
    }

    // Issue #228: the bbt observations. `_bbtWriteFor` enforces source
    // separation (resolveBasalBodyTemperature returns null for a
    // platform/wearable-sourced or excluded row).
    for (final row in observationRows) {
      // Issue #930: every *live* exportable BBT row counts as present even
      // when the forward-only cursor excludes it from this pass's writes —
      // so an unchanged reading is never mistaken for a cleared one.
      if (resolveBasalBodyTemperature(row) != null) {
        batch.liveBbtRecordIds.add(healthBbtRecordId(row.id));
      }
      final bbt = _bbtWriteFor(row, cursor);
      if (bbt != null) batch.pendingBbt.add(bbt);
    }
  }

  /// Resolves one eligible day entry's fertility tags (Issue #228): its
  /// cervical-mucus appearance (at most one — discharge is single-select)
  /// and its ovulation-test results (deduplicated by platform result).
  ({
    _PendingCervicalMucusWrite? cervicalMucus,
    List<_PendingOvulationWrite> ovulation,
  }) _fertilityWritesFor(DayEntry entry) {
    final cervical = resolveCervicalMucus(entry.tags);
    final ovulation = resolveOvulationTests(entry.tags);
    return (
      cervicalMucus: cervical == null
          ? null
          : _PendingCervicalMucusWrite(
              date: entry.localDate,
              tzName: entry.tz,
              resolved: cervical,
              recordId: healthCervicalMucusRecordId(entry.id),
              updatedAt: entry.updatedAt,
            ),
      ovulation: [
        for (final result in ovulation)
          _PendingOvulationWrite(
            date: entry.localDate,
            tzName: entry.tz,
            resolved: result,
            recordId:
                healthOvulationRecordId(entry.id, result.healthKitResult),
            updatedAt: entry.updatedAt,
          ),
      ],
    );
  }

  /// Resolves one BBT observation row (Issue #228), or null when it is not
  /// an eligible manually tracked/imported `bbt` value. Source separation
  /// is enforced by [resolveBasalBodyTemperature] (a platform- or
  /// wearable-sourced value produces no write) and by [_isEligible]
  /// (forward-only, never echo a health-store-sourced row).
  _PendingBbtWrite? _bbtWriteFor(Observation row, DateTime cursor) {
    if (row.category != ObservationCategory.bbt) return null;
    if (!_isEligible(row.updatedAt, row.source, cursor)) return null;
    final resolved = resolveBasalBodyTemperature(row);
    if (resolved == null) return null;
    return _PendingBbtWrite(
      date: row.localDate,
      tzName: row.tz,
      resolved: resolved,
      recordId: healthBbtRecordId(row.id),
      updatedAt: row.updatedAt,
      observedAt: row.observedAt,
    );
  }

  /// Resolves one eligible day entry's [DayEntry.tags] into its symptom
  /// write, or null when the day carries no mapped symptom. Never sends an
  /// empty batch (the port documents that at least one sample is present).
  _PendingSymptomWrite? _symptomWriteFor(
    DayEntry entry,
    Map<String, int> gradedPain,
  ) {
    final resolved = resolveHealthKitSymptoms(
      tags: entry.tags,
      gradedPainIntensities: gradedPain,
    );
    if (resolved.isEmpty) return null;
    final versionMs = entry.updatedAt.millisecondsSinceEpoch;
    return _PendingSymptomWrite(
      date: entry.localDate,
      tzName: entry.tz,
      updatedAt: entry.updatedAt,
      samples: [
        for (final symptom in resolved)
          HealthSymptomSample(
            healthKitTypeIdentifier: symptom.typeIdentifier,
            severity: symptom.severity,
            // Stable per (day entry, symptom type): a re-write replaces the
            // same sample (sync identifier/version), and a future
            // reconciliation can address it by this exact id.
            recordId: healthSymptomRecordId(entry.id, symptom.typeIdentifier),
            recordVersionMs: versionMs,
          ),
      ],
    );
  }

  /// Resolves the pain intensity map for a single [entry] from the profile's
  /// pain observations (Issue #934). Groups by entry id and date so an entry
  /// only inherits pain intensities logged for that specific day, avoiding
  /// profile-lifetime severity leakage.
  Map<String, int> _gradedPainForEntry(
    DayEntry entry,
    Map<String, List<Observation>> painByEntryId,
    Map<LocalDate, List<Observation>> painByDate,
  ) {
    final entryPain = painByEntryId[entry.id];
    final datePain = painByDate[entry.localDate];
    if (entryPain == null && datePain == null) {
      return const {};
    }
    final combined = {
      ...?entryPain,
      ...?datePain,
    }.toList();
    return gradedPainIntensitiesFrom(combined);
  }

  /// One `MenstruationPeriodRecord` write per period episode that contains
  /// at least one eligible (post-cursor, not health-store-sourced) bleed
  /// day. The stable clientRecordId (`period-<profile>-<start>`) is
  /// identical across re-writes as an in-progress episode extends, so
  /// Health Connect's upsert-by-clientRecordId *updates* rather than
  /// duplicates; a closed episode stops being re-written once none of its
  /// days is new, so its last write already carries the complete interval —
  /// the #202 update-on-close strategy.
  List<_PendingPeriodWrite> _periodWritesFor(
    String profileId,
    List<Episode> episodes,
    Map<LocalDate, _EligibleBleed> eligibleBleed,
  ) {
    final writes = <_PendingPeriodWrite>[];
    for (final episode in episodes) {
      _EligibleBleed? newest;
      for (var date = episode.start;
          !date.isAfter(episode.end);
          date = date.addDays(1)) {
        final bleed = eligibleBleed[date];
        if (bleed == null) continue;
        if (newest == null || bleed.updatedAt.isAfter(newest.updatedAt)) {
          newest = bleed;
        }
      }
      if (newest == null) continue;
      writes.add(_PendingPeriodWrite(
        start: episode.start,
        end: episode.end,
        tzName: newest.tzName,
        recordId: healthPeriodRecordId(profileId, episode.start),
        updatedAt: newest.updatedAt,
      ));
    }
    return writes;
  }

  /// Sends [pending] (per-day flow/marker writes) and [pendingPeriods]
  /// (per-episode interval writes) to the port. Keeps writing after a
  /// failure (one bad day must not hide the others), remembering the first
  /// failure and leaving the cursor — the next pass retries the batch
  /// rather than half-skipping (see the class doc's forward-only note).
  Future<_BatchOutcome> _writeBatch(
    _Batch batch,
    HealthGuardFacts facts,
  ) async {
    final flow = await _writeFlowRecords(batch.pending, facts);
    final periods = await _writePeriodRecords(batch.pendingPeriods, facts);
    final symptoms = await _writeSymptomRecords(batch.pendingSymptoms, facts);
    final cervical =
        await _writeCervicalMucusRecords(batch.pendingCervicalMucus, facts);
    final ovulation =
        await _writeOvulationTestRecords(batch.pendingOvulation, facts);
    final bbt = await _writeBbtRecords(batch.pendingBbt, facts);
    // Issue #930: after this pass's writes, reconcile away any sample a
    // PRIOR export wrote for the day/observation that no longer asserts it.
    // Runs after the writes so the remembered sets move "now" -> "after the
    // write"; a failure here blocks the pass (and leaves the cursor) so the
    // removal is retried rather than silently skipped.
    final removed = await _reconcileRemovedRecords(batch, facts);
    return _BatchOutcome(
      written: flow.written,
      reconciled: flow.reconciled,
      periodRecordsWritten: periods.written,
      symptomSamplesWritten: symptoms.written,
      cervicalMucusSamplesWritten: cervical.written,
      ovulationTestSamplesWritten: ovulation.written,
      basalBodyTemperatureSamplesWritten: bbt.written,
      failure: flow.failure ??
          periods.failure ??
          symptoms.failure ??
          cervical.failure ??
          ovulation.failure ??
          bbt.failure ??
          removed,
      newest: _latest(
        _latest(_latest(flow.newest, periods.newest), symptoms.newest),
        _latest(_latest(cervical.newest, ovulation.newest), bbt.newest),
      ),
    );
  }

  /// Reconciles the records a *previous* export wrote against what this pass
  /// found (Issue #930) — the fix for a symptom/BTT/fertility sample left
  /// orphaned when a live day entry is edited rather than deleted.
  ///
  /// The remembered set is this service's own [_exportedEntryRecordIds] /
  /// [_exportedBbtRecordIds], seeded only from this device's own exports
  /// through [healthRecordIdsForEntry] and the BBT builder. A remembered id
  /// that the current state no longer produces is deleted;
  /// an id that is unchanged (a graded intensity or flow edit rewrites the
  /// same id) is left alone. Deleting is a health-API touch, so it goes
  /// through the same `_authorityDrift` recheck and guarded
  /// [HealthPlatformStore.deleteRecords] as every write — no new bypass.
  /// Returns the first removal failure, or null when every removal was
  /// allowed.
  Future<HealthPlatformResult?> _reconcileRemovedRecords(
    _Batch batch,
    HealthGuardFacts facts,
  ) async {
    final entryFailure = await _reconcileEntryRemovals(batch, facts);
    final bbtFailure = await _reconcileBbtRemovals(batch, facts);
    // Only once the BBT diff is computed: every BBT id this pass exported is
    // remembered so a LATER clear can address it.
    for (final item in batch.pendingBbt) {
      _exportedBbtRecordIds.add(item.recordId);
    }
    return entryFailure ?? bbtFailure;
  }

  /// The day-entry half of [_reconcileRemovedRecords]: for every eligible
  /// entry, delete the ids it produced on a previous export but no longer
  /// produces, then remember the current set. A delete failure leaves the
  /// old set in place so the removal is retried on the next pass (LLA-019's
  /// discipline), rather than being silently acknowledged.
  Future<HealthPlatformResult?> _reconcileEntryRemovals(
    _Batch batch,
    HealthGuardFacts facts,
  ) async {
    HealthPlatformResult? failure;
    for (final entry in batch.entryRecordIds.entries) {
      final current = entry.value;
      final previous = _exportedEntryRecordIds[entry.key] ?? const <String>{};
      final removed = previous.difference(current);
      if (removed.isEmpty) {
        _exportedEntryRecordIds[entry.key] = current;
        continue;
      }
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        continue;
      }
      final result = await _platform.deleteRecords(facts, removed.toList());
      if (result is HealthPlatformAllowed) {
        _exportedEntryRecordIds[entry.key] = current;
      } else {
        failure ??= result;
      }
    }
    return failure;
  }

  /// The BBT half of [_reconcileRemovedRecords]: a remembered BBT record
  /// whose observation is no longer live-and-resolved (the operator cleared
  /// the reading, leaving the day itself in place) is deleted. The memory is
  /// only cleared on success, so a refusal retries.
  Future<HealthPlatformResult?> _reconcileBbtRemovals(
    _Batch batch,
    HealthGuardFacts facts,
  ) async {
    final removed = _exportedBbtRecordIds.difference(batch.liveBbtRecordIds);
    if (removed.isEmpty) return null;
    final drift = await _authorityDrift(facts);
    if (drift != null) return drift;
    final result = await _platform.deleteRecords(facts, removed.toList());
    if (result is HealthPlatformAllowed) {
      _exportedBbtRecordIds.removeAll(removed);
      return null;
    }
    return result;
  }

  /// Re-validates ownership/profile authority against the CURRENT stored
  /// binding, signed-in session, and guardian rows — never [facts], which
  /// was captured once when the pass began (Issue #620, LLA-023): a batch
  /// can span many individual platform writes, and a pass suspended
  /// mid-batch (the OS backgrounds the app between calls) can resume after
  /// an ownership transfer or a profile edit changed who may write here.
  /// Reusing `HealthSyncBinding.canWrite` — the same recheck every guarded
  /// port call already performs — means a resolved profile whose ownership
  /// or minor status changed denies exactly the way a fresh call would.
  /// Returns the refusal to cancel the rest of the pass with, or null when
  /// authority still holds.
  Future<HealthPlatformResult?> _authorityDrift(HealthGuardFacts facts) async {
    final profile = await _profiles.findById(facts.profile.id);
    if (profile == null) {
      // The profile row itself vanished mid-pass (deleted, or its device
      // no longer has it) — no HealthSyncCheck reason fits "the thing we
      // were writing to is gone", so this is a platform-level failure
      // rather than a guard refusal.
      return const HealthPlatformResult.failed(
        'bound profile no longer resolves mid-pass',
      );
    }
    final recheck = await _binding.canWrite(
      profile: profile,
      signedInUserId: _signedInUserId(),
      ownerUserId: ownerUserIdFor(await _guardiansForProfile(profile.id)),
      minorBindingAllowed: _minorBindingAllowed,
    );
    return recheck.isAllowed ? null : HealthPlatformResult.refused(recheck);
  }

  /// Sends the per-day flow/marker writes to the port. Keeps writing after
  /// a failure (one bad day must not hide the others), remembering the
  /// first failure and leaving the cursor — the next pass retries the batch
  /// rather than half-skipping (see the class doc's forward-only note).
  /// Stops outright, rather than skipping just the one day, the moment
  /// [_authorityDrift] detects the pass's authority has changed underneath
  /// it (Issue #620, LLA-023) — a drift found on day N means every day
  /// after N is written under the same now-invalid authority too.
  ///
  /// Issue #619, LLA-024: a [HealthFlowNoWrite] item is not merely skipped
  /// — it issues [HealthPlatformStore.deleteRecords] for its own
  /// [_PendingWrite.recordId], reconciling away whatever sample a PRIOR
  /// pass may have written under that exact id for a day that has since
  /// been edited to no sample (e.g. bleeding edited to `notBleeding`). An
  /// id with no matching store sample is a documented no-op delete, so
  /// this is issued unconditionally rather than only when a prior write is
  /// known to have happened — see [_resolveNoWriteOutcome].
  Future<
      ({
        int written,
        int reconciled,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeFlowRecords(
    List<_PendingWrite> pending,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    var reconciled = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final write in pending) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      final current = newest;
      if (current == null || write.updatedAt.isAfter(current)) {
        newest = write.updatedAt;
      }
      final result = await _resolveNoWriteOutcome(write, facts) ??
          await _sendSample(write, facts);
      if (result is! HealthPlatformAllowed) {
        failure ??= result;
      } else if (write.plan is HealthFlowNoWrite) {
        reconciled++;
      } else {
        written++;
      }
    }
    return (
      written: written,
      reconciled: reconciled,
      failure: failure,
      newest: newest,
    );
  }

  /// [write]'s reconciliation delete when its plan is [HealthFlowNoWrite],
  /// or null for every other plan (the caller then sends the sample
  /// itself via [_sendSample]). Split out purely to keep
  /// [_writeFlowRecords]'s own CRAP score under the quality gate.
  Future<HealthPlatformResult?> _resolveNoWriteOutcome(
    _PendingWrite write,
    HealthGuardFacts facts,
  ) async {
    if (write.plan is! HealthFlowNoWrite) return null;
    return _platform.deleteRecords(facts, [write.recordId]);
  }

  /// Sends [write]'s menstrual-flow or intermenstrual-bleeding sample.
  /// Never called for a [HealthFlowNoWrite] plan — [_resolveNoWriteOutcome]
  /// handles that case first.
  Future<HealthPlatformResult> _sendSample(
    _PendingWrite write,
    HealthGuardFacts facts,
  ) {
    switch (write.plan) {
      case HealthFlowMenstrualSample(:final value):
        return _platform.writeMenstrualFlow(
          HealthMenstrualFlowWrite(
            facts: facts,
            date: write.date,
            tzName: write.tzName,
            flow: value,
            cycleStart: write.cycleStart,
            recordId: write.recordId,
            recordVersionMs: write.recordVersionMs,
          ),
        );
      case HealthFlowIntermenstrualMarker():
        return _platform.writeIntermenstrualBleeding(
          HealthIntermenstrualBleedingWrite(
            facts: facts,
            date: write.date,
            tzName: write.tzName,
            recordId: write.recordId,
            recordVersionMs: write.recordVersionMs,
          ),
        );
      case HealthFlowNoWrite():
        throw StateError(
          'unreachable: _resolveNoWriteOutcome handles HealthFlowNoWrite',
        );
    }
  }

  /// The later of [a] and [b], or the non-null one when only one is set.
  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Sends the per-episode interval writes (Issue #202's
  /// `MenstruationPeriodRecord`). A platform that answers `unavailable` —
  /// HealthKit encodes episode boundaries via menstrual-flow cycle-start
  /// metadata instead (#193) — is a graceful skip, never a pass-blocking
  /// failure (on Android a genuinely missing Health Connect surfaces as
  /// `unavailable` on the per-day writes above, which already blocks).
  /// Stops outright on the same mid-pass authority drift
  /// [_writeFlowRecords] guards against (Issue #620, LLA-023).
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writePeriodRecords(
    List<_PendingPeriodWrite> pendingPeriods,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final period in pendingPeriods) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      if (newest == null || period.updatedAt.isAfter(newest)) {
        newest = period.updatedAt;
      }
      final result = await _platform.writeMenstrualPeriod(
        HealthMenstrualPeriodWrite(
          facts: facts,
          start: period.start,
          end: period.end,
          tzName: period.tzName,
          recordId: period.recordId,
          recordVersionMs: period.recordVersionMs,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written++;
      } else if (result is HealthPlatformUnavailable) {
        continue;
      } else {
        failure ??= result;
      }
    }
    return (written: written, failure: failure, newest: newest);
  }

  /// Sends the per-day symptom writes (Issue #238). A platform that
  /// answers `unavailable` — Health Connect has no symptom category types
  /// at all, permanently — is a graceful skip, never a pass-blocking
  /// failure, exactly like [HealthPlatformUnavailable] period records.
  /// Every other failure blocks the pass and leaves the cursor for a
  /// retry, matching [_writeFlowRecords]. Stops outright on the same
  /// mid-pass authority drift [_writeFlowRecords] guards against.
  ///
  /// **Not done in this PR:** a symptom removed from a day entry is not
  /// reconciled away in the health store (the native delete path still
  /// queries only the flow types); see the PR's `## Not done`.
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeSymptomRecords(
    List<_PendingSymptomWrite> pendingSymptoms,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final symptom in pendingSymptoms) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      if (newest == null || symptom.updatedAt.isAfter(newest)) {
        newest = symptom.updatedAt;
      }
      final result = await _platform.writeSymptomSamples(
        HealthSymptomSamplesWrite(
          facts: facts,
          date: symptom.date,
          tzName: symptom.tzName,
          samples: symptom.samples,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written += symptom.samples.length;
      } else if (result is HealthPlatformUnavailable) {
        continue;
      } else {
        failure ??= result;
      }
    }
    return (written: written, failure: failure, newest: newest);
  }

  /// Sends the per-day cervical-mucus writes (Issue #228). Both platforms
  /// have the type, so `unavailable` is not expected — but it is still a
  /// graceful skip rather than a pass-blocking failure, for parity with the
  /// other writers and so a future platform gap cannot wedge a pass. Stops
  /// on the same mid-pass authority drift as [_writeFlowRecords].
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeCervicalMucusRecords(
    List<_PendingCervicalMucusWrite> pending,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final item in pending) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      if (newest == null || item.updatedAt.isAfter(newest)) {
        newest = item.updatedAt;
      }
      final result = await _platform.writeCervicalMucus(
        HealthCervicalMucusWrite(
          facts: facts,
          date: item.date,
          tzName: item.tzName,
          healthKitValue: item.resolved.healthKitValue,
          healthConnectAppearance: item.resolved.healthConnectAppearance,
          recordId: item.recordId,
          recordVersionMs: item.recordVersionMs,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written++;
      } else if (result is HealthPlatformUnavailable) {
        continue;
      } else {
        failure ??= result;
      }
    }
    return (written: written, failure: failure, newest: newest);
  }

  /// Sends the per-day ovulation-test writes (Issue #228). Same error
  /// handling as [_writeCervicalMucusRecords] and the same mid-pass
  /// authority-drift stop.
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeOvulationTestRecords(
    List<_PendingOvulationWrite> pending,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final item in pending) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      if (newest == null || item.updatedAt.isAfter(newest)) {
        newest = item.updatedAt;
      }
      final result = await _platform.writeOvulationTest(
        HealthOvulationTestWrite(
          facts: facts,
          date: item.date,
          tzName: item.tzName,
          healthKitResult: item.resolved.healthKitResult,
          healthConnectResult: item.resolved.healthConnectResult,
          recordId: item.recordId,
          recordVersionMs: item.recordVersionMs,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written++;
      } else if (result is HealthPlatformUnavailable) {
        continue;
      } else {
        failure ??= result;
      }
    }
    return (written: written, failure: failure, newest: newest);
  }

  /// Sends the per-observation BBT writes (Issue #228). Same error handling
  /// and mid-pass authority-drift stop as [_writeCervicalMucusRecords].
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeBbtRecords(
    List<_PendingBbtWrite> pending,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final item in pending) {
      final drift = await _authorityDrift(facts);
      if (drift != null) {
        failure ??= drift;
        break;
      }
      if (newest == null || item.updatedAt.isAfter(newest)) {
        newest = item.updatedAt;
      }
      final result = await _platform.writeBasalBodyTemperature(
        HealthBasalBodyTemperatureWrite(
          facts: facts,
          date: item.date,
          tzName: item.tzName,
          celsius: item.resolved.celsius,
          healthConnectMeasurementLocation:
              item.resolved.healthConnectMeasurementLocation,
          recordId: item.recordId,
          recordVersionMs: item.recordVersionMs,
          observedAt: item.observedAt,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written++;
      } else if (result is HealthPlatformUnavailable) {
        continue;
      } else {
        failure ??= result;
      }
    }
    return (written: written, failure: failure, newest: newest);
  }

  /// The unbind/reset half of the write flow: clears the forward-only
  /// cursor and the native-side binding mirror. Called by the coordinator
  /// whenever the stored binding goes away *or is replaced* — forward-only
  /// consent belongs to one binding, so re-binding (same or different
  /// profile) re-grants from the new authorization moment rather than
  /// backfilling under the old cursor.
  @override
  Future<void> onUnbound() async {
    await _settings.set(SettingsKeys.healthSyncWrittenThroughMs, '');
    // Issue #930: the remembered export sets belong to one binding —
    // forward-only consent belongs to one binding too, so re-binding must
    // never diff (and delete) against the old profile's exports.
    _exportedEntryRecordIds.clear();
    _exportedBbtRecordIds.clear();
    await _platform.unbindProfile();
  }

  /// Forward-only eligibility: the row must have been written strictly
  /// after the cursor, and must not have come *from* a health store (see
  /// the class doc's one-way note).
  bool _isEligible(DateTime updatedAt, Object? source, DateTime cursor) {
    if (!updatedAt.isAfter(cursor)) return false;
    if (source is DayEntrySource &&
        (source == DayEntrySource.healthkit ||
            source == DayEntrySource.healthConnect)) {
      return false;
    }
    if (source is ObservationSource &&
        (source == ObservationSource.appleHealth ||
            source == ObservationSource.healthConnect)) {
      return false;
    }
    return true;
  }

  static Episode? _containing(List<Episode> episodes, LocalDate date) {
    for (final episode in episodes) {
      if (episode.contains(date)) return episode;
    }
    return null;
  }

  /// The pass-blocking outcome of [result], or null when it was allowed.
  static HealthPlatformResult? _notAllowed(HealthPlatformResult result) =>
      result is HealthPlatformAllowed ? null : result;

  Future<DateTime?> _readCursor() async {
    final raw = await _settings.get(SettingsKeys.healthSyncWrittenThroughMs);
    final ms = int.tryParse(raw ?? '');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
