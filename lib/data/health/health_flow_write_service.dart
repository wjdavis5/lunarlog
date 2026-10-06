/// The one-way, opt-in, forward-only menstrual-flow write path (Issue
/// #193): turns the bound profile's day entries and spotting observations
/// into `writeMenstrualFlow` / `writeIntermenstrualBleeding` calls on the
/// #173 platform port, in the order the issue's acceptance criteria pin:
///
/// * **Opt-in** — nothing runs until the operator binds a profile in
///   Settings (`SettingsKeys.healthStoreProfileId`), and nothing is
///   requested from the OS health store until the first sync pass asks for
///   write authorization (stamping the grant instant). Off is the default.
///   The pass asks only while the platform reports the write permission as
///   not yet asked; once it is granted there is nothing to ask, and a pass
///   that finds it already granted stamps the cursor without a request
///   (Issue #1478 — on Android the grant can come from the import's own
///   sheet or from Health Connect's settings, and a request there could
///   put a second sheet in front of the person for a read permission they
///   had just declined).
/// * **One-way** — this file only ever calls write (or, since Issue #619's
///   LLA-024, delete-by-own-record-id reconciliation) methods on
///   [HealthPlatformStore]; no read/query API exists on the port in this
///   issue, and no entry is ever created or modified from health-store
///   data. Entries the app itself imported *from* a health store
///   ([DayEntrySource.healthkit]/[DayEntrySource.healthConnect]) are never
///   echoed back — writing them would duplicate rows Apple Health already
///   holds and could become a loop once #217's import direction exists.
/// * **Forward-only** — the first successful authorization stamps
///   [SettingsKeys.healthSyncWrittenThroughMs] with the grant instant, and
///   that floor does not move. A row is looked at only when its
///   `updatedAt` is strictly after it, so pre-grant history is never
///   backfilled (Clue's own documented behavior, A3-35).
///
/// **What is sent is decided from what has been written (Issue #1581).**
/// The record ids this device wrote are held in the device-local
/// [HealthExportLedger] (Issue #936), each with the `updatedAt` its row
/// had when it was written, and read through [HealthExportMemory]. A pass
/// works out, for every row in scope, the records it should have in the
/// store now; sends the ones the ledger does not hold at the row's
/// present version; and deletes the ones the ledger holds that the row no
/// longer produces. Only a write the store accepted is remembered, so a
/// failed write, or one whose type is switched off, is still due on the
/// next pass, and nothing that was written is sent twice.
///
/// Until #1581 the floor was a cursor that moved to the newest row each
/// pass wrote, and a row was sent when it was newer than the cursor. That
/// cannot see a row that turns up with an older time: one that arrives
/// late from another device, a spotting entry whose day stops being a
/// bleed day, a row stamped by a clock a few seconds behind the one that
/// stamped the cursor, or an edit made while its type was switched off.
/// The floor is still stored to the microsecond ([_writeCursor], Issue
/// #1577).
///
/// **Forward-only holds for each write type** ([HealthWritePassState]).
/// Access is given type by type. A record of a type that was switched
/// off when its row was saved has never been written, and is not sent
/// when the type is switched on later: every pass that finds a type off
/// moves that type's own floor to the present. A record the ledger
/// already holds is different. It is in the store, so a correction to
/// its row made while the type was off is sent once the type is back,
/// instead of the store keeping the old value.
///
/// **An install that upgrades** keeps the cursor it had as its floor.
/// Its ledger was written by a build that listed every record a row
/// could produce, written or not, with the time of the pass; the first
/// pass of this build re-stamps it from the rows themselves
/// ([LocalHealthFlowWriteService._adoptEarlierLedger]).
///
/// **One pass at a time.** A request that arrives while a pass is
/// running gets the next pass, which starts when that one ends
/// ([LocalHealthFlowWriteService.syncNow]).
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

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;

import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/health/health_write_cursor.dart';
import 'package:lunarlog/domain/health/health_write_pass_state.dart';
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

import 'health_export_memory.dart';
import 'health_fertility_mapping.dart';
import 'health_flow_mapping.dart';
import 'health_record_ids.dart';
import 'health_symptom_mapping.dart';
import 'health_written_types.dart';

/// One due flow or spotting record, before it is sent to the port.
class _PendingWrite {
  _PendingWrite({
    required this.date,
    required this.tzName,
    required this.plan,
    required this.cycleStart,
    required this.recordId,
    required this.updatedAt,
    required this.kind,
    DateTime? storeVersion,
  }) : storeVersion = storeVersion ?? updatedAt;

  final LocalDate date;
  final String tzName;

  /// Never [HealthFlowNoWrite]: a row that maps to no sample is not queued
  /// ([_Batch.add]'s callers count it instead).
  final HealthFlowWritePlan plan;

  /// Whether [date] is the first day of its period episode — the
  /// `HKMetadataKeyMenstrualCycleStart` flag every `menstrualFlow` sample
  /// must carry (true on the cycle's first day, false otherwise). Always
  /// false for intermenstrual markers (that type carries no metadata).
  final bool cycleStart;

  /// The source row's ULID (day-entry id for flow, observation id for
  /// spotting) — Issue #186 sync mechanics: becomes Health Connect's
  /// `clientRecordId` / HealthKit's `HKMetadataKeyExternalUUID` so the
  /// write is idempotent and a tombstone can delete the exact sample. It
  /// is the row's own id, which is also what the export ledger files the
  /// record under.
  final String recordId;
  final DateTime updatedAt;

  /// Whether the row is a day entry or a spotting observation.
  final HealthExportLedgerKind kind;

  /// The version the store is given for the record. The row's own
  /// `updatedAt`, except for a spotting entry, whose record comes and
  /// goes with its day's flow while its own row stays as it was (see
  /// [LocalHealthFlowWriteService._collectSpotting]).
  final DateTime storeVersion;

  int get recordVersionMs => storeVersion.millisecondsSinceEpoch;
}

/// The longest period episode this service writes as one interval record
/// (Issue #1478). Health Connect's `MenstruationPeriodRecord` refuses an
/// interval longer than 31 days ("Period must not exceed 31 days",
/// connect-client 1.1.0) by throwing while the record is built, which would
/// fail every later pass. Thirty rather than thirty-one because the limit
/// is on elapsed time, and thirty-one calendar days that include an autumn
/// clock change last an hour longer than that. A longer episode keeps its
/// daily flow records; only the interval record is left out.
const int kHealthPeriodRecordMaxDays = 30;

/// The interval record one period episode should have in the store
/// (Issue #202's `MenstruationPeriodRecord`; Issue #1478). Its record id is
/// derived from [start], so the same episode keeps the same record as it
/// grows at its end and gets a new one when its first day changes.
class _DesiredPeriod {
  const _DesiredPeriod({
    required this.start,
    required this.end,
    required this.tzName,
  });

  /// The episode's first hand-logged bleed day (inclusive).
  final LocalDate start;

  /// The episode's last hand-logged bleed day (inclusive); the record ends
  /// on the last instant of this date (`localDayLastInstant`).
  final LocalDate end;

  /// The zone the record's instants are computed in: a hand-logged day's
  /// own zone (#180), and one `day_boundary.dart` can resolve.
  final String tzName;
}

/// An exported period interval as the ledger stores it:
/// `<first day>/<last day>`, ISO dates.
String _periodInterval(LocalDate start, LocalDate end) =>
    '${start.iso}/${end.iso}';

/// One day's due symptom writes (Issue #238): the HealthKit symptom
/// samples the day entry's tags resolve to that the store does not hold at
/// this version of the entry, in one channel call.
class _PendingSymptomWrite {
  const _PendingSymptomWrite({
    required this.entryId,
    required this.date,
    required this.tzName,
    required this.samples,
    required this.updatedAt,
  });

  /// The source day entry, which the export ledger files the samples
  /// under.
  final String entryId;
  final LocalDate date;
  final String tzName;

  /// Already-resolved samples, each carrying its own stable `recordId`
  /// (`symptom-<entryId>-<typeIdentifier>`) and the source entry's
  /// `updatedAt` as `recordVersionMs`.
  final List<HealthSymptomSample> samples;

  final DateTime updatedAt;
}

/// One day's due cervical-mucus write (Issue #228), before the port
/// payload's guard facts are attached.
class _PendingCervicalMucusWrite {
  const _PendingCervicalMucusWrite({
    required this.entryId,
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
  });

  final String entryId;
  final LocalDate date;
  final String tzName;
  final ResolvedCervicalMucus resolved;
  final String recordId;
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// One day's due ovulation-test write (Issue #228).
class _PendingOvulationWrite {
  const _PendingOvulationWrite({
    required this.entryId,
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
  });

  final String entryId;
  final LocalDate date;
  final String tzName;
  final ResolvedOvulationTest resolved;
  final String recordId;
  final DateTime updatedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// One due BBT observation write (Issue #228).
class _PendingBbtWrite {
  const _PendingBbtWrite({
    required this.observationId,
    required this.date,
    required this.tzName,
    required this.resolved,
    required this.recordId,
    required this.updatedAt,
    this.observedAt,
  });

  /// The source `observations` row id, preserved as the persisted ledger's
  /// grouping key (Issue #936).
  final String observationId;
  final LocalDate date;
  final String tzName;
  final ResolvedBasalBodyTemperature resolved;
  final String recordId;
  final DateTime updatedAt;
  final DateTime? observedAt;

