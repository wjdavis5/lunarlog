/// The device's memory that a purge of a store's imported data owes a
/// whole-history read (Issue #1876), against a real database: what is
/// remembered, what reads back, and what clears it.
///
/// The rule being pinned: "Remove imported data" leaves the store a clean
/// slate, and an anchored or changes read never returns a record that did
/// not change — so the next import pass must read the whole history. The
/// memory is set in the purge's own transaction and goes when a whole
/// read settles it or the profile is wiped from this device.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 9, 1, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    storage = LunarLogStorage(db, clock: () => t0);
    for (final id in ['p1', 'p10']) {
      await storage.upsertProfile(
        id: id,
        displayName: 'Riley',
        isMinor: true,
        updatedAt: t0,
      );
    }
  });

  test('nothing is owed until it is remembered, and forgetting clears it',
      () async {
    expect(await storage.wholeReadOwed('p1'), isFalse);

    await storage.rememberWholeReadOwed('p1');
    expect(await storage.wholeReadOwed('p1'), isTrue);
    // Another profile's memory is its own, and `p1` is not a prefix of
    // `p10` as far as the keys go.
    expect(await storage.wholeReadOwed('p10'), isFalse);

    await storage.forgetWholeReadOwed('p1');
    expect(await storage.wholeReadOwed('p1'), isFalse);
  });

  test('removing a store\'s imported data owes a whole read for the '
      'profile', () async {
    await storage.applyLocalImportedDataPurge(
      profileId: 'p1',
      source: 'healthkit',
    );

    expect(await storage.wholeReadOwed('p1'), isTrue);
    expect(await storage.wholeReadOwed('p10'), isFalse);
  });

  test('a profile wiped from this device takes the obligation with it, '
      'and leaves another profile\'s alone', () async {
    await storage.rememberWholeReadOwed('p1');
    await storage.rememberWholeReadOwed('p10');

    await storage.applyLocalProfilePurge('p1');

    expect(await storage.wholeReadOwed('p1'), isFalse);
    expect(await storage.wholeReadOwed('p10'), isTrue);
  });
}
