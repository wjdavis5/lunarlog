/// Drift-backed [DayEntriesRepository] over U2's storage layer. Every
/// storage call is scoped to exactly one profile id (R3).
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart'
    as mergelog;
import 'package:lunarlog/domain/logging/merge_notice_dismissals.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

import 'mappers.dart';

class DriftDayEntriesRepository
    implements
        DayEntriesRepository,
        LatestDayEntryReader,
        DayEntrySyncStateReader,
        DeletedDayEntryReader {
  DriftDayEntriesRepository(this._storage);

  final DayEntriesRepositoryStore _storage;

  /// Persists [entry] as-is, tag codes included. This boundary does **not**
  /// gate on the client's tag taxonomy (`domain.validateTagCodes`,
  /// `kTagTaxonomy`): a stored entry can carry a code the running build does
  /// not recognise — from a newer peer, an import, or test fixtures — and it
  /// must remain writable rather than being permanently rejected (#237).
  /// Taxonomy membership is a UI/display concern; a caller that wants strict
  /// validation of newly-chosen codes should call `validateTagCodes` itself
  /// before constructing [entry] (see `DaySheet`).
  @override
  Future<domain.DayEntry> save(domain.DayEntry entry) =>
      saveDayEntryWithObservations(entry: entry);

  @override
  Future<domain.DayEntry> saveDayEntryWithObservations({
    required domain.DayEntry entry,
    List<domain.Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) async {
    return dayEntryToDomain(await _storage.saveDayEntryWithObservations(
      id: entry.id.isEmpty ? null : entry.id,
      profileId: entry.profileId,
      localDate: entry.localDate.iso,
      tz: entry.tz,
      flow: flowFromDomain(entry.flow),
      tags: entry.tags,
      note: entry.note,
      notePrivate: entry.notePrivate,
      pms: entry.pms,
      source: entry.source.toDb(),
      sourceId: entry.sourceId,
      importId: entry.importId,
      observationsToUpsert: [
        for (final o in observationsToUpsert)
          UpsertObservationPayload(
            id: o.id.isEmpty ? null : o.id,
            dayEntryId: o.dayEntryId.isEmpty ? null : o.dayEntryId,
            profileId: o.profileId,
            localDate: o.localDate.iso,
            observedAt: o.observedAt,
            tz: o.tz,
            category: o.category.wireCode,
            code: o.code,
            valueNum: o.valueNum,
            valueText: o.valueText,
            unit: o.unit,
            intensity: o.intensity,
            excluded: o.excluded,
            source: o.source.toDb(),
            sourceId: o.sourceId,
            importId: o.importId,
            raw: o.raw,
            updatedAt: o.updatedAt,
          ),
      ],
      observationIdsToDelete: observationIdsToDelete,
    ));
  }

  @override
  Future<domain.DayEntry?> find(
      String profileId, domain.LocalDate localDate) async {
    final row = await _storage.getDayEntry(
      profileId: profileId,
      localDate: localDate.iso,
    );
    return row == null ? null : dayEntryToDomain(row);
  }

  @override
  Future<List<domain.DayEntry>> listForProfile(String profileId) async =>
      [for (final row in await _storage.getDayEntries(profileId: profileId))
        dayEntryToDomain(row)];

  @override
  Future<bool> hasAnyEntries(String profileId) =>
      _storage.hasAnyEntries(profileId);

  /// Issue #1561: the deleted row carrying this provenance, however it
  /// came to be deleted. The storage lookup answers live and deleted rows
  /// alike; a live one is not what was asked for.
  @override
  Future<domain.DayEntry?> findDeletedBySource({
    required String profileId,
    required domain.DayEntrySource source,
    required String sourceId,
  }) async {
    final row = await _storage.findDayEntryBySource(
      profileId: profileId,
      source: source.toDb(),
      sourceId: sourceId,
    );
    if (row == null || row.deletedAt == null) return null;
    return dayEntryToDomain(row);
  }

  /// Issue #850 U5: the guardian logistics card's bounded "last logged"
  /// read — one indexed live row at the greatest civil date.
  @override
  Future<domain.DayEntry?> latestEntryFor(String profileId) async {
    final row = await _storage.getLatestDayEntry(profileId);
    return row == null ? null : dayEntryToDomain(row);
  }

  /// Issue #1071 follow-up: whether the (profileId, date) row's note has been
  /// pushed (`dirty == false`) with text still present. The live-only
  /// `getDayEntry` read excludes tombstones for free, so a deleted note reads
  /// as never shared — the right answer, since the note is not out there for
  /// anyone to read.
  @override
  Future<bool> hasBeenShared(String profileId, domain.LocalDate date) async {
    final row = await _storage.getDayEntry(
      profileId: profileId,
      localDate: date.iso,
    );
    return row != null &&
        !row.dirty &&
        (row.note?.trim().isNotEmpty ?? false);
  }

  @override
  Stream<bool> watchHasAnyEntries(String profileId) =>
      _storage.watchHasAnyEntries(profileId);

  @override
  Stream<List<domain.DayEntry>> watchForProfile(
    String profileId, {
    domain.LocalDate? from,
    domain.LocalDate? to,
  }) =>
      _storage
          .watchDayEntries(
            profileId: profileId,
            fromLocalDate: from?.iso,
            toLocalDate: to?.iso,
          )
          .map((rows) => [for (final row in rows) dayEntryToDomain(row)]);

  /// Deletes the day, and remembers which health-store records it and its
  /// entries had come from (Issue #1561), so the next import does not
  /// bring them back. A day she logged herself leaves nothing behind.
  @override
  Future<void> delete(String profileId, domain.LocalDate localDate) async {
    final live = await _storage.getDayEntry(
      profileId: profileId,
      localDate: localDate.iso,
    );
    final entries = live == null
        ? const <(String, String?)>[]
        : [
            for (final o in await _storage.getObservationsForDayEntry(live.id))
              (o.source, o.sourceId),
          ];
    await _storage.softDeleteDayEntry(
      profileId: profileId,
      localDate: localDate.iso,
    );
    if (live == null) return;
    await rememberDeletedHealthImports(_storage, profileId, [
      (live.source, live.sourceId),
      ...entries,
    ]);
  }

  @override
  Future<Map<String, DateTime>> handDeletedRecords(String profileId) async =>
      decodeHealthImportDeletions(
        await _storage.getSetting(healthImportDeletionsKey(profileId)),
      );

  /// Issue #130: the day sheet's merge-notice list — the window-filtered
  /// storage read minus this device's dismissed ids. Dismissal filtering
  /// happens here (not in the SQL) because the dismissal list is a
  /// device-local `app_settings` value, not a column on the row.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
      String profileId, domain.LocalDate date) async {
    final dismissed = decodeMergeNoticeDismissals(
        await _storage.getSetting(mergeNoticeDismissalsKey(profileId)));
    final dismissedSet = dismissed.toSet();
    final rows =
        await _storage.getDayEntryMergeEventsForDay(profileId, date.iso);
    return [
      for (final row in rows)
        if (!dismissedSet.contains(row.id)) dayEntryMergeEventToDomain(row),
    ];
  }

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) =>
      _storage.dismissDayEntryMergeEvent(
        profileId: profileId,
        eventId: eventId,
      );

  /// Issue #130: the local JSON export's read — the same window-filtered
  /// storage read as [mergeEventsForDay], minus the dismissal filter (a
  /// dismissed notice is a per-device display choice; the disclosure
  /// itself is data the export should still carry while it exists).
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
          String profileId) async =>
      [
    for (final row
        in await _storage.getDayEntryMergeEventsForProfile(profileId))
      dayEntryMergeEventToDomain(row),
  ];
}

/// Adds the health-store records among [records] to [profileId]'s
/// device-local memory of what she deleted (Issue #1561). Writes nothing
/// when none of them came from the health store. Shared by the two
/// repositories whose `delete` she reaches: a whole day, and one entry.
Future<void> rememberDeletedHealthImports(
  AppSettingsStore settings,
  String profileId,
  Iterable<(String source, String? sourceId)> records,
) async {
  final key = healthImportDeletionsKey(profileId);
  final before = decodeHealthImportDeletions(await settings.getSetting(key));
  final after = rememberHealthImportDeletions(
    before,
    records,
    DateTime.now().toUtc(),
  );
  if (identical(after, before)) return;
  await settings.setSetting(
    key: key,
    value: encodeHealthImportDeletions(after),
  );
}
