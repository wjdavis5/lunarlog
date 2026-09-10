import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The exact schema-v1 DDL as drift generated it for the committed v1
/// `db.g.dart` (dumped from `sqlite_master` before the v2 change). Tests
/// execute it raw so the migration is exercised against a real v1 file, not
/// against whatever the current data classes would create.
const List<String> kV1Ddl = [
  'CREATE TABLE "profiles" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, '
      '"is_minor" INTEGER NOT NULL CHECK ("is_minor" IN (0, 1)), '
      '"sort_order" INTEGER NOT NULL DEFAULT 0, "archived_at" TEXT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"deleted_at" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "day_entries" ("id" TEXT NOT NULL, '
      '"profile_id" TEXT NOT NULL REFERENCES profiles (id), '
      '"local_date" TEXT NOT NULL, "tz" TEXT NOT NULL, "flow" TEXT NOT NULL, '
      '"tags" TEXT NOT NULL DEFAULT \'[]\', "note" TEXT NULL, '
      '"updated_at" TEXT NOT NULL, "deleted_at" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE UNIQUE INDEX uq_day_entries_profile_date_live ON day_entries '
      '(profile_id, local_date) WHERE deleted_at IS NULL',
];

const String kV1ProfileId = '01JV1PROFILE00000000000000';
const String kV1EntryId = '01JV1ENTRY000000000000000A';
const String kV1TombstoneId = '01JV1ENTRY000000000000000B';
const String kV1Stamp = '2026-07-01T09:00:00.000000Z';

/// Executes the v1 DDL plus a small fixture (one profile, one live entry,
/// one tombstone, one setting) on a raw sqlite3 handle and stamps
/// `user_version = 1`.
void seedV1(sqlite3.Database raw) {
  for (final ddl in kV1Ddl) {
    raw.execute(ddl);
  }
  raw.execute(
      "INSERT INTO profiles (id, display_name, is_minor, sort_order, archived_at, "
      "created_at, updated_at, deleted_at) VALUES "
      "('$kV1ProfileId', 'Migrated', 1, 0, NULL, '$kV1Stamp', '$kV1Stamp', NULL)");
  raw.execute(
      "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, tags, note, "
      "updated_at, deleted_at) VALUES "
      "('$kV1EntryId', '$kV1ProfileId', '2026-07-01', 'UTC', 'medium', "
      "'[\"migrating\"]', 'keep me', '$kV1Stamp', NULL)");
  raw.execute(
      "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, tags, note, "
      "updated_at, deleted_at) VALUES "
      "('$kV1TombstoneId', '$kV1ProfileId', '2026-06-30', 'UTC', 'light', "
      "'[]', NULL, '$kV1Stamp', '$kV1Stamp')");
  raw.execute(
      "INSERT INTO app_settings (key, value, updated_at) VALUES ('k', 'v', '$kV1Stamp')");
  raw.execute('PRAGMA user_version = 1');
}

/// The exact schema-v3 DDL as drift generated it for the committed v3
/// `db.g.dart` (dumped from `sqlite_master` on a fresh v4 database, with the
/// v4-only `profiles` columns — `birth_year`, `relationship`,
/// `transferred_at` — stripped back out of the `profiles` CREATE TABLE; the
/// other four tables and the partial index are unchanged from v3 to v4).
/// Tests execute it raw so the v3→v4 migration is exercised against a real
/// v3 file, not against whatever the current data classes would create.
const List<String> kV3Ddl = [
  'CREATE TABLE "profiles" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, '
      '"is_minor" INTEGER NOT NULL CHECK ("is_minor" IN (0, 1)), '
      '"sort_order" INTEGER NOT NULL DEFAULT 0, "archived_at" TEXT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"deleted_at" TEXT NULL, "dirty" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("dirty" IN (0, 1)), "local_rev" INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY ("id"))',
  'CREATE TABLE "day_entries" ("id" TEXT NOT NULL, '
      '"profile_id" TEXT NOT NULL REFERENCES profiles (id), '
      '"local_date" TEXT NOT NULL, "tz" TEXT NOT NULL, "flow" TEXT NOT NULL, '
      '"tags" TEXT NOT NULL DEFAULT \'[]\', "note" TEXT NULL, '
      '"updated_at" TEXT NOT NULL, "deleted_at" TEXT NULL, '
      '"dirty" INTEGER NOT NULL DEFAULT 0 CHECK ("dirty" IN (0, 1)), '
      '"local_rev" INTEGER NOT NULL DEFAULT 0, "logged_by_user_id" TEXT NULL, '
      '"last_modified_by_user_id" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "profile_guardians" ("id" TEXT NOT NULL, '
      '"profile_id" TEXT NOT NULL REFERENCES profiles (id), '
      '"user_id" TEXT NOT NULL, "role" TEXT NOT NULL, '
      '"status" TEXT NOT NULL DEFAULT \'accepted\', "display_name" TEXT NULL, '
      '"invited_by" TEXT NULL, "created_at" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE TABLE "sync_state" ("id" INTEGER NOT NULL CHECK("id" = 1), '
      '"bound_user_id" TEXT NULL, "device_id" TEXT NOT NULL DEFAULT \'\', '
      '"cursor_profiles" INTEGER NOT NULL DEFAULT 0, '
      '"cursor_day_entries" INTEGER NOT NULL DEFAULT 0, '
      '"last_full_pull_at" TEXT NULL, "last_sync_at" TEXT NULL, '
      '"last_error" TEXT NULL, "server_clock_offset_ms" INTEGER NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE UNIQUE INDEX uq_day_entries_profile_date_live ON day_entries '
      '(profile_id, local_date) WHERE deleted_at IS NULL',
];

const String kV3ProfileId = '01JV3PROFILE00000000000000';
const String kV3EntryId = '01JV3ENTRY0000000000000000';
const String kV3GuardianId = 'v3-guardian-1';
const String kV3Stamp = '2026-08-01T09:00:00.000000Z';

/// Executes the v3 DDL plus a small fixture (one profile, one live entry
/// with attribution, one profile_guardians row) on a raw sqlite3 handle and
/// stamps `user_version = 3`.
void seedV3(sqlite3.Database raw) {
  for (final ddl in kV3Ddl) {
    raw.execute(ddl);
  }
  raw.execute(
      "INSERT INTO profiles (id, display_name, is_minor, sort_order, archived_at, "
      "created_at, updated_at, deleted_at, dirty, local_rev) VALUES "
      "('$kV3ProfileId', 'V3 Profile', 0, 0, NULL, '$kV3Stamp', '$kV3Stamp', NULL, 0, 0)");
  raw.execute(
      "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, tags, note, "
      "updated_at, deleted_at, dirty, local_rev, logged_by_user_id, last_modified_by_user_id) VALUES "
      "('$kV3EntryId', '$kV3ProfileId', '2026-08-01', 'UTC', 'light', "
      "'[]', NULL, '$kV3Stamp', NULL, 0, 0, 'u-v3', 'u-v3')");
  raw.execute(
      "INSERT INTO profile_guardians (id, profile_id, user_id, role, status, "
      "display_name, invited_by, created_at, updated_at) VALUES "
      "('$kV3GuardianId', '$kV3ProfileId', 'u-v3', 'primary_guardian', 'accepted', "
      "NULL, NULL, '$kV3Stamp', '$kV3Stamp')");
  raw.execute('PRAGMA user_version = 3');
}

