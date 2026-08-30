/// Drift-backed [DayEntriesRepository] over U2's storage layer. Every
/// storage call is scoped to exactly one profile id (R3).
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/tags.dart' as domain;

import 'mappers.dart';

class DriftDayEntriesRepository implements DayEntriesRepository {
  DriftDayEntriesRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<domain.DayEntry> save(domain.DayEntry entry) async {
    domain.validateTagCodes(entry.tags);
    return dayEntryToDomain(await _storage.upsertDayEntry(
      profileId: entry.profileId,
      localDate: entry.localDate.iso,
      tz: entry.tz,
      flow: flowFromDomain(entry.flow),
      tags: entry.tags,
      note: entry.note,
    ));
  }

  @override
  Future<domain.DayEntry?> find(
      String profileId, domain.LocalDate localDate) async {
    final rows = await _storage.getDayEntries(profileId: profileId);
    for (final row in rows) {
      if (row.localDate == localDate.iso) return dayEntryToDomain(row);
    }
    return null;
  }

  @override
  Future<List<domain.DayEntry>> listForProfile(String profileId) async =>
      [for (final row in await _storage.getDayEntries(profileId: profileId))
        dayEntryToDomain(row)];

  @override
  Stream<List<domain.DayEntry>> watchForProfile(String profileId) =>
      _storage
          .watchDayEntries(profileId: profileId)
          .map((rows) => [for (final row in rows) dayEntryToDomain(row)]);

  @override
  Future<void> delete(String profileId, domain.LocalDate localDate) =>
      _storage.softDeleteDayEntry(
        profileId: profileId,
        localDate: localDate.iso,
      );
}
