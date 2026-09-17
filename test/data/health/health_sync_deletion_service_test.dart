/// Coverage for Issue #186 AC6 (tombstone → health-store deletion): the
/// `LocalHealthSyncDeletionService` resolves the bound profile's guard facts
/// and hands tombstoned entry ULIDs to the platform's `deleteRecords`, and
/// the `HealthSyncTombstoneCoordinator` watches the bound profile's day
/// entries and spotting observations and triggers the service for
/// newly-tombstoned rows.
///
/// Issue #619 regressions:
/// * LLA-018 — the coordinator must watch a tombstones-included source, not
///   `DayEntriesRepository.watchForProfile` (which filters them for UI
///   reads and so never carried a production deletion at all). Proven here
///   against a real Drift-backed `DriftHealthSyncTombstoneSource`, not a
///   fake that (pre-fix) could emit whatever the test wanted regardless of
///   the real storage layer's tombstone filtering.
/// * LLA-019 — a refused/thrown deletion attempt must not be marked done;
///   the same id is retried on the coordinator's next pass.
/// * LLA-020 — a spotting observation's own id (not its parent day entry's)
///   must reach deletion, both when it is deleted directly and when its
///   parent day entry's own deletion cascades the tombstone (Issue #470).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide DayEntry, Profile, Observation;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' show FlowLevel;
import 'package:lunarlog/data/health/health_sync_deletion_service.dart';
import 'package:lunarlog/data/health/health_sync_tombstone_coordinator.dart';
import 'package:lunarlog/data/repositories/drift_health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/health/health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _profileId = 'p1';
const _entryId = '01ARZ3NDEKTSV4RRFFQ69G5FAV';

