/// Drift-backed [DayEntriesRepository] over U2's storage layer. Every
/// storage call is scoped to exactly one profile id (R3).
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

import 'mappers.dart';

class DriftDayEntriesRepository implements DayEntriesRepository {
  DriftDayEntriesRepository(this._storage);

  final LunarLogStorage _storage;

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
            category: o.category,
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

  @override
  Future<void> delete(String profileId, domain.LocalDate localDate) =>
      _storage.softDeleteDayEntry(
        profileId: profileId,
        localDate: localDate.iso,
      );
}
