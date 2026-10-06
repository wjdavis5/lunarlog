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
///   [SettingsKeys.healthSyncWrittenThroughMs] with the grant instant; a
///   day is eligible only when its row's `updatedAt` is strictly after the
///   cursor, so pre-grant history is never backfilled (Clue's own
///   documented behavior, A3-35). A fully successful pass advances the
///   cursor to the newest processed row's `updatedAt`; any failure leaves
///   it (and the whole batch) to be retried by the next pass rather than
///   half-skipping.
///
/// **The remember-side is persisted (Issue #936).** The record ids a prior
/// export wrote are held in the device-local [HealthExportLedger], not only
/// in [_exportedEntryRecordIds]/[_exportedBbtRecordIds] process memory, and
/// are seeded from it on the first pass for a bound profile. Before this,
/// a symptom/BTT/fertility sample exported in an earlier app session was
/// never reconciled away after a relaunch (on iOS a fresh process is the
/// common case), because the diff's "previous" side was empty. The ledger
/// is cleared per profile on deletion and outright on unbind; it never
/// syncs and holds ids/provenance only.
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
import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
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

/// A period record this device has written: the days it was last written
/// with ([_periodInterval]) and the version that write carried.
class _ExportedPeriod {
  const _ExportedPeriod(this.interval, this.versionMs);

  final String interval;
  final int versionMs;
}

/// An exported period interval as the ledger stores it:
/// `<first day>/<last day>`, ISO dates.
String _periodInterval(LocalDate start, LocalDate end) =>
    '${start.iso}/${end.iso}';

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

/// Accumulates one pass's write plan: every day (whatever it maps to,
/// [HealthFlowNoWrite] included since Issue #619's LLA-024 — see [add])
/// joins [pending], days mapped to no sample are additionally counted in
/// [withoutSample], period episodes join [desiredPeriods], and the Issue
/// #228 fertility/measurement signals join their own lists.
class _Batch {
  final List<_PendingWrite> pending = [];
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

  /// The ISO civil date behind each [entryRecordIds] key, so the persisted
  /// ledger can record provenance (Issue #936).
  final Map<String, String> entryLocalDates = {};

  /// Every spotting observation written through the flow writer this pass
  /// (Issue #936), keyed by observation id: its record id and civil date.
  /// Spotting writes are not part of [entryRecordIds], so the persisted
  /// ledger needs them separately for the tombstone coordinator's
  /// cross-session spotting deletion.
  final Map<String, ({String recordId, String localDate})> spottingExports =
      {};

  /// Every live, exportable BBT observation's record id this pass,
  /// regardless of the forward-only cursor — the "still present" side of
  /// the BBT diff. A remembered id absent from this set is a reading the
  /// operator cleared (its row is tombstoned or no longer resolves).
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
    required HealthExportLedger ledger,
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
        _ledger = ledger,
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

  /// The persisted device-local export ledger (Issue #936). Both in-memory
  /// sets below are seeded from it on the first pass for a bound profile, so
  /// a tombstone or an edit made in a later app session still reconciles.
  final HealthExportLedger _ledger;

  final DateTime Function() _now;

  /// The profile [_exportedEntryRecordIds]/[_exportedBbtRecordIds] currently
  /// hold ledger state for; null until the first pass. Cleared by
  /// [onUnbound].
  String? _ledgerProfileId;

  /// The record ids the previous pass recorded for each day entry (Issue
  /// #930) — the "previously exported" side of the removed-record diff.
  /// Keyed by day-entry id; populated from [healthRecordIdsForEntry], the
  /// same derivation the tombstone coordinator remembers and the write path
  /// writes, so a delete can never address an id a write did not use.
  ///
  /// Deliberately this service's own memory rather than the tombstone
  /// coordinator's: only the write path knows which record was actually
  /// exported (the coordinator's set is seeded by live stream emissions,
  /// including rows the forward-only cursor never wrote). Persisted across
  /// sessions in [HealthExportLedger] (Issue #936) — seeded from it by
  /// [_ensureLedgerLoaded] on the first pass for a bound profile. See
  /// [_reconcileRemovedRecords].
  final Map<String, Set<String>> _exportedEntryRecordIds = {};

  /// The BBT record ids a previous export wrote (Issue #930), compared
  /// against the live BBT set on every pass so a reading cleared from a day
  /// that itself still exists is reconciled away. Also persisted across
  /// sessions in [HealthExportLedger] (Issue #936).
  final Set<String> _exportedBbtRecordIds = {};

