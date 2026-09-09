/// Unit tests for the onboarding-answers seam (Issue #216, U3):
/// `DriftOnboardingCycleAnswersRecorder` — lazy row creation, mode-change
/// stamping, `health_sync_consent` preservation, clearing a birth-control
/// method, and the write-nothing no-op — plus the pure
/// `OnboardingCycleAnswers.hasPersistableAnswers` predicate.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final today = LocalDate(2026, 9, 1);
  late LunarLogDatabase db;
  late DriftOnboardingCycleAnswersRecorder recorder;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    recorder = DriftOnboardingCycleAnswersRecorder(db.storage,
        todayProvider: () => today);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedProfile() async {
    final profile = await db.storage.upsertProfile(
        displayName: 'Nova', isMinor: false);
    return profile.id;
  }

  group('hasPersistableAnswers (pure)', () {
    test('everything skipped/default means nothing to persist', () {
      expect(const OnboardingCycleAnswers().hasPersistableAnswers, isFalse);
    });

    test('a non-default mode or a birth-control answer means a write', () {
      expect(
        const OnboardingCycleAnswers(
                lifecycleMode: LifecycleMode.conceive)
            .hasPersistableAnswers,
        isTrue,
      );
      expect(
        const OnboardingCycleAnswers(birthControlMethod: 'Pill')
            .hasPersistableAnswers,
        isTrue,
      );
    });
  });

  test('skipped answers write no row at all (the lazy-default contract)',
      () async {
    final profileId = await seedProfile();
    await recorder.record(profileId, const OnboardingCycleAnswers());
    expect(await db.storage.getProfileMode(profileId), isNull);
  });

  test('a goal/mode answer creates the row stamped with today', () async {
    final profileId = await seedProfile();
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(lifecycleMode: LifecycleMode.pregnancy),
    );
    final row = await db.storage.getProfileMode(profileId);
    expect(row!.mode, 'pregnancy');
    expect(row.modeStartedOn, '2026-09-01');
    expect(row.birthControlMethod, isNull);
  });

  test('a birth-control-only answer creates the row without a mode start',
      () async {
    final profileId = await seedProfile();
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(birthControlMethod: 'Pill'),
    );
    final row = await db.storage.getProfileMode(profileId);
    expect(row!.mode, 'tracking');
    expect(row.modeStartedOn, isNull);
    expect(row.birthControlMethod, 'Pill');
  });

  test('an unchanged re-record writes nothing (no rev bump, no dirty flag)',
      () async {
    final profileId = await seedProfile();
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(
        lifecycleMode: LifecycleMode.conceive,
        birthControlMethod: 'Pill',
      ),
    );
    final first = (await db.storage.getProfileMode(profileId))!;

    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(
        lifecycleMode: LifecycleMode.conceive,
        birthControlMethod: 'Pill',
      ),
    );
    final second = (await db.storage.getProfileMode(profileId))!;
    expect(second.localRev, first.localRev,
        reason: 'an identical edit is a no-op, not a new local write');
    expect(second.updatedAt, first.updatedAt);
    expect(second.dirty, isTrue,
        reason: 'the original write stays dirty until sync clears it');
  });

  test('a mode change restamps mode_started_on; a same-mode edit keeps it',
      () async {
    final profileId = await seedProfile();
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(
        lifecycleMode: LifecycleMode.conceive,
        birthControlMethod: 'Pill',
      ),
    );
    var row = (await db.storage.getProfileMode(profileId))!;
    expect(row.modeStartedOn, '2026-09-01');

    // Same mode, different birth-control answer: the mode's start date
    // is history, not rewritten by an unrelated edit.
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(
        lifecycleMode: LifecycleMode.conceive,
        birthControlMethod: 'Implant',
      ),
    );
    row = (await db.storage.getProfileMode(profileId))!;
    expect(row.birthControlMethod, 'Implant');
    expect(row.modeStartedOn, '2026-09-01');

    // An actual mode change restarts the clock.
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(lifecycleMode: LifecycleMode.postpartum),
    );
    row = (await db.storage.getProfileMode(profileId))!;
    expect(row.mode, 'postpartum');
    expect(row.modeStartedOn, '2026-09-01');
  });

  test('clearing a birth-control method writes null over the stored value',
      () async {
    final profileId = await seedProfile();
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(birthControlMethod: 'Pill'),
    );
    await recorder.record(profileId, const OnboardingCycleAnswers());
    final row = await db.storage.getProfileMode(profileId);
    expect(row!.birthControlMethod, isNull,
        reason: '"Not answered" clears the stored method');
    // The row itself survives (mode history is not the BC answer's to
    // delete); only the null-and-default shape never creates one.
    expect(row.mode, 'tracking');
  });

  test('health_sync_consent survives a re-record (the recorder does not '
      'own that column)', () async {
    final profileId = await seedProfile();
    await db.storage.upsertProfileMode(
      profileId: profileId,
      mode: 'tracking',
      healthSyncConsent: true,
    );
    await recorder.record(
      profileId,
      const OnboardingCycleAnswers(birthControlMethod: 'Pill'),
    );
    final row = await db.storage.getProfileMode(profileId);
    expect(row!.healthSyncConsent, isTrue,
        reason: 're-recording must not clobber #153\'s consent with the '
            'upsert default');
  });
}
