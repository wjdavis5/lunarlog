/// The drift database for lunarlog: one class, one schema version, and a
/// migration framework ready for step-by-step upgrades.
///
/// Platform differences (a plain file on mobile, WASM/IndexedDB on web)
/// live entirely in the [QueryExecutor] handed to the constructor — see
/// `db_factory.dart`, `native_db.dart` and `web_db.dart`.
library;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'storage.dart';
import 'tables.dart';

part 'db.g.dart';

/// SQL for the partial unique index backing day-entry uniqueness: at most one
/// *live* entry per (profile, date). Tombstoned rows are exempt so a date can
/// be re-created with a new ULID while the tombstone remains for sync.
const String kLiveDayEntryIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_day_entries_profile_date_live '
    'ON day_entries (profile_id, local_date) WHERE deleted_at IS NULL';

@DriftDatabase(tables: [
  Profiles,
  DayEntries,
  ProfileGuardians,
  Observations,
  AppSettings,
  SyncState,
])
class LunarLogDatabase extends _$LunarLogDatabase {
  LunarLogDatabase(super.executor);

  /// Storage-level API (upserts with monotonic updated_at, tombstone
  /// soft-deletes, UI and full-fidelity reads, and the sync API). Domain
  /// repositories build on top of this.
  late final LunarLogStorage storage = LunarLogStorage(this);

