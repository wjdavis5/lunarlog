/// Issue #568 (b): the drift-backed [CycleOverridesRepository] — the
/// narrow "excluded from average" seam [CycleExclusionList] reads and
/// writes through over Issue #188's `cycle_overrides` storage, instead of
/// the pre-#568 device-local settings list.
///
/// Issue #551 problem 1 follow-up: this used to open a real drift database
/// solely to feed [DriftCycleOverridesRepository]. It now drives a
/// hand-written [FakeCycleStore], so the repository's own
/// create/withdraw/preserve rules and excluded-set shaping are tested in
/// isolation with no database.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';

import '../../support/fakes/fake_cycle_store.dart';

void main() {
  late FakeCycleStore store;
  late DriftCycleOverridesRepository overrides;
  const profileId = 'p1';

  setUp(() {
    store = FakeCycleStore();
    addTearDown(store.close);
    overrides = DriftCycleOverridesRepository(store);
  });

  test('excludedCycleStarts is empty when no overrides exist', () async {
    expect(await overrides.excludedCycleStarts(profileId), isEmpty);
  });

  test('setExcludedFromAverage(true) creates a fresh override when none '
      'exists for that date', () async {
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: true,
    );
    expect(
        await overrides.excludedCycleStarts(profileId), {'2026-01-01'});
    final stored =
        (await store.getCycleOverridesForProfile(profileId)).single;
    expect(stored.manualStart, isFalse);
    expect(stored.noteId, isNull);
  });

  test('setExcludedFromAverage(false) on a date never excluded is a '
      'harmless no-op — no row is created', () async {
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: false,
    );
    expect(await store.getCycleOverridesForProfile(profileId), isEmpty);
  });

  test('setExcludedFromAverage(false) withdraws an override that exists '
      'only to carry the exclusion (a tombstone, not an empty husk row)',
      () async {
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: true,
    );
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: false,
    );
    expect(await overrides.excludedCycleStarts(profileId), isEmpty);
    expect(await store.getCycleOverridesForProfile(profileId), isEmpty);
    final tombstoned = (await store.getCycleOverridesForProfile(
            profileId,
            includeTombstones: true))
        .single;
    expect(tombstoned.deletedAt, isNotNull);
  });

  test('setExcludedFromAverage never clobbers an existing manualStart or '
      'noteId it was not asked to change', () async {
    await store.upsertCycleOverride(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      manualStart: true,
      noteId: 'note-1',
    );

    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: true,
    );
    var stored =
        (await store.getCycleOverridesForProfile(profileId)).single;
    expect(stored.manualStart, isTrue);
    expect(stored.noteId, 'note-1');
    expect(stored.excludedFromAverage, isTrue);

    // Un-excluding must keep the row alive — manualStart/noteId still make
    // it meaningful — not withdraw it like the carries-only-the-exclusion
    // case above.
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: false,
    );
    stored =
        (await store.getCycleOverridesForProfile(profileId)).single;
    expect(stored.excludedFromAverage, isFalse);
    expect(stored.manualStart, isTrue);
    expect(stored.noteId, 'note-1');
  });

  test('watchExcludedCycleStarts emits the current set and again on every '
      'change', () async {
    final seen = <Set<String>>[];
    final sub = overrides.watchExcludedCycleStarts(profileId).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await overrides.setExcludedFromAverage(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excluded: true,
    );
    await pumpEventQueue();
    expect(seen, [
      isEmpty,
      {'2026-01-01'},
    ]);
  });

  test('excludedCycleStarts only counts live overrides — a tombstoned one '
      'is excluded from the set', () async {
    final created = await store.upsertCycleOverride(
      profileId: profileId,
      cycleStartDate: '2026-01-01',
      excludedFromAverage: true,
    );
    await store
        .softDeleteCycleOverride(id: created.id, profileId: profileId);
    expect(await overrides.excludedCycleStarts(profileId), isEmpty);
  });

  group('listForProfile (Issue #140 review, LLA-084)', () {
    test('returns every live override with full fidelity — id, '
        'manualStart, noteId included, not just the excluded flag',
        () async {
      final created = await store.upsertCycleOverride(
        profileId: profileId,
        cycleStartDate: '2026-01-01',
        excludedFromAverage: true,
        manualStart: true,
        noteId: 'note-1',
      );

      final result = await overrides.listForProfile(profileId);
      expect(result, hasLength(1));
      expect(result.single.id, created.id);
      expect(result.single.profileId, profileId);
      expect(result.single.cycleStartDate, '2026-01-01');
      expect(result.single.excludedFromAverage, isTrue);
      expect(result.single.manualStart, isTrue);
      expect(result.single.noteId, 'note-1');
    });

    test('excludes a tombstoned override', () async {
      final created = await store.upsertCycleOverride(
        profileId: profileId,
        cycleStartDate: '2026-01-01',
      );
      await store
          .softDeleteCycleOverride(id: created.id, profileId: profileId);
      expect(await overrides.listForProfile(profileId), isEmpty);
    });

    test('is empty for a profile with no overrides', () async {
      expect(await overrides.listForProfile(profileId), isEmpty);
    });
  });
}
