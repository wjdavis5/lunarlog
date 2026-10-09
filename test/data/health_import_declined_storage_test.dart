/// The device's memory of health-store records the import declined (Issue
/// #1652), against a real database: what is remembered, what reads back,
/// and what clears it.
///
/// The rule being pinned: the import remembers a record the merge declined
/// over her own value, the same memory beside the deletion one, and it goes
/// when a merge settles it, the store reports it deleted, or a purge of the
/// store's imported data clears it.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/health/health_import_declined.dart';
import 'package:lunarlog/domain/models/local_date.dart';

class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late _Clock clock;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 9, 1, 8);
  final flowDate = LocalDate(2026, 8, 1);
  final spotDate = LocalDate(2026, 8, 2);
  const flowKey = 'healthkit|rec-1';
  const spotKey = 'apple_health|spot-1';

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = _Clock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    for (final id in ['p1', 'p10']) {
      await storage.upsertProfile(
        id: id,
        displayName: 'Riley',
        isMinor: true,
        updatedAt: t0,
      );
    }
  });

  Future<Map<String, HealthImportDeclinedRecord>> remembered([
    String profileId = 'p1',
  ]) => storage.readDeclinedHealthRecords(profileId);

  Future<void> rememberFlow({
    String profileId = 'p1',
    String recordId = 'rec-1',
    LocalDate? date,
  }) => storage.rememberDeclinedHealthRecord(
    profileId,
    source: 'healthkit',
    recordId: recordId,
    kind: HealthImportDeclinedKind.flow,
    date: date ?? flowDate,
  );

  Future<void> rememberSpotting({String profileId = 'p1'}) =>
      storage.rememberDeclinedHealthRecord(
        profileId,
        source: 'apple_health',
        recordId: 'spot-1',
        kind: HealthImportDeclinedKind.spotting,
        date: spotDate,
      );

  test('a declined record round-trips: its source, kind, and date', () async {
    await rememberFlow();
    await rememberSpotting();

    final rows = await remembered();
    expect(rows.keys, unorderedEquals([flowKey, spotKey]));
    final flow = rows[flowKey]!;
    expect(flow.kind, HealthImportDeclinedKind.flow);
    expect(flow.date, flowDate);
    expect(flow.source, 'healthkit');
    expect(flow.recordId, 'rec-1');
    expect(rows[spotKey]!.kind, HealthImportDeclinedKind.spotting);
    expect(rows[spotKey]!.date, spotDate);

    // Another profile's memory is its own, and `p1` is not a prefix of
    // `p10` as far as the keys go.
    expect(await remembered('p10'), isEmpty);
  });

  test('remembering the same record again refreshes its date', () async {
    await rememberFlow();
    clock.now = DateTime.utc(2026, 9, 5, 8);
    await rememberFlow(date: LocalDate(2026, 8, 3));

    final rows = await remembered();
    expect(rows, hasLength(1));
    expect(rows[flowKey]!.date, LocalDate(2026, 8, 3));
  });

  test('forgetting removes only the named records', () async {
    await rememberFlow();
    await rememberSpotting();

    await storage.forgetDeclinedHealthRecords('p1', {flowKey});
    expect((await remembered()).keys, [spotKey]);

    await storage.forgetDeclinedHealthRecords('p1', const {});
    expect((await remembered()).keys, [spotKey]);
  });

  test('a value this build cannot read is skipped, not guessed', () async {
    await storage.setSetting(
      key: 'health_import_declined_p1|healthkit|rec-9',
      value: 'warp|2026-08-01',
    );
    await storage.setSetting(
      key: 'health_import_declined_p1|healthkit|rec-8',
      value: 'flow|not-a-date',
    );

    expect(await remembered(), isEmpty);
  });

  // Removing a store's imported data is a clean slate for that store (the
  // deletion memory's rule, mirrored). On an iPhone the days carry
  // `healthkit` and the entries on them `apple_health`: removing the days
  // clears both, removing the measurements clears only their own.
  for (final (named, remaining) in [
    ('healthkit', <String>[]),
    ('apple_health', [flowKey]),
  ]) {
    test('removing Apple Health\'s imported data, named as $named, forgets '
        'the declined records of that store and nothing else', () async {
      await rememberFlow();
      await rememberSpotting();

      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: named,
      );

      expect((await remembered()).keys, unorderedEquals(remaining));
    });
  }

  test('a profile wiped from this device takes its memory with it, and '
      'leaves another profile\'s alone', () async {
    await rememberFlow();
    await rememberFlow(profileId: 'p10', recordId: 'rec-7');

    await storage.applyLocalProfilePurge('p1');

    expect(await remembered(), isEmpty);
    expect((await remembered('p10')).keys, ['healthkit|rec-7']);
  });
}