  /// Schema history:
  /// * 1 — profiles, day_entries, app_settings, live-entry partial index.
  /// * 2 — `dirty` + `local_rev` on profiles and day_entries; `sync_state`
  ///   singleton (KTD4).
  /// * 3 — `logged_by_user_id` + `last_modified_by_user_id` on day_entries;
  ///   `profile_guardians` table (Issue #8).
  /// * 4 — `birth_year` + `relationship` + `transferred_at` on profiles
  ///   (Issue #4, parent-first custodianship and ownership transfer).
  /// * 5 — `mode` on profiles (Issue #131, care modes).
  /// * 6 — `observations` table (Issue #240, the Clue tracking model's
  ///   child-table observation shape) and `cursor_observations` on
  ///   `sync_state`.
  /// * 7 — `source` + `source_id` + `import_id` on `day_entries`, and
  ///   `import_id` on `observations` (Issue #159, import-dedup provenance).
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(kLiveDayEntryIndexSql);
        },
        onUpgrade: (m, from, to) => onUpgradeSteps(m, from, to),
        beforeOpen: (details) async {
          // Enforce referential integrity for per-profile isolation (R3).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Test seam: awaited after each DDL step of an upgrade with a label for
  /// the step just completed (`profiles.dirty`, `profiles.local_rev`,
  /// `day_entries.dirty`, `day_entries.local_rev`, `sync_state`,
  /// `day_entries.logged_by_user_id`, `day_entries.last_modified_by_user_id`,
  /// `profile_guardians`, `profiles.birth_year`, `profiles.relationship`,
  /// `profiles.transferred_at`, `profiles.mode`, `day_entries.live_index`,
  /// `observations`, `sync_state.cursor_observations`). A hook that throws
  /// proves the transaction wrapper rolls the whole upgrade back. Must be
  /// set before the first query. Null in production. Issue #159 adds
  /// `day_entries.source`, `day_entries.source_id`, `day_entries.import_id`,
  /// `observations.import_id`.
  @visibleForTesting
  Future<void> Function(String completedStep)? migrationStepHook;

  /// Step-by-step migration steps, one `if (from < n)` block per version.
  ///
  /// Drift 2.34.3 does **not** wrap `onUpgrade` in a transaction: the
  /// runner (`drift/src/runtime/executor/helpers/engines.dart`,
  /// `_runMigrations`) calls `beforeOpen` directly and only writes the new
  /// `user_version` after it returns. Without the explicit `transaction()`
  /// below, a failure after the first `addColumn` would leave
  /// `user_version = 1` with half-applied DDL, and the next open would fail
  /// again on the already-present column — quarantining the install
  /// forever. With it, a failing step rolls everything back and the next
  /// launch retries from a clean v1.
  ///
  /// Kept as a separate overridable method so tests can prove the migration
  /// path preserves rows and sync columns.
  @visibleForTesting
  Future<void> onUpgradeSteps(Migrator m, int from, int to) async {
    if (from < 2) {
      await transaction(() async {
        await m.addColumn(profiles, profiles.dirty);
        await migrationStepHook?.call('profiles.dirty');
        await m.addColumn(profiles, profiles.localRev);
        await migrationStepHook?.call('profiles.local_rev');
        await m.addColumn(dayEntries, dayEntries.dirty);
        await migrationStepHook?.call('day_entries.dirty');
        await m.addColumn(dayEntries, dayEntries.localRev);
        await migrationStepHook?.call('day_entries.local_rev');
        await m.createTable(syncState);
        await migrationStepHook?.call('sync_state');
      });
    }
    if (from < 3) {
      await transaction(() async {
        await m.addColumn(dayEntries, dayEntries.loggedByUserId);
        await migrationStepHook?.call('day_entries.logged_by_user_id');
        await m.addColumn(dayEntries, dayEntries.lastModifiedByUserId);
        await migrationStepHook?.call('day_entries.last_modified_by_user_id');
        await m.createTable(profileGuardians);
        await migrationStepHook?.call('profile_guardians');
      });
    }
    if (from < 4) {
      await transaction(() async {
        await m.addColumn(profiles, profiles.birthYear);
        await migrationStepHook?.call('profiles.birth_year');
        await m.addColumn(profiles, profiles.relationship);
        await migrationStepHook?.call('profiles.relationship');
        await m.addColumn(profiles, profiles.transferredAt);
        await migrationStepHook?.call('profiles.transferred_at');
      });
    }
    if (from < 5) {
      await transaction(() async {
        await m.addColumn(profiles, profiles.mode);
        await migrationStepHook?.call('profiles.mode');
      });
    }
    if (from < 6) {
      await transaction(() async {
        await m.createTable(observations);
        await migrationStepHook?.call('observations');
        // `sync_state` itself is only ever created once, above, by
        // `m.createTable(syncState)` in the `from < 2` block — and
        // `createTable` builds it from the *current* `SyncState` table
        // class, which already declares `cursorObservations`. So a device
        // upgrading straight from v1 (where this `from < 2` block is the
        // one that creates `sync_state` for the first time) already has
        // the column by the time execution reaches here; adding it again
        // would be a duplicate-column error. Only a device that already
        // had `sync_state` *before* this version (from >= 2) is missing
        // the column and needs the explicit `addColumn` below.
        if (from >= 2) {
          await m.addColumn(syncState, syncState.cursorObservations);
          await migrationStepHook?.call('sync_state.cursor_observations');
        }
      });
    }
    if (from < 7) {
      await transaction(() async {
        // day_entries has existed since v1 on every real device, so this
        // addColumn is always safe regardless of `from`.
        await m.addColumn(dayEntries, dayEntries.source);
        await migrationStepHook?.call('day_entries.source');
        await m.addColumn(dayEntries, dayEntries.sourceId);
        await migrationStepHook?.call('day_entries.source_id');
        await m.addColumn(dayEntries, dayEntries.importId);
        await migrationStepHook?.call('day_entries.import_id');
        // Mirrors the `sync_state.cursor_observations` gotcha right above:
        // `m.createTable(observations)` in the `from < 6` block builds the
        // table from the *current* `Observations` class, which already
        // declares `importId` — so a device upgrading straight from before
        // v6 gets the column for free as part of that createTable, and
        // adding it again here would be a duplicate-column error. Only a
        // device that already had `observations` *before* this version
        // (from >= 6) is missing the column and needs the explicit
        // `addColumn` below.
        if (from >= 6) {
          await m.addColumn(observations, observations.importId);
          await migrationStepHook?.call('observations.import_id');
        }
      });
    }
    // Re-assert unconditionally on every upgrade (issue #200): `onCreate` is
    // the only place this partial index was ever created, so a device whose
    // schema was reconstructed from something other than a real `onCreate`
    // run (the drift schema-verification harness's `schemaAt(1)` fixture in
    // `test/data/db/schema_migration_test.dart` is exactly that case) would
    // reach v4 without it, silently losing the one-live-entry-per-day
    // constraint. `CREATE UNIQUE INDEX IF NOT EXISTS` is a no-op for the
    // real upgrade path (every shipped device's `onCreate` already made it),
    // so this only ever does work in the previously-uncovered case.
    await customStatement(kLiveDayEntryIndexSql);
    await migrationStepHook?.call('day_entries.live_index');
  }

  /// Hard-deletes every row in every table, the `sync_state` row included —
  /// the web build's wipe-local-data action and the web half of device
  /// reset (KTD16). This is a wipe, not a sync-domain soft delete:
  /// tombstones go too. Native device reset deletes the file instead.
  Future<void> wipeAllData() async {
    await transaction(() async {
      // observations references day_entries(id) and profiles(id): it must
      // be emptied before either or the FK fails the whole wipe.
      await delete(observations).go();
      await delete(dayEntries).go();
      // profile_guardians references profiles(id): it must be emptied
      // before profiles or the FK fails the whole wipe.
      await delete(profileGuardians).go();
      await delete(profiles).go();
      await delete(appSettings).go();
      await delete(syncState).go();
    });
  }
}
