part of 'storage.dart';

// The device's memory of deleted health-store records (issue #1561). What
// it is for is in `lib/domain/health/health_import_deletions.dart`.
//
// One `app_settings` row per record, not one value per profile. A deletion
// that arrives by sync is noted inside the page's own transaction, and a
// page can carry hundreds of them: a row is one small write, where a
// single growing value would be read, decoded, encoded and written again
// for every one.
//
// Key: `health_import_deleted_<profileId>|<source>|<record id>`.
// Value: the moment of the deletion, in UTC milliseconds.

const String _kHealthImportDeletedPrefix = 'health_import_deleted_';

/// The key prefix of [profileId]'s remembered records, or of those from
/// one [source]. It always ends in `|`.
String _healthImportDeletedPrefix(String profileId, [String? source]) {
  final ofProfile = '$_kHealthImportDeletedPrefix$profileId|';
  return source == null ? ofProfile : '$ofProfile$source|';
}

/// The settings rows whose key starts with [prefix]. A range and not
/// `LIKE`: the keys hold `_`, which `LIKE` reads as "any one character".
/// [prefix] ends in `|`, and `}` is the code unit after it.
Expression<bool> _healthImportDeletedIn($AppSettingsTable t, String prefix) {
  final end = '${prefix.substring(0, prefix.length - 1)}}';
  return t.key.isBiggerOrEqualValue(prefix) & t.key.isSmallerThanValue(end);
}

/// Remembers the health-store records among [records] as deleted at [at].
/// A row that did not come from the health store, or carries no record id,
/// is skipped, so a caller passes whatever rows it is deleting.
Future<void> _rememberHealthImportDeletions(
  LunarLogDatabase db,
  String profileId,
  Iterable<(String source, String? sourceId)> records,
  DateTime at,
) async {
  final stamp = at.toUtc();
  for (final (source, sourceId) in records) {
    if (sourceId == null || !kHealthStoreSources.contains(source)) continue;
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: '${_healthImportDeletedPrefix(profileId, source)}$sourceId',
            value: '${stamp.millisecondsSinceEpoch}',
            updatedAt: stamp,
          ),
        );
  }
}

/// Forgets [profileId]'s remembered records: those of one [source], or
/// every one when [source] is null.
Future<void> _forgetHealthImportDeletions(
  LunarLogDatabase db,
  String profileId, [
  String? source,
]) async {
  final prefix = _healthImportDeletedPrefix(profileId, source);
  await (db.delete(db.appSettings)
        ..where((t) => _healthImportDeletedIn(t, prefix)))
      .go();
}

/// What the health import reads of that memory, and the one correction it
/// makes to it ([HealthImportDeletionStore]).
mixin LunarLogStorageHealthImportDeletions on LunarLogStorageQueries
    implements HealthImportDeletionStore {
  /// [profileId]'s remembered records, each named
  /// `<source>|<record id>` (`healthImportDeletionId`), with the moment of
  /// its deletion. A value that is not a number reads as the epoch, so the
  /// record still counts as deleted.
  @override
  Future<Map<String, DateTime>> readHealthImportDeletions(
    String profileId,
  ) async {
    final prefix = _healthImportDeletedPrefix(profileId);
    final rows = await (db.select(db.appSettings)
          ..where((t) => _healthImportDeletedIn(t, prefix)))
        .get();
    return {
      for (final row in rows)
        row.key.substring(prefix.length): DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(row.value) ?? 0,
          isUtc: true,
        ),
    };
  }

  /// Forgets the named records: the import found each of them on a live
  /// row again, so the deletion was undone.
  @override
  Future<void> forgetHealthImportDeletions(
    String profileId,
    Iterable<String> recordIds,
  ) async {
    final prefix = _healthImportDeletedPrefix(profileId);
    final keys = [for (final id in recordIds) '$prefix$id'];
    await (db.delete(db.appSettings)..where((t) => t.key.isIn(keys))).go();
  }
}
