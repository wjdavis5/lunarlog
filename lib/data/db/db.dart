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

@DriftDatabase(tables: [Profiles, DayEntries, AppSettings])
class LunarLogDatabase extends _$LunarLogDatabase {
  LunarLogDatabase(super.executor);

  /// Storage-level API (upserts with monotonic updated_at, tombstone
  /// soft-deletes, UI and full-fidelity reads). Domain repositories (U3)
  /// build on top of this.
  late final LunarLogStorage storage = LunarLogStorage(this);

  @override
  int get schemaVersion => 1;

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

  /// Step-by-step migration steps. Override together with [schemaVersion]
  /// when bumping the schema, e.g.:
  ///
  ///     if (from < 2) {
  ///       await m.addColumn(dayEntries, dayEntries.newColumn);
  ///     }
  ///
  /// Kept as a separate overridable method so tests can prove the migration
  /// path preserves rows and sync columns.
  @visibleForTesting
  Future<void> onUpgradeSteps(Migrator m, int from, int to) async {}

  /// Hard-deletes every row in every table — the web build's wipe-local-
  /// data action (KTD9). This is a wipe, not a sync-domain soft delete:
  /// tombstones go too. The web store is the only intended caller.
  Future<void> wipeAllData() async {
    await transaction(() async {
      await delete(dayEntries).go();
      await delete(profiles).go();
      await delete(appSettings).go();
    });
  }
}
