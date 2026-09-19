/// Issue #848: restore/import drops (and reports) day entries whose date is
/// out of bounds — more than a day in the future, or before the profile's
/// known birth year — rather than writing them. `planImport` is what counts
/// them, and `ImportPlanSummary.entryDatesRejected` is what reports them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart' as domain;

final _today = LocalDate(2026, 9, 19);

const _p1 = '01ARZ3NDEKTSV4RRFFQ69G5FAV';

ImportedDayEntry _entry(String id, String iso) => ImportedDayEntry(
      id: id,
      localDate: LocalDate.fromIso(iso),
      tz: 'UTC',
      flow: FlowLevel.light,
      updatedAt: DateTime.utc(2026, 1, 2),
      source: 'manual',
    );

ImportedObservation _observation(String id, String iso) => ImportedObservation(
      id: id,
      localDate: LocalDate.fromIso(iso),
      tz: 'UTC',
      category: 'pain',
    );

AccountImportDocument _document(ImportedProfile profile) =>
    AccountImportDocument(schemaVersion: 1, profiles: [profile]);

String? _neverBlocked(domain.Profile _) => null;

void main() {
  test('a future-dated and a pre-birth-year entry are dropped and counted',
      () {
    final profile = ImportedProfile(
      id: _p1,
      displayName: 'Riley',
      birthYear: 2015,
      dayEntries: [
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA1', '2026-09-15'), // valid
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA2', '2026-09-20'), // today + 1
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA3', '2026-12-31'), // future
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA4', '2010-06-01'), // pre-birth
      ],
    );

    final plan = planImport(
      document: _document(profile),
      existingProfiles: const [],
      writeBlockReason: _neverBlocked,
      today: _today,
    );

    final profilePlan = plan.profiles.single;
    expect(profilePlan.entryDatesRejected, 2);
    expect(profilePlan.entries, hasLength(2));
    expect(
      profilePlan.entries.map((e) => e.localDate.iso),
      containsAll(<String>['2026-09-15', '2026-09-20']),
    );
    expect(plan.summary.entryDatesRejected, 2);
    expect(plan.summary.entriesAdded, 2);
  });

  test('a profile with no birth year keeps every in-bounds old date', () {
    final profile = ImportedProfile(
      id: _p1,
      displayName: 'Riley',
      dayEntries: [
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA1', '2010-06-01'),
      ],
    );

    final plan = planImport(
      document: _document(profile),
      existingProfiles: const [],
      writeBlockReason: _neverBlocked,
      today: _today,
    );

    expect(plan.profiles.single.entryDatesRejected, 0);
    expect(plan.profiles.single.entries, hasLength(1));
  });

  test('a matched profile bounds against its STORED birth year', () {
    final profile = ImportedProfile(
      id: _p1,
      displayName: 'Riley',
      // The file omits birthYear, but the stored profile has one.
      dayEntries: [
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA1', '2010-06-01'),
      ],
    );
    final existing = domain.Profile(
      id: _p1,
      displayName: 'Riley',
      isMinor: true,
      birthYear: 2015,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final plan = planImport(
      document: _document(profile),
      existingProfiles: [existing],
      writeBlockReason: _neverBlocked,
      today: _today,
    );

    expect(plan.profiles.single.entryDatesRejected, 1);
    expect(plan.profiles.single.entries, isEmpty);
  });

  test('an observation on a rejected date is skipped, not added', () {
    final profile = ImportedProfile(
      id: _p1,
      displayName: 'Riley',
      dayEntries: [
        _entry('01ARZ3NDEKTSV4RRFFQ69G5FA1', '2026-12-31'), // future, dropped
      ],
      observations: [
        _observation('01ARZ3NDEKTSV4RRFFQ69G5FB1', '2026-12-31'),
      ],
    );

    final plan = planImport(
      document: _document(profile),
      existingProfiles: const [],
      writeBlockReason: _neverBlocked,
      today: _today,
    );

    expect(plan.summary.entryDatesRejected, 1);
    expect(plan.profiles.single.entries, isEmpty);
    expect(plan.summary.observationsAdded, 0);
    expect(plan.summary.observationsSkipped, 1);
  });
}
