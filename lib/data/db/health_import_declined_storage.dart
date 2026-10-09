part of 'storage.dart';

// The device's memory of health-store records the import declined (issue
// #1652). What it is for is in
// `lib/domain/health/health_import_declined.dart`.
//
// One `app_settings` row per record, like the deletion memory beside it.
//
// Key: `health_import_declined_<profileId>|<source>|<record id>`.
// Value: `<kind>|<ISO date>`, e.g. `flow|2026-06-03`.

const String _kHealthImportDeclinedPrefix = 'health_import_declined_';

/// The key prefix of [profileId]'s remembered records, or of those from
/// one [source]. It always ends in `|`.
String _healthImportDeclinedPrefix(String profileId, [String? source]) {
  final ofProfile = '$_kHealthImportDeclinedPrefix$profileId|';
  return source == null ? ofProfile : '$ofProfile$source|';
}

/// The settings rows whose key starts with [prefix]. A range and not
/// `LIKE`, for the same reason the deletion memory uses one: the keys hold
/// `_`, which `LIKE` reads as "any one character".
Expression<bool> _healthImportDeclinedIn($AppSettingsTable t, String prefix) {
  final end = '${prefix.substring(0, prefix.length - 1)}}';
  return t.key.isBiggerOrEqualValue(prefix) & t.key.isSmallerThanValue(end);
}

/// Forgets [profileId]'s remembered declined records: those of one
/// [source], or every one when [source] is null. Called where the deletion
/// memory is cleared — a profile wipe, and a purge of a store's imported
/// data (Issue #1652).
Future<void> _forgetHealthImportDeclined(
  LunarLogDatabase db,
  String profileId, [
  String? source,
]) async {
  final prefix = _healthImportDeclinedPrefix(profileId, source);
  await (db.delete(db.appSettings)
        ..where((t) => _healthImportDeclinedIn(t, prefix)))
      .go();
}

/// The record [key] and [value] name, or null when this build cannot read
/// them.
HealthImportDeclinedRecord? _parseHealthImportDeclined(
  String key,
  String value,
) {
  final bar = key.indexOf('|');
  if (bar <= 0 || bar == key.length - 1) return null;
  final parts = value.split('|');
  if (parts.length != 2) return null;
  final kind = HealthImportDeclinedKind.fromWire(parts[0]);
  final date = LocalDate.tryParseIso(parts[1]);
  if (kind == null || date == null) return null;
  return HealthImportDeclinedRecord(key: key, kind: kind, date: date);
}

/// What the health import reads and writes of that memory
/// ([HealthImportDeclinedStore]).
mixin LunarLogStorageHealthImportDeclined implements HealthImportDeclinedStore {
  AppSettingsStore get appSettings;
  LunarLogDatabase get db;

  /// [profileId]'s remembered declined records, keyed `<source>|<record
  /// id>`. A row whose value this build cannot read is skipped, so a later
  /// build's kind never makes an earlier one misread a date.
  @override
  Future<Map<String, HealthImportDeclinedRecord>> readDeclinedHealthRecords(
    String profileId,
  ) async {
    final prefix = _healthImportDeclinedPrefix(profileId);
    final rows = await (db.select(db.appSettings)
          ..where((t) => _healthImportDeclinedIn(t, prefix)))
        .get();
    final parsed = <String, HealthImportDeclinedRecord>{};
    for (final row in rows) {
      final record = _parseHealthImportDeclined(
        row.key.substring(prefix.length),
        row.value,
      );
      if (record != null) parsed[record.key] = record;
    }
    return parsed;
  }

  /// Remembers [recordId] as declined for [date]. The same record
  /// remembered again refreshes its date and kind.
  @override
  Future<void> rememberDeclinedHealthRecord(
    String profileId, {
    required String source,
    required String recordId,
    required HealthImportDeclinedKind kind,
    required LocalDate date,
  }) =>
      appSettings.setSetting(
        key: '${_healthImportDeclinedPrefix(profileId, source)}$recordId',
        value: '${kind.wire}|${date.iso}',
      );

  /// Forgets the named records, keyed as [readDeclinedHealthRecords]
  /// returns them.
  @override
  Future<void> forgetDeclinedHealthRecords(
    String profileId,
    Set<String> keys,
  ) async {
    final prefix = _healthImportDeclinedPrefix(profileId);
    for (final key in keys) {
      await (db.delete(db.appSettings)
            ..where((t) => t.key.equals('$prefix$key')))
          .go();
    }
  }
}
