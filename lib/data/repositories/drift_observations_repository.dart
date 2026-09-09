/// Drift-backed [ObservationsRepository] over U2's storage layer (Issue
/// #240). Every storage call is scoped to exactly one profile id (R3),
/// mirroring [DriftDayEntriesRepository].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' as db;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/repositories/observations_repository.dart';

import 'mappers.dart';

class DriftObservationsRepository implements ObservationsRepository {
  DriftObservationsRepository(this._storage);

  final LunarLogStorage _storage;

  /// Issue #247: alongside every persisted observation, synthesises a
  /// `category: 'spotting'` row (never written back) for any live day
  /// entry whose stored `flow` is still the deprecated `spotting` alias
  /// and that doesn't already have a persisted spotting observation —
  /// this migration's server-side backfill inserts the real row for
  /// every already-synced account, so this only ever fires for a legacy
  /// row a peer hasn't synced since, or a device that hasn't pulled the
  /// backfilled row yet.
  @override
  Future<List<domain.Observation>> listForProfile(String profileId) async {
    final observations = [
      for (final row in await _storage.getObservationsForProfile(profileId))
        observationToDomain(row),
    ];
    final daySpottingIds = {
      for (final o in observations)
        if (o.category == 'spotting') o.dayEntryId,
    };
    for (final entry in await _storage.getDayEntries(profileId: profileId)) {
      if (entry.flow == db.FlowLevel.spotting &&
          !daySpottingIds.contains(entry.id)) {
        observations.add(_spottingObservationFor(entry));
      }
    }
    return observations;
  }

  @override
  Future<List<domain.Observation>> listForDayEntry(String dayEntryId) async => [
        for (final row in await _storage.getObservationsForDayEntry(dayEntryId))
          observationToDomain(row),
      ];

  @override
  Future<domain.Observation> save(domain.Observation observation) async =>
      observationToDomain(await _storage.upsertObservation(
        id: observation.id.isEmpty ? null : observation.id,
        dayEntryId: observation.dayEntryId,
        profileId: observation.profileId,
        localDate: observation.localDate.iso,
        observedAt: observation.observedAt,
        tz: observation.tz,
        category: observation.category,
        code: observation.code,
        valueNum: observation.valueNum,
        valueText: observation.valueText,
        unit: observation.unit,
        intensity: observation.intensity,
        excluded: observation.excluded,
        source: observation.source.toDb(),
        sourceId: observation.sourceId,
        importId: observation.importId,
        raw: observation.raw,
      ));

  @override
  Future<void> delete(String id) => _storage.softDeleteObservation(id);
}

/// A never-persisted `spotting` observation standing in for a legacy
/// `day_entries.flow = 'spotting'` row (Issue #247) — same shape
/// `DaySheet`'s own spotting write produces, keyed by [spottingAliasId] so
/// two calls in the same session (or the same row appearing via two list
/// reads) never disagree.
domain.Observation _spottingObservationFor(db.DayEntry entry) =>
    domain.Observation(
      id: spottingAliasId(entry.id),
      dayEntryId: entry.id,
      profileId: entry.profileId,
      localDate: domain.LocalDate.fromIso(entry.localDate),
      tz: entry.tz,
      category: 'spotting',
      code: 'spotting',
      updatedAt: entry.updatedAt,
    );

/// Review fix (blocking): the client-synthesised alias id now matches the
/// server backfill's own formula exactly
/// (`supabase/migrations/20260908200000_flow_model.sql`'s
/// `substr(upper(md5(day_entry_id || ':flow:spotting')), 1, 26)`) rather
/// than an arbitrary `'$dayEntryId-spotting-alias'` placeholder — so a
/// client that reads this synthesised row before the server backfill (or
/// a peer's sync) lands the real one sees the SAME id either way, never a
/// transient duplicate. The `':flow:spotting'` namespace segment is what
/// keeps this keyspace disjoint from `20260908160000_observations.sql`'s
/// own tag backfill (`md5(day_entry_id || ':' || tag)`) — a day entry
/// that is both `flow = 'spotting'` and carries a literal `'spotting'`
/// tag must still get two distinct observation rows, not one silently
/// dropped by the other's `on conflict (id) do nothing`. Uppercase hex is
/// entirely within the Crockford32 alphabet this schema's ULID CHECK
/// requires (digits plus A-F, a subset of the allowed A-H), so the result
/// is always a syntactically valid ULID.
String spottingAliasId(String dayEntryId) {
  final digest = md5.convert(utf8.encode('$dayEntryId:flow:spotting'));
  return digest.toString().toUpperCase().substring(0, 26);
}
