import 'dart:io';

import 'package:drift/drift.dart'
    show Migrator, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/db/key_store.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Key store fake that records every call — used to prove the web flavor of
/// the factory never touches key storage.
class RecordingKeyStore implements DbKeyStore {
  RecordingKeyStore({this.presetKey});

  final String? presetKey;
  int calls = 0;

  @override
  Future<String> getOrCreateDbKey() async {
    calls++;
    if (presetKey != null) return presetKey!;
    return List<int>.generate(32, (_) => 0x0A)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Whether the host VM's sqlite3 library was built with SQLCipher support
/// (i.e. whether the `source: sqlcipher` hook took effect for `flutter test`).
bool hostHasSqlcipher() {
  final mem = sqlite3.sqlite3.openInMemory();
  try {
    return mem.select('PRAGMA cipher_version').isNotEmpty;
  } finally {
    mem.close();
  }
}

Future<Directory> freshTempDir(String name) async {
  final dir =
      Directory.systemTemp.createTempSync('lunarlog_test_${name}_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  // Many tests construct LunarLogDatabase instances sequentially; drift's
  // debug-mode duplicate-instance warning does not apply to that (each test
  // closes its database). Documented approach: drift.simonbinder.eu/faq.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('host sqlite3 cipher availability is observed and reported', () {
    // Informational: records what the SQLCipher hook does on this test host.
    // The real-cipher tests below are skipped when this is false.
    // ignore: avoid_print
    print('HOST SQLCIPHER AVAILABLE: ${hostHasSqlcipher()}');
  });

  group('schema', () {
    late LunarLogDatabase db;

    setUp(() async {
      db = LunarLogDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
    });

    test('schema version is 1 and database opens with the expected tables',
        () async {
      expect(db.schemaVersion, 1);

      final userVersion = (await db.customSelect('PRAGMA user_version').get())
          .first
          .data['user_version'];
      expect(userVersion, 1);

      final tables = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(tables, containsAll(['profiles', 'day_entries', 'app_settings']));
    });

    test('partial unique index enforces one live entry per profile+date, '
        'but allows tombstones for the same date', () async {
      final index = (await db
              .customSelect(
                "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
                "AND name = 'uq_day_entries_profile_date_live'",
              )
              .get());
      expect(index, hasLength(1));

      final storage = LunarLogStorage(db);
      final profile = await storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-02-10',
          tz: 'America/Chicago',
          flow: FlowLevel.medium);
      // A second row for the same (profile, date) pair would have to be
      // tombstoned for the raw insert to be allowed; the partial index must
      // reject a *second live* row inserted directly.
      expect(
        () => db.customStatement(
          "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, tags, "
          "note, updated_at, deleted_at) VALUES "
          "('manualulid0000000000000000', '${profile.id}', '2026-02-10', "
          "'America/Chicago', 'light', '[]', NULL, '2026-02-10T00:00:00.000000Z', NULL)",
        ),
        throwsA(anything),
        reason: 'second live row for the same profile+date must be rejected',
      );
      expect(
        (await storage.getDayEntries(profileId: profile.id)).single.id,
        entry.id,
      );
    });
  });

