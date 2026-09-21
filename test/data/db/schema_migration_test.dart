/// Schema-verification harness (issue #200).
///
/// Where `db_test.dart`'s `migrationStepHook`-based `migrations` group
/// proves that each upgrade step runs in the right order and rolls back
/// transactionally on failure, this file proves the *result*: that walking
/// every historical `onUpgradeSteps` path (v1→v5, v2→v5, v3→v5, v4→v5) via drift's
/// `SchemaVerifier` lands on a live schema that is structurally identical to
/// a schema dumped straight from the current `lib/data/db/db.dart` — not
/// just that the migration ran without throwing. Neither file supersedes
/// the other; both are kept (last acceptance criterion of #200).
///
/// `SchemaVerifier.startAt(version)` builds its starting database purely
/// from the generated `generated_migrations/schema_v<N>.dart` classes
/// (themselves generated from the `drift_schemas/drift_schema_v<N>.json`
/// dumps) — i.e. from `createAll()` over the declared tables/columns only.
/// It does **not** run the real historical `onCreate`, so any schema state
/// that only ever existed because `onCreate` set it up imperatively (a raw
/// `customStatement`, not a drift-DSL table/column/index) is invisible to
/// both the dump and this starting fixture. `kLiveDayEntryIndexSql` is
/// exactly that: it has never been anything but a `customStatement` inside
/// `onCreate`, so `SchemaVerifier.migrateAndValidate` alone cannot catch a
/// regression in it — the expected-schema side of that comparison is
/// equally blind to it. Hence the dedicated index assertion below,
/// alongside (not instead of) the structural `migrateAndValidate` check.
///
/// Regenerating this harness after a schema bump — see AGENTS.md's Codegen
/// bullet for the short version:
///   1. Bump `schemaVersion` and add the new `onUpgradeSteps` block in
///      `lib/data/db/db.dart` as usual, then
///      `dart run build_runner build --delete-conflicting-outputs`.
///   2. `dart run drift_dev schema dump lib/data/db/db.dart
///      drift_schemas/drift_schema_vN.json` (N = the new current version).
///   3. `dart run drift_dev schema generate drift_schemas/
///      test/data/db/generated_migrations/` to refresh the generated
///      migration-test helpers for *every* version (overwrites all of
///      `generated_migrations/`).
///   4. Add `<N - 1>` to the `_kOlderSchemaVersions` list below and re-run
///      `flutter test`.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/tables.dart' show FlowLevel;
import 'package:lunarlog/data/sync/row_codec.dart' show encodeDayEntry, encodeProfile;

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v18.dart' as v18;
import 'generated_migrations/schema_v27.dart' as v27;
import 'generated_migrations/schema_v7.dart' as v7;

/// The current schema version, kept in lockstep with
/// `LunarLogDatabase.schemaVersion` and the highest `drift_schemas/*.json`
/// dump. A mismatch here is caught by the `schema version is 20` assertion
/// in `db_test.dart`, not by this file.
const int _kCurrentSchemaVersion = 29;

/// Every schema version older than [_kCurrentSchemaVersion] that has a dump
/// under `drift_schemas/` — i.e. every version this harness can start an
/// upgrade from. Step 4 of the regeneration procedure above is: add the new
/// pre-bump version here.
const List<int> _kOlderSchemaVersions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28];

