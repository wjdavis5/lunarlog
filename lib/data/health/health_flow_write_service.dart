/// The one-way, opt-in, forward-only menstrual-flow write path (Issue
/// #193): turns the bound profile's day entries and spotting observations
/// into `writeMenstrualFlow` / `writeIntermenstrualBleeding` calls on the
/// #173 platform port, in the order the issue's acceptance criteria pin:
///
/// * **Opt-in** — nothing runs until the operator binds a profile in
///   Settings (`SettingsKeys.healthStoreProfileId`), and nothing is
///   requested from the OS health store until the first sync pass asks for
///   write authorization (stamping the grant instant). Off is the default.
/// * **One-way** — this file only ever calls write methods on
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
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import 'health_flow_mapping.dart';

/// Resolves the guardian rows for one profile, mapped to the domain model
/// (`ownerUserIdFor` turns them into the guard's owner fact). Production
/// wiring passes `ProfileGuardiansRepository.getForProfile` as a tear-off;
/// a bare function type keeps this file free of the concrete repository
/// and its storage dependency.
typedef GuardiansForProfile = Future<List<ProfileGuardian>> Function(
    String profileId);

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

/// Accumulates one pass's write plan: days mapped to no sample are
/// counted, everything else joins [pending].
class _Batch {
  final List<_PendingWrite> pending = [];
  int withoutSample = 0;

  void add(LocalDate date, String tzName, DateTime updatedAt, String recordId,
      HealthFlowWritePlan plan, Episode? containing) {
    switch (plan) {
      case HealthFlowNoWrite():
        withoutSample++;
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
    final outcome = await _writeBatch(batch.pending, bound.facts);
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
      daysWithoutSample: batch.withoutSample,
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
  /// and spotting observations: everything strictly newer than [cursor]
  /// (forward-only), mapped through `health_flow_mapping.dart`.
  Future<({List<_PendingWrite> pending, int withoutSample})> _collectBatch(
    String profileId,
    DateTime cursor,
  ) async {
    final entries = await _dayEntries.listForProfile(profileId);
    final spottingRows = [
      for (final observation in await _observations.listForProfile(profileId))
        if (observation.category == kSpottingObservationCategory) observation,
    ];
    final episodes = deriveEpisodes(bleedDatesOf(entries));
    final bleedDays = bleedDatesOf(entries);
    final batch = _Batch();

    for (final entry in entries) {
      if (!_isEligible(entry.updatedAt, entry.source, cursor)) continue;
      final containing = _containing(episodes, entry.localDate);
      batch.add(
        entry.localDate,
        entry.tz,
        entry.updatedAt,
        entry.id,
        mapFlowToHealthWrite(
          entry.flow,
          inPeriodEpisode: containing != null,
        ),
        containing,
      );
    }

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
        row.id,
        mapSpottingToHealthWrite(inPeriodEpisode: containing != null),
        containing,
      );
    }
    return (pending: batch.pending, withoutSample: batch.withoutSample);
  }

  /// Sends [pending] to the port. Keeps writing after a failure (one bad
  /// day must not hide the others), remembering the first failure and
  /// leaving the cursor — the next pass retries the batch rather than
  /// half-skipping (see the class doc's forward-only note).
  Future<
      ({
        int written,
        HealthPlatformResult? failure,
        DateTime? newest,
      })> _writeBatch(
    List<_PendingWrite> pending,
    HealthGuardFacts facts,
  ) async {
    var written = 0;
    HealthPlatformResult? failure;
    DateTime? newest;
    for (final write in pending) {
      final current = newest;
      if (current == null || write.updatedAt.isAfter(current)) {
        newest = write.updatedAt;
      }
      final HealthPlatformResult result;
      switch (write.plan) {
        case HealthFlowMenstrualSample(:final value):
          result = await _platform.writeMenstrualFlow(
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
          result = await _platform.writeIntermenstrualBleeding(
            HealthIntermenstrualBleedingWrite(
              facts: facts,
              date: write.date,
              tzName: write.tzName,
              recordId: write.recordId,
              recordVersionMs: write.recordVersionMs,
            ),
          );
        case HealthFlowNoWrite():
          continue;
      }
      if (result is HealthPlatformAllowed) {
        written++;
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
