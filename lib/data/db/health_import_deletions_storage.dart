part of 'storage.dart';

// The device's memory of deleted health-store records (issue #1561). What
// it is for is in `lib/domain/health/health_import_deletions.dart`.
//
// One `app_settings` row per record, not one value per profile: a deletion
// is one small write inside the transaction that deletes the row, and
// forgetting one record does not rewrite the others.
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

/// Forgets one remembered record: a live row carrying it was written
/// (Issue #1587 item 3) or an undo removed the row that carried it without
/// remembering it — either way the record is no longer deleted. No-op for
/// a row that did not come from a health store or carries no record id.
Future<void> _forgetHealthImportDeletion(
  LunarLogDatabase db,
  String profileId,
  String source,
  String? sourceId,
) async {
  if (sourceId == null || !kHealthStoreSources.contains(source)) return;
  await (db.delete(db.appSettings)
        ..where((t) => t.key
            .equals('${_healthImportDeletedPrefix(profileId, source)}$sourceId')))
      .go();
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
  ///
  /// Each is forgotten only if it still carries the moment the import
  /// read ([deletedAt]). A record deleted again since then has a new one,
  /// and that deletion is kept.
  @override
  Future<void> forgetHealthImportDeletions(
    String profileId,
    Map<String, DateTime> deletedAt,
  ) async {
    final prefix = _healthImportDeletedPrefix(profileId);
    for (final MapEntry(key: id, value: at) in deletedAt.entries) {
      await (db.delete(db.appSettings)
            ..where((t) =>
                t.key.equals('$prefix$id') &
                t.value.equals('${at.toUtc().millisecondsSinceEpoch}')))
          .go();
    }
  }

  /// Issue #1587 item 6: the remembered deletions still held for
  /// [profileId], counted by the source each key names — what a purge of a
  /// source with no live rows left has to clear. Satisfies
  /// [ImportedDataPurgeStore] on the composed storage class.
  Future<Map<String, int>> rememberedImportedSourceCounts(
    String profileId,
  ) async {
    final prefix = _healthImportDeletedPrefix(profileId);
    final rows = await (db.select(db.appSettings)
          ..where((t) => _healthImportDeletedIn(t, prefix)))
        .get();
    final counts = <String, int>{};
    for (final row in rows) {
      // Key: `<source>|<record id>` under the profile prefix.
      final id = row.key.substring(prefix.length);
      final bar = id.indexOf('|');
      if (bar <= 0) continue;
      final source = id.substring(0, bar);
      counts.update(source, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}