void main() {
  // Several tests below open more than one LunarLogDatabase instance across
  // the file; matches the same opt-out db_test.dart uses and for the same
  // reason (drift.simonbinder.eu/faq).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final verifier = SchemaVerifier(GeneratedHelper());

  for (final fromVersion in _kOlderSchemaVersions) {
    test(
        'upgrading from v$fromVersion lands on a schema identical to the '
        'dumped v$_kCurrentSchemaVersion schema', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      // Throws SchemaMismatch if the live schema after onUpgradeSteps
      // differs from a database built fresh from
      // drift_schemas/drift_schema_v5.json — table/column/type/constraint
      // additions, removals or changes alike.
      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
    });

    test(
        'upgrading from v$fromVersion recreates the live-entry partial '
        'unique index, not just a fresh onCreate', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      // migrateAndValidate's structural comparison can't see this index at
      // all (see the file doc comment) — assert it directly instead.
      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final index = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'uq_day_entries_profile_date_live'",
          )
          .get();
      expect(index, hasLength(1),
          reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must leave '
              'uq_day_entries_profile_date_live in place; this harness '
              'starts from a schema-dump fixture, which — unlike a real '
              'device\'s onCreate — never creates it, so onUpgradeSteps is '
              'the only thing that can');
    });

    test(
        'upgrading from v$fromVersion creates the observations table '
        '(Issue #240) with its column-family present', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final table = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'observations'",
          )
          .get();
      expect(table, hasLength(1),
          reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create '
              'the observations table (Issue #240)');

      final columns =
          await db.customSelect("PRAGMA table_info('observations')").get();
      final columnNames =
          columns.map((row) => row.data['name'] as String).toSet();
      expect(
        columnNames,
        containsAll([
          'id',
          'day_entry_id',
          'profile_id',
          'local_date',
          'category',
          'code',
          'intensity',
          'source',
          'dirty',
          'local_rev',
        ]),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must land the '
            'full observations column shape, not just an empty table',
      );
    });

    test(
        'upgrading from v$fromVersion adds source/source_id/import_id to '
        'day_entries and import_id to observations (Issue #159)', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);

      final dayEntryColumns =
          await db.customSelect("PRAGMA table_info('day_entries')").get();
      final dayEntryColumnNames =
          dayEntryColumns.map((row) => row.data['name'] as String).toSet();
      expect(
        dayEntryColumnNames,
        containsAll(['source', 'source_id', 'import_id']),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'day_entries.source/source_id/import_id (Issue #159)',
      );

      final observationColumns =
          await db.customSelect("PRAGMA table_info('observations')").get();
      final observationColumnNames =
          observationColumns.map((row) => row.data['name'] as String).toSet();
      expect(
        observationColumnNames,
        contains('import_id'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'observations.import_id (Issue #159)',
      );
    });

    test(
        'upgrading from v$fromVersion creates the four issue #197 read-path '
        'indexes — same invisible-to-migrateAndValidate situation as '
        'uq_day_entries_profile_date_live above', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      // A real device at v8+ already carries these indexes (its own v8
      // upgrade, or its v8 onCreate, created them) — but the dump fixture
      // this harness starts from is drift-DSL-only and never includes
      // customStatement indexes, so for fromVersion >= 8 the `from < 8`
      // block that would create them is correctly skipped and the
      // assertion below would fail on fixture grounds alone, not because
      // the upgrade is wrong. Seed what the real device already has, so
      // this test keeps proving the later steps preserve them.
      if (fromVersion >= 8) {
        await db.customStatement(kDayEntriesProfileDateIndexSql);
        await db.customStatement(kDayEntriesDirtyIndexSql);
        await db.customStatement(kDayEntriesUpdatedAtIndexSql);
        await db.customStatement(kProfileGuardiansProfileIndexSql);
      }
      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
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
        ]),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create all '
            'four issue #197 indexes',
      );
    });

    test(
        'upgrading from v$fromVersion creates the two issue #625 (LLA-101) '
        'observations indexes — same invisible-to-migrateAndValidate '
        'situation as uq_day_entries_profile_date_live above', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      // Every fixture in _kOlderSchemaVersions is < 19 (the version these
      // two indexes were introduced at), so the `_upgradeToV19` step always
      // runs here — unlike the four issue #197 indexes above, no
      // pre-seeding is needed for any fromVersion this loop covers.
      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final indexNames = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        indexNames,
        containsAll(['ix_observations_day_entry_id', 'ix_observations_profile_id']),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create both '
            'issue #625 observations indexes',
      );
    });

    test(
        'upgrading from v$fromVersion creates the profile_modes and '
        'cycle_overrides tables (Issue #188) with their column families and '
        'both sync_state cursors', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('profile_modes', 'cycle_overrides')",
          )
          .get();
      expect(tables, hasLength(2),
          reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create '
              'both Issue #188 tables');

      final modeColumns =
          await db.customSelect("PRAGMA table_info('profile_modes')").get();
      expect(
        modeColumns.map((row) => row.data['name'] as String),
        containsAll([
          'profile_id',
          'mode',
          'mode_started_on',
          'birth_control_method',
          'birth_control_started_on',
          'birth_control_stopped_on',
          'health_sync_consent',
          'updated_at',
          'dirty',
          'local_rev',
        ]),
        reason: 'the full profile_modes column shape must land',
      );

      final overrideColumns =
          await db.customSelect("PRAGMA table_info('cycle_overrides')").get();
      expect(
        overrideColumns.map((row) => row.data['name'] as String),
        containsAll([
          'id',
          'profile_id',
          'cycle_start_date',
          'excluded_from_average',
          'manual_start',
          'note_id',
          'deleted_at',
          'updated_at',
          'dirty',
          'local_rev',
        ]),
        reason: 'the full cycle_overrides column shape must land',
      );

      final syncStateColumns =
          await db.customSelect("PRAGMA table_info('sync_state')").get();
      expect(
        syncStateColumns.map((row) => row.data['name'] as String),
        containsAll(['cursor_profile_modes', 'cursor_cycle_overrides']),
        reason: 'both Issue #188 pull cursors must land on sync_state',
      );
    });

    test(
        'upgrading from v$fromVersion keeps the Issue #218 onboarding '
        'cycle-fact columns on profiles (no column loss in the v11 rebase)',
        () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final profileColumns =
          await db.customSelect("PRAGMA table_info('profiles')").get();
      expect(
        profileColumns.map((row) => row.data['name'] as String),
        containsAll([
          'last_period_start',
          'typical_cycle_length_days',
          'typical_period_length_days',
        ]),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must preserve '
            'the Issue #218 cycle-fact columns; the v11 rebase moved the '
            'Issue #128 tables to their own step and must not drop these',
      );
    });

    test(
        'upgrading from v$fromVersion creates the care_notes and '
        'visit_prep_items tables (Issue #128) with their column families, '
        'both sync_state cursors, and both profile_id indexes', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      // Same fixture-vs-real-device gap as the four issue #197 indexes
      // above: the two Issue #128 profile_id indexes are customStatement
      // creations invisible to the dump fixture this harness starts from,
      // and a fromVersion >= 11 upgrade correctly skips the v11 step that
      // would recreate them. Seed what the real device already has so
      // this test keeps proving the later steps preserve them.
      if (fromVersion >= 11) {
        await db.customStatement(kCareNotesProfileIndexSql);
        await db.customStatement(kVisitPrepItemsProfileIndexSql);
      }
      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('care_notes', 'visit_prep_items')",
          )
          .get();
      expect(tables, hasLength(2),
          reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create '
              'both Issue #128 tables');

      final noteColumns =
          await db.customSelect("PRAGMA table_info('care_notes')").get();
      expect(
        noteColumns.map((row) => row.data['name'] as String),
        containsAll([
          'id',
          'profile_id',
          'body',
          'updated_at',
          'deleted_at',
          'dirty',
          'local_rev',
          'logged_by_user_id',
          'last_modified_by_user_id',
        ]),
        reason: 'the full care_notes column shape must land',
      );

      final prepColumns =
          await db.customSelect("PRAGMA table_info('visit_prep_items')").get();
      expect(
        prepColumns.map((row) => row.data['name'] as String),
        containsAll([
          'id',
          'profile_id',
          'body',
          'is_checked',
          'checked_by_user_id',
          'checked_at',
          'updated_at',
          'deleted_at',
          'dirty',
          'local_rev',
          'logged_by_user_id',
          'last_modified_by_user_id',
        ]),
        reason: 'the full visit_prep_items column shape must land',
      );

      final syncStateColumns =
          await db.customSelect("PRAGMA table_info('sync_state')").get();
      expect(
        syncStateColumns.map((row) => row.data['name'] as String),
        containsAll(['cursor_care_notes', 'cursor_visit_prep_items']),
        reason: 'both Issue #128 pull cursors must land on sync_state',
      );

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
          'ix_care_notes_profile_id',
          'ix_visit_prep_items_profile_id',
        ]),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create both '
            'Issue #128 profile_id indexes',
      );
    });

    test(
        'upgrading from v$fromVersion adds cursor_profile_guardians to '
        'sync_state (Issue #525)', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);
      final syncStateColumns =
          await db.customSelect("PRAGMA table_info('sync_state')").get();
      expect(
        syncStateColumns.map((row) => row.data['name'] as String),
        contains('cursor_profile_guardians'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'sync_state.cursor_profile_guardians (Issue #525)',
      );
    });

    test(
        'upgrading from v$fromVersion adds server_version to '
        'profile_guardians and access_revoked_at to profiles (Issue #635)',
        () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);

      final guardianColumns = await db
          .customSelect("PRAGMA table_info('profile_guardians')")
          .get();
      expect(
        guardianColumns.map((row) => row.data['name'] as String),
        contains('server_version'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'profile_guardians.server_version (Issue #635, LLA-035)',
      );

      final profileColumns =
          await db.customSelect("PRAGMA table_info('profiles')").get();
      expect(
        profileColumns.map((row) => row.data['name'] as String),
        contains('access_revoked_at'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'profiles.access_revoked_at (Issue #635, LLA-041)',
      );
    });

    test(
        'upgrading from v$fromVersion adds pms_unconfirmed to day_entries, '
        'units_unconfirmed to profiles, and cursor_deleted_profiles to '
        'sync_state (Issue #637 LLA-039, Issue #597)', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);

      final dayEntryColumns =
          await db.customSelect("PRAGMA table_info('day_entries')").get();
      expect(
        dayEntryColumns.map((row) => row.data['name'] as String),
        contains('pms_unconfirmed'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'day_entries.pms_unconfirmed (Issue #637, LLA-039)',
      );

      final profileColumns =
          await db.customSelect("PRAGMA table_info('profiles')").get();
      expect(
        profileColumns.map((row) => row.data['name'] as String),
        contains('units_unconfirmed'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'profiles.units_unconfirmed (Issue #637, LLA-039)',
      );

      final syncStateColumns =
          await db.customSelect("PRAGMA table_info('sync_state')").get();
      expect(
        syncStateColumns.map((row) => row.data['name'] as String),
        contains('cursor_deleted_profiles'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'sync_state.cursor_deleted_profiles (Issue #597)',
      );
    });

    test(
        'upgrading from v$fromVersion creates the day_entry_history table '
        '(Issue #170) with its column family, its sync_state cursor, and '
        'its profile/recency index', () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);

      final columns =
          await db.customSelect("PRAGMA table_info('day_entry_history')").get();
      expect(
        columns.map((row) => row.data['name'] as String),
        containsAll([
          'id',
          'entry_id',
          'profile_id',
          'changed_by_user_id',
          'changed_at',
          'change_kind',
          'changed_fields',
        ]),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create the '
            'full day_entry_history column shape (Issue #170) — no '
            'dirty/local_rev: the table is pull-only',
      );

      final syncStateColumns =
          await db.customSelect("PRAGMA table_info('sync_state')").get();
      expect(
        syncStateColumns.map((row) => row.data['name'] as String),
        contains('cursor_day_entry_history'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must add '
            'sync_state.cursor_day_entry_history (Issue #170)',
      );

      final indexNames = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        indexNames,
        contains('ix_day_entry_history_profile_changed_at'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create the '
            'issue #170 feed index (a customStatement creation invisible '
            'to migrateAndValidate, same situation as the live-entry '
            'partial index above)',
      );
    });

    test(
        'upgrading from v$fromVersion creates the health_export_ledger table '
        '(Issue #936) with its id/provenance columns and its profile index',
        () async {
      final connection = await verifier.startAt(fromVersion);
      final db = LunarLogDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _kCurrentSchemaVersion);

      final columns =
          await db.customSelect("PRAGMA table_info('health_export_ledger')").get();
      expect(
        columns.map((row) => row.data['name'] as String).toSet(),
        {
          'record_id',
          'profile_id',
          'source_row_id',
          'kind',
          'local_date',
          'exported_at',
        },
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create the '
            'full device-local export-ledger shape (ids/provenance only)',
      );

      final indexNames = (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        indexNames,
        contains('ix_health_export_ledger_profile_id'),
        reason: 'v$fromVersion -> v$_kCurrentSchemaVersion must create the '
            'issue #936 profile index (a customStatement creation invisible '
            'to migrateAndValidate, same situation as the live-entry '
            'partial index above)',
      );
    });
  }

  group('issue #637 review, bug 2: the unconfirmed backfill is gated to '
      'devices genuinely crossing v12/v16, not every device at v20', () {
    test('a device already past v16 (v18) before this journey began gets '
        'NO unitsUnconfirmed/pmsUnconfirmed marker at all — a dirty row '
        'and a clean row both push their real bbt_unit/weight_unit/pms '
        'values normally', () async {
      final schema = await verifier.schemaAt(18);
      final seedDb = v18.DatabaseAtV18(schema.newConnection());
      // A dirty row (the exact LLA-039 precondition: dirty for an
      // unrelated reason) and a clean row, both with real, non-default
      // preference values a genuine v16+ device would actually have.
      await seedDb.customStatement(
        "INSERT INTO profiles (id, display_name, is_minor, created_at, "
        "updated_at, bbt_unit, weight_unit, dirty) VALUES "
        "('01J000000000000000000000D1', 'Dirty', 0, "
        "'2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z', "
        "'fahrenheit', 'lb', 1)",
      );
      await seedDb.customStatement(
        "INSERT INTO profiles (id, display_name, is_minor, created_at, "
        "updated_at, bbt_unit, weight_unit, dirty) VALUES "
        "('01J000000000000000000000C1', 'Clean', 0, "
        "'2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z', "
        "'fahrenheit', 'lb', 0)",
      );
      await seedDb.customStatement(
        "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, "
        "updated_at, pms, dirty, source) VALUES "
        "('01J000000000000000000000E1', '01J000000000000000000000D1', "
        "'2026-01-02', 'UTC', 'medium', '2026-01-01T00:00:00.000000Z', "
        "1, 1, 'manual')",
      );
      await seedDb.close();

      final testedDb = LunarLogDatabase(schema.newConnection());
      addTearDown(testedDb.close);
      await verifier.migrateAndValidate(testedDb, _kCurrentSchemaVersion);

      final profiles = await testedDb.storage.getProfiles();
      final dirtyProfile =
          profiles.firstWhere((p) => p.id == '01J000000000000000000000D1');
      final cleanProfile =
          profiles.firstWhere((p) => p.id == '01J000000000000000000000C1');
      expect(dirtyProfile.unitsUnconfirmed, isNot(true),
          reason: 'a device already past v16 must never get the marker — '
              'its bbt_unit/weight_unit are real, synced data');
      expect(cleanProfile.unitsUnconfirmed, isNot(true));

      final dirtyPayload = encodeProfile(dirtyProfile);
      expect(dirtyPayload['bbt_unit'], 'fahrenheit',
          reason: 'the dirty row\'s real preference must push, not be '
              'withheld behind a marker it never should have gotten');
      expect(dirtyPayload['weight_unit'], 'lb');
      expect(encodeProfile(cleanProfile)['bbt_unit'], 'fahrenheit');

      final entry = (await testedDb.storage.getDayEntries(
              profileId: '01J000000000000000000000D1'))
          .single;
      expect(entry.pmsUnconfirmed, isNot(true));
      expect(encodeDayEntry(entry)['pms'], true,
          reason: 'the dirty entry\'s real pms must push too');
    });

    test('a device upgrading from before pms/bbt_unit/weight_unit existed '
        '(v7) marks only the rows already on the device — a fresh local '
        'row created after the upgrade is never marked', () async {
      final schema = await verifier.schemaAt(7);
      final seedDb = v7.DatabaseAtV7(schema.newConnection());
      await seedDb.customStatement(
        "INSERT INTO profiles (id, display_name, is_minor, created_at, "
        "updated_at) VALUES ('01J000000000000000000000P1', 'Old', 0, "
        "'2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z')",
      );
      await seedDb.customStatement(
        "INSERT INTO day_entries (id, profile_id, local_date, tz, flow, "
        "updated_at, source) VALUES ('01J000000000000000000000Q1', "
        "'01J000000000000000000000P1', '2026-01-02', 'UTC', 'medium', "
        "'2026-01-01T00:00:00.000000Z', 'manual')",
      );
      await seedDb.close();

      final testedDb = LunarLogDatabase(schema.newConnection());
      addTearDown(testedDb.close);
      await verifier.migrateAndValidate(testedDb, _kCurrentSchemaVersion);

      final oldProfile =
          await testedDb.storage.getProfile('01J000000000000000000000P1');
      expect(oldProfile!.unitsUnconfirmed, isTrue,
          reason: 'a row that predates v16 must be marked — its '
              'bbt_unit/weight_unit are a migration default, not real data');
      final oldEntry = (await testedDb.storage
              .getDayEntries(profileId: '01J000000000000000000000P1'))
          .single;
      expect(oldEntry.pmsUnconfirmed, isTrue,
          reason: 'a row that predates v12 must be marked — its pms is a '
              'migration default, not real data');

      // A fresh local row created after the upgrade completes — never
      // marked, because it never went through the v12/v16 backfill.
      final freshProfile = await testedDb.storage.upsertProfile(
          displayName: 'New', isMinor: false, bbtUnit: 'celsius');
      expect(freshProfile.unitsUnconfirmed, isNot(true));
      final freshEntry = await testedDb.storage.upsertDayEntry(
        profileId: freshProfile.id,
        localDate: '2026-01-03',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      expect(freshEntry.pmsUnconfirmed, isNot(true));
    });
  });

  group('issue #853: v28 adds profiles.irregular_framing and folds the '
      'legacy rival mode', () {
    test('a v27 device with stored mode=irregular rows converges to '
        'standard + irregular_framing=1; every other row keeps its mode '
        'and reads irregular_framing=null (engine default)', () async {
      final schema = await verifier.schemaAt(27);
      final seedDb = v27.DatabaseAtV27(schema.newConnection());
      await seedDb.customStatement(
        "INSERT INTO profiles (id, display_name, is_minor, mode, "
        "created_at, updated_at, dirty) VALUES "
        "('01J000000000000000000000I1', 'Legacy Irregular', 0, "
        "'irregular', '2026-01-01T00:00:00.000000Z', "
        "'2026-01-01T00:00:00.000000Z', 0)",
      );
      await seedDb.customStatement(
        "INSERT INTO profiles (id, display_name, is_minor, mode, "
        "created_at, updated_at, dirty) VALUES "
        "('01J000000000000000000000I2', 'Teen', 1, "
        "'teen', '2026-01-01T00:00:00.000000Z', "
        "'2026-01-01T00:00:00.000000Z', 0)",
      );
      await seedDb.close();

      final testedDb = LunarLogDatabase(schema.newConnection());
      addTearDown(testedDb.close);
      await verifier.migrateAndValidate(testedDb, _kCurrentSchemaVersion);

      final legacy =
          await testedDb.storage.getProfile('01J000000000000000000000I1');
      expect(legacy!.mode, 'standard',
          reason: 'the legacy rival value must not survive the upgrade');
      expect(legacy.irregularFraming, isTrue,
          reason: 'the fold must preserve the framing the stored value '
              'selected');

      final teen =
          await testedDb.storage.getProfile('01J000000000000000000000I2');
      expect(teen!.mode, 'teen');
      expect(teen.irregularFraming, isNull,
          reason: 'a never-set flag stays null (engine default), never a '
              'silent false');
    });
  });
}
