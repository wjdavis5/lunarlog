part of 'storage.dart';

// Role interfaces for the storage surface (issue
// #551 problem 1).
//
// `LunarLogStorage` is one large class with no abstraction, so every
// production consumer bound to the concrete type and every repository test
// opened a real drift database. These interfaces name the parts of that
// surface by consumer concern — `DayEntryStore`, `ProfileStore`,
// `SyncApplyStore`, and so on — and `LunarLogStorage` implements them all.
// Consumers are typed against the narrowest role they actually call, so a
// fake can stand in for storage in a focused test.
//
// Purely a declaration split: no member moved, no logic changed.

/// Reads and writes for the `profiles` table, plus the revocation purge.
abstract interface class ProfileStore {
  Future<List<Profile>> getProfiles({bool includeTombstones = false});
  Stream<List<Profile>> watchProfiles({bool includeTombstones = false});
  Future<Profile?> getProfile(String id, {bool includeTombstones = false});
  Future<Profile> upsertProfile({
    String? id,
    required String displayName,
    required bool isMinor,
    String mode = 'standard',
    bool? irregularFraming,
    String bbtUnit = 'celsius',
    String weightUnit = 'kg',
    String? trackingPreferences,
    int sortOrder = 0,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? birthYear,
    String? relationship,
    String? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
  });
  Future<Profile?> setTrackingPreferences(String profileId, String? jsonText);
  Future<void> softDeleteProfile(String id);
  Future<Profile> reviveTombstonedProfile(String id);
  Future<void> applyLocalProfilePurge(String profileId);
}

/// Reads and writes for the `day_entries` table.
abstract interface class DayEntryStore {
  Future<List<DayEntry>> getDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
    String? fromLocalDate,
    String? toLocalDate,
  });
  Stream<List<DayEntry>> watchDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
    String? fromLocalDate,
    String? toLocalDate,
  });
  Future<DayEntry?> getDayEntry({
    required String profileId,
    required String localDate,
  });
  Future<DayEntry?> getDayEntryById(String id);
  Future<DayEntry?> findDayEntryBySource({
    required String profileId,
    required String source,
    required String? sourceId,
  });
  Future<bool> hasAnyEntries(String profileId);
  Stream<bool> watchHasAnyEntries(String profileId);
  Future<DayEntry> upsertDayEntry({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    List<String> tags = const [],
    String? note,
    bool notePrivate = false,
    bool pms = false,
    DateTime? updatedAt,
    String source = 'manual',
    String? sourceId,
    String? importId,
  });
  Future<DayEntry> saveDayEntryWithObservations({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    List<String> tags = const [],
    String? note,
    bool notePrivate = false,
    bool pms = false,
    DateTime? updatedAt,
    String source = 'manual',
    String? sourceId,
    String? importId,
    List<UpsertObservationPayload> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  });
  Future<List<DayEntry>> bulkUpsertDayEntries(
    List<DayEntry> entries, {
    List<Observation> observations = const [],
  });
  Future<void> softDeleteDayEntry({
    required String profileId,
    required String localDate,
  });
}

/// Reads and writes for the `observations` table.
abstract interface class ObservationStore {
  Future<Observation?> getObservationById(String id);
  Future<List<Observation>> getObservationsForDayEntry(
    String dayEntryId, {
    bool includeTombstones = false,
  });
  Stream<List<Observation>> watchObservationsForDayEntry(
    String dayEntryId, {
    bool includeTombstones = false,
  });
  Future<Observation?> findObservationBySource({
    required String profileId,
    required String source,
    required String? sourceId,
  });
  Future<List<Observation>> getObservationsForProfile(
    String profileId, {
    bool includeTombstones = false,
    String? fromLocalDate,
    String? toLocalDate,
    String? category,
  });
  Stream<List<Observation>> watchObservationsForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Future<Observation> upsertObservation({
    String? id,
    required String dayEntryId,
    required String profileId,
    required String localDate,
    DateTime? observedAt,
    required String tz,
    required String category,
    String? code,
    double? valueNum,
    String? valueText,
    String? unit,
    int? intensity,
    bool excluded = false,
    String source = 'manual',
    String? sourceId,
    String? importId,
    String? raw,
    DateTime? updatedAt,
  });
  Future<void> softDeleteObservation(String id);
}