  int get recordVersionMs => updatedAt.millisecondsSinceEpoch;
}

/// Accumulates one pass's plan: the due flow and spotting records join
/// [pending], rows that map to no sample are counted in [withoutSample],
/// period episodes join [desiredPeriods], the Issue #228
/// fertility/measurement signals join their own lists, and every row in
/// scope says what it should have in the store ([desiredByRow]).
class _Batch {
  final List<_PendingWrite> pending = [];
  final List<_PendingSymptomWrite> pendingSymptoms = [];
  final List<_PendingCervicalMucusWrite> pendingCervicalMucus = [];
  final List<_PendingOvulationWrite> pendingOvulation = [];
  final List<_PendingBbtWrite> pendingBbt = [];
  int withoutSample = 0;

  /// The record ids each in-scope day entry or spotting observation should
  /// have in the store now (Issues #930 and #1581), keyed by the row's id.
  /// Whatever the export ledger remembers for the row beyond this set is
  /// deleted ([LocalHealthFlowWriteService._reconcileRemovedRecords]). A
  /// row that is not in scope has no key here, and nothing of its is
  /// touched.
  final Map<String, Set<String>> desiredByRow = {};

  /// The flow record ids of no-flow days the ledger knows nothing of and
  /// that have not been asked for yet, with each day's `updatedAt`
  /// ([LocalHealthFlowWriteService._clearUnknownFlowRecords]).
  final Map<String, DateTime> unknownFlowRecords = {};

  /// The flow record id of every in-scope no-flow day, with the day's
  /// `updatedAt`. When the pass deletes one the ledger knew, the day has
  /// been asked for and must not be asked for again as an unknown one.
  final Map<String, DateTime> noFlowDays = {};

  /// Every live, exportable BBT observation's record id this pass, whether
  /// or not it is due — the "still present" side of the BBT diff. A
  /// remembered id absent from this set is a reading the operator cleared
  /// (its row is tombstoned or no longer resolves).
  final Set<String> liveBbtRecordIds = {};

  /// The period interval records the store should hold after this pass,
  /// keyed by record id (Issue #1478, [LocalHealthFlowWriteService
  /// ._collectPeriods]). A remembered record id absent from this map
  /// belongs to no qualifying episode any more.
  final Map<String, _DesiredPeriod> desiredPeriods = {};

  /// Qualifying episodes none of whose days carries a zone the day-boundary
  /// maths can resolve. Nothing can be written for one, so nothing that
  /// overlaps it is deleted either: a record that cannot be replaced is
  /// left alone rather than taken away.
  final List<Episode> unresolvedPeriods = [];

  /// Queues one due record. [plan] is never [HealthFlowNoWrite].
  void add(
    LocalDate date,
    String tzName,
    DateTime updatedAt,
    String recordId,
    HealthFlowWritePlan plan,
    Episode? containing,
    HealthExportLedgerKind kind, {
    DateTime? storeVersion,
  }) {
    pending.add(_PendingWrite(
      date: date,
      tzName: tzName,
      plan: plan,
      // #193 AC: the cycle-start flag is true exactly on the first day of
      // the containing episode (per episodes.dart) and false on every
      // other written sample. An intermenstrual marker carries no such
      // metadata, so it is always false there.
      cycleStart: plan is HealthFlowMenstrualSample &&
          containing != null &&
          containing.start == date,
      recordId: recordId,
      updatedAt: updatedAt,
      kind: kind,
      storeVersion: storeVersion,
    ));
  }
}

/// One pass's aggregate outcome, across every type (flow, period, symptom,
/// and Issue #228's fertility/measurement signals).
class _BatchOutcome {
  const _BatchOutcome({
    required this.written,
    required this.removed,
    required this.periodRecordsWritten,
    required this.symptomSamplesWritten,
    required this.cervicalMucusSamplesWritten,
    required this.ovulationTestSamplesWritten,
    required this.basalBodyTemperatureSamplesWritten,
    required this.failure,
  });

  final int written;

  /// Records taken out of the store because their row no longer produces
  /// them.
  final int removed;
  final int periodRecordsWritten;
  final int symptomSamplesWritten;
  final int cervicalMucusSamplesWritten;
  final int ovulationTestSamplesWritten;
  final int basalBodyTemperatureSamplesWritten;
  final HealthPlatformResult? failure;
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
    required HealthExportLedger ledger,
    DateTime Function()? now,
    DateTime Function()? rowClock,
  })  : _platform = platform,
        _binding = binding,
        _minorBindingAllowed = minorBindingAllowed,
        _profiles = profiles,
        _dayEntries = dayEntries,
        _observations = observations,
        _settings = settings,
        _guardiansForProfile = guardiansForProfile,
        _signedInUserId = signedInUserId,
        _memory = HealthExportMemory(ledger),
        _now = now ?? _deviceNow,
        _rowClock = rowClock ?? now ?? _deviceNow;

  static DateTime _deviceNow() => DateTime.now().toUtc();

  final HealthPlatformStore _platform;
  final HealthSyncBinding _binding;
  final bool _minorBindingAllowed;
  final ProfilesRepository _profiles;
  final DayEntriesRepository _dayEntries;
  final ObservationsRepository _observations;
  final SettingsStore _settings;
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;

  /// What this device has written to the store, and at which version of
  /// each row (Issue #1581): the persisted export ledger (Issue #936),
  /// read once for the bound profile so a tombstone or an edit made in a
  /// later app session still reconciles. Emptied by [onUnbound].
  final HealthExportMemory _memory;

  /// The device's own clock: the version a period record is written with,
  /// and what a reading's time is checked against before it is sent (the
  /// store refuses a record dated in its future, and its clock is the
  /// device's).
  final DateTime Function() _now;

  /// The clock rows are stamped with: the device's, plus what the sync
  /// engine has learned of how far it is from the server's. Used for one
  /// thing, the floor stamped when write access is granted (Issue #1581).
  /// Stamped with the device's own clock on a phone running ahead of the
  /// server, the floor was later than the time given to a day saved just
  /// after it, and that day was never sent.
  final DateTime Function() _rowClock;

  /// What this pass knows beside the floor and the ledger: each write
  /// type's own floor, and how far no-flow days have been cleared
  /// ([_openState] reads it, [_closeState] stores it).
  HealthWritePassState _state = const HealthWritePassState();

  /// The pass that is running, and the one waiting behind it.
  Future<HealthFlowSyncReport>? _running;
  Future<HealthFlowSyncReport>? _queued;

  /// Runs one sync pass for the currently bound profile. Never throws —
  /// every expected failure mode is a [HealthFlowSyncReport.blocked];
  /// unexpected storage errors propagate (the coordinator's job to
  /// tolerate), matching the port adapters' own contract of surfacing
  /// rather than swallowing protocol errors. Decomposed into one private
  /// method per stage (resolve → guard → grant → collect → write) so each
  /// stays under the quality gate's CRAP ceiling.
  ///
  /// One pass at a time (Issue #1581). Two passes side by side would each
  /// decide from the ledger before the other had written to it, and send
  /// the same records twice. A request that arrives while a pass is
  /// running is answered by the next pass, which starts when that one
  /// ends and so sees whatever was saved in the meantime; any number of
  /// such requests share that one pass.
  @override
  Future<HealthFlowSyncReport> syncNow() {
    final running = _running;
    if (running == null) return _startPass();
    return _queued ??= running.then(
      (_) => _startPass(),
      onError: (Object _) => _startPass(),
    );
  }

  Future<HealthFlowSyncReport> _startPass() {
    _queued = null;
    final pass = _pass();
    _running = pass;
    return pass.whenComplete(() {
      if (identical(_running, pass)) _running = null;
    });
  }

