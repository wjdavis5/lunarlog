/// The drift database for lunarlog: one class, one schema version, and a
/// migration framework ready for step-by-step upgrades.
///
/// Platform differences (SQLCipher on mobile, plain WASM/IndexedDB on web)
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

@DriftDatabase(tables: [Profiles, DayEntries, ProfileGuardians, AppSettings, SyncState])
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
  @override
  int get schemaVersion => 4;

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
  /// `profiles.transferred_at`). A hook
  /// that throws proves the transaction wrapper rolls the whole upgrade
  /// back. Must be set before the first query. Null in production.
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
  }

  /// Hard-deletes every row in every table, the `sync_state` row included —
  /// the web build's wipe-local-data action and the web half of device
  /// reset (KTD16). This is a wipe, not a sync-domain soft delete:
  /// tombstones go too. Native device reset deletes the file instead.
  Future<void> wipeAllData() async {
    await transaction(() async {
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