/// The v4 schema as drift generated it: [kV3Ddl] with the v4-only
/// `profiles` columns (`birth_year`, `relationship`, `transferred_at`)
/// present. Seeds one profile (birth year and relationship set, no mode —
/// the column does not exist in v4) and stamps `user_version = 4`, so the
/// v4→v5 migration (profiles.mode, Issue #131) is exercised against a real
/// v4 file.
void seedV4(sqlite3.Database raw) {
  final v4Ddl = [
    // kV3Ddl's profiles CREATE TABLE with the three v4 columns added in
    // drift's declaration order (after local_rev, before the PK).
    kV3Ddl.first.replaceFirst(
        '"local_rev" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id")',
        '"local_rev" INTEGER NOT NULL DEFAULT 0, "birth_year" INTEGER NULL, '
        '"relationship" TEXT NULL, "transferred_at" TEXT NULL, '
        'PRIMARY KEY ("id")'),
    ...kV3Ddl.skip(1),
  ];
  for (final ddl in v4Ddl) {
    raw.execute(ddl);
  }
  raw.execute(
      "INSERT INTO profiles (id, display_name, is_minor, sort_order, archived_at, "
      "created_at, updated_at, deleted_at, dirty, local_rev, birth_year, relationship) VALUES "
      "('$kV3ProfileId', 'V4 Profile', 0, 0, NULL, '$kV3Stamp', '$kV3Stamp', NULL, 0, 0, 2013, 'daughter')");
  raw.execute('PRAGMA user_version = 4');
}

/// The v7 schema as drift generated it: the v4/v5 shape of [kV3Ddl] (with
/// profiles' birth_year/relationship/transferred_at/mode) plus the v6
/// `observations` table and `sync_state.cursor_observations`, and the v7
/// provenance columns (`day_entries.source/source_id/import_id`,
/// `observations.import_id`). Seeds one profile (care mode `teen`, to pin
/// #131's axis surviving untouched beside the new #188 tables), one
/// imported day entry, one observation, and a bound `sync_state` row, then
/// stamps `user_version = 7`, so the v7→v9 migrations (main's v8
/// indexes then Issue #188's
/// profile_modes/cycle_overrides tables and their two cursors) is exercised
/// against a real v7 file.
void seedV7(sqlite3.Database raw) {
  final v7Ddl = [
    kV3Ddl.first.replaceFirst(
        '"local_rev" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id")',
        '"local_rev" INTEGER NOT NULL DEFAULT 0, "birth_year" INTEGER NULL, '
        '"relationship" TEXT NULL, "transferred_at" TEXT NULL, '
        '"mode" TEXT NOT NULL DEFAULT \'standard\', PRIMARY KEY ("id")'),
    kV3Ddl[1].replaceFirst(
        '"last_modified_by_user_id" TEXT NULL, PRIMARY KEY ("id")',
        '"last_modified_by_user_id" TEXT NULL, "source" TEXT NOT NULL '
        'DEFAULT \'manual\', "source_id" TEXT NULL, "import_id" TEXT NULL, '
        'PRIMARY KEY ("id")'),
    kV3Ddl[2],
    'CREATE TABLE "observations" ("id" TEXT NOT NULL, "day_entry_id" TEXT '
        'NOT NULL REFERENCES day_entries (id), "profile_id" TEXT NOT NULL '
        'REFERENCES profiles (id), "local_date" TEXT NOT NULL, '
        '"observed_at" TEXT NULL, "tz" TEXT NOT NULL, "category" TEXT NULL, '
        '"code" TEXT NULL, "value_num" REAL NULL, "value_text" TEXT NULL, '
        '"unit" TEXT NULL, "intensity" INTEGER NULL, "excluded" INTEGER '
        'NOT NULL DEFAULT 0 CHECK ("excluded" IN (0, 1)), "source" TEXT '
        'NOT NULL DEFAULT \'manual\', "source_id" TEXT NULL, "import_id" '
        'TEXT NULL, "raw" TEXT NULL, "updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, "dirty" INTEGER NOT NULL DEFAULT 0 '
        'CHECK ("dirty" IN (0, 1)), "local_rev" INTEGER NOT NULL DEFAULT 0, '
        '"logged_by_user_id" TEXT NULL, "last_modified_by_user_id" TEXT '
        'NULL, PRIMARY KEY ("id"))',
    kV3Ddl[3],
    kV3Ddl[4].replaceFirst(
        '"cursor_day_entries" INTEGER NOT NULL DEFAULT 0,',
        '"cursor_day_entries" INTEGER NOT NULL DEFAULT 0, '
        '"cursor_observations" INTEGER NOT NULL DEFAULT 0,'),
    kV3Ddl[5],
  ];
  for (final ddl in v7Ddl) {
    raw.execute(ddl);
  }
  raw.execute(
      "INSERT INTO profiles (id, display_name, is_minor, sort_order, archived_at, "
      "created_at, updated_at, deleted_at, dirty, local_rev, birth_year, relationship, mode) VALUES "
      "('$kV3ProfileId', 'V7 Profile', 1, 0, NULL, '$kV3Stamp', '$kV3Stamp', NULL, 0, 0, 2013, 'daughter', 'teen')");
  raw.execute(
      "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, tags, note, "
      "updated_at, deleted_at, dirty, local_rev, logged_by_user_id, last_modified_by_user_id, source, source_id) VALUES "
      "('$kV3EntryId', '$kV3ProfileId', '2026-08-01', 'UTC', 'light', "
      "'[]', NULL, '$kV3Stamp', NULL, 0, 0, 'u-v7', 'u-v7', 'clue_import', 'clue-42')");
  raw.execute(
      "INSERT INTO observations (id, day_entry_id, profile_id, local_date, tz, category, code, "
      "updated_at, dirty, local_rev, logged_by_user_id, last_modified_by_user_id, import_id) VALUES "
      "('01JV7OBSERVATION0000000000', '$kV3EntryId', '$kV3ProfileId', '2026-08-01', 'UTC', 'pain', 'cramps', "
      "'$kV3Stamp', 0, 0, 'u-v7', 'u-v7', NULL)");
  raw.execute(
      "INSERT INTO sync_state (id, bound_user_id, device_id, cursor_profiles, "
      "cursor_day_entries, cursor_observations, last_full_pull_at, last_sync_at, last_error, server_clock_offset_ms) VALUES "
      "(1, 'u-v7', 'dev-v7', 11, 12, 13, NULL, NULL, NULL, NULL)");
  raw.execute('PRAGMA user_version = 7');
}