Profile _profile({bool isMinor = false}) => Profile(
      id: _profileId,
      displayName: 'Riley',
      isMinor: isMinor,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

class _FakeProfiles implements ProfilesRepository {
  Profile? profile = _profile();

  @override
  Future<Profile?> findById(String id) async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Issue #619, LLA-018: a fake [HealthSyncTombstoneSource] for the
/// coordinator's own trigger-contract tests (debounce, dedup, retry) — the
/// tombstone-visibility bug itself (a live-only stream can never carry a
/// deletion) is instead proven below against a real, Drift-backed source.
class _FakeTombstoneSource implements HealthSyncTombstoneSource {
  // Issue #548: per-test fakes with no close() call — the test process is
  // short-lived and nothing here leaks meaningfully.
  // ignore: close_sinks
  final entryChanges = StreamController<List<DayEntry>>.broadcast();
  // ignore: close_sinks
  final observationChanges =
      StreamController<List<HealthTombstoneObservation>>.broadcast();

  @override
  Stream<List<DayEntry>> watchDayEntries(String profileId) =>
      entryChanges.stream;

  @override
  Stream<List<HealthTombstoneObservation>> watchObservations(
    String profileId,
  ) =>
      observationChanges.stream;

  /// Adds [entries] once the coordinator's watch subscription is actually
  /// attached (mirrors `health_flow_write_coordinator_test.dart`'s
  /// `_FakeDayEntries.emit`): the binding watch is an async* chain, so an
  /// event fired on a broadcast stream immediately after `start()` would
  /// otherwise risk being dropped with no listener attached yet.
  Future<void> emitEntries(List<DayEntry> entries) async {
    await _waitForListener(entryChanges);
    entryChanges.add(entries);
  }

  /// [emitEntries]'s twin for the observations watch.
  Future<void> emitObservations(
    List<HealthTombstoneObservation> observations,
  ) async {
    await _waitForListener(observationChanges);
    observationChanges.add(observations);
  }

  static Future<void> _waitForListener(StreamController<Object?> controller) async {
    var spins = 0;
    while (!controller.hasListener) {
      await Future<void>.delayed(Duration.zero);
      spins++;
      if (spins > 1000) {
        throw StateError('coordinator never subscribed to the stream');
      }
    }
  }
}

class _RecordingPlatform implements HealthPlatformStore {
  final List<List<String>> deleted = [];
  HealthPlatformResult deleteResult = const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async {
    deleted.add(List.of(recordIds));
    return deleteResult;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDeletion implements HealthSyncDeletionService {
  final List<List<String>> calls = [];
  HealthSyncDeletionReport result =
      const HealthSyncDeletionReport(attempted: 0, blocked: null);
  Object? throwOnNextCall;

  @override
  Future<HealthSyncDeletionReport> deleteSamples(List<String> recordIds) async {
    calls.add(List.of(recordIds));
    final toThrow = throwOnNextCall;
    if (toThrow != null) {
      throwOnNextCall = null;
      throw toThrow;
    }
    return result;
  }
}

DayEntry _entry(String id, {DateTime? deletedAt}) => DayEntry(
      id: id,
      profileId: _profileId,
      localDate: LocalDate(2026, 9, 1),
      tz: 'UTC',
      flow: domain.FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

HealthTombstoneObservation _observation(
  String id, {
  String? category,
  DateTime? deletedAt,
}) =>
    HealthTombstoneObservation(id: id, category: category, deletedAt: deletedAt);

void main() {
  group('LocalHealthSyncDeletionService', () {
    test('no bound profile issues no platform call', () async {
      final platform = _RecordingPlatform();
      final binding = HealthSyncBinding(FakeSettingsStore());
      final service = LocalHealthSyncDeletionService(
        platform: platform,
        binding: binding,
        profiles: _FakeProfiles(),
        guardiansForProfile: (_) async => const [],
        signedInUserId: () => 'u1',
      );

      final report = await service.deleteSamples([_entryId]);

      expect(report.attempted, 0);
      expect(platform.deleted, isEmpty);
    });

    test('a bound profile routes the tombstoned ULIDs to deleteRecords '
        'with the resolved guard facts', () async {
      final platform = _RecordingPlatform();
      final binding = HealthSyncBinding(FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      }));
      final service = LocalHealthSyncDeletionService(
        platform: platform,
        binding: binding,
        profiles: _FakeProfiles(),
        guardiansForProfile: (_) async => [
          ProfileGuardian(
            id: 'g1',
            profileId: _profileId,
            userId: 'u1',
            role: GuardianRole.primaryGuardian,
            status: GuardianStatus.accepted,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ],
        signedInUserId: () => 'u1',
      );

      final report = await service.deleteSamples([_entryId]);

      expect(report.attempted, 1);
      expect(platform.deleted, [
        [_entryId]
      ]);
      expect(report.blocked, isNull);
    });

    test('a refused delete is reported as blocked', () async {
      final platform = _RecordingPlatform()
        ..deleteResult =
            const HealthPlatformResult.refused(HealthSyncCheck.notOwner);
      final binding = HealthSyncBinding(FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      }));
      final service = LocalHealthSyncDeletionService(
        platform: platform,
        binding: binding,
        profiles: _FakeProfiles(),
        guardiansForProfile: (_) async => const [],
        signedInUserId: () => 'u1',
      );

      final report = await service.deleteSamples([_entryId]);

      expect(report.blocked, isA<HealthPlatformRefused>());
    });
  });

  group('HealthSyncTombstoneCoordinator (trigger contract)', () {
    test('tombstoned entries trigger the deletion service once', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final source = _FakeTombstoneSource();
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: source,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      // A live entry: nothing to delete.
      await source.emitEntries([_entry(_entryId)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);

      // The same entry tombstoned: its ULID is handed to the service.
      await source
          .emitEntries([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, [
        [_entryId]
      ]);

      // A repeat emission of the same tombstone is not re-deleted.
      await source
          .emitEntries([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(1));
    });

    test('unbound: no deletion is ever issued', () async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      final source = _FakeTombstoneSource();
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: source,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      // Unbound: the coordinator never subscribes to the source at all, so
      // this event has nowhere to be delivered — asserted below regardless.
      source.entryChanges.add([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);
    });

    test(
        'issue #619, LLA-019: a refused deletion is retried on the next '
        'change rather than acknowledged', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final source = _FakeTombstoneSource();
      final deletion = _FakeDeletion()
        ..result = const HealthSyncDeletionReport(
          attempted: 1,
          blocked: HealthPlatformResult.refused(HealthSyncCheck.notOwner),
        );
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: source,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      final tombstoned = [_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))];
      await source.emitEntries(tombstoned);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, [
        [_entryId]
      ], reason: 'the refused attempt was still issued');

      // A later change re-arms the pass; the SAME id is retried because a
      // refusal must never be treated as done (pre-#619 fix, it would have
      // joined _alreadyDeleted on the first, refused attempt).
      deletion.result = const HealthSyncDeletionReport(attempted: 1, blocked: null);
      await source.emitEntries(List.of(tombstoned));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(2));
      expect(deletion.calls.last, [_entryId]);

      // Now that it succeeded, a further repeat is not re-sent.
      await source.emitEntries(List.of(tombstoned));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(2));
    });

    test(
        'issue #619, LLA-019: a throwing deletion attempt is retried, not '
        'acknowledged', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final source = _FakeTombstoneSource();
      final deletion = _FakeDeletion()..throwOnNextCall = StateError('boom');
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: source,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      final tombstoned = [_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))];
      await source.emitEntries(tombstoned);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(1));

      await source.emitEntries(List.of(tombstoned));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(2));
      expect(deletion.calls.last, [_entryId]);
    });

    test(
        'issue #619, LLA-020: a spotting observation tombstoned after being '
        'seen live is deleted by its own id', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final source = _FakeTombstoneSource();
      final deletion = _FakeDeletion();
      const observationId = '01ARZ3NDEKTSV4RRFFQ69G5FBW';
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: source,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      // Seen live as spotting first (mirrors the write path exporting it).
      await source
          .emitObservations([_observation(observationId, category: 'spotting')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);

      // A non-spotting observation tombstoned WITHOUT ever being seen live
      // as spotting must never be sent — only identities this coordinator
      // actually tracked as exported are deletable.
      await source.emitObservations([
        _observation(observationId, category: 'spotting'),
        _observation('never-live-obs', deletedAt: DateTime.utc(2026, 9, 2)),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);

      // Now tombstoned (category cleared, like a real cascade/direct
      // delete would leave it) — its previously-seen spotting identity is
      // enough to trigger deletion.
      await source.emitObservations([
        _observation(observationId, deletedAt: DateTime.utc(2026, 9, 2)),
        _observation('never-live-obs', deletedAt: DateTime.utc(2026, 9, 2)),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, [
        [observationId]
      ]);
    });
  });

  group('HealthSyncTombstoneCoordinator (real Drift storage)', () {
    late LunarLogDatabase db;
    late LunarLogStorage storage;

    setUp(() async {
      db = LunarLogDatabase(NativeDatabase.memory());
      storage = LunarLogStorage(db);
      await storage.upsertProfile(
        id: _profileId,
        displayName: 'Riley',
        isMinor: false,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
    });

    tearDown(() => db.close());

    test(
        'issue #619, LLA-018: a locally-deleted day entry is delivered to '
        'the deletion service (DayEntriesRepository.watchForProfile filters '
        'exactly this row, which is why the coordinator must never use it)',
        () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: DriftHealthSyncTombstoneSource(storage),
        deletionService: deletion,
        debounce: const Duration(milliseconds: 20),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      final saved = await storage.saveDayEntryWithObservations(
        profileId: _profileId,
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deletion.calls, isEmpty);

      await storage.softDeleteDayEntry(
        profileId: _profileId,
        localDate: '2026-09-01',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(deletion.calls, [
        [saved.id]
      ]);
    });

    test(
        'issue #619, LLA-020: deleting the parent day entry cascades to '
        "delete its spotting observation's own id too", () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: DriftHealthSyncTombstoneSource(storage),
        deletionService: deletion,
        debounce: const Duration(milliseconds: 20),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      final saved = await storage.saveDayEntryWithObservations(
        profileId: _profileId,
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.none,
        observationsToUpsert: const [
          UpsertObservationPayload(
            profileId: _profileId,
            localDate: '2026-09-01',
            tz: 'UTC',
            category: 'spotting',
            code: 'spotting',
          ),
        ],
      );
      final spotting =
          (await storage.getObservationsForDayEntry(saved.id)).single;
      // Let the coordinator see the observation live (as spotting) before
      // it is tombstoned — the same sequencing a real export/edit does.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await storage.softDeleteDayEntry(
        profileId: _profileId,
        localDate: '2026-09-01',
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final deletedIds = deletion.calls.expand((call) => call).toSet();
      expect(deletedIds, containsAll([saved.id, spotting.id]));
    });

    test(
        'issue #619, LLA-020: a directly-deleted spotting observation is '
        'sent to deletion by its own id (parent entry stays live)', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        source: DriftHealthSyncTombstoneSource(storage),
        deletionService: deletion,
        debounce: const Duration(milliseconds: 20),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      final saved = await storage.saveDayEntryWithObservations(
        profileId: _profileId,
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.none,
        observationsToUpsert: const [
          UpsertObservationPayload(
            profileId: _profileId,
            localDate: '2026-09-01',
            tz: 'UTC',
            category: 'spotting',
            code: 'spotting',
          ),
        ],
      );
      final spotting =
          (await storage.getObservationsForDayEntry(saved.id)).single;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await storage.softDeleteObservation(spotting.id);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(deletion.calls, [
        [spotting.id]
      ]);
    });
  });
}
