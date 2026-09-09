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
///
/// Issue #248 adds the server-side half: [buildMergedAccountExport] wraps
/// [buildAccountExport]'s local-only document with whatever
/// `public.export_account_data()` returns (guardian memberships,
/// invitations, ownership-transfer history, notification preferences,
/// registered devices, missed-entry alert state, feedback tickets, and
/// reminder windows - none of which the local Drift store holds), merged
/// under a `server` key by [mergeAccountExport] without altering this
/// file's own `profiles`/`dayEntries` shape at all. The sign-in gate on
/// "Export my data" itself is unchanged by this issue (that ungating is
/// #222) - only the *local* half of export is meant to ever run signed
/// out, and [buildMergedAccountExport] already treats a null
/// [AccountExportRemoteSource] (or one that resolves to `null`) as
/// "nothing to merge", so it degrades correctly either way.
library;

import 'dart:convert';

import '../models/day_entry.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import 'account_export_remote_source.dart';

/// Bumped whenever the exported document's shape changes in a way a reader
/// (a future importer, or a person opening the file) must know about.
/// v2 adds `profiles[].mode` (Issue #131). v3 adds
/// `profiles[].observations` (Issue #240): a real per-profile read wired
/// through `ObservationsRepository`/`DriftObservationsRepository`,
/// `lib/data/export/account_export_writer.dart`, and its UI callers
/// (`lib/ui/account/export_account_collaborator.dart`,
/// `lib/ui/settings/your_data_section.dart`) — a reader of an old (v2)
/// export still knows the absence of the key means "not yet collected,"
/// not "this profile has none."
const int kAccountExportSchemaVersion = 3;

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
  Map<String, List<Observation>> observationsByProfile = const {},
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
        _exportProfile(
          profile,
          entriesByProfile[profile.id] ?? const [],
          observationsByProfile[profile.id] ?? const [],
        ),
    ],
  };
}

Map<String, Object?> _exportProfile(
  Profile profile,
  List<DayEntry> entries,
  List<Observation> observations,
) {
  final sortedEntries = [...entries]
    ..sort((a, b) => a.localDate.compareTo(b.localDate));
  final sortedObservations = [...observations]
    ..sort((a, b) => a.id.compareTo(b.id));
  return {
    'id': profile.id,
    'displayName': profile.displayName,
    'isMinor': profile.isMinor,
    'mode': profile.mode.toDb(),
    'sortOrder': profile.sortOrder,
    'archivedAt': profile.archivedAt?.toUtc().toIso8601String(),
    'createdAt': profile.createdAt.toUtc().toIso8601String(),
    'updatedAt': profile.updatedAt.toUtc().toIso8601String(),
    'dayEntries': [for (final entry in sortedEntries) _exportDayEntry(entry)],
    // Issue #240; see this file's `kAccountExportSchemaVersion` v3 doc
    // comment — this is a real per-profile read, not a placeholder.
    'observations': [
      for (final observation in sortedObservations) _exportObservation(observation),
    ],
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

/// Merges [serverDocument] (an already-decoded `export_account_data()`
/// document) into [localDocument] under a `server` key (Issue #248),
/// without altering [localDocument]'s own keys or shape - the future
/// importer (#140) round-trips the local `profiles`/`dayEntries` section
/// exactly as it does today.
///
/// [serverDocument] is `null` when the server step never ran or produced
/// nothing usable (signed out, offline, unconfigured build - see
/// [AccountExportRemoteSource]): the document then carries
/// `serverIncluded: false` and no `server` key at all, so a reader (a
/// person, or the importer) can tell "the server step never ran" apart
/// from "it ran and the account genuinely has no server-side data".
Map<String, Object?> mergeAccountExport({
  required Map<String, Object?> localDocument,
  required Map<String, Object?>? serverDocument,
}) {
  if (serverDocument == null) {
    return {
      ...localDocument,
      'serverIncluded': false,
    };
  }
  return {
    ...localDocument,
    'serverIncluded': true,
    'server': serverDocument,
  };
}

/// Builds the full export document (Issue #248): [buildAccountExport]'s
/// local-only document, merged with the server's own export via
/// [remoteSource] when one is supplied.
///
/// [remoteSource] is `null` for an unconfigured build (no Supabase client
/// - see `AccountExportWriter`) or a signed-out/offline session; either
/// way this never turns export into a hard failure -
/// [AccountExportRemoteSource.fetchServerExport] itself resolves to `null`
/// on any failure (no session, network, server error), and this function
/// treats that identically to "no remote source at all" via
/// [mergeAccountExport].
Future<Map<String, Object?>> buildMergedAccountExport({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  Map<String, List<Observation>> observationsByProfile = const {},
  required DateTime exportedAt,
  String appName = kAccountExportAppName,
  required String appVersion,
  AccountExportRemoteSource? remoteSource,
}) async {
  final localDocument = buildAccountExport(
    profiles: profiles,
    entriesByProfile: entriesByProfile,
    observationsByProfile: observationsByProfile,
    exportedAt: exportedAt,
    appName: appName,
    appVersion: appVersion,
  );
  final serverDocument = await remoteSource?.fetchServerExport();
  return mergeAccountExport(
    localDocument: localDocument,
    serverDocument: serverDocument,
  );
}
Map<String, Object?> _exportObservation(Observation o) => {
      'id': o.id,
      'dayEntryId': o.dayEntryId,
      'localDate': o.localDate.iso,
      'observedAt': o.observedAt?.toUtc().toIso8601String(),
      'tz': o.tz,
      'category': o.category,
      'code': o.code,
      'valueNum': o.valueNum,
      'valueText': o.valueText,
      'unit': o.unit,
      'intensity': o.intensity,
      'excluded': o.excluded,
      'source': o.source.toDb(),
      'sourceId': o.sourceId,
      'raw': o.raw == null ? null : jsonDecode(o.raw!),
      'updatedAt': o.updatedAt.toUtc().toIso8601String(),
    };