  Future<HealthFlowSyncReport> _pass() async {
    final bound = await _resolveBound();
    if (bound == null) {
      return const HealthFlowSyncReport(bound: false);
    }

    // Issue #936: read what this device has written from the persisted
    // ledger before deciding anything, so a relaunch (a fresh process on
    // iOS is the common case) neither sends everything again nor misses
    // an edit made in an earlier session.
    await _memory.load(bound.profile.id);

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

    // Issue #959: re-check the OS write permission on EVERY pass, not only
    // on the first write. The forward-only cursor is deliberately left in
    // place when the OS permission is revoked (nothing already written is
    // deleted), but the pass stops before any write — so a revocation in OS
    // settings takes effect on the very next pass and surfaces in the
    // Health sync screen's status line. `notAsked` does NOT block: that is
    // exactly the first-pass grant moment the stage below performs. No
    // exception text and no health content enters the report or the logs —
    // the blocked result is the typed `permissionDenied`, nothing more.
    final permission = await _platform.permissionStatus();
    if (permission == HealthPermissionStatus.denied) {
      await _noteEveryTypeOff();
      return const HealthFlowSyncReport(
        bound: true,
        blocked: HealthPlatformResult.permissionDenied(),
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

    final grant = await _ensureForwardOnlyCursor(
      bound.facts,
      alreadyGranted: permission.canWriteSome,
      currentStatus: permission,
    );
    if (grant.blocked != null) {
      // A refused/denied authorization — or `unavailable` (consent was
      // stamped but there is nothing to write to) — ends the pass.
      return HealthFlowSyncReport(
        bound: true,
        authorizationRequested: grant.grantedNow,
        blocked: grant.blocked,
      );
    }

    // Issue #1584: a failed query for which types are on says nothing
    // about them, so the pass ends here. Since Issue #1581 that matters
    // twice over: read as "none are on", it would also move every
    // type's floor to the present, and what was logged before it would
    // never be sent.
    final resolved = await _resolveGrantedTypes(grant.status);
    if (resolved.blocked != null) {
      return HealthFlowSyncReport(
        bound: true,
        authorizationRequested: grant.grantedNow,
        blocked: resolved.blocked,
      );
    }
    final grantedTypes = resolved.types;
    final floor = grant.cursor!;
    final opened = await _openState(floor, grantedTypes);

    final batch = await _collectBatch(
      bound.profile.id,
      floor,
      adoptEarlierLedger: opened.firstPass,
    );
    final outcome = await _writeBatch(
      batch,
      bound.facts,
      bound.profile.id,
      grantedTypes: grantedTypes,
    );
    await _closeState(opened.stored);

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
      samplesReconciled: outcome.removed,
    );
  }

  /// Reads [_state] for this pass and moves the floor of every write type
  /// that is switched off to the present (see [HealthWritePassState]).
  ///
  /// `firstPass` is true when nothing is stored: this binding has not run
  /// a pass on this build, so its ledger may be in the form an earlier
  /// build wrote ([_adoptEarlierLedger]). No-flow days then start out
  /// cleared through [floor]: a row is not looked at before it anyway, and
  /// the earlier build asked for every such day up to where its cursor
  /// stood.
  Future<({String? stored, bool firstPass})> _openState(
    DateTime floor,
    Set<String>? grantedTypes,
  ) async {
    final stored = await _settings.get(SettingsKeys.healthSyncWriteState);
    final earlier = HealthWritePassState.decode(stored);
    _state = (earlier ?? HealthWritePassState(clearedThrough: floor))
        .withTypesOff(healthWriteTypesOff(grantedTypes), _rowClock());
    return (stored: stored, firstPass: earlier == null);
  }

  /// Moves every write type's floor to the present, on a pass that found
  /// write access removed altogether. Such a pass ends before it reads
  /// which types are on, and without this what she logs meanwhile would
  /// be sent when a type comes back, which is not what happens when only
  /// some types are off.
  ///
  /// `denied` is something the store said: a status that could not be
  /// read comes back as `unavailable`, never as this.
  ///
  /// Nothing is stored when nothing is stored yet. This binding has then
  /// not run a pass on this build, and a state left here would stop its
  /// first real pass from reading an earlier build's ledger as one
  /// ([_adoptEarlierLedger]).
  Future<void> _noteEveryTypeOff() async {
    final stored = await _settings.get(SettingsKeys.healthSyncWriteState);
    final earlier = HealthWritePassState.decode(stored);
    if (earlier == null) return;
    _state = earlier.withTypesOff(
      healthWriteTypesOff(const <String>{}),
      _rowClock(),
    );
    await _closeState(stored);
  }

  /// Stores [_state] when the pass has changed it.
  Future<void> _closeState(String? stored) async {
    final now = _state.encode();
    if (now != stored) {
      await _settings.set(SettingsKeys.healthSyncWriteState, now);
    }
  }

  /// Brings a ledger written by a build before Issue #1581 into this
  /// build's form, on the first pass a binding runs here.
  ///
  /// That build listed, under each row it looked at, every record the row
  /// could produce, whether or not it was written, stamped with the time
  /// of the pass by the device's clock. Read as it stands, a write that
  /// failed on that build's last pass would count as done, and on a phone
  /// whose clock trails the server every row would look newer than its
  /// record and be sent again. So each row is stamped from the row itself:
  ///
  /// * a row at or before [floor] (where that build's cursor stood) was
  ///   written as it now is, and takes its own `updatedAt`;
  /// * a row after it was still owed, or its pass had failed, and takes
  ///   [floor], which leaves it due;
  /// * the flow record of a day with no flow is dropped: that build asked
  ///   for it to be deleted instead of writing it. If the day was saved
  ///   after [floor], so that the delete may not have gone through, it is
  ///   asked for again by [_clearUnknownFlowRecords], like any no-flow day
  ///   the ledger knows nothing of.
  ///
  /// Doing this twice changes nothing but to send again what was saved
  /// after the floor, so it is safe to repeat if the stored state is lost.
  Future<void> _adoptEarlierLedger(
    DateTime floor,
    List<DayEntry> entries,
    List<Observation> observationRows,
  ) async {
    final versions = <String, DateTime>{
      for (final entry in entries) entry.id: entry.updatedAt,
      for (final row in observationRows) row.id: row.updatedAt,
    };
    final neverWritten = <String>{
      for (final entry in entries)
        if (!isBleed(entry.flow)) healthFlowRecordId(entry.id),
    };
    final stamped = <HealthExportLedgerEntry>[];
    for (final written in _memory.all) {
      // A period record names an interval, not a row, so it has no
      // version here and is left as it is.
      final version = versions[written.sourceRowId];
      if (version == null) continue;
      if (neverWritten.contains(written.recordId)) continue;
      stamped.add(HealthExportLedgerEntry(
        recordId: written.recordId,
        profileId: written.profileId,
        sourceRowId: written.sourceRowId,
        kind: written.kind,
        localDate: written.localDate,
        exportedAt: version.isAfter(floor) ? floor : version,
      ));
    }
    await _memory.forget(neverWritten.where((id) => _memory.entryOf(id) != null));
    await _memory.remember(stamped);
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

  /// Forward-only grant stage: the cursor's first stamp is the moment
  /// write access is granted. `unavailable` also stamps — a device with no
  /// health store can never be written to, and re-prompting on every pass
  /// would churn; any other outcome leaves the cursor unset so the next
  /// pass retries. A non-null [GrantOutcome.blocked] always ends the pass.
  ///
  /// [alreadyGranted] is this pass's own #959 probe answering
  /// [HealthPermissionStatus.granted] (Issue #1478): every write is already
  /// allowed, so the stage stamps the cursor and asks nothing. The request
  /// is for the not-yet-asked state only. On Android it carries the read
  /// permissions too, so asking while the writes were already granted
  /// could raise Health Connect's sheet again — in the middle of logging a
  /// day — for a read permission the person had just declined.
  ///
  /// **An allowed request is not a grant** (Issue #1478's review). Neither
  /// native half reports the person's choice: iOS answers allowed when its
  /// sheet completes, whatever was chosen, and Android answers allowed when
  /// *any* permission was granted — the reads alone, for instance. So the
  /// status is read again after the request and the cursor is stamped only
  /// when it says granted. Stamping on "allowed" gave someone who allowed
  /// only the reads a cursor dated at the sheet: when they turned the
  /// writes on weeks later, every day logged since was written at once,
  /// days logged while write access was refused.
  Future<
      ({
        DateTime? cursor,
        HealthPlatformResult? blocked,
        bool grantedNow,
        HealthPermissionStatus status,
      })> _ensureForwardOnlyCursor(
    HealthGuardFacts facts, {
    required bool alreadyGranted,
    required HealthPermissionStatus currentStatus,
  }) async {
    final existing = await _readCursor();
    if (existing != null) {
      return (
        cursor: existing,
        blocked: null,
        grantedNow: false,
        status: currentStatus,
      );
    }
    if (alreadyGranted) {
      return (
        cursor: await _stampCursor(),
        blocked: null,
        grantedNow: false,
        status: currentStatus,
      );
    }
    final auth = await _platform.requestWriteAuthorization(facts);
    if (auth is HealthPlatformUnavailable) {
      return (
        cursor: await _stampCursor(),
        blocked: auth,
        grantedNow: true,
        status: currentStatus,
      );
    }
    final notAllowed = _notAllowed(auth);
    if (notAllowed != null) {
      return (
        cursor: null,
        blocked: notAllowed,
        grantedNow: true,
        status: currentStatus,
      );
    }
    final afterAuth = await _writesStillNotGranted();
    if (afterAuth.blocked == null) {
      return (
        cursor: await _stampCursor(),
        blocked: null,
        grantedNow: true,
        status: afterAuth.status,
      );
    }
    return (
      cursor: null,
      blocked: afterAuth.blocked,
      grantedNow: true,
      status: afterAuth.status,
    );
  }

  /// After an allowed authorization request: null when the write permission
  /// is now granted, otherwise the result the pass ends with (see
  /// [_ensureForwardOnlyCursor]). A permission surface that cannot answer
  /// is reported as that, not as a denial.
  Future<({HealthPlatformResult? blocked, HealthPermissionStatus status})>
      _writesStillNotGranted() async {
    final status = await _platform.permissionStatus();
    final blocked = switch (status) {
      HealthPermissionStatus.granted ||
      HealthPermissionStatus.writingSome =>
        null,
      HealthPermissionStatus.unavailable =>
        const HealthPlatformResult.unavailable(),
      HealthPermissionStatus.notAsked ||
      HealthPermissionStatus.denied =>
        const HealthPlatformResult.permissionDenied(),
    };
    return (blocked: blocked, status: status);
  }

  static HealthPlatformResult _grantedTypesErrorToResult(Object error) {
    if (error is PlatformException && error.code == 'unavailable') {
      return const HealthPlatformResult.unavailable();
    }
    if (error is MissingPluginException) {
      return const HealthPlatformResult.unavailable();
    }
    return HealthPlatformResult.failed('grantedWriteTypes failed: $error');
  }

  /// When permission is [HealthPermissionStatus.writingSome], queries the
  /// specific write types granted by the OS.
  Future<({Set<String>? types, HealthPlatformResult? blocked})>
      _resolveGrantedTypes(HealthPermissionStatus status) async {
    if (status != HealthPermissionStatus.writingSome) {
      return (types: null, blocked: null);
    }
    try {
      final types = await _platform.grantedWriteTypes();
      return (types: types, blocked: null);
    } catch (e) {
      return (types: null, blocked: _grantedTypesErrorToResult(e));
    }
  }

  /// Stamps the forward-only floor with the present moment, by the clock
  /// rows are stamped with ([_rowClock]), and returns it.
  Future<DateTime> _stampCursor() async {
    final stamped = _rowClock();
    await _writeCursor(stamped);
    return stamped;
  }

  /// Stores the cursor in both of its forms: the millisecond value this
  /// path has always written, and the microsecond value beside it (Issue
  /// #1577; why there are two is in `health_write_cursor.dart`).
  ///
  /// The microsecond value goes first. The millisecond value is the one
  /// that decides, so a write cut short between the two leaves the old
  /// cursor in force, and a new millisecond value is never read beside
  /// a microsecond value older than it.
  Future<void> _writeCursor(DateTime instant) async {
    await _settings.set(
      SettingsKeys.healthSyncWrittenThroughUs,
      '${instant.microsecondsSinceEpoch}',
    );
    await _settings.set(
      SettingsKeys.healthSyncWrittenThroughMs,
      '${instant.millisecondsSinceEpoch}',
    );
  }

  /// Builds the pass's plan from the bound profile's day entries and
  /// observations (Issue #1581). Every row in scope ([_inScope]) says
  /// which records it should have in the store now
  /// ([_Batch.desiredByRow]); of those, the ones the store does not hold
  /// at the row's present version ([_isDue]) are queued to be written.
  /// Mapped through `health_flow_mapping.dart`,
  /// `health_symptom_mapping.dart`, and — Issue #228 —
  /// `health_fertility_mapping.dart`, plus the period interval records the
  /// store should hold (Issue #202 — see [_collectPeriods]).
  Future<_Batch> _collectBatch(
    String profileId,
    DateTime floor, {
    bool adoptEarlierLedger = false,
  }) async {
    final entries = await _dayEntries.listForProfile(profileId);
    final observationRows = await _observations.listForProfile(profileId);
    if (adoptEarlierLedger) {
      await _adoptEarlierLedger(floor, entries, observationRows);
    }
    final pain = _indexPain(observationRows);
    final bleedDays = bleedDatesOf(entries);
    final episodes = deriveEpisodes(bleedDays);
    final batch = _Batch();
    _collectPeriods(profileId, entries, floor, batch);
    for (final entry in entries) {
      if (!_inScope(entry.id, entry.updatedAt, entry.source, floor)) continue;
      _collectEntry(
        entry,
        _containing(episodes, entry.localDate),
        _gradedPainForEntry(entry, pain.byEntryId, pain.byDate),
        batch,
      );
    }
    _collectObservationWrites(
      observationRows: observationRows,
      bleedDays: bleedDays,
      episodes: episodes,
      dayVersions: {
        for (final entry in entries) entry.localDate: entry.updatedAt,
      },
      batch: batch,
      floor: floor,
    );
    return batch;
  }

  /// Issue #238 / Issue #934: the pain observations by entry id and by
  /// date, so each entry resolves its own graded pain severity rather than
  /// inheriting the profile's lifetime maximum.
  static ({
    Map<String, List<Observation>> byEntryId,
    Map<LocalDate, List<Observation>> byDate,
  }) _indexPain(List<Observation> observationRows) {
    final byEntryId = <String, List<Observation>>{};
    final byDate = <LocalDate, List<Observation>>{};
    for (final observation in observationRows) {
      if (observation.category != ObservationCategory.pain) continue;
      byEntryId.putIfAbsent(observation.dayEntryId, () => []).add(observation);
      byDate.putIfAbsent(observation.localDate, () => []).add(observation);
    }
    return (byEntryId: byEntryId, byDate: byDate);
  }

  /// One in-scope day entry's part of the plan: the records it should have
  /// in the store, and the writes for those that are due.
  void _collectEntry(
    DayEntry entry,
    Episode? containing,
    Map<String, int> gradedPain,
    _Batch batch,
  ) {
    final desired = healthRecordIdsForEntry(entry);
    final flowId = healthFlowRecordId(entry.id);
    final plan = mapFlowToHealthWrite(
      entry.flow,
      inPeriodEpisode: containing != null,
    );
    if (plan is HealthFlowNoWrite) {
      // [healthRecordIdsForEntry] always names the flow record, because a
      // tombstone has to be able to address it. A day with no flow to
      // write should have none in the store: if an earlier pass wrote one
      // (Issue #619, LLA-024 — bleeding edited to `notBleeding`), leaving
      // it out here is what gets it deleted.
      desired.remove(flowId);
      batch.withoutSample++;
      batch.noFlowDays[flowId] = entry.updatedAt;
      // And if the ledger knows of none, one may still be there from an
      // earlier binding or an earlier install, whose ledger is gone.
      if (_memory.entryOf(flowId) == null &&
          _state.notYetCleared(entry.updatedAt)) {
        batch.unknownFlowRecords[flowId] = entry.updatedAt;
      }
    } else if (_isDue(flowId, entry.updatedAt, _writeTypeOf(plan))) {
      batch.add(
        entry.localDate,
        entry.tz,
        entry.updatedAt,
        flowId,
        plan,
        containing,
        HealthExportLedgerKind.entry,
      );
    }
    batch.desiredByRow[entry.id] = desired;
    final symptomWrite = _symptomWriteFor(entry, gradedPain);
    if (symptomWrite != null) batch.pendingSymptoms.add(symptomWrite);
    final fertility = _fertilityWritesFor(entry);
    final cervical = fertility.cervicalMucus;
    if (cervical != null) batch.pendingCervicalMucus.add(cervical);
    batch.pendingOvulation.addAll(fertility.ovulation);
  }

  /// Decides which period interval records the store should hold after
  /// this pass (Issue #202; rewritten by Issue #1478's review), into
  /// [_Batch.desiredPeriods]. [_reconcilePeriodRecords] then makes the
  /// store match. Three rules:
  ///
  /// * **Hand-logged days only.** The episodes are derived from the bleed
  ///   days lunarlog itself logged — the same source test [_inScope]
  ///   applies, without the floor. A day imported from Apple Health or
  ///   Health Connect can therefore never start, extend, or reshape a
  ///   written period: an import (a background one included) writes
  ///   nothing back to the store. It also means the record's zone always
  ///   comes from a hand-logged day; an imported row carries a
  ///   fixed-offset name (`UTC+02:00`) that `day_boundary.dart` cannot
  ///   resolve. One imported day between two hand-logged ones is an
  ///   ordinary one-day gap; two in a row split the episode.
  /// * **A record exactly when a day of the episode is in the store.** An
  ///   episode qualifies when this device has exported a record for at
  ///   least one of its days, or is doing so in this pass
  ///   ([_isOrWillBeExported]), and it is no longer than
  ///   [kHealthPeriodRecordMaxDays]. So an episode made only of days logged
  ///   before sync was turned on gets nothing, and an episode that loses
  ///   its first day, is split, or shrinks back under the limit still gets
  ///   a record for what remains. A qualifying episode is written with its
  ///   true first day even when that day was logged before sync was on: a
  ///   clipped start would put a wrong period in the store.
  /// * **A zone that resolves, or nothing.** The zone is the first of the
  ///   episode's days whose zone the day-boundary maths accepts. If none
  ///   does, the episode goes to [_Batch.unresolvedPeriods] and is left
  ///   alone — a failure that can never succeed must not fail every pass.
  void _collectPeriods(
    String profileId,
    List<DayEntry> entries,
    DateTime floor,
    _Batch batch,
  ) {
    final own = <LocalDate, DayEntry>{
      for (final entry in entries)
        if (_isHandLoggedBleed(entry)) entry.localDate: entry,
    };
    for (final episode in deriveEpisodes(own.keys)) {
      if (episode.lengthDays > kHealthPeriodRecordMaxDays) continue;
      final days = _handLoggedDaysOf(episode, own);
      if (!days.any((day) => _isOrWillBeExported(day, floor))) continue;
      final tzName = _firstResolvableZone(days, episode);
      if (tzName == null) {
        batch.unresolvedPeriods.add(episode);
        continue;
      }
      batch.desiredPeriods[healthPeriodRecordId(profileId, episode.start)] =
          _DesiredPeriod(
            start: episode.start,
            end: episode.end,
            tzName: tzName,
          );
    }
  }

  /// A live bleed day lunarlog itself logged, as opposed to one imported
  /// from an OS health store.
  static bool _isHandLoggedBleed(DayEntry entry) =>
      entry.deletedAt == null &&
      isBleed(entry.flow) &&
      !_isHealthStoreImport(entry.source);

  /// Whether the store holds, or is about to be sent, a flow record for
  /// [day]: the export ledger remembers one, or the row was saved after
  /// the forward-only [floor] and after flow was last found switched off,
  /// so this pass writes it if an earlier one has not.
  ///
  /// The day's flow record, not any record of its row: a discharge or an
  /// ovulation test written from the same day while flow was off says
  /// nothing about a period, and counting it wrote the period's dates
  /// when flow came back though none of its days was sent.
  bool _isOrWillBeExported(DayEntry day, DateTime floor) =>
      _memory.entryOf(healthFlowRecordId(day.id)) != null ||
      (day.updatedAt.isAfter(floor) &&
          _state.admitsNew(HealthWriteTypes.menstrualFlow, day.updatedAt));

  /// [episode]'s hand-logged bleed days, first to last.
  static List<DayEntry> _handLoggedDaysOf(
    Episode episode,
    Map<LocalDate, DayEntry> own,
  ) {
    final days = <DayEntry>[];
    for (var date = episode.start;
        !date.isAfter(episode.end);
        date = date.addDays(1)) {
      final entry = own[date];
      if (entry != null) days.add(entry);
    }
    return days;
  }

  /// The zone of the first of [days] in which [episode]'s two instants can
  /// be computed, or null when none of them can.
  static String? _firstResolvableZone(List<DayEntry> days, Episode episode) {
    for (final day in days) {
      try {
        localDayInstant(episode.start, day.tz);
        localDayLastInstant(episode.end, day.tz);
        return day.tz;
      } on TimeZoneResolutionException {
        continue;
      }
    }
    return null;
  }

  /// The observation half of [_collectBatch]: spotting markers and Issue
  /// #228's BBT values.
  void _collectObservationWrites({
    required List<Observation> observationRows,
    required Set<LocalDate> bleedDays,
    required List<Episode> episodes,
    required Map<LocalDate, DateTime> dayVersions,
    required _Batch batch,
    required DateTime floor,
  }) {
    for (final row in observationRows) {
      if (row.category == ObservationCategory.spotting) {
        _collectSpotting(
          row,
          bleedDays,
          episodes,
          dayVersions[row.localDate],
          batch,
          floor,
        );
      }
      // Issue #930: every *live* exportable BBT row counts as present,
      // whether or not it is due, so an unchanged reading is never mistaken
      // for a cleared one. `_bbtWriteFor` enforces source separation
      // (resolveBasalBodyTemperature returns null for a platform- or
      // wearable-sourced or excluded row).
      if (resolveBasalBodyTemperature(row) != null) {
        batch.liveBbtRecordIds.add(healthBbtRecordId(row.id));
      }
      final bbt = _bbtWriteFor(row, floor);
      if (bbt != null) batch.pendingBbt.add(bbt);
    }
  }

  /// One spotting observation's part of the plan.
  ///
  /// On a bleed day it should have nothing in the store: the day's own
  /// flow sample already carries the intensity, and a spotting record
  /// beside it would be a second, contradictory sample for the same day.
  /// The row stays in scope all the same (Issue #1581), which is what puts
  /// both changes of mind right. A marker written before the day was given
  /// a flow is taken out; and when a flow is cleared, the spotting entry
  /// under it, which nothing has touched, is written.
  ///
  /// That second write is of a record the store has held and let go, for
  /// a row that has not changed. A store may refuse a record it has seen
  /// at the same version, so the version it is given is the later of the
  /// row's own time and its day's ([dayVersion]): the day changed each
  /// time the record came or went.
  void _collectSpotting(
    Observation row,
    Set<LocalDate> bleedDays,
    List<Episode> episodes,
    DateTime? dayVersion,
    _Batch batch,
    DateTime floor,
  ) {
    if (!_inScope(row.id, row.updatedAt, row.source, floor)) return;
    if (bleedDays.contains(row.localDate)) {
      batch.withoutSample++;
      batch.desiredByRow[row.id] = const {};
      return;
    }
    final recordId = healthSpottingRecordId(row.id);
    batch.desiredByRow[row.id] = {recordId};
    final containing = _containing(episodes, row.localDate);
    final plan = mapSpottingToHealthWrite(inPeriodEpisode: containing != null);
    if (!_isDue(recordId, row.updatedAt, _writeTypeOf(plan))) return;
    batch.add(
      row.localDate,
      row.tz,
      row.updatedAt,
      recordId,
      plan,
      containing,
      HealthExportLedgerKind.spotting,
      storeVersion: _later(row.updatedAt, dayVersion),
    );
  }

  /// The write type a flow or spotting record is stored as.
  static String _writeTypeOf(HealthFlowWritePlan plan) =>
      plan is HealthFlowIntermenstrualMarker
          ? HealthWriteTypes.spotting
          : HealthWriteTypes.menstrualFlow;

  /// The later of [a] and [b], or [a] when there is no [b].
  static DateTime _later(DateTime a, DateTime? b) =>
      b != null && b.isAfter(a) ? b : a;

  /// Resolves one in-scope day entry's fertility tags (Issue #228) into
  /// the writes that are due: its cervical-mucus appearance (at most one —
  /// discharge is single-select) and its ovulation-test results
  /// (deduplicated by platform result).
  ({
    _PendingCervicalMucusWrite? cervicalMucus,
    List<_PendingOvulationWrite> ovulation,
  }) _fertilityWritesFor(DayEntry entry) {
    final cervical = resolveCervicalMucus(entry.tags);
    final cervicalId = healthCervicalMucusRecordId(entry.id);
    return (
      cervicalMucus: cervical == null ||
              !_isDue(
                cervicalId,
                entry.updatedAt,
                HealthWriteTypes.cervicalMucus,
              )
          ? null
          : _PendingCervicalMucusWrite(
              entryId: entry.id,
              date: entry.localDate,
              tzName: entry.tz,
              resolved: cervical,
              recordId: cervicalId,
              updatedAt: entry.updatedAt,
            ),
      ovulation: [
        for (final result in resolveOvulationTests(entry.tags))
          if (_isDue(
            healthOvulationRecordId(entry.id, result.healthKitResult),
            entry.updatedAt,
            HealthWriteTypes.ovulationTest,
          ))
            _PendingOvulationWrite(
              entryId: entry.id,
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
  /// a manually tracked/imported `bbt` value that is in scope and due.
  /// Source separation is enforced by [resolveBasalBodyTemperature] (a
  /// platform- or wearable-sourced value produces no write) and by
  /// [_inScope] (forward-only, never echo a health-store-sourced row).
  _PendingBbtWrite? _bbtWriteFor(Observation row, DateTime floor) {
    if (row.category != ObservationCategory.bbt) return null;
    if (!_inScope(row.id, row.updatedAt, row.source, floor)) return null;
    final resolved = resolveBasalBodyTemperature(row);
    if (resolved == null) return null;
    final recordId = healthBbtRecordId(row.id);
    if (!_isDue(
      recordId,
      row.updatedAt,
      HealthWriteTypes.basalBodyTemperature,
    )) {
      return null;
    }
    return _PendingBbtWrite(
      observationId: row.id,
      date: row.localDate,
      tzName: row.tz,
      resolved: resolved,
      recordId: recordId,
      updatedAt: row.updatedAt,
      observedAt: row.observedAt,
    );
  }

  /// Resolves one in-scope day entry's [DayEntry.tags] into its due
  /// symptom write, or null when the day carries no mapped symptom that
  /// the store does not already hold at this version of the entry. Never
  /// sends an empty batch (the port documents that at least one sample is
  /// present).
  _PendingSymptomWrite? _symptomWriteFor(
    DayEntry entry,
    Map<String, int> gradedPain,
  ) {
    final versionMs = entry.updatedAt.millisecondsSinceEpoch;
    final due = [
      for (final symptom in resolveHealthKitSymptoms(
        tags: entry.tags,
        gradedPainIntensities: gradedPain,
      ))
        if (_isDue(
          healthSymptomRecordId(entry.id, symptom.typeIdentifier),
          entry.updatedAt,
          symptom.typeIdentifier,
        ))
          HealthSymptomSample(
            healthKitTypeIdentifier: symptom.typeIdentifier,
            severity: symptom.severity,
            // Stable per (day entry, symptom type): a re-write replaces the
            // same sample (sync identifier/version), and a later removal
            // can address it by this exact id.
            recordId: healthSymptomRecordId(entry.id, symptom.typeIdentifier),
            recordVersionMs: versionMs,
          ),
    ];
    if (due.isEmpty) return null;
    return _PendingSymptomWrite(
      entryId: entry.id,
      date: entry.localDate,
      tzName: entry.tz,
      updatedAt: entry.updatedAt,
      samples: due,
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

  static bool _canWriteType(Set<String>? granted, String type) =>
      granted == null || granted.contains(type);

  static HealthPlatformResult? _firstBatchFailure(
    List<HealthPlatformResult?> results,
  ) {
    for (final result in results) {
      if (result != null) return result;
    }
    return null;
  }

  /// Sends the plan to the port: the due writes, then the removal of
  /// records their rows no longer produce, and last the period interval
  /// records. Keeps going after a failure (one bad day must not hide the
  /// others) and reports the first one. Nothing that failed is remembered
  /// as written, so the next pass sends it again; everything the store
  /// accepted is, so the next pass does not.
  Future<_BatchOutcome> _writeBatch(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId, {
    Set<String>? grantedTypes,
  }) async {
    final canWriteFlow =
        _canWriteType(grantedTypes, HealthWriteTypes.menstrualFlow);
    final flow = await _writeFlowRecords(
      batch.pending,
      facts,
      profileId,
      canWriteFlow: canWriteFlow,
      canWriteSpotting: _canWriteType(grantedTypes, HealthWriteTypes.spotting),
    );
    final symptoms = await _writeSymptomRecords(
      batch.pendingSymptoms,
      facts,
      profileId,
      grantedTypes: grantedTypes,
    );
    final cervical = await _writeCervicalMucusRecords(
      batch.pendingCervicalMucus,
      facts,
      profileId,
      allowed: _canWriteType(grantedTypes, HealthWriteTypes.cervicalMucus),
    );
    final ovulation = await _writeOvulationTestRecords(
      batch.pendingOvulation,
      facts,
      profileId,
      allowed: _canWriteType(grantedTypes, HealthWriteTypes.ovulationTest),
    );
    final bbt = await _writeBbtRecords(
      batch.pendingBbt,
      facts,
      profileId,
      allowed:
          _canWriteType(grantedTypes, HealthWriteTypes.basalBodyTemperature),
    );
    // Issue #930: after this pass's writes, take out any record a row put
    // in the store and no longer produces.
    final removed = await _reconcileRemovedRecords(batch, facts, grantedTypes);
    // Issue #1478: and the period interval records, which no single day
    // entry owns. Last, so the days a record covers are already in the
    // store when it is written.
    final periods = await _reconcilePeriodRecords(
      batch,
      facts,
      profileId,
      allowed: canWriteFlow,
    );
    return _BatchOutcome(
      written: flow.written,
      removed: removed.removed,
      periodRecordsWritten: periods.written,
      symptomSamplesWritten: symptoms.written,
      cervicalMucusSamplesWritten: cervical.written,
      ovulationTestSamplesWritten: ovulation.written,
      basalBodyTemperatureSamplesWritten: bbt.written,
      failure: _firstBatchFailure([
        flow.failure,
        symptoms.failure,
        cervical.failure,
        ovulation.failure,
        bbt.failure,
        removed.failure,
        periods.failure,
      ]),
    );
  }

  /// Remembers that the store accepted [recordId] for its row as it stood
  /// at [version]. The only way a day's or an observation's record enters
  /// the export ledger, so the ledger never names a record that was not
  /// written.
  Future<void> _remember(
    String profileId, {
    required String recordId,
    required String sourceRowId,
    required HealthExportLedgerKind kind,
    required LocalDate date,
    required DateTime version,
  }) =>
      _memory.remember([
        HealthExportLedgerEntry(
          recordId: recordId,
          profileId: profileId,
          sourceRowId: sourceRowId,
          kind: kind,
          localDate: date.iso,
          exportedAt: version,
        ),
      ]);

  /// Takes out of the store every record a row put there and no longer
  /// produces (Issue #930; rewritten by Issue #1581): a symptom or a
  /// fertility tag removed from a day, a flow cleared, a spotting entry
  /// whose day was given a flow, a reading cleared or excluded.
  ///
  /// The comparison is between what the export ledger remembers for a row
  /// and what the row produces now ([_Batch.desiredByRow]), so it covers
  /// every row in scope on every pass, not only the rows that changed
  /// since the last one. An id that is unchanged (a graded intensity or a
  /// flow edit rewrites the same id) is left alone. One delete is sent for
  /// each row, so a failure costs that row's removals and no others, and a
  /// record is forgotten only when the store has let it go: a delete that
  /// failed is sent again on the next pass.
  ///
  /// A record whose type is switched off is not asked for at all
  /// ([healthRecordDeletable]). The native halves pass over a type they
  /// may not write and still answer allowed, so asking would forget a
  /// record that is still in the store. It stays remembered, and is
  /// removed once the type is back on.
  ///
  /// Deleting is a health-API touch, so it goes through the same
  /// [_authorityDrift] recheck and guarded
  /// [HealthPlatformStore.deleteRecords] as every write — no new bypass.
  Future<({int removed, HealthPlatformResult? failure})>
      _reconcileRemovedRecords(
    _Batch batch,
    HealthGuardFacts facts,
    Set<String>? grantedTypes,
  ) async {
    var removed = 0;
    HealthPlatformResult? failure;
    // The no-flow days whose flow record this pass has just deleted.
    final cleared = <DateTime>[];
    for (final stale in _staleRecords(batch, grantedTypes)) {
      final outcome = await _removeFromStore(stale, facts);
      removed += outcome.gone.length;
      failure ??= outcome.failure;
      cleared.addAll([
        for (final recordId in outcome.gone) ?batch.noFlowDays[recordId],
      ]);
    }
    final unclear =
        await _clearUnknownFlowRecords(batch, facts, grantedTypes, cleared);
    return (removed: removed, failure: failure ?? unclear);
  }

  /// Asks the store to delete the flow record of each no-flow day the
  /// ledger knows nothing of, once (Issue #619, LLA-024; kept by Issue
  /// #1581).
  ///
  /// The ledger says what this binding wrote. A record written under an
  /// earlier binding, or by an install whose data is gone, is still in the
  /// store and is in no ledger, so a day she has since cleared would keep
  /// its flow there. The record's id is the day's own, so the delete can
  /// be sent without knowing: a delete of an id the store does not hold is
  /// a no-op. It is sent once for each save of such a day
  /// ([HealthWritePassState.clearedThrough]), which is what every build
  /// before this one did, and not at all while flow is switched off.
  ///
  /// [alreadyCleared] is the no-flow days whose flow record the pass has
  /// just deleted because the ledger did know it. Those have been asked
  /// for; without this the next pass would find them unknown and ask
  /// again. They count only once the unknown ones are through, since the
  /// mark is one time for all of them.
  ///
  /// Returns the store's answer when it did not let the records go, or
  /// null.
  Future<HealthPlatformResult?> _clearUnknownFlowRecords(
    _Batch batch,
    HealthGuardFacts facts,
    Set<String>? grantedTypes,
    List<DateTime> alreadyCleared,
  ) async {
    final unknown = batch.unknownFlowRecords;
    if (unknown.isNotEmpty) {
      if (!_canWriteType(grantedTypes, HealthWriteTypes.menstrualFlow)) {
        return null;
      }
      final drift = await _authorityDrift(facts);
      if (drift != null) return drift;
      final result = await _platform.deleteRecords(facts, unknown.keys.toList());
      if (!_flowRecordsGone(result)) return result;
    }
    for (final version in [...unknown.values, ...alreadyCleared]) {
      _state = _state.withClearedThrough(version);
    }
    return null;
  }

  /// The records to delete, one list for each row that has any, and one
  /// for the BBT readings whose observation is no longer live and
  /// resolved (the operator cleared the reading and left the day in
  /// place).
  List<List<String>> _staleRecords(_Batch batch, Set<String>? grantedTypes) {
    final groups = [
      for (final row in batch.desiredByRow.entries)
        _deletable(
          _memory.recordIdsOf(row.key).difference(row.value),
          grantedTypes,
        ),
      _deletable(
        {
          for (final written in _memory.ofKind(HealthExportLedgerKind.bbt))
            if (!batch.liveBbtRecordIds.contains(written.recordId))
              written.recordId,
        },
        grantedTypes,
      ),
    ];
    return [
      for (final group in groups)
        if (group.isNotEmpty) group,
    ];
  }

  /// Those of [recordIds] a delete is sure to reach with [grantedTypes]
  /// switched on.
  List<String> _deletable(Set<String> recordIds, Set<String>? grantedTypes) => [
        for (final recordId in recordIds)
          if (healthRecordDeletable(_memory.entryOf(recordId), grantedTypes))
            recordId,
      ];

  /// Deletes [recordIds] from the store and forgets the ones it let go.
  /// Answers which those were, and the store's answer when any of the
  /// rest is still there: a refusal, or a delete that passed some over.
  Future<({List<String> gone, HealthPlatformResult? failure})>
      _removeFromStore(
    List<String> recordIds,
    HealthGuardFacts facts,
  ) async {
    final drift = await _authorityDrift(facts);
    if (drift != null) return (gone: const <String>[], failure: drift);
    final result = await _platform.deleteRecords(facts, recordIds);
    final gone = _letGo(recordIds, result);
    if (gone == null) return (gone: const <String>[], failure: result);
    await _memory.forget(gone);
    return (
      gone: gone,
      failure: gone.length == recordIds.length ? null : result,
    );
  }

  /// Those of [recordIds] the store let go, going by its answer to the
  /// delete, or null when it refused the delete altogether.
  ///
  /// Since Issue #1583 the native halves say which types they passed over
  /// because their write permission is off ([HealthPlatformPartial]), and
  /// they say so for any type that is off, whether or not one of
  /// [recordIds] is of that type. A record of a type they name is still in
  /// the store and stays remembered; the rest are gone. The pass does not
  /// ask for a record whose type it knows to be off ([_deletable]), so
  /// this matters when a type is switched off between that check and the
  /// delete.
  List<String>? _letGo(List<String> recordIds, HealthPlatformResult result) {
    if (result is HealthPlatformAllowed) return recordIds;
    if (result is! HealthPlatformPartial) return null;
    return [
      for (final recordId in recordIds)
        if (!_passedOver(recordId, result.skippedTypes)) recordId,
    ];
  }

  /// Whether a delete that skipped [skippedTypes] may have left [recordId]
  /// in the store. A spotting entry's record is an intermenstrual marker,
  /// or a light flow sample when its day falls inside a period, and the
  /// ledger does not say which, so either type being skipped counts.
  bool _passedOver(String recordId, Set<String> skippedTypes) {
    final spotting =
        _memory.entryOf(recordId)?.kind == HealthExportLedgerKind.spotting;
    return healthRecordMatchesSkippedType(
          recordId,
          skippedTypes,
          isSpotting: spotting,
        ) ||
        (spotting && skippedTypes.contains(HealthWriteTypes.menstrualFlow));
  }

  /// Whether a delete of flow or period records went through: the store
  /// allowed it, or passed over other types only (Issue #1583).
  static bool _flowRecordsGone(HealthPlatformResult result) =>
      result is HealthPlatformAllowed ||
      (result is HealthPlatformPartial &&
          !result.skippedTypes.contains(HealthWriteTypes.menstrualFlow));

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

  /// Whether [write]'s own type is switched on (Issue #1555).
  static bool _canWriteFlowPlan(
    _PendingWrite write, {
    required bool canWriteFlow,
    required bool canWriteSpotting,
  }) {
    if (write.plan is HealthFlowMenstrualSample && !canWriteFlow) {
      return false;
    }
    if (write.plan is HealthFlowIntermenstrualMarker && !canWriteSpotting) {
      return false;
    }
    return true;
  }

  /// Sends the due flow and spotting records to the port and remembers
  /// each one the store accepts.
  ///
  /// Keeps writing after a failure (one bad day must not hide the others)
  /// and reports the first. A record that failed is not remembered, so the
  /// next pass sends it again. A record whose type is switched off is
  /// passed over in the same way (Issue #1555): it stays due, and is sent
  /// when the type is back on, with whatever its row says then.
  ///
  /// Stops outright in two cases. The moment [_authorityDrift] finds the
  /// pass's authority has changed underneath it (Issue #620, LLA-023): a
  /// drift found on day N means every day after N would be written under
  /// the same now-invalid authority too. And when the platform answers
  /// that it has no such store: every other record would get the same
  /// answer.
  Future<({int written, HealthPlatformResult? failure})> _writeFlowRecords(
    List<_PendingWrite> pending,
    HealthGuardFacts facts,
    String profileId, {
    bool canWriteFlow = true,
    bool canWriteSpotting = true,
  }) async {
    var written = 0;
    HealthPlatformResult? failure;
    for (final write in pending) {
      if (!_canWriteFlowPlan(
        write,
        canWriteFlow: canWriteFlow,
        canWriteSpotting: canWriteSpotting,
      )) {
        continue;
      }
      final stopped = await _authorityDrift(facts);
      if (stopped != null) {
        failure ??= stopped;
        break;
      }
      final result = await _sendSample(write, facts);
      if (result is HealthPlatformAllowed) {
        written++;
        await _remember(
          profileId,
          recordId: write.recordId,
          sourceRowId: write.recordId,
          kind: write.kind,
          date: write.date,
          version: write.updatedAt,
        );
        continue;
      }
      failure ??= result;
      if (result is HealthPlatformUnavailable) break;
    }
    return (written: written, failure: failure);
  }

  /// Sends [write]'s menstrual-flow or intermenstrual-bleeding sample.
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
        throw StateError('unreachable: a row with no sample is never queued');
    }
  }

  /// Makes the store's period interval records match
  /// [_Batch.desiredPeriods] (Issue #202's `MenstruationPeriodRecord`;
  /// Issue #1478 and its review).
  ///
  /// A period record is the one export derived from several day entries,
  /// so neither a tombstone nor [_reconcileEntryRemovals]'s per-entry diff
  /// can address it; this is the only place one is written or removed.
  /// What it does:
  ///
  /// * writes every desired record the export ledger does not remember, or
  ///   remembers with different days ([_writeDuePeriodRecords]);
  /// * then deletes every remembered record that is no longer desired
  ///   ([_removeStalePeriodRecords]) — its episode is gone, no longer
  ///   qualifies, or now starts on a different day (the record id is
  ///   derived from the first day, so that episode has a new record).
  ///
  /// Writes come first and a failed write ends the step, so a record is
  /// never taken away while its replacement is still owed. A failure is
  /// reported, and the step is tried again on the next pass.
  ///
  /// On iOS nothing here reaches the store: HealthKit has no interval
  /// record (episode boundaries ride the flow samples' cycle-start
  /// metadata, #193), the write answers `unavailable`, and nothing is ever
  /// remembered.
  Future<({int written, HealthPlatformResult? failure})>
      _reconcilePeriodRecords(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId, {
    bool allowed = true,
  }) async {
    if (!allowed) {
      return (written: 0, failure: null);
    }
    final writes = await _writeDuePeriodRecords(batch, facts, profileId);
    if (writes.failure != null) return writes;
    return (
      written: writes.written,
      failure: await _removeStalePeriodRecords(batch, facts),
    );
  }

  /// Writes each desired period record that is missing or whose days have
  /// changed. Health Connect keeps whichever copy of a record carries the
  /// higher version, so every write takes [_nextPeriodVersion]. A platform
  /// that answers `unavailable` has no such record type: that is not a
  /// failure, and there is no point asking again in this pass. Stops at the
  /// first failure, and before any store call on a mid-pass loss of
  /// authority ([_authorityDrift]; Issue #620, LLA-023).
  Future<({int written, HealthPlatformResult? failure})>
      _writeDuePeriodRecords(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId,
  ) async {
    var written = 0;
    for (final due in batch.desiredPeriods.entries) {
      final period = due.value;
      final remembered = _memory.entryOf(due.key);
      final interval = _periodInterval(period.start, period.end);
      if (remembered?.sourceRowId == interval) continue;
      final drift = await _authorityDrift(facts);
      if (drift != null) return (written: written, failure: drift);
      final versionMs = _nextPeriodVersion(remembered);
      final result = await _platform.writeMenstrualPeriod(
        HealthMenstrualPeriodWrite(
          facts: facts,
          start: period.start,
          end: period.end,
          tzName: period.tzName,
          recordId: due.key,
          recordVersionMs: versionMs,
        ),
      );
      if (result is HealthPlatformUnavailable) break;
      if (result is! HealthPlatformAllowed) {
        return (written: written, failure: result);
      }
      written++;
      await _rememberPeriod(
        profileId,
        due.key,
        interval,
        period.start,
        versionMs,
      );
    }
    return (written: written, failure: null);
  }

  /// Deletes each remembered period record that is no longer desired, and
  /// forgets it once the store has let it go. A record overlapping an
  /// episode whose zone cannot be resolved is left alone
  /// ([_Batch.unresolvedPeriods]): nothing could be written in its place.
  /// Returns the first failure, or null.
  Future<HealthPlatformResult?> _removeStalePeriodRecords(
    _Batch batch,
    HealthGuardFacts facts,
  ) async {
    for (final written in _memory.ofKind(HealthExportLedgerKind.period)) {
      final recordId = written.recordId;
      if (batch.desiredPeriods.containsKey(recordId)) continue;
      // The ledger files a period record under the days it was written
      // with.
      if (_overlapsAny(written.sourceRowId, batch.unresolvedPeriods)) continue;
      final drift = await _authorityDrift(facts);
      if (drift != null) return drift;
      final deleted = await _platform.deleteRecords(facts, [recordId]);
      if (!_flowRecordsGone(deleted)) return deleted;
      await _memory.forget([recordId]);
    }
    return null;
  }

  /// The version the next write of a period record carries: the present
  /// moment, and in any case above the version this device last wrote it
  /// with.
  ///
  /// One clock for every write (Issue #1478's review). The first version of
  /// this used a day entry's own timestamp for an ordinary write and the
  /// present moment for a correction, so a write after a correction could
  /// carry the lower of the two — and the store ignores a lower version
  /// while the ledger records the new days as written. The floor covers the
  /// one case left, a device clock that has been set back.
  int _nextPeriodVersion(HealthExportLedgerEntry? remembered) {
    final nowMs = _now().millisecondsSinceEpoch;
    if (remembered == null) return nowMs;
    // The ledger row's export instant is the version it was written with
    // ([_rememberPeriod]).
    final lastMs = remembered.exportedAt.millisecondsSinceEpoch;
    return nowMs > lastMs ? nowMs : lastMs + 1;
  }

  /// Whether the exported [interval] (`<first day>/<last day>`) shares a
  /// day with any of [episodes]. An interval that does not parse shares
  /// none.
  static bool _overlapsAny(String interval, List<Episode> episodes) {
    if (episodes.isEmpty) return false;
    final days = interval.split('/');
    final start = LocalDate.tryParseIso(days.first);
    final end = LocalDate.tryParseIso(days.last);
    if (start == null || end == null) return false;
    return episodes.any(
      (episode) => !end.isBefore(episode.start) && !start.isAfter(episode.end),
    );
  }

  /// Records that this device wrote the period record [recordId] for
  /// [interval] at [versionMs]. The ledger row's export instant *is* the
  /// version, which is how a later session knows what the next write has
  /// to exceed, and its source row is the interval, since a period record
  /// comes from no single row.
  Future<void> _rememberPeriod(
    String profileId,
    String recordId,
    String interval,
    LocalDate start,
    int versionMs,
  ) =>
      _memory.remember([
        HealthExportLedgerEntry(
          recordId: recordId,
          profileId: profileId,
          sourceRowId: interval,
          kind: HealthExportLedgerKind.period,
          localDate: start.iso,
          exportedAt:
              DateTime.fromMillisecondsSinceEpoch(versionMs, isUtc: true),
        ),
      ]);

  /// Sends the due symptom samples (Issue #238) and remembers the ones the
  /// store accepts. A platform that answers `unavailable` — Health Connect
  /// has no symptom category types at all, permanently — is a graceful
  /// skip, never a pass-blocking failure, and ends the step: the answer
  /// would be the same for every other day. Any other failure is reported
  /// and leaves its samples due. Stops outright on the same mid-pass
  /// authority drift [_writeFlowRecords] guards against.
  ///
  /// Only the samples whose type is switched on are sent (Issue #1555).
  /// The rest stay due.
  Future<({int written, HealthPlatformResult? failure})> _writeSymptomRecords(
    List<_PendingSymptomWrite> pendingSymptoms,
    HealthGuardFacts facts,
    String profileId, {
    Set<String>? grantedTypes,
  }) async {
    var written = 0;
    HealthPlatformResult? failure;
    for (final symptom in pendingSymptoms) {
      final samples = _filterGrantedSymptomSamples(
        symptom.samples,
        grantedTypes,
      );
      if (samples.isEmpty) continue;
      final stopped = await _authorityDrift(facts);
      if (stopped != null) {
        failure ??= stopped;
        break;
      }
      final result = await _platform.writeSymptomSamples(
        HealthSymptomSamplesWrite(
          facts: facts,
          date: symptom.date,
          tzName: symptom.tzName,
          samples: samples,
        ),
      );
      if (result is HealthPlatformUnavailable) break;
      if (result is! HealthPlatformAllowed) {
        failure ??= result;
        continue;
      }
      written += samples.length;
      await _memory.remember([
        for (final sample in samples)
          HealthExportLedgerEntry(
            recordId: sample.recordId,
            profileId: profileId,
            sourceRowId: symptom.entryId,
            kind: HealthExportLedgerKind.entry,
            localDate: symptom.date.iso,
            exportedAt: symptom.updatedAt,
          ),
      ]);
    }
    return (written: written, failure: failure);
  }

  static List<HealthSymptomSample> _filterGrantedSymptomSamples(
    List<HealthSymptomSample> samples,
    Set<String>? grantedTypes,
  ) {
    if (grantedTypes == null ||
        grantedTypes.contains(HealthWriteTypes.symptoms)) {
      return samples;
    }
    return samples
        .where((s) => grantedTypes.contains(s.healthKitTypeIdentifier))
        .toList();
  }

  /// Sends the due cervical-mucus records (Issue #228) and remembers the
  /// ones the store accepts. Both platforms have the type, so
  /// `unavailable` is not expected — but it is still a graceful skip that
  /// ends the step rather than a pass-blocking failure, for parity with
  /// the other writers and so a future platform gap cannot wedge a pass.
  /// With the type switched off ([allowed] false) nothing is sent and
  /// everything stays due. Stops on the same mid-pass authority drift as
  /// [_writeFlowRecords].
  Future<({int written, HealthPlatformResult? failure})>
      _writeCervicalMucusRecords(
    List<_PendingCervicalMucusWrite> pending,
    HealthGuardFacts facts,
    String profileId, {
    bool allowed = true,
  }) =>
          _writeEach(
            allowed ? pending : const <_PendingCervicalMucusWrite>[],
            facts,
            send: (item) => _platform.writeCervicalMucus(
              HealthCervicalMucusWrite(
                facts: facts,
                date: item.date,
                tzName: item.tzName,
                healthKitValue: item.resolved.healthKitValue,
                healthConnectAppearance: item.resolved.healthConnectAppearance,
                recordId: item.recordId,
                recordVersionMs: item.recordVersionMs,
              ),
            ),
            remember: (item) => _remember(
              profileId,
              recordId: item.recordId,
              sourceRowId: item.entryId,
              kind: HealthExportLedgerKind.entry,
              date: item.date,
              version: item.updatedAt,
            ),
          );

  /// Sends the due ovulation-test records (Issue #228). Same handling as
  /// [_writeCervicalMucusRecords].
  Future<({int written, HealthPlatformResult? failure})>
      _writeOvulationTestRecords(
    List<_PendingOvulationWrite> pending,
    HealthGuardFacts facts,
    String profileId, {
    bool allowed = true,
  }) =>
          _writeEach(
            allowed ? pending : const <_PendingOvulationWrite>[],
            facts,
            send: (item) => _platform.writeOvulationTest(
              HealthOvulationTestWrite(
                facts: facts,
                date: item.date,
                tzName: item.tzName,
                healthKitResult: item.resolved.healthKitResult,
                healthConnectResult: item.resolved.healthConnectResult,
                recordId: item.recordId,
                recordVersionMs: item.recordVersionMs,
              ),
            ),
            remember: (item) => _remember(
              profileId,
              recordId: item.recordId,
              sourceRowId: item.entryId,
              kind: HealthExportLedgerKind.entry,
              date: item.date,
              version: item.updatedAt,
            ),
          );

  /// Sends the due BBT readings (Issue #228). Same handling as
  /// [_writeCervicalMucusRecords].
  Future<({int written, HealthPlatformResult? failure})> _writeBbtRecords(
    List<_PendingBbtWrite> pending,
    HealthGuardFacts facts,
    String profileId, {
    bool allowed = true,
  }) =>
      _writeEach(
        allowed ? pending : const <_PendingBbtWrite>[],
        facts,
        send: (item) => _platform.writeBasalBodyTemperature(
          HealthBasalBodyTemperatureWrite(
            facts: facts,
            date: item.date,
            tzName: item.tzName,
            celsius: item.resolved.celsius,
            healthConnectMeasurementLocation:
                item.resolved.healthConnectMeasurementLocation,
            recordId: item.recordId,
            recordVersionMs: item.recordVersionMs,
            observedAt: _bbtObservedAt(item),
          ),
        ),
        remember: (item) => _remember(
          profileId,
          recordId: item.recordId,
          sourceRowId: item.observationId,
          kind: HealthExportLedgerKind.bbt,
          date: item.date,
          version: item.updatedAt,
        ),
      );

  /// The loop the three one-record-at-a-time writers share: [send] each of
  /// [pending], [remember] the ones the store accepts, report the first
  /// failure and keep going, stop on a loss of authority, and stop quietly
  /// when the platform has no such type.
  Future<({int written, HealthPlatformResult? failure})> _writeEach<T>(
    List<T> pending,
    HealthGuardFacts facts, {
    required Future<HealthPlatformResult> Function(T item) send,
    required Future<void> Function(T item) remember,
  }) async {
    var written = 0;
    HealthPlatformResult? failure;
    for (final item in pending) {
      final stopped = await _authorityDrift(facts);
      if (stopped != null) {
        failure ??= stopped;
        break;
      }
      final result = await send(item);
      if (result is HealthPlatformUnavailable) break;
      if (result is! HealthPlatformAllowed) {
        failure ??= result;
        continue;
      }
      written++;
      await remember(item);
    }
    return (written: written, failure: failure);
  }

  /// The moment to write [item]'s reading at: its own recorded time when it
  /// has one; otherwise null, which the port resolves to the 07:00
  /// local-morning default (Issue #920) — unless that default has not
  /// happened yet, in which case the present moment is used instead (Issue
  /// #1478).
  ///
  /// A waking temperature is typically entered before seven in the
  /// morning, and Health Connect refuses a record dated in the future
  /// ("Record time must not be in the future"). Seen on an emulator: a
  /// reading entered at 03:27 was refused with its 07:00 default, and
  /// went on being refused on every pass until seven o'clock came. The
  /// reading exists now, so now is
  /// a truthful time for it; a later re-write of the same record after
  /// seven uses the default again, which the store ignores unless the row
  /// itself changed.
  DateTime? _bbtObservedAt(_PendingBbtWrite item) {
    final observedAt = item.observedAt;
    if (observedAt != null) return observedAt;
    final now = _now();
    try {
      final fallback = basalBodyTemperatureInstant(
        date: item.date,
        tzName: item.tzName,
      ).instant;
      return fallback.isAfter(now) ? now : null;
    } on TimeZoneResolutionException {
      // An unresolvable zone is the port's to report (it turns it into a
      // failed result); nothing to adjust here.
      return null;
    }
  }

  /// The unbind/reset half of the write flow: clears the forward-only
  /// floor, what this device remembers writing, and the native-side
  /// binding mirror. Called by the coordinator
  /// whenever the stored binding goes away *or is replaced* — forward-only
  /// consent belongs to one binding, so re-binding (same or different
  /// profile) re-grants from the new authorization moment rather than
  /// backfilling under the old cursor.
  @override
  Future<void> onUnbound() async {
    await _settings.set(SettingsKeys.healthSyncWrittenThroughMs, '');
    await _settings.set(SettingsKeys.healthSyncWrittenThroughUs, '');
    await _settings.set(SettingsKeys.healthSyncWriteState, '');
    _state = const HealthWritePassState();
    // Issues #930 and #936: what was written belongs to one binding,
    // exactly like the floor. A re-bind must never diff (and delete)
    // against the old profile's exports, and the rows describe a health
    // store this device may no longer be permitted to touch.
    await _memory.reset();
    await _platform.unbindProfile();
  }

  /// Whether the pass looks at a row at all (Issue #1581): one lunarlog
  /// logged itself (never one that came *from* a health store — see the
  /// class doc's one-way note), saved strictly after the forward-only
  /// [floor], or one this device has already written a record from. The
  /// second arm matters for an install that upgraded: its floor is where
  /// its cursor stood, which is not before the rows it had written.
  bool _inScope(
    String rowId,
    DateTime updatedAt,
    Object? source,
    DateTime floor,
  ) =>
      !_isHealthStoreImport(source) &&
      (updatedAt.isAfter(floor) || _memory.knowsRow(rowId));

  /// Whether [recordId] has to be sent: the store does not hold it for its
  /// row as it stands at [version], and it may be sent.
  ///
  /// A record the store holds at an older version may always be: it is
  /// there already, and what it says is out of date. One that has never
  /// been written may be only if its row was saved after its [type] was
  /// last found switched off ([HealthWritePassState.admitsNew]): what was
  /// logged while a type was off stays out when the type is switched on.
  bool _isDue(String recordId, DateTime version, String type) {
    if (_memory.holds(recordId, version)) return false;
    return _memory.entryOf(recordId) != null ||
        _state.admitsNew(type, version);
  }

  /// Whether [source] marks a row that came *from* an OS health store (a
  /// day entry or an observation the import wrote) rather than one lunarlog
  /// logged itself. Such a row is never written back, and never counts
  /// towards a period record ([_collectPeriods]).
  static bool _isHealthStoreImport(Object? source) =>
      source == DayEntrySource.healthkit ||
      source == DayEntrySource.healthConnect ||
      source == ObservationSource.appleHealth ||
      source == ObservationSource.healthConnect;

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
    final exact = await _settings.get(SettingsKeys.healthSyncWrittenThroughUs);
    return healthWriteCursorFrom(
      milliseconds: ms,
      microseconds: int.tryParse(exact ?? ''),
    );
  }
}