/// Reads and writes for the life-stage `profile_modes` and
/// `cycle_overrides` tables.
abstract interface class CycleStore {
  Future<ProfileModeData?> getProfileMode(String profileId);
  Stream<ProfileModeData?> watchProfileMode(String profileId);
  Future<CycleOverrideData?> getCycleOverrideById(String id, String profileId);
  Future<List<CycleOverrideData>> getCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Stream<List<CycleOverrideData>> watchCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Future<ProfileModeData> upsertProfileMode({
    required String profileId,
    required String mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
    String? birthControlStartedOn,
    String? birthControlStoppedOn,
    bool healthSyncConsent = false,
    DateTime? updatedAt,
  });
  Future<CycleOverrideData> upsertCycleOverride({
    String? id,
    required String profileId,
    required String cycleStartDate,
    bool excludedFromAverage = false,
    bool manualStart = false,
    String? noteId,
    DateTime? updatedAt,
  });
  Future<void> softDeleteCycleOverride({
    required String id,
    required String profileId,
  });
}

/// Reads and writes for the `care_notes` and `visit_prep_items` tables.
abstract interface class CareContentStore {
  Future<List<CareNoteData>> getCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Stream<List<CareNoteData>> watchCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Future<CareNoteData> upsertCareNote({
    String? id,
    required String profileId,
    required String body,
    DateTime? updatedAt,
  });
  Future<void> softDeleteCareNote(String id);
  Future<List<VisitPrepItemData>> getVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
    String? kind,
  });
  Stream<List<VisitPrepItemData>> watchVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
    String? kind,
  });
  Future<VisitPrepItemData> addVisitPrepItem({
    String? id,
    required String profileId,
    required String body,
    String kind = 'visit_prep',
    DateTime? updatedAt,
  });
  Future<VisitPrepItemData?> editVisitPrepItem({
    required String id,
    required String body,
    DateTime? updatedAt,
  });
  Future<VisitPrepItemData?> setVisitPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
    DateTime? updatedAt,
  });
  Future<void> softDeleteVisitPrepItem(String id);
  Future<int> clearCheckedVisitPrepItems(
    String profileId, {
    String kind = 'visit_prep',
  });
}

/// Reads and writes for the dated `guardian_notes` table.
abstract interface class GuardianNoteStore {
  Future<List<GuardianNoteData>> getGuardianNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Future<GuardianNoteData?> getGuardianNoteById(String id);
  Stream<List<GuardianNoteData>> watchGuardianNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  });
  Future<GuardianNoteData?> findLiveGuardianNoteForDate({
    required String profileId,
    required String localDate,
    required String? authorUserId,
  });
  Future<GuardianNoteData> upsertGuardianNote({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
    DateTime? updatedAt,
  });
  Future<void> softDeleteGuardianNote(String id);
}

/// Reads and writes for the per-profile `profile_tag_registry` table.
abstract interface class TagRegistryStore {
  Future<List<ProfileTagRegistryEntry>> getProfileTagRegistry(
    String profileId,
  );
  Stream<List<ProfileTagRegistryEntry>> watchProfileTagRegistry(
    String profileId,
  );
  Future<ProfileTagRegistryEntry?> getProfileTagRegistryEntriesById(String id);
  Future<ProfileTagRegistryEntry?> findProfileTagByCode(
    String profileId,
    String code,
  );
  Future<ProfileTagRegistryEntry> upsertProfileTagRegistryEntry({
    String? id,
    required String profileId,
    required String code,
    required String displayName,
    String category = kCustomTagCategory,
    bool intensityEnabled = false,
    DateTime? hiddenAt,
    int? sortOrder,
    DateTime? updatedAt,
  });
  Future<bool> retireProfileTagRegistryEntry(String id);
}

/// Reads and writes for the device-local `app_settings` key-value table.
abstract interface class AppSettingsStore {
  Future<String?> getSetting(String key);
  Stream<String?> watchSetting(String key);
  Future<void> setSetting({
    required String key,
    required String value,
    DateTime? updatedAt,
  });
}

/// Reads and writes for the same-date merge `day_entry_merge_events` table.
abstract interface class MergeEventStore {
  Future<List<DayEntryMergeEventData>> getDayEntryMergeEventsForDay(
    String profileId,
    String localDate, {
    DateTime? now,
  });
  Future<List<DayEntryMergeEventData>> getDayEntryMergeEventsForProfile(
    String profileId, {
    DateTime? now,
  });
  Future<void> dismissDayEntryMergeEvent({
    required String profileId,
    required String eventId,
  });
}

/// Reads for the `profile_guardians` table (pull-only: guardians are never
/// written locally).
abstract interface class ProfileGuardianStore {
  Future<List<ProfileGuardianData>> getGuardiansForProfile(String profileId);
  Stream<List<ProfileGuardianData>> watchGuardiansForProfile(String profileId);
}

/// The `sync_state` singleton and the in-memory clock offset.
abstract interface class SyncCursorStore {
  Future<SyncStateRow> readSyncState();
  Future<void> writeSyncState(SyncStateRow state);
  void setClockOffset(Duration offset);
}