/// Column names of [table] via `PRAGMA table_info`.
Future<Set<String>> columnsOf(LunarLogDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<int> userVersion(LunarLogDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').get())
        .first
        .read<int>('user_version');

/// Asserts everything the v1 fixture held survived the upgrade with the
/// new sync columns, profile_guardians table, v4 profile subject
/// metadata columns, and the v5 care-mode column at their defaults.
Future<void> expectFullyUpgraded(LunarLogDatabase db) async {
  expect(await userVersion(db), 13);
  expect(await columnsOf(db, 'profiles'),
      containsAll(['dirty', 'local_rev', 'birth_year', 'relationship', 'transferred_at', 'mode',
              'last_period_start', 'typical_cycle_length_days', 'typical_period_length_days']));
  expect(
      await columnsOf(db, 'day_entries'),
      containsAll(['dirty', 'local_rev', 'logged_by_user_id', 'last_modified_by_user_id',
          'source', 'source_id', 'import_id']));
  expect(await columnsOf(db, 'observations'), contains('import_id'));

  final stamp = DateTime.parse(kV1Stamp);
  final profile =
      (await db.storage.getProfiles(includeTombstones: true)).single;
  expect(profile.id, kV1ProfileId);
  expect(profile.displayName, 'Migrated');
  expect(profile.isMinor, isTrue);
  expect(profile.createdAt, stamp);
  expect(profile.updatedAt, stamp);
  expect(profile.dirty, isFalse);
  expect(profile.localRev, 0);
  expect(profile.birthYear, isNull);
  expect(profile.relationship, isNull);
  expect(profile.transferredAt, isNull);
  expect(profile.mode, 'standard',
      reason: 'the v5 column defaults to standard for pre-existing rows');

  final entries = await db.storage
      .getDayEntries(profileId: kV1ProfileId, includeTombstones: true);
  expect(entries.map((e) => e.id).toSet(), {kV1EntryId, kV1TombstoneId});
  final live = entries.firstWhere((e) => e.id == kV1EntryId);
  expect(live.tags, ['migrating']);
  expect(live.note, 'keep me');
  expect(live.updatedAt, stamp);
  expect(live.deletedAt, isNull);
  expect(live.dirty, isFalse);
  expect(live.localRev, 0);
  final tomb = entries.firstWhere((e) => e.id == kV1TombstoneId);
  expect(tomb.deletedAt, stamp);
  expect(tomb.dirty, isFalse);
  expect(tomb.localRev, 0);

  expect(await db.storage.getSetting('k'), 'v');

  final state = await db.storage.readSyncState();
  expect(state.boundUserId, isNull);
  expect(state.deviceId, '');
  expect(state.cursorProfiles, 0);
  expect(state.cursorDayEntries, 0);
  final stateRows =
      await db.customSelect('SELECT COUNT(*) AS n FROM sync_state').getSingle();
  expect(stateRows.data['n'], 0,
      reason: 'the upgrade creates the table, not a row; defaults are read');

  // The partial unique index survived (it is not recreated by the upgrade).
  final index = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'uq_day_entries_profile_date_live'")
      .get();
  expect(index, hasLength(1));
}

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
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

  group('schema', () {
    late LunarLogDatabase db;

    setUp(() async {
      db = LunarLogDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
    });

    test('schema version is 13 and database opens with the expected tables',
        () async {
      expect(db.schemaVersion, 13);
      expect(await userVersion(db), 13);

      final tables = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(tables,
          containsAll(['profiles', 'day_entries', 'profile_guardians', 'app_settings', 'sync_state',
              'observations', 'profile_modes', 'cycle_overrides',
              'care_notes', 'visit_prep_items']));
      expect(await columnsOf(db, 'profiles'),
          containsAll(['dirty', 'local_rev', 'birth_year', 'relationship', 'transferred_at', 'mode',
              'last_period_start', 'typical_cycle_length_days', 'typical_period_length_days']));
      expect(
          await columnsOf(db, 'day_entries'),
          containsAll(['dirty', 'local_rev', 'logged_by_user_id', 'last_modified_by_user_id',
              'source', 'source_id', 'import_id']));
      expect(
          await columnsOf(db, 'profile_guardians'), containsAll(['id', 'profile_id', 'user_id', 'role', 'status', 'display_name']));
      expect(await columnsOf(db, 'observations'), contains('import_id'));
      expect(await columnsOf(db, 'profile_modes'),
          containsAll(['profile_id', 'mode', 'mode_started_on', 'birth_control_method',
              'birth_control_started_on', 'birth_control_stopped_on', 'health_sync_consent',
              'updated_at', 'dirty', 'local_rev']));
      expect(await columnsOf(db, 'cycle_overrides'),
          containsAll(['id', 'profile_id', 'cycle_start_date', 'excluded_from_average',
              'manual_start', 'note_id', 'deleted_at', 'updated_at', 'dirty', 'local_rev']));
      expect(await columnsOf(db, 'care_notes'),
          containsAll(['id', 'profile_id', 'body', 'updated_at', 'deleted_at',
              'dirty', 'local_rev', 'logged_by_user_id', 'last_modified_by_user_id']));
      expect(await columnsOf(db, 'visit_prep_items'),
          containsAll(['id', 'profile_id', 'body', 'is_checked', 'checked_by_user_id',
              'checked_at', 'updated_at', 'deleted_at', 'dirty', 'local_rev',
              'logged_by_user_id', 'last_modified_by_user_id']));
      expect(await columnsOf(db, 'sync_state'),
          containsAll(['cursor_profile_modes', 'cursor_cycle_overrides',
              'cursor_care_notes', 'cursor_visit_prep_items']));

      // Issue #197: the four read-path indexes exist on a fresh onCreate
      // too, not just via onUpgradeSteps (see schema_migration_test.dart
      // for the upgrade-path assertion). Issue #128 adds two more
      // (care_notes / visit_prep_items profile_id), asserted the same way.
      final indexNames = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
          indexNames,
          containsAll([
            'ix_day_entries_profile_date',
            'ix_day_entries_dirty',
            'ix_day_entries_updated_at',
            'ix_profile_guardians_profile_id',
            'ix_care_notes_profile_id',
            'ix_visit_prep_items_profile_id',
          ]));
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

    test('issue #218: onboarding cycle facts round-trip through create, '
        'update, and clear; a malformed date is rejected', () async {
      final created = await storage.upsertProfile(
          displayName: 'Luna',
          isMinor: false,
          lastPeriodStart: '2026-01-02',
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5);
      expect(created.lastPeriodStart, '2026-01-02');
      expect(created.typicalCycleLengthDays, 28);
      expect(created.typicalPeriodLengthDays, 5);

      clock.now = clock.now.add(const Duration(hours: 1));
      final updated = await storage.upsertProfile(
          id: created.id,
          displayName: 'Luna',
          isMinor: false,
          lastPeriodStart: '2026-01-09',
          typicalCycleLengthDays: 30,
          typicalPeriodLengthDays: 6);
      expect(updated.lastPeriodStart, '2026-01-09');
      expect(updated.typicalCycleLengthDays, 30);
      expect(updated.typicalPeriodLengthDays, 6);

      // Clearing an answer is an explicit null, not an omission: the
      // whole-row upsert writes nulls when nulls are handed to it.
      clock.now = clock.now.add(const Duration(hours: 1));
      final cleared = await storage.upsertProfile(
          id: created.id,
          displayName: 'Luna',
          isMinor: false,
          lastPeriodStart: null,
          typicalCycleLengthDays: null,
          typicalPeriodLengthDays: null);
      expect(cleared.lastPeriodStart, isNull);
      expect(cleared.typicalCycleLengthDays, isNull);
      expect(cleared.typicalPeriodLengthDays, isNull);

      expect(
        () => storage.upsertProfile(
            displayName: 'Luna',
            isMinor: false,
            lastPeriodStart: 'January 2'),
        throwsArgumentError,
        reason: 'the stored date must be a real ISO yyyy-MM-dd string',
      );
    });

    test('issue #218: remote-applyed profile rows carry the cycle facts '
        '(the sync pull path)', () async {
      final created = await storage.upsertProfile(
          displayName: 'RemoteSeed',
          isMinor: false,
          lastPeriodStart: '2026-01-02',
          typicalCycleLengthDays: 26,
          typicalPeriodLengthDays: 4);
      // Round-trip through the codec + remote apply, the way a pull does.
      final decoded = decodeProfile(encodeProfile(created));
      final applied = await storage.applyRemoteProfile(decoded);
      expect(applied, isTrue);
      final reread = await storage.getProfile(created.id);
      expect(reread!.lastPeriodStart, '2026-01-02');
      expect(reread.typicalCycleLengthDays, 26);
      expect(reread.typicalPeriodLengthDays, 4);
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

    test(
        'issue #224: soft delete clears flow to none alongside note and '
        'tags — a tombstone carries no payload, the most sensitive field '
        'included', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-03-04',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          tags: const ['cramps'],
          note: 'a heavy day');

      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-03-04');

      final tombstone = (await storage.getDayEntries(
              profileId: profile.id, includeTombstones: true))
          .single;
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.flow, FlowLevel.none);
      expect(tombstone.note, isNull);
      expect(tombstone.tags, isEmpty);
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

    group('issue #197: fromLocalDate/toLocalDate range', () {
      test('bounds are inclusive on both ends', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        for (final date in [
          '2026-05-31',
          '2026-06-01',
          '2026-06-15',
          '2026-06-30',
          '2026-07-01',
        ]) {
          await storage.upsertDayEntry(
              profileId: profile.id,
              localDate: date,
              tz: 'UTC',
              flow: FlowLevel.light);
        }

        final windowed = await storage.getDayEntries(
          profileId: profile.id,
          fromLocalDate: '2026-06-01',
          toLocalDate: '2026-06-30',
        );
        expect(windowed.map((e) => e.localDate).toList(), [
          '2026-06-01',
          '2026-06-15',
          '2026-06-30',
        ], reason: 'the boundary dates themselves must be included');

        final fromOnly = await storage.getDayEntries(
          profileId: profile.id,
          fromLocalDate: '2026-06-15',
        );
        expect(fromOnly.map((e) => e.localDate),
            ['2026-06-15', '2026-06-30', '2026-07-01']);

        final toOnly = await storage.getDayEntries(
          profileId: profile.id,
          toLocalDate: '2026-06-15',
        );
        expect(toOnly.map((e) => e.localDate),
            ['2026-05-31', '2026-06-01', '2026-06-15']);
      });

      test('a tombstoned date inside the range is excluded from UI reads '
          'but present in a full-fidelity read', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-06-10',
            tz: 'UTC',
            flow: FlowLevel.medium);
        await storage.softDeleteDayEntry(
            profileId: profile.id, localDate: '2026-06-10');

        final ui = await storage.getDayEntries(
          profileId: profile.id,
          fromLocalDate: '2026-06-01',
          toLocalDate: '2026-06-30',
        );
        expect(ui, isEmpty,
            reason: 'the tombstone must not appear in a UI-scoped range read');

        final full = await storage.getDayEntries(
          profileId: profile.id,
          fromLocalDate: '2026-06-01',
          toLocalDate: '2026-06-30',
          includeTombstones: true,
        );
        expect(full, hasLength(1));
        expect(full.single.deletedAt, isNotNull);
      });

      test('never returns another profile\'s rows, range or no range',
          () async {
        final a = await storage.upsertProfile(displayName: 'A', isMinor: true);
        final b = await storage.upsertProfile(displayName: 'B', isMinor: false);
        await storage.upsertDayEntry(
            profileId: a.id,
            localDate: '2026-06-15',
            tz: 'UTC',
            flow: FlowLevel.light);
        await storage.upsertDayEntry(
            profileId: b.id,
            localDate: '2026-06-15',
            tz: 'UTC',
            flow: FlowLevel.heavy);

        final aWindowed = await storage.getDayEntries(
          profileId: a.id,
          fromLocalDate: '2026-06-01',
          toLocalDate: '2026-06-30',
        );
        expect(aWindowed, hasLength(1));
        expect(aWindowed.single.profileId, a.id);

        final aStream = await storage
            .watchDayEntries(
              profileId: a.id,
              fromLocalDate: '2026-06-01',
              toLocalDate: '2026-06-30',
            )
            .first;
        expect(aStream.map((e) => e.profileId).toSet(), {a.id});
      });

      test('a date just outside the range is excluded', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-05-31',
            tz: 'UTC',
            flow: FlowLevel.light);
        await storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-07-01',
            tz: 'UTC',
            flow: FlowLevel.light);

        final windowed = await storage.getDayEntries(
          profileId: profile.id,
          fromLocalDate: '2026-06-01',
          toLocalDate: '2026-06-30',
        );
        expect(windowed, isEmpty,
            reason: 'both entries fall one day outside the range');
      });
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

    test('monotonic updated_at: a clock running backwards stamps the edit '
        'one millisecond after the stored updated_at', () async {
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
      expect(regressed.updatedAt,
          edited.updatedAt.add(const Duration(milliseconds: 1)),
          reason: 'updated_at must strictly increase on a local edit');
      expect(regressed.flow, FlowLevel.none,
          reason: 'content is still written; only the timestamp is bumped');
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
      expect(imported.updatedAt,
          entry.updatedAt.add(const Duration(milliseconds: 1)),
          reason: 'a stale explicit timestamp still lands strictly after');
    });

    test('payload limits: an 81-character display_name and a 2001-character '
        'note are rejected before anything is written', () async {
      await expectLater(
        storage.upsertProfile(displayName: 'a' * 81, isMinor: false),
        throwsArgumentError,
      );
      expect(await storage.getProfiles(includeTombstones: true), isEmpty);

      final profile = await storage.upsertProfile(
          displayName: 'b' * 80, isMinor: false);
      expect(profile.displayName.length, 80, reason: '80 is the limit');
      await expectLater(
        storage.upsertProfile(
            id: profile.id, displayName: 'c' * 81, isMinor: false),
        throwsArgumentError,
      );
      expect((await storage.getProfiles()).single.displayName, 'b' * 80);

      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-05-03',
            tz: 'UTC',
            flow: FlowLevel.light,
            note: 'n' * 2001),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: profile.id), isEmpty);
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-03',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'n' * 2000);
      expect(entry.note!.length, 2000);
    });

    test('payload limits: a tag element over kMaxTagLength characters or a '
        'tags list over kMaxTagCount elements is rejected before anything is '
        'written', () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);

      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-05-04',
            tz: 'UTC',
            flow: FlowLevel.light,
            tags: ['x' * (kMaxTagLength + 1)]),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: profile.id), isEmpty,
          reason: 'nothing was written');

      final bounded = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-04',
          tz: 'UTC',
          flow: FlowLevel.light,
          tags: ['x' * kMaxTagLength]);
      expect(bounded.tags, ['x' * kMaxTagLength],
          reason: 'the boundary value is inclusive and round-trips');

      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-05-05',
            tz: 'UTC',
            flow: FlowLevel.light,
            tags: List.generate(kMaxTagCount + 1, (i) => 't$i')),
        throwsArgumentError,
      );
      expect((await storage.getDayEntries(profileId: profile.id)).length, 1,
          reason: 'the over-count write persisted nothing');
      final thirtyTwo = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-05',
          tz: 'UTC',
          flow: FlowLevel.light,
          tags: List.generate(kMaxTagCount, (i) => 't$i'));
      expect(thirtyTwo.tags.length, kMaxTagCount,
          reason: 'the count boundary value is inclusive');

      // Updating an existing live entry with an over-length tag must leave
      // the stored row completely untouched.
      final before = await storage.getDayEntry(
          profileId: profile.id, localDate: '2026-05-04');
      await expectLater(
        storage.upsertDayEntry(
            profileId: profile.id,
            localDate: '2026-05-04',
            tz: 'UTC',
            flow: FlowLevel.heavy,
            tags: ['x' * (kMaxTagLength + 1)],
            note: 'should never land'),
        throwsArgumentError,
      );
      final after = await storage.getDayEntry(
          profileId: profile.id, localDate: '2026-05-04');
      expect(after!.id, before!.id);
      expect(after.tags, before.tags);
      expect(after.note, before.note);
      expect(after.updatedAt, before.updatedAt);
      expect(after.localRev, before.localRev,
          reason: 'local_rev is not bumped by a rejected write');

      // Empty and defaulted tags are not accidentally rejected.
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-06',
          tz: 'UTC',
          flow: FlowLevel.none,
          tags: const []);
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-07',
          tz: 'UTC',
          flow: FlowLevel.none);

      // The curated taxonomy passes the bounds check. Issue #249/#251 grew
      // the taxonomy to 67 codes — more than the 32-element
      // day_entries.tags cap — so the round-trip covers the first
      // kMaxTagCount of them (longest code still well under
      // kMaxTagLength).
      final taxonomyCodes = kTagTaxonomy.map((t) => t.code).toList();
      expect(taxonomyCodes.length, greaterThan(kMaxTagCount),
          reason: 'this test exists to pin taxonomy codes against the '
              'per-day count bound — it must stay meaningful');
      final storedCodes = taxonomyCodes.take(kMaxTagCount).toList();
      final taxonomyEntry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-05-08',
          tz: 'UTC',
          flow: FlowLevel.spotting,
          tags: storedCodes);
      expect(taxonomyEntry.tags, storedCodes);
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

    test('characterization: the strict bump applies to soft deletes and '
        'profile edits too — a regressed clock lands 1ms after the stored '
        'updated_at, and a tombstone stamps deleted_at with that value',
        () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-03',
          tz: 'UTC',
          flow: FlowLevel.light);
      final stored = entry.updatedAt;

      clock.now = stored.subtract(const Duration(days: 1));
      await storage.softDeleteDayEntry(
          profileId: profile.id, localDate: '2026-06-03');
      final tombstone = (await storage.getDayEntries(
              profileId: profile.id, includeTombstones: true))
          .single;
      const ms = Duration(milliseconds: 1);
      expect(tombstone.updatedAt, stored.add(ms));
      expect(tombstone.deletedAt, stored.add(ms));

      final edited = await storage.upsertProfile(
          id: profile.id, displayName: 'P2', isMinor: false);
      expect(edited.updatedAt, profile.updatedAt.add(ms));
      expect(edited.displayName, 'P2');

      await storage.softDeleteProfile(profile.id);
      final gone = (await storage.getProfiles(includeTombstones: true)).single;
      expect(gone.updatedAt, edited.updatedAt.add(ms));
      expect(gone.deletedAt, edited.updatedAt.add(ms));
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

    test('R6: getProfiles and watchProfiles read through one shared query — '
        'identical lists over live, archived and tombstoned profiles',
        () async {
      final live = await storage.upsertProfile(
          id: '01JPROFILELIVE000000000000',
          displayName: 'Live',
          isMinor: false,
          sortOrder: 1);
      final archived = await storage.upsertProfile(
          id: '01JPROFILEARCHIVED00000000',
          displayName: 'Archived',
          isMinor: true,
          sortOrder: 2,
          archivedAt: DateTime.utc(2026, 1, 1));
      final gone = await storage.upsertProfile(
          id: '01JPROFILETOMBSTONED000000',
          displayName: 'Gone',
          isMinor: false,
          sortOrder: 3);
      clock.now = clock.now.add(const Duration(hours: 1));
      await storage.softDeleteProfile(gone.id);

      final fetched = await storage.getProfiles();
      final watched = await storage.watchProfiles().first;
      expect(fetched.map((p) => p.id), [live.id, archived.id],
          reason: 'archived rows stay; only tombstones are filtered');
      expect(watched, fetched);
    });

    test('R6: both profile reads include tombstones when asked, ordered by '
        'sortOrder then id', () async {
      final b = await storage.upsertProfile(
          id: '01JPROFILEBBBBBBBBBBBBBBBB',
          displayName: 'B',
          isMinor: false,
          sortOrder: 0);
      final a = await storage.upsertProfile(
          id: '01JPROFILEAAAAAAAAAAAAAAAA',
          displayName: 'A',
          isMinor: false,
          sortOrder: 0);
      final c = await storage.upsertProfile(
          id: '01JPROFILECCCCCCCCCCCCCCCC',
          displayName: 'C',
          isMinor: true,
          sortOrder: 1);
      clock.now = clock.now.add(const Duration(hours: 1));
      await storage.softDeleteProfile(c.id);

      final fetched = await storage.getProfiles(includeTombstones: true);
      final watched =
          await storage.watchProfiles(includeTombstones: true).first;
      expect(fetched.map((p) => p.id), [a.id, b.id, c.id]);
      expect(watched, fetched);
    });

    test('getDayEntry returns the live entry for a (profile, date), and null '
        'for a date with no entry', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final saved = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-04-01',
          tz: 'UTC',
          flow: FlowLevel.medium);

      // Row identity is compared field by field: drift's generated DayEntry
      // `==` compares `tags` by reference, so two reads of the same row are
      // never `==` to each other.
      final found =
          await storage.getDayEntry(profileId: p.id, localDate: '2026-04-01');
      expect(found, isNotNull);
      expect(found!.id, saved.id);
      expect(found.profileId, p.id);
      expect(found.localDate, '2026-04-01');
      expect(found.flow, FlowLevel.medium);
      expect(found.deletedAt, isNull);

      expect(
          await storage.getDayEntry(profileId: p.id, localDate: '2026-04-02'),
          isNull);
    });

    test('getDayEntry reads null for a date whose only row is a tombstone',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-04-01',
          tz: 'UTC',
          flow: FlowLevel.light);
      clock.now = clock.now.add(const Duration(hours: 1));
      await storage.softDeleteDayEntry(
          profileId: p.id, localDate: '2026-04-01');

      expect(
          await storage.getDayEntry(profileId: p.id, localDate: '2026-04-01'),
          isNull);
      expect(
          await storage.getDayEntries(
              profileId: p.id, includeTombstones: true),
          hasLength(1),
          reason: 'the tombstone is still held for sync');
    });

    test('getDayEntry is scoped to one profile: the same date under another '
        'profile is not returned', () async {
      final a = await storage.upsertProfile(displayName: 'A', isMinor: false);
      final b = await storage.upsertProfile(displayName: 'B', isMinor: true);
      final bEntry = await storage.upsertDayEntry(
          profileId: b.id,
          localDate: '2026-04-01',
          tz: 'UTC',
          flow: FlowLevel.heavy);

      expect(
          await storage.getDayEntry(profileId: a.id, localDate: '2026-04-01'),
          isNull);
      final forB =
          await storage.getDayEntry(profileId: b.id, localDate: '2026-04-01');
      expect(forB, isNotNull);
      expect(forB!.id, bEntry.id);
      expect(forB.profileId, b.id);
    });

    test('getProfile is an indexed lookup that excludes tombstones by '
        'default and reads null for unknown ids', () async {
      final live =
          await storage.upsertProfile(displayName: 'Live', isMinor: false);
      final gone =
          await storage.upsertProfile(displayName: 'Gone', isMinor: true);
      clock.now = clock.now.add(const Duration(hours: 1));
      await storage.softDeleteProfile(gone.id);

      expect(await storage.getProfile(live.id), live);
      expect(await storage.getProfile(gone.id), isNull);

      final tombstone =
          await storage.getProfile(gone.id, includeTombstones: true);
      expect(tombstone, isNotNull);
      expect(tombstone!.id, gone.id);
      expect(tombstone.deletedAt, isNotNull);

      expect(await storage.getProfile('01JPROFILEUNKNOWN000000000'), isNull);
    });

    test('R5: applying a revoked membership for the bound user tombstones '
        'the shared profile and its day entries', () async {
      final profile =
          await storage.upsertProfile(displayName: 'Shared', isMinor: true);
      await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['cramps'],
          note: 'secret');
      await storage.writeSyncState(
          kDefaultSyncState.copyWith(boundUserId: const Value('u-revoked')));

      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-1',
          profileId: profile.id,
          userId: 'u-revoked',
          role: 'caregiver',
          status: 'revoked',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ]);

      // UI reads see nothing; full-fidelity reads see tombstones.
      expect(await storage.getProfile(profile.id), isNull);
      final tombstone =
          await storage.getProfile(profile.id, includeTombstones: true);
      expect(tombstone!.deletedAt, isNotNull);
      expect(await storage.getDayEntries(profileId: profile.id), isEmpty);
      final entryTombstones = await storage.getDayEntries(
          profileId: profile.id, includeTombstones: true);
      expect(entryTombstones, isNotEmpty);
      expect(entryTombstones.every((e) => e.deletedAt != null), isTrue);
      // issue #224: the revocation wipe is a tombstone like any other - it
      // must carry no payload, flow included, not just note/tags.
      expect(
        entryTombstones.every((e) => e.flow == FlowLevel.none),
        isTrue,
      );
      // The membership row itself is stored (status revoked).
      expect(
        (await storage.getGuardiansForProfile(profile.id))
            .single
            .status,
        'revoked',
      );
    });

    test('R5 does not fire for another user\'s revoked membership or for '
        'an accepted own membership', () async {
      final profile =
          await storage.upsertProfile(displayName: 'Mine', isMinor: false);
      await storage.writeSyncState(
          kDefaultSyncState.copyWith(boundUserId: const Value('u-me')));

      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-other',
          profileId: profile.id,
          userId: 'u-someone-else',
          role: 'caregiver',
          status: 'revoked',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        RemoteProfileGuardianRow(
          id: 'g-me',
          profileId: profile.id,
          userId: 'u-me',
          role: 'co_parent',
          status: 'accepted',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ]);

      expect(await storage.getProfile(profile.id), isNotNull);
    });

    test('a profile_guardians row whose profile is not held locally throws '
        'RetryableSyncApplyError (typed, retried next cycle)', () async {
      await expectLater(
        storage.applyRemoteRows([
          RemoteProfileGuardianRow(
            id: 'g-x',
            profileId: '01ANOTHELDPROFILE0000000000000',
            userId: 'u-me',
            role: 'co_parent',
            status: 'accepted',
            displayName: null,
            invitedBy: null,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ]),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });

    test('finding #8: a revoked or pending membership whose profile is not '
        'held locally is skipped, not retried forever', () async {
      const revokedProfileId = '01ANOTHELDPROFILE0000000000001';
      const pendingProfileId = '01ANOTHELDPROFILE0000000000002';

      // Neither throws: `profiles_select_guardians` only ever returns a
      // profile row for an accepted membership, so a non-accepted row
      // referencing a profile this device never held would retry
      // identically every cycle forever if it threw the same way the
      // accepted case above does.
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-revoked',
          profileId: revokedProfileId,
          userId: 'u-me',
          role: 'caregiver',
          status: 'revoked',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-pending',
          profileId: pendingProfileId,
          userId: 'u-me',
          role: 'caregiver',
          status: 'pending',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      // Skipped, not applied: there is nothing to retry.
      expect(await storage.getGuardiansForProfile(revokedProfileId), isEmpty);
      expect(await storage.getGuardiansForProfile(pendingProfileId), isEmpty);
    });

    test('wipeAllData empties profile_guardians before profiles (FK order)',
        () async {
      final profile =
          await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-1',
          profileId: profile.id,
          userId: 'u-me',
          role: 'primary_guardian',
          status: 'accepted',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      expect(await storage.getGuardiansForProfile(profile.id), isNotEmpty);

      await db.wipeAllData();

      expect(await storage.getProfiles(includeTombstones: true), isEmpty);
      expect(await storage.getGuardiansForProfile(profile.id), isEmpty);
    });

    group('Issue #159 review finding: upsertDayEntry update-branch '
        'provenance containment', () {
      test('an update that omits provenance (the manual/null/null default) '
          'leaves an existing non-manual row\'s source/sourceId/importId '
          'untouched', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final imported = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-01',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-1',
          importId: 'import-1',
        );
        expect(imported.source, 'clue_import');

        // Mirrors day_sheet.dart's pre-fix `_save()`: an update call that
        // supplies no provenance at all (the storage API's own defaults).
        final resaved = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-01',
          tz: 'UTC',
          flow: FlowLevel.heavy,
        );

        expect(resaved.id, imported.id, reason: 'same live row, in place');
        expect(resaved.flow, FlowLevel.heavy,
            reason: 'the actual edit still applies');
        expect(resaved.source, 'clue_import',
            reason: 'an unspecified provenance update must not reset an '
                'already-imported row to manual');
        expect(resaved.sourceId, 'clue-1');
        expect(resaved.importId, 'import-1');
      });

      test('an update that omits provenance on an already-manual row simply '
          'stays manual (nothing to contain)', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-02',
          tz: 'UTC',
          flow: FlowLevel.light,
        );
        expect(entry.source, 'manual');

        final resaved = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-02',
          tz: 'UTC',
          flow: FlowLevel.heavy,
        );
        expect(resaved.source, 'manual');
        expect(resaved.sourceId, null);
        expect(resaved.importId, null);
      });

      test('an update that supplies a genuinely different, non-default '
          'provenance triple is applied verbatim (containment only ever '
          'fires for the exact manual/null/null default triple)', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-03',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-3',
          importId: 'import-3',
        );

        final reimported = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-03',
          tz: 'UTC',
          flow: FlowLevel.medium,
          source: 'healthkit',
          sourceId: 'hk-1',
          importId: 'import-4',
        );
        expect(reimported.source, 'healthkit',
            reason: 'a genuine re-import still overwrites, since it is not '
                'the manual/null/null default triple');
        expect(reimported.sourceId, 'hk-1');
        expect(reimported.importId, 'import-4');
      });

      test('known limitation: an explicit source: \'manual\' call with no '
          'sourceId/importId is indistinguishable from the storage API\'s '
          'own default and is therefore ALSO treated as unspecified against '
          'a non-manual row -- the documented rule this containment picks '
          'trades away a true explicit-reset-to-manual signal (there is no '
          'sentinel to carry "I really mean manual" separately from "I '
          'said nothing"); day_sheet.dart never needs this because it '
          'always forwards the loaded entry\'s own provenance (item 1a)',
          () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-04',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-4',
          importId: 'import-4',
        );

        final stillImported = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-06-04',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          source: 'manual',
        );
        expect(stillImported.source, 'clue_import');
        expect(stillImported.sourceId, 'clue-4');
        expect(stillImported.importId, 'import-4');
      });
    });

    group('Issue #140 review round 2, item 2: upsertDayEntry\'s id: '
        'revival path writes localDate', () {
      test('reviving a tombstoned row at a DIFFERENT date than it was '
          'originally tombstoned at moves it to the new date instead of '
          'throwing \'day entry disappeared\'', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final original = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-07-01',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-move',
        );
        await storage.softDeleteDayEntry(
            profileId: profile.id, localDate: '2026-07-01');

        // The revival path (`id:` supplied) targets the tombstone directly
        // by id, at a DIFFERENT date than it was tombstoned at — mirrors
        // `AccountImporter._revivalIdFor` finding a row by (profileId,
        // source, sourceId) whose stored local_date differs from the plan
        // it's about to apply.
        final revived = await storage.upsertDayEntry(
          id: original.id,
          profileId: profile.id,
          localDate: '2026-07-05',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          source: 'clue_import',
          sourceId: 'clue-move',
        );

        expect(revived.id, original.id);
        expect(revived.localDate, '2026-07-05',
            reason: 'the row\'s own local_date column must move with it, '
                'not stay stuck at the tombstone\'s old date');
        expect(revived.flow, FlowLevel.heavy);
        expect(revived.deletedAt, isNull);

        // The new date now reads it back as the live entry.
        final atNewDate = await storage.getDayEntry(
            profileId: profile.id, localDate: '2026-07-05');
        expect(atNewDate?.id, original.id);
        // The old date no longer holds a live entry.
        final atOldDate = await storage.getDayEntry(
            profileId: profile.id, localDate: '2026-07-01');
        expect(atOldDate, isNull);
      });
    });

    group('findDayEntryBySource (Issue #140 review round 2, item 7)', () {
      test('finds a live row', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-08-01',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-live',
        );

        final found = await storage.findDayEntryBySource(
          profileId: profile.id,
          source: 'clue_import',
          sourceId: 'clue-live',
        );
        expect(found?.id, entry.id);
      });

      test('finds a tombstoned row', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-08-02',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-tomb',
        );
        await storage.softDeleteDayEntry(
            profileId: profile.id, localDate: '2026-08-02');

        final found = await storage.findDayEntryBySource(
          profileId: profile.id,
          source: 'clue_import',
          sourceId: 'clue-tomb',
        );
        expect(found?.id, entry.id);
        expect(found?.deletedAt, isNotNull);
      });

      test('a null sourceId returns null without querying — the server\'s '
          'partial unique index only applies where source_id is not null',
          () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-08-03',
          tz: 'UTC',
          flow: FlowLevel.light,
        );

        final found = await storage.findDayEntryBySource(
          profileId: profile.id,
          source: 'manual',
          sourceId: null,
        );
        expect(found, isNull);
      });

      test('more than one local match does not throw — reads as "found '
          'one", never a StateError (this store carries no local '
          'uniqueness constraint on (profile_id, source, source_id), only '
          'the server does)', () async {
        final profile =
            await storage.upsertProfile(displayName: 'P', isMinor: false);
        final first = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-08-04',
          tz: 'UTC',
          flow: FlowLevel.light,
          source: 'clue_import',
          sourceId: 'clue-dup',
        );
        final second = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-08-05',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          source: 'clue_import',
          sourceId: 'clue-dup',
        );

        final found = await storage.findDayEntryBySource(
          profileId: profile.id,
          source: 'clue_import',
          sourceId: 'clue-dup',
        );
        expect(found, isNotNull);
        expect({first.id, second.id}, contains(found!.id));
      });
    });
  });

  group('migrations', () {
    test('a real v1 fixture (raw DDL, in memory) upgrades to v2 with every '
        'row intact, dirty = false, local_rev = 0 and default sync_state',
        () async {
      final raw = sqlite3.sqlite3.openInMemory();
      seedV1(raw);
      final db = LunarLogDatabase(NativeDatabase.opened(raw));
      addTearDown(() => db.close());
      await expectFullyUpgraded(db);

      // The upgraded database is fully usable: local writes and sync
      // applies work against the migrated rows.
      final edited = await db.storage.upsertDayEntry(
          profileId: kV1ProfileId,
          localDate: '2026-07-01',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(edited.id, kV1EntryId);
      expect(edited.dirty, isTrue);
      expect(edited.localRev, 1);
    });

    test('a real v1 fixture on a file upgrades to v2 (plain sqlite)',
        () async {
      final dir = await freshTempDir('migration_file');
      final file = File('${dir.path}${Platform.pathSeparator}v1.db');
      final raw = sqlite3.sqlite3.open(file.path);
      seedV1(raw);
      raw.close();

      final db = LunarLogDatabase(NativeDatabase(file));
      addTearDown(() => db.close());
      await expectFullyUpgraded(db);
    });

    test('an upgrade step failing after the first addColumn leaves '
        'user_version = 1, no new columns and the rows intact; a clean '
        'reopen completes the upgrade', () async {
      final dir = await freshTempDir('migration_fail');
      final file = File('${dir.path}${Platform.pathSeparator}v1.db');
      final raw = sqlite3.sqlite3.open(file.path);
      seedV1(raw);
      raw.close();

      final completedSteps = <String>[];
      final failing = LunarLogDatabase(NativeDatabase(file))
        ..migrationStepHook = (step) async {
          completedSteps.add(step);
          if (step == 'profiles.dirty') {
            throw StateError('injected failure after the first addColumn');
          }
        };
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );
      await failing.close();
      expect(completedSteps, ['profiles.dirty'],
          reason: 'the first DDL step ran before the injected failure');

      // Inspect the file with a raw handle: nothing half-applied.
      final check = sqlite3.sqlite3.open(file.path);
      try {
        expect(check.select('PRAGMA user_version').first.values.first, 1);
        final profileCols = check
            .select('PRAGMA table_info(profiles)')
            .map((r) => r['name'])
            .toSet();
        expect(profileCols, isNot(contains('dirty')),
            reason: 'the addColumn must have been rolled back');
        expect(profileCols, isNot(contains('local_rev')));
        final entryCols = check
            .select('PRAGMA table_info(day_entries)')
            .map((r) => r['name'])
            .toSet();
        expect(entryCols, isNot(contains('dirty')));
        final tables = check
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((r) => r['name'])
            .toSet();
        expect(tables, isNot(contains('sync_state')));
        expect(check.select('SELECT COUNT(*) AS n FROM profiles').first['n'], 1);
        expect(
            check.select('SELECT COUNT(*) AS n FROM day_entries').first['n'], 2);
        expect(check.select('SELECT note FROM day_entries WHERE id = ?',
            [kV1EntryId]).first['note'], 'keep me');
      } finally {
        check.close();
      }

      // Clean reopen: the upgrade retries and completes.
      final db = LunarLogDatabase(NativeDatabase(file));
      addTearDown(() => db.close());
      await expectFullyUpgraded(db);
    });

    test('a database already at the latest version does not re-run the '
        'upgrade on reopen', () async {
      final dir = await freshTempDir('migration_noop');
      final file = File('${dir.path}${Platform.pathSeparator}v4.db');
      final first = LunarLogDatabase(NativeDatabase(file));
      await first.storage.upsertProfile(displayName: 'P', isMinor: false);
      await first.close();

      final steps = <String>[];
      final second = LunarLogDatabase(NativeDatabase(file))
        ..migrationStepHook = (step) async => steps.add(step);
      addTearDown(() => second.close());
      expect(await userVersion(second), 13);
      expect(steps, isEmpty);
      expect(await second.storage.getProfiles(), hasLength(1));
    });

    test('a real v3 fixture (raw DDL, in memory) upgrades to v4 with rows '
        'in profiles, day_entries and profile_guardians preserved and the '
        'three new columns null', () async {
      final raw = sqlite3.sqlite3.openInMemory();
      seedV3(raw);
      final db = LunarLogDatabase(NativeDatabase.opened(raw));
      addTearDown(() => db.close());

      expect(await userVersion(db), 13);
      expect(await columnsOf(db, 'profiles'),
          containsAll(['birth_year', 'relationship', 'transferred_at', 'mode']));

      final profile =
          (await db.storage.getProfiles(includeTombstones: true)).single;
      expect(profile.id, kV3ProfileId);
      expect(profile.displayName, 'V3 Profile');
      expect(profile.birthYear, isNull);
      expect(profile.relationship, isNull);
      expect(profile.transferredAt, isNull);
      expect(profile.mode, 'standard',
          reason: 'the v5 care-mode column defaults to standard');

      final entries = await db.storage
          .getDayEntries(profileId: kV3ProfileId, includeTombstones: true);
      expect(entries.map((e) => e.id), [kV3EntryId]);
      expect(entries.single.loggedByUserId, 'u-v3');

      final guardians = await db.storage.getGuardiansForProfile(kV3ProfileId);
      expect(guardians.map((g) => g.id), [kV3GuardianId]);
      expect(guardians.single.role, 'primary_guardian');

      // The upgraded database is fully usable: a local write persists the
      // new columns.
      final edited = await db.storage.upsertProfile(
          id: kV3ProfileId,
          displayName: 'V3 Profile',
          isMinor: false,
          mode: 'teen',
          birthYear: 2015,
          relationship: 'daughter');
      expect(edited.birthYear, 2015);
      expect(edited.relationship, 'daughter');
      expect(edited.mode, 'teen');
    });

    test('a v4 fixture upgrades to v5 by adding profiles.mode, preserving '
        'every v4 column and defaulting mode to standard (Issue #131)',
        () async {
      final raw = sqlite3.sqlite3.openInMemory();
      seedV4(raw);
      final db = LunarLogDatabase(NativeDatabase.opened(raw));
      addTearDown(() => db.close());

      expect(await userVersion(db), 13);
      expect(await columnsOf(db, 'profiles'),
          containsAll(['birth_year', 'relationship', 'transferred_at', 'mode']));

      final profile =
          (await db.storage.getProfiles(includeTombstones: true)).single;
      expect(profile.id, kV3ProfileId);
      expect(profile.displayName, 'V4 Profile');
      expect(profile.birthYear, 2013);
      expect(profile.relationship, 'daughter');
      expect(profile.transferredAt, isNull);
      expect(profile.mode, 'standard',
          reason: 'a pre-#131 row carries no mode; the default applies');

      // The upgraded database accepts mode writes and they persist.
      final edited = await db.storage.upsertProfile(
          id: kV3ProfileId,
          displayName: 'V4 Profile',
          isMinor: false,
          mode: 'irregular',
          birthYear: 2013,
          relationship: 'daughter');
      expect(edited.mode, 'irregular');
    });

    test('a v7 fixture upgrades to v11 by adding profile_modes and '
        'cycle_overrides with their sync_state cursors, preserving every '
        'row (Issue #188)', () async {
      final raw = sqlite3.sqlite3.openInMemory();
      seedV7(raw);
      final db = LunarLogDatabase(NativeDatabase.opened(raw));
      addTearDown(() => db.close());

      expect(await userVersion(db), 13);
      expect(await columnsOf(db, 'profile_modes'),
          containsAll(['profile_id', 'mode', 'mode_started_on',
              'birth_control_method', 'birth_control_started_on',
              'birth_control_stopped_on', 'health_sync_consent',
              'updated_at', 'dirty', 'local_rev']));
      expect(await columnsOf(db, 'cycle_overrides'),
          containsAll(['id', 'profile_id', 'cycle_start_date',
              'excluded_from_average', 'manual_start', 'note_id',
              'deleted_at', 'updated_at', 'dirty', 'local_rev']));
      expect(await columnsOf(db, 'sync_state'),
          containsAll(['cursor_profile_modes', 'cursor_cycle_overrides']));

      // Every v7 row survived, care mode and provenance included.
      final profile =
          (await db.storage.getProfiles(includeTombstones: true)).single;
      expect(profile.id, kV3ProfileId);
      expect(profile.mode, 'teen',
          reason: '#131''s care-mode axis is untouched by the #188 tables');
      final entry = (await db.storage.getDayEntries(
              profileId: kV3ProfileId, includeTombstones: true))
          .single;
      expect(entry.source, 'clue_import');
      expect(entry.sourceId, 'clue-42');
      final observation = (await db.storage.getObservationsForDayEntry(
              kV3EntryId,
              includeTombstones: true))
          .single;
      expect(observation.code, 'cramps');
      final state = await db.storage.readSyncState();
      expect(state.boundUserId, 'u-v7');
      expect(state.cursorProfiles, 11);
      expect(state.cursorObservations, 13);
      expect(state.cursorProfileModes, 0,
          reason: 'the new cursors start at zero');
      expect(state.cursorCycleOverrides, 0);

      // The upgraded database is immediately usable for the new tables.
      final mode = await db.storage.upsertProfileMode(
          profileId: kV3ProfileId, mode: 'perimenopause');
      expect(mode.dirty, isTrue);
      expect((await db.storage.getProfileMode(kV3ProfileId))!.mode,
          'perimenopause');
      final override = await db.storage.upsertCycleOverride(
          profileId: kV3ProfileId,
          cycleStartDate: '2026-08-01',
          excludedFromAverage: true);
      expect(override.dirty, isTrue);
      expect(await db.storage.getCycleOverridesForProfile(kV3ProfileId),
          hasLength(1));
    });

    test('a v7 fixture upgrades to v12 by adding the first-class day-entry '
        'pms column (Issue #220), preserving every row, and the upgraded '
        'database immediately logs and reads a PMS day', () async {
      final raw = sqlite3.sqlite3.openInMemory();
      seedV7(raw);
      final db = LunarLogDatabase(NativeDatabase.opened(raw));
      addTearDown(() => db.close());

      expect(await userVersion(db), 13);
      expect(await columnsOf(db, 'day_entries'), containsAll(['pms']));
      // The new column defaults to false for every already-stored row.
      final existing = await db.storage.getDayEntries(
          profileId: kV3ProfileId, includeTombstones: true);
      expect(existing.single.pms, isFalse,
          reason: 'the v12 addColumn back-fills existing rows to false');

      // The upgraded database is immediately usable for the new marker:
      // log a PMS-only day, read it back, tombstone it, and watch the
      // payload rule hold locally too.
      final saved = await db.storage.upsertDayEntry(
        profileId: kV3ProfileId,
        localDate: '2026-09-10',
        tz: 'UTC',
        flow: FlowLevel.none,
        pms: true,
      );
      expect(saved.pms, isTrue);
      expect((await db.storage.getDayEntries(profileId: kV3ProfileId))
          .where((e) => e.localDate == '2026-09-10')
          .single
          .pms,
          isTrue);
      await db.storage.softDeleteDayEntry(
          profileId: kV3ProfileId, localDate: '2026-09-10');
      final tombstone = (await db.storage.getDayEntries(
              profileId: kV3ProfileId, includeTombstones: true))
          .where((e) => e.localDate == '2026-09-10')
          .single;
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.pms, isFalse,
          reason: 'a local tombstone carries no payload, the marker included');
    });

    test('an upgrade step failing on profiles.relationship leaves the '
        'database at v3 with no partially-added v4 column, and the next '
        'open retries cleanly', () async {
      final dir = await freshTempDir('migration_fail_v4');
      final file = File('${dir.path}${Platform.pathSeparator}v3.db');
      final raw = sqlite3.sqlite3.open(file.path);
      seedV3(raw);
      raw.close();

      final completedSteps = <String>[];
      final failing = LunarLogDatabase(NativeDatabase(file))
        ..migrationStepHook = (step) async {
          completedSteps.add(step);
          if (step == 'profiles.relationship') {
            throw StateError('injected failure after the second addColumn');
          }
        };
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );
      await failing.close();
      expect(completedSteps, ['profiles.birth_year', 'profiles.relationship'],
          reason: 'birth_year landed before the injected failure on '
              'relationship');

      // Inspect the file with a raw handle: nothing half-applied.
      final check = sqlite3.sqlite3.open(file.path);
      try {
        expect(check.select('PRAGMA user_version').first.values.first, 3);
        final profileCols = check
            .select('PRAGMA table_info(profiles)')
            .map((r) => r['name'])
            .toSet();
        expect(profileCols, isNot(contains('birth_year')),
            reason: 'the addColumn must have been rolled back');
        expect(profileCols, isNot(contains('relationship')));
        expect(profileCols, isNot(contains('transferred_at')));
        expect(check.select('SELECT COUNT(*) AS n FROM profiles').first['n'], 1);
        expect(
            check.select('SELECT COUNT(*) AS n FROM day_entries').first['n'], 1);
        expect(
            check.select('SELECT COUNT(*) AS n FROM profile_guardians').first['n'],
            1);
      } finally {
        check.close();
      }

      // Clean reopen: the upgrade retries and completes.
      final db = LunarLogDatabase(NativeDatabase(file));
      addTearDown(() => db.close());
      expect(await userVersion(db), 13);
      expect(await columnsOf(db, 'profiles'),
          containsAll(['birth_year', 'relationship', 'transferred_at']));
      final profile =
          (await db.storage.getProfiles(includeTombstones: true)).single;
      expect(profile.id, kV3ProfileId);
      expect(profile.birthYear, isNull);
      expect(profile.relationship, isNull);
      expect(profile.transferredAt, isNull);
      expect(profile.mode, 'standard',
          reason: 'the retried upgrade lands the v5 column at its default');
    });
  });

  group('database factory', () {
    test('opens via the injected executor builder', () async {
      final factory = LunarLogDbFactory(
        databasePath: 'test:in-memory',
        executorBuilder: () => NativeDatabase.memory(),
      );
      final db = await factory.open();
      addTearDown(() => db.close());

      final profile =
          await db.storage.upsertProfile(displayName: 'Web', isMinor: true);
      expect((await db.storage.getProfiles()).single.id, profile.id);
    });

    test('garbage existing file raises DatabaseQuarantineError and is never '
        'wiped or recreated', () async {
      final dir = await freshTempDir('quarantine');
      final file = File('${dir.path}${Platform.pathSeparator}corrupt.db');
      final garbage = 'this is definitely not a sqlite database file'.codeUnits;
      file.writeAsBytesSync(garbage);

      final factory = nativeDbFactory(file: file);
      await expectLater(
          factory.open(), throwsA(isA<DatabaseQuarantineError>()));

      expect(file.existsSync(), isTrue, reason: 'file must not be deleted');
      expect(file.readAsBytesSync(), garbage,
          reason: 'file content must be untouched');
    });

    test('first-run creation over a non-existent file is normal', () async {
      final dir = await freshTempDir('firstrun');
      final file = File('${dir.path}${Platform.pathSeparator}fresh.db');
      final factory = nativeDbFactory(file: file);
      final db = await factory.open();
      await db.close();
      expect(file.existsSync(), isTrue, reason: 'fresh database file created');
    });
  });
}