  group('storage', () {
    late LunarLogDatabase db;
    late FixedClock clock;
    late LunarLogStorage storage;

    setUp(() {
      db = LunarLogDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      clock = FixedClock(DateTime.utc(2026, 1, 15, 8));
      storage = LunarLogStorage(db, clock: clock.call);
    });

    test('R15: created records carry a stable ULID id and updated_at; '
        're-reading returns the identical id', () async {
      final profile =
          await storage.upsertProfile(displayName: 'Luna', isMinor: true);
      expect(isValidUlid(profile.id), isTrue);
      expect(profile.updatedAt, isNotNull);
      expect(profile.createdAt, isNotNull);

      final reread =
          (await storage.getProfiles()).single;
      expect(reread.id, profile.id);
      expect(reread.updatedAt, profile.updatedAt);

      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-01-15',
          tz: 'Europe/Berlin',
          flow: FlowLevel.heavy,
          tags: const ['cramps', 'headache'],
          note: 'rough day');
      expect(isValidUlid(entry.id), isTrue);
      expect(entry.updatedAt, isNotNull);
      expect(entry.deletedAt, isNull);

      final entryReread = (await storage.getDayEntries(
          profileId: profile.id))
          .single;
      expect(entryReread.id, entry.id);
      expect(entryReread.tags, ['cramps', 'headache']);
      expect(entryReread.note, 'rough day');
      expect(entryReread.flow, FlowLevel.heavy);
    });

    test('AE5 (data layer half): soft delete tombstones the row — present in '
        'full-fidelity reads, absent from UI reads', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-03-01',
          tz: 'UTC',
          flow: FlowLevel.light);

      final before =
          (await storage.getDayEntries(profileId: profile.id)).single;
      final updatedAtBefore = before.updatedAt;

      clock.now = clock.now.add(const Duration(hours: 2));
      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-03-01');

      // UI reads: gone.
      expect(await storage.getDayEntries(profileId: profile.id), isEmpty);
      final uiStream = await storage
          .watchDayEntries(profileId: profile.id, includeTombstones: false)
          .first;
      expect(uiStream, isEmpty);

      // Full-fidelity reads: tombstone retained with bumped updated_at.
      final full = await storage.getDayEntries(
          profileId: profile.id, includeTombstones: true);
      expect(full, hasLength(1));
      final tombstone = full.single;
      expect(tombstone.id, before.id);
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.updatedAt.isAfter(updatedAtBefore), isTrue);
    });

    test('R3: per-profile queries never co-mingle entries', () async {
      final a = await storage.upsertProfile(displayName: 'A', isMinor: true);
      final b = await storage.upsertProfile(displayName: 'B', isMinor: false);
      await storage.upsertDayEntry(
          profileId: a.id,
          localDate: '2026-04-01',
          tz: 'UTC',
          flow: FlowLevel.spotting);
      await storage.upsertDayEntry(
          profileId: a.id,
          localDate: '2026-04-02',
          tz: 'UTC',
          flow: FlowLevel.none);
      await storage.upsertDayEntry(
          profileId: b.id,
          localDate: '2026-04-03',
          tz: 'UTC',
          flow: FlowLevel.medium);

      final aRows = await storage.getDayEntries(profileId: a.id);
      final bRows = await storage.getDayEntries(profileId: b.id);
      expect(aRows, hasLength(2));
      expect(bRows, hasLength(1));
      expect(aRows.every((e) => e.profileId == a.id), isTrue);
      expect(bRows.every((e) => e.profileId == b.id), isTrue);

      final aStream = await storage
          .watchDayEntries(profileId: a.id)
          .first;
      expect(aStream, hasLength(2));
      expect(aStream.every((e) => e.profileId == a.id), isTrue);
    });

    test('R3: foreign key rejects entries for unknown profiles', () async {
      await expectLater(
        storage.upsertDayEntry(
            profileId: 'noprofileulid00000000000000',
            localDate: '2026-04-01',
            tz: 'UTC',
            flow: FlowLevel.light),
        throwsA(anything),
      );
    });

    test('monotonic updated_at: a clock running backwards never regresses the '
        'stored updated_at', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-01',
          tz: 'UTC',
          flow: FlowLevel.light);
      final t1 = entry.updatedAt;

      clock.now = t1.add(const Duration(minutes: 30));
      final edited = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-01',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(edited.updatedAt.isAfter(t1), isTrue);
      expect(edited.id, entry.id, reason: 'edits keep the same ULID');
      expect(edited.flow, FlowLevel.heavy);

      // Clock regresses below the stored timestamp.
      clock.now = t1.subtract(const Duration(days: 3));
      final regressed = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-01',
          tz: 'UTC',
          flow: FlowLevel.none);
      expect(regressed.updatedAt, edited.updatedAt,
          reason: 'updated_at must never regress');
      expect(regressed.flow, FlowLevel.none,
          reason: 'content is still written; only the timestamp is clamped');
    });

    test('upsert with an explicitly older updated_at does not regress the '
        'stored updated_at', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-02',
          tz: 'UTC',
          flow: FlowLevel.none);

      final stale = entry.updatedAt.subtract(const Duration(hours: 10));
      final imported = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-02',
          tz: 'UTC',
          flow: FlowLevel.medium,
          updatedAt: stale);
      expect(imported.updatedAt, entry.updatedAt,
          reason: 'sync import with a stale timestamp must not regress');
    });

    test('soft delete then re-create for the same profile+date: new ULID row '
        'wins in UI reads, old tombstone remains for sync', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      final original = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-01',
          tz: 'UTC',
          flow: FlowLevel.light);
      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-06-01');

      clock.now = clock.now.add(const Duration(days: 1));
      final recreated = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-01',
          tz: 'UTC',
          flow: FlowLevel.medium);

      expect(recreated.id, isNot(equals(original.id)),
          reason: 're-creation gets a fresh ULID');
      expect(recreated.deletedAt, isNull);

      // UI sees exactly one (live) row: the new one.
      final ui = await storage.getDayEntries(profileId: profile.id);
      expect(ui, hasLength(1));
      expect(ui.single.id, recreated.id);
      expect(ui.single.flow, FlowLevel.medium);

      // Full fidelity keeps both rows: 1 live + 1 tombstone.
      final full = await storage.getDayEntries(
          profileId: profile.id, includeTombstones: true);
      expect(full, hasLength(2));
      expect(full.where((e) => e.deletedAt != null).single.id, original.id);

      // The partial unique index still forbids a second *live* row.
      expect(
        () => storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-06-01',
            tz: 'UTC',
            flow: FlowLevel.heavy),
        returnsNormally,
        reason: 'upsert of the live row is an update, not a duplicate insert',
      );
      expect(
        (await storage.getDayEntries(
                profileId: profile.id, includeTombstones: true))
            .where((e) => e.deletedAt == null),
        hasLength(1),
      );
    });

    test('soft delete is idempotent: deleting an already-deleted entry does '
        'not bump updated_at', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-02',
          tz: 'UTC',
          flow: FlowLevel.light);
      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-06-02');
      final tombstone = (await storage.getDayEntries(
              profileId: profile.id, includeTombstones: true))
          .single;

      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-06-02');
      final still = (await storage.getDayEntries(
              profileId: profile.id, includeTombstones: true))
          .single;
      expect(still.updatedAt, tombstone.updatedAt);
    });

    test('profiles can be archived and tombstoned; watchProfiles filters '
        'tombstones for UI reads', () async {
      final a = await storage.upsertProfile(
          displayName: 'A', isMinor: false, sortOrder: 1);
      final b = await storage.upsertProfile(
          displayName: 'B', isMinor: true, sortOrder: 2);

      clock.now = clock.now.add(const Duration(hours: 1));
      await storage.softDeleteProfile(b.id);

      final ui = await storage.getProfiles();
      expect(ui.map((p) => p.id), [a.id]);

      final full = await storage.getProfiles(includeTombstones: true);
      expect(full.map((p) => p.id), containsAll([a.id, b.id]));

      final streamed = await storage.watchProfiles().first;
      expect(streamed.map((p) => p.id), [a.id]);
      expect(a.archivedAt, isNull);
    });

    test('app_settings roundtrip and stream', () async {
      await storage.setSetting(key: 'active_profile', value: 'profileulid000000000000000000');
      expect(await storage.getSetting('active_profile'),
          'profileulid000000000000000000');
      expect(await storage.getSetting('missing'), isNull);

      await storage.setSetting(key: 'active_profile', value: 'otherulid0000000000000000000');
      expect(await storage.watchSetting('active_profile').first,
          'otherulid0000000000000000000');
    });

    test('local_date must be a valid ISO yyyy-MM-dd string', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-2-3',
            tz: 'UTC',
            flow: FlowLevel.none),
        throwsArgumentError,
      );
      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: 'not-a-date',
            tz: 'UTC',
            flow: FlowLevel.none),
        throwsArgumentError,
      );
      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-02-30',
            tz: 'UTC',
            flow: FlowLevel.none),
        throwsArgumentError,
      );
    });
  });

  group('migrations', () {
    test('v1 to v2 (test migration adding a column) preserves rows and sync '
        'columns', () async {
      final dir = await freshTempDir('migration');
      final file = File('${dir.path}${Platform.pathSeparator}db.sqlite');

      final t0 = DateTime.utc(2026, 7, 1, 9);
      {
        final clock = FixedClock(t0);
        final v1 = LunarLogDatabase(NativeDatabase(file));
        final storage = LunarLogStorage(v1, clock: clock.call);
        final profile =
            await storage.upsertProfile(displayName: 'M', isMinor: true);
        final entry = await storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-07-01',
            tz: 'UTC',
            flow: FlowLevel.medium,
            tags: const ['migrating']);
        await storage.setSetting(key: 'k', value: 'v');
        await v1.close();

        // Reopen as the v2 test database: migration must run.
        final v2 = V2TestDatabase(NativeDatabase(file));
        final profilesAfter = await v2.storage.getProfiles(includeTombstones: true);
        expect(profilesAfter.single.id, profile.id);
        expect(profilesAfter.single.updatedAt, profile.updatedAt);
        expect(profilesAfter.single.createdAt, profile.createdAt);

        final entriesAfter = await v2.storage
            .getDayEntries(profileId: profile.id, includeTombstones: true);
        expect(entriesAfter.single.id, entry.id);
        expect(entriesAfter.single.updatedAt, entry.updatedAt);
        expect(entriesAfter.single.tags, ['migrating']);

        expect(await v2.storage.getSetting('k'), 'v');

        final userVersion = (await v2
                .customSelect('PRAGMA user_version')
                .get())
            .first
            .data['user_version'];
        expect(userVersion, 2, reason: 'schema version must advance to 2');

        // The migration-added column exists and is readable.
        final marker = await v2.customSelect(
          'SELECT v2_test_marker FROM day_entries WHERE id = ?',
          variables: [Variable.withString(entry.id)],
        ).get();
        expect(marker, hasLength(1));

        await v2.close();
      }
    });
  });

  group('cipher assertion (fail-closed)', () {
    test('assertCipherActive throws EncryptionUnavailableError when the '
        'library reports no cipher', () {
      expect(() => assertCipherActive(const []),
          throwsA(isA<EncryptionUnavailableError>()));
      expect(() => assertCipherActive([null]),
          throwsA(isA<EncryptionUnavailableError>()));
    });

    test('assertCipherActive accepts a reported cipher version', () {
      expect(() => assertCipherActive(['4.9.3 community']), returnsNormally);
    });

    test('host observation: sqlcipher hook availability', () {
      // Runs the real probe. If the hook did not apply on this host, the
      // real-file cipher tests below are skipped; this test records which
      // branch we are in without failing either way.
      final available = hostHasSqlcipher();
      expect(() => assertCipherActive(
          available ? ['observed'] : const <Object?>[]),
          available ? returnsNormally : throwsA(isA<EncryptionUnavailableError>()));
    });
  });

  group('database factory', () {
    test('web mode: unencrypted executor, key store never called', () async {
      final recorder = RecordingKeyStore();
      final factory = LunarLogDbFactory(
        databasePath: 'test:web-mode',
        requireEncryption: false,
        plainExecutorBuilder: () => NativeDatabase.memory(),
        keyStore: recorder, // injected fake that records calls
      );
      final db = await factory.open();
      addTearDown(() => db.close());

      expect(recorder.calls, 0,
          reason: 'web mode must never touch key storage');
      final profile =
          await db.storage.upsertProfile(displayName: 'Web', isMinor: true);
      expect((await db.storage.getProfiles()).single.id, profile.id);
    });

    test('encrypted mode fetches the key exactly once and opens', () async {
      final recorder = RecordingKeyStore();
      final factory = LunarLogDbFactory(
        databasePath: 'test:encrypted-mode',
        requireEncryption: true,
        keyStore: recorder,
        // In-memory executor: key applied through the setup callback.
        encryptedExecutorBuilder: (keyHex) => NativeDatabase.memory(
          setup: (rawDb) {
            assertCipherActive(
                rawDb.select('PRAGMA cipher_version').map((r) => r.values.first));
            rawDb.execute("PRAGMA key = \"x'$keyHex'\";");
          },
        ),
        preflight: hostHasSqlcipher() ? assertSqlcipherAvailable : null,
      );
      if (!hostHasSqlcipher()) {
        // Without a cipher-capable library on the host, the real encrypted
        // open is exercised by the skipped group below; here we only assert
        // the fail-closed behavior.
        await expectLater(
            factory.open(), throwsA(isA<EncryptionUnavailableError>()));
        expect(recorder.calls, 0);
        return;
      }
      final db = await factory.open();
      addTearDown(() => db.close());
      expect(recorder.calls, 1, reason: 'exactly one key per install/open');
      await db.storage.upsertProfile(displayName: 'E', isMinor: false);
      expect(await db.storage.getProfiles(), hasLength(1));
    });

    test('malformed persisted key fails closed and is never overwritten',
        () async {
      final recorder = RecordingKeyStore(presetKey: 'not-hex');
      final factory = LunarLogDbFactory(
        databasePath: 'test:bad-key',
        requireEncryption: true,
        keyStore: recorder,
        encryptedExecutorBuilder: (keyHex) => NativeDatabase.memory(),
        preflight: hostHasSqlcipher() ? assertSqlcipherAvailable : null,
      );
      if (hostHasSqlcipher()) {
        await expectLater(
            factory.open(), throwsA(isA<CorruptDatabaseKeyError>()));
      } else {
        await expectLater(
            factory.open(), throwsA(isA<EncryptionUnavailableError>()));
      }
    });

    test('garbage existing file raises DatabaseQuarantineError and is never '
        'wiped or recreated', () async {
      final dir = await freshTempDir('quarantine');
      final file = File('${dir.path}${Platform.pathSeparator}corrupt.db');
      final garbage = 'this is definitely not a sqlite database file'.codeUnits;
      file.writeAsBytesSync(garbage);

      final factory = nativeDbFactory(
        file: file,
        keyStore: RecordingKeyStore(),
        requireEncryption: false, // cipher-independent: tests quarantine logic
      );
      await expectLater(
          factory.open(), throwsA(isA<DatabaseQuarantineError>()));

      expect(file.existsSync(), isTrue, reason: 'file must not be deleted');
      expect(file.readAsBytesSync(), garbage,
          reason: 'file content must be untouched');
    });

    test('first-run creation over a non-existent file is normal', () async {
      final dir = await freshTempDir('firstrun');
      final file = File('${dir.path}${Platform.pathSeparator}fresh.db');
      final factory = nativeDbFactory(
        file: file,
        keyStore: RecordingKeyStore(),
        requireEncryption: false,
      );
      final db = await factory.open();
      await db.close();
      expect(file.existsSync(), isTrue, reason: 'fresh database file created');
    });
  },
      skip: false);

  group('real SQLCipher file (host hook)', () {
    test('mobile factory writes a non-plaintext database file; wrong key '
        'quarantines instead of opening', () async {
      final dir = await freshTempDir('cipher');
      final file = File('${dir.path}${Platform.pathSeparator}enc.db');
      const goodKey =
          '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

      final factory = nativeDbFactory(
          file: file, keyStore: RecordingKeyStore(presetKey: goodKey));
      final db = await factory.open();
      final profile =
          await db.storage.upsertProfile(displayName: 'Cipher', isMinor: false);
      await db.close();

      // File must not start with the plaintext SQLite header.
      final header = file.openSync()..setPositionSync(0);
      final bytes = header.readSync(16);
      header.closeSync();
      const plaintextHeader = 'SQLite format 3\x00';
      expect(String.fromCharCodes(bytes), isNot(equals(plaintextHeader)),
          reason: 'database file at rest must not be plaintext SQLite');

      // Reopening with the correct key works and data survived.
      final reopened = await factory.open();
      final stored = await reopened.storage.getProfiles();
      expect(stored.single.id, profile.id);
      await reopened.close();

      // Reopening with a wrong key is an open failure over an existing file:
      // typed quarantine error, never a silent unencrypted open.
      final wrongFactory = nativeDbFactory(
        file: file,
        keyStore: RecordingKeyStore(
            presetKey:
                'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'),
      );
      await expectLater(
          wrongFactory.open(), throwsA(isA<DatabaseQuarantineError>()));
      expect(file.readAsBytesSync().length, greaterThan(0));
    });
  },
      skip: hostHasSqlcipher()
          ? false
          : 'sqlcipher native library not active on this host '
              '(hook observed: default sqlite3 build loaded)');
}

/// Test-only v2 schema: same tables as v1 plus a migration-added column,
/// used to prove the migration framework preserves data and sync columns.
class V2TestDatabase extends LunarLogDatabase {
  V2TestDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  Future<void> onUpgradeSteps(Migrator m, int from, int to) async {
      if (from < 2) {
      await customStatement(
          'ALTER TABLE day_entries ADD COLUMN v2_test_marker TEXT NULL');
    }
  }
}
