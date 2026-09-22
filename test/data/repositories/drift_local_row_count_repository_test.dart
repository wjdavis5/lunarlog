/// Issue #551 (part 3): [DriftLocalRowCountRepository] — the repository
/// seam over `LunarLogStorage.countAllRows`, so `lib/app.dart` provides the
/// upload-consent `LocalRowCounter` without reaching past `AppDependencies`
/// into the raw storage object.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/tables.dart' show FlowLevel;
import 'package:lunarlog/data/repositories/drift_local_row_count_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftLocalRowCountRepository repository;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repository = DriftLocalRowCountRepository(db.storage);
  });

  test('an empty device reports zero rows for both synced tables', () async {
    expect(await repository.countAllRows(), (profiles: 0, dayEntries: 0));
  });

  test('counts profiles and day entries separately, tombstones included',
      () async {
    final first = await db.storage.upsertProfile(
      displayName: 'Alice',
      isMinor: false,
    );
    await db.storage.upsertProfile(displayName: 'Bob', isMinor: false);
    await db.storage.upsertDayEntry(
      profileId: first.id,
      localDate: '2026-01-01',
      tz: 'UTC',
      flow: FlowLevel.light,
    );

    expect(await repository.countAllRows(), (profiles: 2, dayEntries: 1));
  });
}
