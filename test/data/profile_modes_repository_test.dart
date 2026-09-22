/// Issue #218: the drift-backed [ProfileModesRepository] — the onboarding
/// persistence seam for the birth-control-method and goal/mode answers
/// over #188's `profile_modes` storage (create-lazily, one row per
/// profile, absent row means `tracking`).
///
/// Issue #183: `save` also owns the birth-control effective dates the
/// adherence reminders anchor on — stamped with `today` when the method
/// changes to a tracked one, preserved when it does not (including the
/// dateless-tracked-method bootstrap stamp), cleared when the answer
/// becomes non-tracked.
///
/// Issue #551 problem 1 follow-up: this used to open a real drift database
/// solely to feed [DriftProfileModesRepository]. It now drives a
/// hand-written [FakeCycleStore], so the repository's own effective-date
/// rules and row→domain mapping are tested in isolation with no database.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import '../support/fakes/fake_cycle_store.dart';

void main() {
  late FakeCycleStore store;
  late DriftProfileModesRepository modes;

  setUp(() {
    store = FakeCycleStore();
    addTearDown(store.close);
    modes = DriftProfileModesRepository(
      store,
      todayProvider: () => LocalDate(2026, 9, 7),
    );
  });

  test('find on a profile with no row is null (the lazy tracking default)',
      () async {
    expect(await modes.find('p1'), isNull);
  });

  test('save creates the row lazily and find reads it back', () async {
    await modes.save(
      profileId: 'p1',
      mode: LifecycleMode.conceive,
      modeStartedOn: '2026-09-09',
      birthControlMethod: 'none',
    );
    final found = await modes.find('p1');
    expect(found, isNotNull);
    expect(found!.mode, LifecycleMode.conceive);
    expect(found.birthControlMethod, 'none');
  });

  test('save over an existing row updates it (one row per profile)',
      () async {
    await modes.save(
        profileId: 'p1',
        mode: LifecycleMode.tracking,
        modeStartedOn: null,
        estimatedDueDate: null,
        birthControlMethod: 'pill');
    await modes.save(
        profileId: 'p1',
        mode: LifecycleMode.perimenopause,
        modeStartedOn: null,
        estimatedDueDate: null,
        birthControlMethod: null);
    final found = await modes.find('p1');
    expect(found!.mode, LifecycleMode.perimenopause);
    expect(found.birthControlMethod, isNull,
        reason: 'a null answer clears the column on a full-row upsert');
    expect(await store.getProfileMode('p1'), isNotNull);
  });

  test('rows are per profile — a second profile still reads null', () async {
    await modes.save(profileId: 'a', mode: LifecycleMode.pregnancy);
    expect(await modes.find('b'), isNull);
    expect((await modes.find('a'))!.mode, LifecycleMode.pregnancy);
  });

  group('watch (issue #551)', () {
    test('emits null on listen for a profile with no row', () async {
      expect(await modes.watch('p1').first, isNull);
    });

    test('emits the current row on listen, then again on every save',
        () async {
      final events = <LifecycleMode?>[];
      final sub = modes.watch('p1').listen((row) => events.add(row?.mode));
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(events, [null]);

      await modes.save(profileId: 'p1', mode: LifecycleMode.conceive);
      await pumpEventQueue();
      expect(events, [null, LifecycleMode.conceive]);

      await modes.save(
          profileId: 'p1', mode: LifecycleMode.perimenopause);
      await pumpEventQueue();
      expect(events, [null, LifecycleMode.conceive, LifecycleMode.perimenopause]);
    });

    test(
        'scoped to one profile — another profile\'s save never leaks its '
        'value into this one\'s watch', () async {
      final events = <LifecycleMode?>[];
      final sub = modes.watch('a').listen((row) => events.add(row?.mode));
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await modes.save(profileId: 'b', mode: LifecycleMode.conceive);
      await pumpEventQueue();

      expect(events, everyElement(isNull),
          reason: 'profile b\'s save must never leak its value into a\'s watch');
    });
  });

  group('birth-control effective-date stamping (Issue #183)', () {
    test('a tracked method stamps started_on with today on first record',
        () async {
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'patch');
      final found = await modes.find('p1');
      expect(found!.birthControlStartedOn, '2026-09-07');
      expect(found.birthControlStoppedOn, isNull);
    });

    test('an unchanged method keeps its recorded start (no clock restart '
        'on an unrelated edit)', () async {
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'patch');
      // The first save stamped 2026-09-07; back-date it to simulate an
      // older anchor, then re-save the same answer.
      await store.upsertProfileMode(
        profileId: 'p1',
        mode: 'tracking',
        birthControlMethod: 'patch',
        birthControlStartedOn: '2026-08-01',
      );
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'patch');
      final found = await modes.find('p1');
      expect(found!.birthControlStartedOn, '2026-08-01',
          reason: 'an unrelated save never restarts the cadence anchor');
    });

    test('a legacy spelling comparing equal does not restart the clock',
        () async {
      await store.upsertProfileMode(
        profileId: 'p1',
        mode: 'tracking',
        birthControlMethod: 'injection',
        birthControlStartedOn: '2026-06-01',
      );
      // `injection` is the pre-#260 id of the shot: same method, so the
      // anchor survives.
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'shot');
      final found = await modes.find('p1');
      expect(found!.birthControlStartedOn, '2026-06-01');
      expect(found.birthControlMethod, 'shot');
    });

    test('a dateless tracked method bootstraps an anchor on its next save',
        () async {
      // A pre-#183 row: a method recorded before anchoring existed.
      await store.upsertProfileMode(
        profileId: 'p1',
        mode: 'tracking',
        birthControlMethod: 'ring',
      );
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'ring');
      final found = await modes.find('p1');
      expect(found!.birthControlStartedOn, '2026-09-07',
          reason: 'without a stamp the ring cadence could never arm');
    });

    test('switching to a non-tracked answer clears both dates', () async {
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'shot');
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'none');
      final found = await modes.find('p1');
      expect(found!.birthControlMethod, 'none');
      expect(found.birthControlStartedOn, isNull);
      expect(found.birthControlStoppedOn, isNull);
    });

    test('switching between tracked methods moves the anchor to today',
        () async {
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'patch');
      await modes.save(
          profileId: 'p1',
          mode: LifecycleMode.tracking,
          modeStartedOn: null,
          estimatedDueDate: null,
          birthControlMethod: 'ring');
      final found = await modes.find('p1');
      expect(found!.birthControlMethod, 'ring');
      expect(found.birthControlStartedOn, '2026-09-07',
          reason: 'the ring is in effect from today; that is the new '
              'cadence anchor');
      expect(found.birthControlStoppedOn, isNull);
    });
  });
}
