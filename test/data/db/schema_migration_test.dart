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
/// dump. A mismatch here is caught by the `schema version is 5` assertion
/// in `db_test.dart`, not by this file.
const int _kCurrentSchemaVersion = 5;

/// Every schema version older than [_kCurrentSchemaVersion] that has a dump
/// under `drift_schemas/` — i.e. every version this harness can start an
/// upgrade from. Step 4 of the regeneration procedure above is: add the new
/// pre-bump version here.
const List<int> _kOlderSchemaVersions = [1, 2, 3, 4];

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
  }
}
