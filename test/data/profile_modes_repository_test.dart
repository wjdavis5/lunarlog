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
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftProfileModesRepository modes;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    modes = DriftProfileModesRepository(
      db.storage,
      todayProvider: () => LocalDate(2026, 9, 7),
    );
  });

  test('find on a profile with no row is null (the lazy tracking default)',
      () async {
    final profile =
        await db.storage.upsertProfile(displayName: 'A', isMinor: false);
    expect(await modes.find(profile.id), isNull);
  });

  test('save creates the row lazily and find reads it back', () async {
    final profile =
        await db.storage.upsertProfile(displayName: 'A', isMinor: false);
    await modes.save(
      profileId: profile.id,
      mode: LifecycleMode.conceive,
      modeStartedOn: '2026-09-09',
      birthControlMethod: 'none',
    );
    final found = await modes.find(profile.id);
    expect(found, isNotNull);
    expect(found!.mode, LifecycleMode.conceive);
    expect(found.birthControlMethod, 'none');
  });

  test('save over an existing row updates it (one row per profile)',
      () async {
    final profile =
        await db.storage.upsertProfile(displayName: 'A', isMinor: false);
    await modes.save(
        profileId: profile.id,
        mode: LifecycleMode.tracking,
        birthControlMethod: 'pill');
    await modes.save(
        profileId: profile.id,
        mode: LifecycleMode.perimenopause,
        birthControlMethod: null);
    final found = await modes.find(profile.id);
    expect(found!.mode, LifecycleMode.perimenopause);
    expect(found.birthControlMethod, isNull,
        reason: 'a null answer clears the column on a full-row upsert');
    expect(await db.storage.getProfileMode(profile.id), isNotNull);
  });

  test('rows are per profile — a second profile still reads null',
      () async {
    final a = await db.storage.upsertProfile(displayName: 'A', isMinor: false);
    final b = await db.storage.upsertProfile(displayName: 'B', isMinor: false);
    await modes.save(profileId: a.id, mode: LifecycleMode.pregnancy);
    expect(await modes.find(b.id), isNull);
    expect((await modes.find(a.id))!.mode, LifecycleMode.pregnancy);
  });

  group('birth-control effective-date stamping (Issue #183)', () {
    test('a tracked method stamps started_on with today on first record',
        () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'patch');
      final found = await modes.find(profile.id);
      expect(found!.birthControlStartedOn, '2026-09-07');
      expect(found.birthControlStoppedOn, isNull);
    });

    test('an unchanged method keeps its recorded start (no clock restart '
        'on an unrelated edit)', () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'patch');
      // The first save stamped 2026-09-07; back-date it to simulate an
      // older anchor, then re-save the same answer.
      await db.storage.upsertProfileMode(
        profileId: profile.id,
        mode: 'tracking',
        birthControlMethod: 'patch',
        birthControlStartedOn: '2026-08-01',
      );
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'patch');
      final found = await modes.find(profile.id);
      expect(found!.birthControlStartedOn, '2026-08-01',
          reason: 'an unrelated save never restarts the cadence anchor');
    });

    test('a legacy spelling comparing equal does not restart the clock',
        () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      await db.storage.upsertProfileMode(
        profileId: profile.id,
        mode: 'tracking',
        birthControlMethod: 'injection',
        birthControlStartedOn: '2026-06-01',
      );
      // `injection` is the pre-#260 id of the shot: same method, so the
      // anchor survives.
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'shot');
      final found = await modes.find(profile.id);
      expect(found!.birthControlStartedOn, '2026-06-01');
      expect(found.birthControlMethod, 'shot');
    });

    test('a dateless tracked method bootstraps an anchor on its next save',
        () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      // A pre-#183 row: a method recorded before anchoring existed.
      await db.storage.upsertProfileMode(
        profileId: profile.id,
        mode: 'tracking',
        birthControlMethod: 'ring',
      );
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'ring');
      final found = await modes.find(profile.id);
      expect(found!.birthControlStartedOn, '2026-09-07',
          reason: 'without a stamp the ring cadence could never arm');
    });

    test('switching to a non-tracked answer clears both dates', () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'shot');
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'none');
      final found = await modes.find(profile.id);
      expect(found!.birthControlMethod, 'none');
      expect(found.birthControlStartedOn, isNull);
      expect(found.birthControlStoppedOn, isNull);
    });

    test('switching between tracked methods moves the anchor to today',
        () async {
      final profile =
          await db.storage.upsertProfile(displayName: 'A', isMinor: false);
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'patch');
      await modes.save(
          profileId: profile.id,
          mode: LifecycleMode.tracking,
          birthControlMethod: 'ring');
      final found = await modes.find(profile.id);
      expect(found!.birthControlMethod, 'ring');
      expect(found.birthControlStartedOn, '2026-09-07',
          reason: 'the ring is in effect from today; that is the new '
              'cadence anchor');
      expect(found.birthControlStoppedOn, isNull);
    });
  });
}
