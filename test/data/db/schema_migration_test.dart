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

import 'generated_migrations/schema.dart';

/// The current schema version, kept in lockstep with
/// `LunarLogDatabase.schemaVersion` and the highest `drift_schemas/*.json`
/// dump. A mismatch here is caught by the `schema version is 8` assertion
/// in `db_test.dart`, not by this file.
const int _kCurrentSchemaVersion = 9;

/// Every schema version older than [_kCurrentSchemaVersion] that has a dump
/// under `drift_schemas/` — i.e. every version this harness can start an
/// upgrade from. Step 4 of the regeneration procedure above is: add the new
/// pre-bump version here.
const List<int> _kOlderSchemaVersions = [1, 2, 3, 4, 5, 6, 7];

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
  }
}
