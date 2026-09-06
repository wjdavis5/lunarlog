/// Account export builder (Issue #17, Unit U5; KTD5, KTD6). Pure Dart: no
/// Flutter, no Supabase, no `dart:io` - the only untestable part of export
/// is the temp-file write and share-sheet hand-off in
/// `lib/data/export/account_export_writer.dart`.
///
/// The local encrypted Drift store is the app's source of truth (KTD5), so
/// this reads exactly what [ProfilesRepository.list] and
/// [DayEntriesRepository.listForProfile] already return: archived profiles
/// included, tombstoned rows excluded by those repositories themselves
/// (see their own docs) - export never has to reason about `deletedAt`.
///
/// Deliberately excluded from the document (R9): sync bookkeeping
/// (`server_version`, `user_id`), guardian attribution ids
/// (`logged_by_user_id`, `last_modified_by_user_id`), and anything else not
/// already modelled as a plain field on [Profile]/[DayEntry] - this is the
/// family's data, not the sync protocol's.
library;

import '../models/day_entry.dart';
import '../models/profile.dart';

/// Bumped whenever the exported document's shape changes in a way a reader
/// (a future importer, or a person opening the file) must know about.
const int kAccountExportSchemaVersion = 1;

/// The app doesn't read this from a plugin (KTD6: `lib/domain` stays pure
/// Dart and untestable platform calls stay out of the builder) - it is a
/// plain literal the writer passes in, kept in step with `pubspec.yaml`'s
/// `version:` by hand.
const String kAccountExportAppName = 'lunarlog';

/// Builds the exported document: [schemaVersion], [exportedAt] (always
/// normalized to UTC), [app] (name + version, both passed in - see
/// [kAccountExportAppName]), and [profiles] with each profile's own
/// [dayEntries] nested under it.
///
/// Deterministic (profiles sorted by id, entries by [DayEntry.localDate]):
/// two calls with the same input, `jsonEncode`d, produce byte-identical
/// output.
Map<String, Object?> buildAccountExport({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  required DateTime exportedAt,
  String appName = kAccountExportAppName,
  required String appVersion,
}) {
  final sortedProfiles = [...profiles]..sort((a, b) => a.id.compareTo(b.id));
  return {
    'schemaVersion': kAccountExportSchemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'app': {'name': appName, 'version': appVersion},
    'profiles': [
      for (final profile in sortedProfiles)
        _exportProfile(profile, entriesByProfile[profile.id] ?? const []),
    ],
  };
}

Map<String, Object?> _exportProfile(
  Profile profile,
  List<DayEntry> entries,
) {
  final sortedEntries = [...entries]
    ..sort((a, b) => a.localDate.compareTo(b.localDate));
  return {
    'id': profile.id,
    'displayName': profile.displayName,
    'isMinor': profile.isMinor,
    'sortOrder': profile.sortOrder,
    'archivedAt': profile.archivedAt?.toUtc().toIso8601String(),
    'createdAt': profile.createdAt.toUtc().toIso8601String(),
    'updatedAt': profile.updatedAt.toUtc().toIso8601String(),
    'dayEntries': [for (final entry in sortedEntries) _exportDayEntry(entry)],
  };
}

Map<String, Object?> _exportDayEntry(DayEntry entry) => {
      'id': entry.id,
      'localDate': entry.localDate.iso,
      'tz': entry.tz,
      'flow': entry.flow.name,
      'tags': entry.tags,
      'note': entry.note,
      'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
    };