/// Dirty-row scans, push bookkeeping, and local maintenance.
abstract interface class SyncDirtyStore {
  Future<List<Profile>> readDirtyProfiles({int? limit, String? afterId});
  Future<List<DayEntry>> readDirtyDayEntries({int? limit, String? afterId});
  Future<List<Observation>> readDirtyObservations({int? limit, String? afterId});
  Future<List<ProfileModeData>> readDirtyProfileModes({
    int? limit,
    String? afterId,
  });
  Future<List<CycleOverrideData>> readDirtyCycleOverrides({
    int? limit,
    String? afterId,
  });
  Future<List<CareNoteData>> readDirtyCareNotes({int? limit, String? afterId});
  Future<List<VisitPrepItemData>> readDirtyVisitPrepItems({
    int? limit,
    String? afterId,
  });
  Future<List<GuardianNoteData>> readDirtyGuardianNotes({
    int? limit,
    String? afterId,
  });
  Future<List<DayEntryMergeEventData>> readDirtyDayEntryMergeEvents({
    int? limit,
    String? afterId,
  });
  Future<List<ProfileTagRegistryEntry>> readDirtyProfileTagRegistry({
    int? limit,
    String? afterId,
  });
  Future<void> markAllDirty();
  Future<int> dirtyCount();
  Future<bool> isEmpty();
  Future<int> rebaseFutureStampedRows({required DateTime serverNow});
  Future<int> sweepTombstones({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  });
}

/// Remote apply, push-result apply, and rejected-row retry.
abstract interface class SyncApplyStore {
  Future<void> applyRemotePage({
    required SyncTable table,
    required List<RemoteRow> rows,
    required int newCursor,
  });
  Future<void> applyRemoteRows(List<RemoteRow> rows);
  Future<void> applyPushResult({
    required List<({SyncTable table, String id, int localRevAtPush})> accepted,
    required List<RemoteRow> resolved,
  });
  Future<void> bumpLocalRevForRetry({
    required SyncTable table,
    required String id,
  });
}

/// The device-local health-sync anchor and export-ledger tables (never
/// synced to the server).
abstract interface class HealthDeviceStore {
  Future<HealthSyncStateRow?> readHealthSyncAnchor(String platform);
  Future<void> writeHealthSyncAnchor(HealthSyncStateRow anchor);
  Future<List<HealthExportLedgerRowData>> readHealthExportLedger(
    String profileId,
  );
  Future<void> upsertHealthExportLedgerRows(
    List<HealthExportLedgerRowData> rows,
  );
  Future<void> deleteHealthExportLedgerRecordIds(List<String> recordIds);
  Future<void> deleteHealthExportLedgerForProfile(String profileId);
  Future<void> clearHealthExportLedger();
}

/// The local-first imported-data purge (Issue #883).
abstract interface class ImportedDataPurgeStore {
  Future<Map<String, int>> liveImportedSourceCounts(String profileId);
  Future<void> applyLocalImportedDataPurge({
    required String profileId,
    required String source,
  });
}

/// The `day_entries` surface [DriftDayEntriesRepository] calls.
abstract interface class DayEntriesRepositoryStore
    implements DayEntryStore, MergeEventStore, AppSettingsStore {}

/// The `day_entries`/`observations` surface
/// [DriftObservationsRepository] calls.
abstract interface class ObservationsRepositoryStore
    implements ObservationStore, DayEntryStore {}

/// The surface [DriftActivityFeedRepository] calls.
abstract interface class ActivityFeedStore
    implements DayEntryStore, ProfileGuardianStore, AppSettingsStore {}

/// The surface [DriftHealthSyncTombstoneSource] calls.
abstract interface class HealthTombstoneSourceStore
    implements DayEntryStore, ObservationStore {}

/// The surface [DriftAccountExportSnapshotRepository] calls, including the
/// database handle its one transaction wraps.
abstract interface class AccountExportSnapshotStore
    implements TagRegistryStore, GuardianNoteStore {
  LunarLogDatabase get db;
}

/// The surface the account importer and its coordinator call, including the
/// database handle their one transaction wraps.
abstract interface class AccountImportStore
    implements
        ProfileStore,
        CycleStore,
        DayEntryStore,
        ObservationStore,
        TagRegistryStore,
        GuardianNoteStore {
  LunarLogDatabase get db;
}

/// The surface [ClueImporter] calls, including the database handle its one
/// transaction wraps.
abstract interface class ClueImportStore
    implements DayEntryStore, ObservationStore {
  LunarLogDatabase get db;
}

/// The surface [SupabaseSyncEngine] calls, including the database handle it
/// watches for writes.
abstract interface class SyncEngineStore
    implements SyncCursorStore, SyncDirtyStore, SyncApplyStore {
  LunarLogDatabase get db;
}
