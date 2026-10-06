/// Device-local memory of what she deleted that had come from the health
/// store (Issue #1561), so that the next import does not bring it back.
///
/// A deleted day keeps which record it was imported from, but only for as
/// long as the deleted row exists on the phone, and a clean deleted row is
/// swept two days after it has synced. The import then saw no trace of the
/// day and inserted it again. Keeping the deleted row longer is not an
/// option: deleted records are removed once they have synced. So the one
/// thing worth keeping is kept on its own.
///
/// What is kept, per profile: the store's record id as the row held it (see
/// `_recordKey` in `health_import_service.dart`), under the row's source,
/// and the moment of the deletion. No date, no flow, nothing about the day.
/// The record itself is still in the health store on the same phone; this
/// only says "not this one again".
///
/// It is written when she deletes a day or an entry herself. It is NOT
/// derived from deleted rows: "Remove imported data" also leaves deleted
/// rows, and after that an import must bring the days back.
///
/// Never synced: it lives under an `app_settings` key, like the merge-notice
/// dismissals, and it is this phone's health store the ids belong to.
///
/// Pure Dart: `dart:convert` is the only import.
library;

import 'dart:convert';

/// The `app_settings` key holding [profileId]'s deleted health-store records.
String healthImportDeletionsKey(String profileId) =>
    'health_import_deleted_$profileId';

/// The row sources that mean "imported from this phone's health store": the
/// two day-entry sources and the two observation sources (Health Connect
/// uses one name for both).
const Set<String> kHealthStoreSources = {
  'healthkit',
  'health_connect',
  'apple_health',
};

/// Cap on remembered records per profile; the oldest deletions are dropped
/// first. A dropped one can at worst be imported again.
const int kHealthImportDeletionsCap = 2000;

/// One remembered record's name in the map: its source, then its record id.
String healthImportDeletionId(String source, String sourceId) =>
    '$source|$sourceId';

/// Decodes a stored settings value into record name -> moment of deletion.
/// Tolerant by design: a null, empty or corrupt value decodes to nothing,
/// and an entry of the wrong shape is skipped, so a bad value can never
/// stop an import.
Map<String, DateTime> decodeHealthImportDeletions(String? stored) {
  if (stored == null || stored.isEmpty) return const {};
  final dynamic decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  return {
    for (final entry in decoded.entries)
      if (entry.key is String && entry.value is int)
        entry.key as String: DateTime.fromMillisecondsSinceEpoch(
          entry.value as int,
          isUtc: true,
        ),
  };
}

/// Encodes [deletions] for storage, keeping the newest
/// [kHealthImportDeletionsCap].
String encodeHealthImportDeletions(Map<String, DateTime> deletions) {
  final newestFirst = deletions.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return jsonEncode({
    for (final entry in newestFirst.take(kHealthImportDeletionsCap))
      entry.key: entry.value.millisecondsSinceEpoch,
  });
}

/// [deletions] with every health-store record in [records] added at [at].
/// A record is a row's `(source, sourceId)`; one that did not come from the
/// health store, or has no id, is left out. Returns [deletions] itself when
/// nothing is added, so a caller can tell there is nothing to write.
Map<String, DateTime> rememberHealthImportDeletions(
  Map<String, DateTime> deletions,
  Iterable<(String source, String? sourceId)> records,
  DateTime at,
) {
  final added = <String, DateTime>{};
  for (final (source, sourceId) in records) {
    if (sourceId == null || !kHealthStoreSources.contains(source)) continue;
    added[healthImportDeletionId(source, sourceId)] = at;
  }
  if (added.isEmpty) return deletions;
  return {...deletions, ...added};
}

/// [deletions] without the records of [source]: what "Remove imported data"
/// leaves, so that a later import of that source starts clean.
Map<String, DateTime> forgetHealthImportSource(
  Map<String, DateTime> deletions,
  String source,
) {
  final prefix = '$source|';
  return {
    for (final entry in deletions.entries)
      if (!entry.key.startsWith(prefix)) entry.key: entry.value,
  };
}