  /// The period interval records this device exported (Issue #1478), by
  /// record id. Persisted in [HealthExportLedger] as
  /// [HealthExportLedgerKind.period] rows and seeded from it like the two
  /// sets above. See [_reconcilePeriodRecords].
  final Map<String, _ExportedPeriod> _exportedPeriods = {};

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

    // Issue #936: seed the remembered export sets from the persisted ledger
    // before diffing, so a relaunch (a fresh process on iOS is the common
    // case) still reconciles a tombstone or edit made in an earlier
    // session.
    await _ensureLedgerLoaded(bound.profile.id);

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
      alreadyGranted: permission == HealthPermissionStatus.granted ||
          permission == HealthPermissionStatus.writingSome,
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

    final grantedTypes = grant.status == HealthPermissionStatus.writingSome
        ? await _platform.grantedWriteTypes()
        : null;

    final batch = await _collectBatch(bound.profile.id, grant.cursor!);
    final outcome = await _writeBatch(
      batch,
      bound.facts,
      bound.profile.id,
      grantedTypes: grantedTypes,
    );
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

  /// Stamps the forward-only cursor with the current instant and returns
  /// it.
  Future<DateTime> _stampCursor() async {
    final stamped = _now();
    await _settings.set(
      SettingsKeys.healthSyncWrittenThroughMs,
      '${stamped.millisecondsSinceEpoch}',
    );
    return stamped;
  }

  /// Builds the pass's write batch from the bound profile's day entries
  /// and observations: everything strictly newer than [cursor]
  /// (forward-only), mapped through `health_flow_mapping.dart`,
  /// `health_symptom_mapping.dart`, and — Issue #228 —
  /// `health_fertility_mapping.dart`, plus the period interval records
  /// the store should hold (Issue #202 — see [_collectPeriods]).
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
    _collectPeriods(profileId, entries, cursor, batch);

    for (final entry in entries) {
      if (!_isEligible(entry.updatedAt, entry.source, cursor)) continue;
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
      // Issue #936: the date behind that grouping key, for the persisted
      // ledger's provenance.
      batch.entryLocalDates[entry.id] = entry.localDate.iso;
    }

