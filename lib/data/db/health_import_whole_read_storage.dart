part of 'storage.dart';

// The device's memory that a store's imported data was purged and the next
// import pass owes a whole-history read (issue #1876). What it is for is in
// `lib/domain/health/health_import_whole_read.dart`.
//
// One `app_settings` row per profile, like the memories beside it.
//
// Key: `health_import_whole_read_<profileId>`.

const String _kHealthImportWholeReadPrefix = 'health_import_whole_read_';

String _healthImportWholeReadKey(String profileId) =>
    '$_kHealthImportWholeReadPrefix$profileId';

/// Remembers that [profileId] owes a whole-history read (issue #1876).
/// Called in the purge's own transaction, beside the memories it clears.
Future<void> _rememberHealthImportWholeRead(
  LunarLogDatabase db,
  String profileId,
  DateTime at,
) =>
    db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _healthImportWholeReadKey(profileId),
            value: '1',
            updatedAt: at.toUtc(),
          ),
        );

/// Forgets it, with the profile's other health-import memories.
Future<void> _forgetHealthImportWholeRead(
  LunarLogDatabase db,
  String profileId,
) async {
  await (db.delete(db.appSettings)
        ..where((t) => t.key.equals(_healthImportWholeReadKey(profileId))))
      .go();
}

/// What the health import reads and writes of that memory
/// ([HealthImportWholeReadStore]).
mixin LunarLogStorageHealthImportWholeRead
    implements HealthImportWholeReadStore {
  AppSettingsStore get appSettings;
  LunarLogDatabase get db;

  @override
  Future<bool> wholeReadOwed(String profileId) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(_healthImportWholeReadKey(profileId))))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> rememberWholeReadOwed(String profileId) => appSettings.setSetting(
        key: _healthImportWholeReadKey(profileId),
        value: '1',
      );

  @override
  Future<void> forgetWholeReadOwed(String profileId) =>
      _forgetHealthImportWholeRead(db, profileId);
}
