/// Issue #218: the drift-backed [ProfileModesRepository] — the onboarding
/// persistence seam for the birth-control-method and goal/mode answers
/// over #188's `profile_modes` storage (create-lazily, one row per
/// profile, absent row means `tracking`).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftProfileModesRepository modes;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    modes = DriftProfileModesRepository(db.storage);
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
}
