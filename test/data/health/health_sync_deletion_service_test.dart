/// Coverage for Issue #186 AC6 (tombstone → health-store deletion): the
/// `LocalHealthSyncDeletionService` resolves the bound profile's guard facts
/// and hands tombstoned entry ULIDs to the platform's `deleteRecords`, and
/// the `HealthSyncTombstoneCoordinator` watches the bound profile's day
/// entries and triggers the service for newly-tombstoned entries.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_sync_deletion_service.dart';
import 'package:lunarlog/data/health/health_sync_tombstone_coordinator.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
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

class _FakeDayEntries implements DayEntriesRepository {
  List<DayEntry> entries = const [];
  final _changes = StreamController<List<DayEntry>>.broadcast();

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      _changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

  @override
  Future<HealthSyncDeletionReport> deleteSamples(List<String> recordIds) async {
    calls.add(List.of(recordIds));
    return result;
  }
}

DayEntry _entry(String id, {DateTime? deletedAt}) => DayEntry(
      id: id,
      profileId: _profileId,
      localDate: LocalDate(2026, 9, 1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

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

  group('HealthSyncTombstoneCoordinator', () {
    test('tombstoned entries trigger the deletion service once', () async {
      final settings = FakeSettingsStore({
        SettingsKeys.healthStoreProfileId: _profileId,
      });
      final binding = HealthSyncBinding(settings);
      final entries = _FakeDayEntries();
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        dayEntries: entries,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      // A live entry: nothing to delete.
      entries._changes.add([_entry(_entryId)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);

      // The same entry tombstoned: its ULID is handed to the service.
      entries._changes
          .add([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, [
        [_entryId]
      ]);

      // A repeat emission of the same tombstone is not re-deleted.
      entries._changes
          .add([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, hasLength(1));
    });

    test('unbound: no deletion is ever issued', () async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      final entries = _FakeDayEntries();
      final deletion = _FakeDeletion();
      final coordinator = HealthSyncTombstoneCoordinator(
        binding: binding,
        dayEntries: entries,
        deletionService: deletion,
        debounce: const Duration(milliseconds: 10),
      );
      coordinator.start();
      addTearDown(() => coordinator.dispose());

      entries._changes
          .add([_entry(_entryId, deletedAt: DateTime.utc(2026, 9, 2))]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(deletion.calls, isEmpty);
    });
  });
}