    _collectObservationWrites(
      observationRows: observationRows,
      spottingRows: spottingRows,
      bleedDays: bleedDays,
      episodes: episodes,
      batch: batch,
      cursor: cursor,
    );
    return batch;
  }

  /// Decides which period interval records the store should hold after
  /// this pass (Issue #202; rewritten by Issue #1478's review), into
  /// [_Batch.desiredPeriods]. [_reconcilePeriodRecords] then makes the
  /// store match. Three rules:
  ///
  /// * **Hand-logged days only.** The episodes are derived from the bleed
  ///   days lunarlog itself logged — the same source test [_isEligible]
  ///   applies, without the cursor. A day imported from Apple Health or
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
    DateTime cursor,
    _Batch batch,
  ) {
    final own = <LocalDate, DayEntry>{
      for (final entry in entries)
        if (_isHandLoggedBleed(entry)) entry.localDate: entry,
    };
    for (final episode in deriveEpisodes(own.keys)) {
      if (episode.lengthDays > kHealthPeriodRecordMaxDays) continue;
      final days = _handLoggedDaysOf(episode, own);
      if (!days.any((day) => _isOrWillBeExported(day, cursor))) continue;
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

  /// Whether the store holds, or is about to be sent, a record for [day]:
  /// the export ledger remembers one from an earlier pass, or the row is
  /// newer than the forward-only [cursor] and so is written by this one.
  bool _isOrWillBeExported(DayEntry day, DateTime cursor) =>
      _exportedEntryRecordIds.containsKey(day.id) ||
      day.updatedAt.isAfter(cursor);

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
      // Issue #936: remember this spotting export for the persisted ledger
      // (its own record id, keyed by the observation id), so a later
      // session's tombstone can delete it.
      batch.spottingExports[row.id] = (
        recordId: healthSpottingRecordId(row.id),
        localDate: row.localDate.iso,
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
      observationId: row.id,
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

  /// Sends the batch to the port: the per-day writes, the removal of
  /// records an edit took away, and last the period interval records.
  /// Keeps writing after a failure (one bad day must not hide the others),
  /// remembering the first failure and leaving the cursor — the next pass
  /// retries the batch rather than half-skipping (see the class doc's
  /// forward-only note).
  Future<_BatchOutcome> _writeBatch(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId, {
    Set<String>? grantedTypes,
  }) async {
    bool canWrite(String type) =>
        grantedTypes == null || grantedTypes.contains(type);

    final flow = await _writeFlowRecords(
      batch.pending,
      facts,
      canWriteFlow: canWrite('menstrualFlow'),
      canWriteSpotting: canWrite('spotting'),
    );
    final symptoms = await _writeSymptomRecords(
      batch.pendingSymptoms,
      facts,
      canWriteSymptom: (type) => canWrite(type) || canWrite('symptoms'),
    );
    final cervical = canWrite('cervicalMucus')
        ? await _writeCervicalMucusRecords(batch.pendingCervicalMucus, facts)
        : (
            written: 0,
            failure: null as HealthPlatformResult?,
            newest: batch.pendingCervicalMucus.isEmpty
                ? null
                : batch.pendingCervicalMucus
                    .map((w) => w.updatedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b),
          );
    final ovulation = canWrite('ovulationTest')
        ? await _writeOvulationTestRecords(batch.pendingOvulation, facts)
        : (
            written: 0,
            failure: null as HealthPlatformResult?,
            newest: batch.pendingOvulation.isEmpty
                ? null
                : batch.pendingOvulation
                    .map((w) => w.updatedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b),
          );
    final bbt = canWrite('basalBodyTemperature')
        ? await _writeBbtRecords(batch.pendingBbt, facts)
        : (
            written: 0,
            failure: null as HealthPlatformResult?,
            newest: batch.pendingBbt.isEmpty
                ? null
                : batch.pendingBbt
                    .map((w) => w.updatedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b),
          );
    // Issue #930: after this pass's writes, reconcile away any sample a
    // PRIOR export wrote for the day/observation that no longer asserts it.
    // Runs after the writes so the remembered sets move "now" -> "after the
    // write"; a failure here blocks the pass (and leaves the cursor) so the
    // removal is retried rather than silently skipped.
    final removed = await _reconcileRemovedRecords(batch, facts, profileId);
    // Issue #1478: and the period interval records, which no single day
    // entry owns. Last, so the days a record covers are already in the
    // store when it is written.
    final periods = canWrite('menstrualFlow')
        ? await _reconcilePeriodRecords(batch, facts, profileId)
        : (written: 0, failure: null as HealthPlatformResult?);
    return _BatchOutcome(
      written: flow.written,
      reconciled: flow.reconciled,
      periodRecordsWritten: periods.written,
      symptomSamplesWritten: symptoms.written,
      cervicalMucusSamplesWritten: cervical.written,
      ovulationTestSamplesWritten: ovulation.written,
      basalBodyTemperatureSamplesWritten: bbt.written,
      failure: flow.failure ??
          symptoms.failure ??
          cervical.failure ??
          ovulation.failure ??
          bbt.failure ??
          removed ??
          periods.failure,
      // A period record has no row of its own to advance the cursor to:
      // the days it covers are among the flow writes.
      newest: _latest(
        _latest(flow.newest, symptoms.newest),
        _latest(_latest(cervical.newest, ovulation.newest), bbt.newest),
      ),
    );
  }

  /// Seeds [_exportedEntryRecordIds]/[_exportedBbtRecordIds] from the
  /// persisted ledger (Issue #936) the first time a pass runs for
  /// [profileId]. A relaunch — a fresh process on iOS is the common case,
  /// not an edge case — otherwise starts with empty sets, so
  /// `previous.difference(current)` is always empty and an edit made in an
  /// earlier session is never reconciled away.
  ///
  /// Spotting rows are deliberately not loaded into memory: the write path
  /// only diffs entry-derived and BBT records, while the persisted spotting
  /// rows exist for the tombstone coordinator's own cross-session deletion.
  Future<void> _ensureLedgerLoaded(String profileId) async {
    if (_ledgerProfileId == profileId) return;
    final rows = await _ledger.readForProfile(profileId);
    _exportedEntryRecordIds.clear();
    _exportedBbtRecordIds.clear();
    _exportedPeriods.clear();
    for (final row in rows) {
      switch (row.kind) {
        case HealthExportLedgerKind.entry:
          _exportedEntryRecordIds
              .putIfAbsent(row.sourceRowId, () => <String>{})
              .add(row.recordId);
        case HealthExportLedgerKind.bbt:
          _exportedBbtRecordIds.add(row.recordId);
        case HealthExportLedgerKind.period:
          // The row's export instant is the version the record was written
          // with ([_rememberPeriod]).
          _exportedPeriods[row.recordId] = _ExportedPeriod(
            row.sourceRowId,
            row.exportedAt.millisecondsSinceEpoch,
          );
        case HealthExportLedgerKind.spotting:
          break;
      }
    }
    _ledgerProfileId = profileId;
  }

  /// Reconciles the records a *previous* export wrote against what this pass
  /// found (Issue #930) — the fix for a symptom/BTT/fertility sample left
  /// orphaned when a live day entry is edited rather than deleted.
  ///
  /// The remembered set is this service's own [_exportedEntryRecordIds] /
  /// [_exportedBbtRecordIds], seeded from the persisted device-local ledger
  /// (Issue #936, [HealthExportLedger]) and otherwise maintained from this
  /// device's own exports through [healthRecordIdsForEntry] and the BBT
  /// builder. A remembered id that the current state no longer produces is
  /// deleted; an id that is unchanged (a graded intensity or flow edit
  /// rewrites the same id) is left alone. Deleting is a health-API touch,
  /// so it goes through the same `_authorityDrift` recheck and guarded
  /// [HealthPlatformStore.deleteRecords] as every write — no new bypass.
  /// Returns the first removal failure, or null when every removal was
  /// allowed.
  Future<HealthPlatformResult?> _reconcileRemovedRecords(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId,
  ) async {
    final entryFailure =
        await _reconcileEntryRemovals(batch, facts, profileId);
    final bbtFailure = await _reconcileBbtRemovals(batch, facts);
    // Only once the BBT diff is computed: every BBT id this pass exported is
    // remembered so a LATER clear can address it.
    final bbtExports = <HealthExportLedgerEntry>[];
    for (final item in batch.pendingBbt) {
      _exportedBbtRecordIds.add(item.recordId);
      bbtExports.add(HealthExportLedgerEntry(
        recordId: item.recordId,
        profileId: profileId,
        sourceRowId: item.observationId,
        kind: HealthExportLedgerKind.bbt,
        localDate: item.date.iso,
        exportedAt: _now(),
      ));
    }
    // Issue #936: spotting exports are persisted too, so a tombstone in a
    // later session can still delete them (the coordinator seeds its own
    // observation memory from the ledger).
    final spottingExports = <HealthExportLedgerEntry>[];
    for (final export in batch.spottingExports.entries) {
      spottingExports.add(HealthExportLedgerEntry(
        recordId: export.value.recordId,
        profileId: profileId,
        sourceRowId: export.key,
        kind: HealthExportLedgerKind.spotting,
        localDate: export.value.localDate,
        exportedAt: _now(),
      ));
    }
    await _ledger.record([...bbtExports, ...spottingExports]);
    return entryFailure ?? bbtFailure;
  }

  /// The day-entry half of [_reconcileRemovedRecords]: for every eligible
  /// entry, delete the ids it produced on a previous export but no longer
  /// produces, then remember the current set. A delete failure leaves the
  /// old set in place so the removal is retried on the next pass (LLA-019's
  /// discipline), rather than being silently acknowledged. The persisted
  /// ledger moves in lockstep: removed ids are dropped on a successful
  /// delete, and the current set is written so the next session's diff sees
  /// it.
  Future<HealthPlatformResult?> _reconcileEntryRemovals(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId,
  ) async {
    HealthPlatformResult? failure;
    for (final entry in batch.entryRecordIds.entries) {
      final current = entry.value;
      final previous = _exportedEntryRecordIds[entry.key] ?? const <String>{};
      final removed = previous.difference(current);
      if (removed.isNotEmpty) {
        final drift = await _authorityDrift(facts);
        if (drift != null) {
          failure ??= drift;
          continue;
        }
        final result = await _platform.deleteRecords(facts, removed.toList());
        if (result is! HealthPlatformAllowed) {
          failure ??= result;
          continue;
        }
        await _ledger.removeRecordIds(removed.toList());
      }
      _exportedEntryRecordIds[entry.key] = current;
      await _ledger.record([
        for (final recordId in current)
          HealthExportLedgerEntry(
            recordId: recordId,
            profileId: profileId,
            sourceRowId: entry.key,
            kind: HealthExportLedgerKind.entry,
            localDate: batch.entryLocalDates[entry.key] ?? '',
            exportedAt: _now(),
          ),
      ]);
    }
    return failure;
  }

  /// The BBT half of [_reconcileRemovedRecords]: a remembered BBT record
  /// whose observation is no longer live-and-resolved (the operator cleared
  /// the reading, leaving the day itself in place) is deleted. The memory is
  /// only cleared on success, so a refusal retries; the persisted ledger
  /// row is dropped only alongside the same successful delete.
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
      await _ledger.removeRecordIds(removed.toList());
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
    HealthGuardFacts facts, {
    bool canWriteFlow = true,
    bool canWriteSpotting = true,
  }) async {
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
      if (write.plan is HealthFlowMenstrualSample && !canWriteFlow) {
        continue;
      }
      if (write.plan is HealthFlowIntermenstrualMarker && !canWriteSpotting) {
        continue;
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
  /// never taken away while its replacement is still owed. A failure blocks
  /// the pass and leaves the cursor, so the step is retried.
  ///
  /// On iOS nothing here reaches the store: HealthKit has no interval
  /// record (episode boundaries ride the flow samples' cycle-start
  /// metadata, #193), the write answers `unavailable`, and nothing is ever
  /// remembered.
  Future<({int written, HealthPlatformResult? failure})>
      _reconcilePeriodRecords(
    _Batch batch,
    HealthGuardFacts facts,
    String profileId,
  ) async {
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
      final remembered = _exportedPeriods[due.key];
      final interval = _periodInterval(period.start, period.end);
      if (remembered?.interval == interval) continue;
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
    for (final recordId in _exportedPeriods.keys.toList()) {
      if (batch.desiredPeriods.containsKey(recordId)) continue;
      final interval = _exportedPeriods[recordId]!.interval;
      if (_overlapsAny(interval, batch.unresolvedPeriods)) continue;
      final drift = await _authorityDrift(facts);
      if (drift != null) return drift;
      final deleted = await _platform.deleteRecords(facts, [recordId]);
      if (deleted is! HealthPlatformAllowed) return deleted;
      _exportedPeriods.remove(recordId);
      await _ledger.removeRecordIds([recordId]);
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
  int _nextPeriodVersion(_ExportedPeriod? remembered) {
    final nowMs = _now().millisecondsSinceEpoch;
    if (remembered == null || nowMs > remembered.versionMs) return nowMs;
    return remembered.versionMs + 1;
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
  /// [interval] at [versionMs], in memory and in the persisted ledger. The
  /// ledger row's export instant *is* the version, which is how a later
  /// session knows what the next write has to exceed.
  Future<void> _rememberPeriod(
    String profileId,
    String recordId,
    String interval,
    LocalDate start,
    int versionMs,
  ) async {
    _exportedPeriods[recordId] = _ExportedPeriod(interval, versionMs);
    await _ledger.record([
      HealthExportLedgerEntry(
        recordId: recordId,
        profileId: profileId,
        sourceRowId: interval,
        kind: HealthExportLedgerKind.period,
        localDate: start.iso,
        exportedAt: DateTime.fromMillisecondsSinceEpoch(versionMs, isUtc: true),
      ),
    ]);
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
    HealthGuardFacts facts, {
    bool Function(String type)? canWriteSymptom,
  }) async {
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
      final samples = canWriteSymptom == null
          ? symptom.samples
          : symptom.samples
              .where((s) => canWriteSymptom(s.healthKitTypeIdentifier))
              .toList();
      if (samples.isEmpty) continue;
      final result = await _platform.writeSymptomSamples(
        HealthSymptomSamplesWrite(
          facts: facts,
          date: symptom.date,
          tzName: symptom.tzName,
          samples: samples,
        ),
      );
      if (result is HealthPlatformAllowed) {
        written += samples.length;
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
          observedAt: _bbtObservedAt(item),
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
  /// because one refused write fails the whole pass, the cursor stopped
  /// advancing until seven o'clock came. The reading exists now, so now is
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
    _exportedPeriods.clear();
    _ledgerProfileId = null;
    // Issue #936: the persisted ledger belongs to one binding, exactly like
    // the cursor — a re-bind must never diff (and delete) against the old
    // profile's exports, and the rows describe a health store this device
    // may no longer be permitted to touch.
    await _ledger.clearAll();
    await _platform.unbindProfile();
  }

  /// Forward-only eligibility: the row must have been written strictly
  /// after the cursor, and must not have come *from* a health store (see
  /// the class doc's one-way note).
  bool _isEligible(DateTime updatedAt, Object? source, DateTime cursor) =>
      updatedAt.isAfter(cursor) && !_isHealthStoreImport(source);

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
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
