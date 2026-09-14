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

/// Introduced in schema v8 (issue #197, performance) — [schemaVersion] has
/// moved on since; see [LunarLogDatabase]'s schema-history doc comment for
/// the current version and everything added after this one. Plain
/// (non-unique, non-partial) index covering the calendar's windowed
/// `(profile_id, local_date)` range scan (`LunarLogStorage._dayEntryQuery`'s
/// `fromLocalDate`/`toLocalDate`) — distinct from [kLiveDayEntryIndexSql],
/// which only ever helps a `deleted_at IS NULL` (live-row) predicate, not
/// this range's tombstoned rows too.
const String kDayEntriesProfileDateIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_day_entries_profile_date '
    'ON day_entries (profile_id, local_date)';

/// Introduced in schema v8 (issue #197) — see [kDayEntriesProfileDateIndexSql]'s
/// doc comment on why "v8" here means introduced-at, not current. Partial
/// index over the sync engine's dirty-row scan
/// (`LunarLogStorage.readDirtyDayEntries`) — `dirty = 1` matches drift's
/// boolean-column encoding (`BoolColumn` stores `0`/`1`), so this mirrors
/// the same partial-index technique [kLiveDayEntryIndexSql] uses, just
/// keyed on `dirty` instead of `deleted_at`.
const String kDayEntriesDirtyIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_day_entries_dirty '
    'ON day_entries (dirty) WHERE dirty = 1';

/// Introduced in schema v8 (issue #197) — see [kDayEntriesProfileDateIndexSql]'s
/// doc comment on why "v8" here means introduced-at, not current. Index
/// over `updated_at`, serving [LunarLogStorage.getDayEntries]'s
/// `updatedAfter` (incremental sync) predicate. Review follow-up: this
/// does **not** serve [LunarLogStorage.readDirtyDayEntries]'s keyset
/// ordering — that query orders by `id` (ULIDs, already insertion order),
/// never by `updated_at`, so an index on `updated_at` has nothing to offer
/// it.
const String kDayEntriesUpdatedAtIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_day_entries_updated_at '
    'ON day_entries (updated_at)';

/// Introduced in schema v8 (issue #197) — see [kDayEntriesProfileDateIndexSql]'s
/// doc comment on why "v8" here means introduced-at, not current. Index
/// over `profile_guardians.profile_id` — every guardian read
/// (`getGuardiansForProfile`, and
/// `ProfileGuardiansRepository.watchForProfile`) filters by it and had no
/// index to do so with before this version.
const String kProfileGuardiansProfileIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_profile_guardians_profile_id '
    'ON profile_guardians (profile_id)';

/// Schema v10 (issue #128): index over `care_notes.profile_id` — every
/// care-note read filters by it.
const String kCareNotesProfileIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_care_notes_profile_id '
    'ON care_notes (profile_id)';

/// Schema v11 (issue #128): index over `visit_prep_items.profile_id` —
/// every prep-item read filters by it.
const String kVisitPrepItemsProfileIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_visit_prep_items_profile_id '
    'ON visit_prep_items (profile_id)';

/// Schema v19 (issue #625, LLA-101): composite index over
/// `observations(day_entry_id, id)` — [LunarLogStorageQueries.
/// getObservationsForDayEntry]/[LunarLogStorageQueries.
/// watchObservationsForDayEntry] (the day-sheet/autosave read path) filter
/// by `day_entry_id` and order by `id`; before this version `observations`
/// carried only its primary-key index, so both queries scanned every
/// observation in the local store. `id` trails `day_entry_id` in the index
/// so the same index also satisfies the `ORDER BY id` without a separate
/// sort step.
const String kObservationsDayEntryIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_observations_day_entry_id '
    'ON observations (day_entry_id, id)';

/// Schema v19 (issue #625, LLA-101): composite index over
/// `observations(profile_id, id)` — see [kObservationsDayEntryIndexSql]'s
/// doc comment; this is the same fix for [LunarLogStorageQueries.
/// getObservationsForProfile]/[LunarLogStorageQueries.
/// watchObservationsForProfile] (account export, and any other
/// whole-profile observation read), which filter by `profile_id` and order
/// by `id` the same way.
const String kObservationsProfileIndexSql =
    'CREATE INDEX IF NOT EXISTS ix_observations_profile_id '
    'ON observations (profile_id, id)';

@DriftDatabase(tables: [
  Profiles,
  DayEntries,
  ProfileGuardians,
  Observations,
  ProfileModes,
  CycleOverrides,
  CareNotes,
  VisitPrepItems,
  AppSettings,
  SyncState,
  HealthSyncState,
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
  /// * 8 — four read-path indexes (Issue #197, performance): a plain
  ///   `(profile_id, local_date)` index on `day_entries` for the calendar's
  ///   windowed range scan, a partial `dirty = 1` index and a plain
  ///   `updated_at` index on `day_entries` for the sync engine's dirty scan
  ///   and incremental reads, and a `profile_id` index on
  ///   `profile_guardians`. No table/column changes.
  /// * 9 — `profile_modes` + `cycle_overrides` tables (Issue #188,
  ///   life-stage modes and manual cycle corrections) and their two pull
  ///   cursors on `sync_state`.
  /// * 10 — `last_period_start` + `typical_cycle_length_days` +
  ///   `typical_period_length_days` on `profiles` (Issue #218, onboarding
  ///   cycle facts seeding provisional predictions).
  /// * 11 — `care_notes` + `visit_prep_items` tables (Issue #128, shared
  ///   care notes and the visit-prep checklist) with their two pull
  ///   cursors on `sync_state` and a `profile_id` index on each.
  /// * 12 — `pms` on `day_entries` (Issue #220, the first-class PMS
  ///   marker that feeds the 6-cycle PMS averages and the predicted PMS
  ///   band).
  /// * 13 — `transferred_to_user_id` on `profiles` (Issue #296, the
  ///   "transferred to whom" ownership signal the health-sync minor gate
  ///   requires).
  /// * 14 — `health_sync_state` table (Issue #186, per-device/per-platform
  ///   health-store sync anchors — never synced to the server) and
  ///   `exported_to_platform_at` on `observations` (Issue #186, the
  ///   round-trip-write marker).
  /// * 15 — `cursor_profile_guardians` on `sync_state` (Issue #525): a
  ///   persisted pull cursor for `profile_guardians`, which previously
  ///   paged from version 0 every cycle.
  /// * 16 — `bbt_unit` + `weight_unit` on `profiles` (Issue #255, the
  ///   per-profile display-unit preferences for numeric measurements).
  ///   Presentation only: each `observations` row keeps the unit it was
  ///   entered/imported in; the client converts at read time.
  /// * 17 — `tracking_preferences` on `profiles` (Issue #259, the synced
  ///   curated-tracking-categories document: which categories the day
  ///   sheet surfaces and in what order, shared by every guardian).
  /// * 18 — `server_version` on `profile_guardians` (Issue #635, LLA-035:
  ///   membership convergence ordered by the server-owned monotonic
  ///   version instead of the client-writable `updated_at`) and
  ///   `access_revoked_at` on `profiles` (Issue #635, LLA-041: marks a
  ///   revocation-wiped row so a later re-share always restores it,
  ///   regardless of a stale, unpushed local `updated_at`).
  /// * 19 — [kObservationsDayEntryIndexSql] and
  ///   [kObservationsProfileIndexSql] (Issue #625, LLA-101): `observations`
  ///   carried only its primary-key index before this version, so the
  ///   day-sheet/autosave read path (`getObservationsForDayEntry`) and the
  ///   whole-profile read path (`getObservationsForProfile`) each scanned
  ///   every observation in the local store.
  /// * 20 — `day_entries.pms_unconfirmed` and `profiles.units_unconfirmed`
  ///   (Issue #637, LLA-039: an upgrade-backfilled default is never pushed
  ///   as if it were real data until a local edit or a pull confirms it —
  ///   see `DayEntries.pmsUnconfirmed`/`Profiles.unitsUnconfirmed`'s doc
  ///   comments). Only ever backfilled `true` for a device genuinely
  ///   crossing v12/v16 in this journey — added and backfilled in
  ///   `_upgradeToV12`/`_upgradeToV16` themselves, not here; this version
  ///   only catches the columns up (with no backfill) for a device that
  ///   skipped those steps. Also `sync_state.cursor_deleted_profiles`
  ///   (Issue #597: a persisted `deletedProfiles` pull cursor, the same
  ///   fix #525 already applied to `profile_guardians`).
  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(kLiveDayEntryIndexSql);
          await customStatement(kDayEntriesProfileDateIndexSql);
          await customStatement(kDayEntriesDirtyIndexSql);
          await customStatement(kDayEntriesUpdatedAtIndexSql);
          await customStatement(kProfileGuardiansProfileIndexSql);
          await customStatement(kCareNotesProfileIndexSql);
          await customStatement(kVisitPrepItemsProfileIndexSql);
          await customStatement(kObservationsDayEntryIndexSql);
          await customStatement(kObservationsProfileIndexSql);
        },
        onUpgrade: (m, from, to) => onUpgradeSteps(m, from, to),
        beforeOpen: (details) async {
          // Enforce referential integrity for per-profile isolation (R3).
          await customStatement('PRAGMA foreign_keys = ON');
          // Issue #203: WAL journal mode and NORMAL synchronous mode for
          // write concurrency and performance.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
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
  /// `observations.import_id`. Issue #197 adds
  /// `day_entries.profile_date_index`, `day_entries.dirty_index`,
  /// `day_entries.updated_at_index`, `profile_guardians.profile_id_index`.
  /// Issue #188 adds `profile_modes`, `cycle_overrides`,
  /// `sync_state.cursor_profile_modes`, `sync_state.cursor_cycle_overrides`.
  /// Issue #218 adds `profiles.last_period_start`,
  /// `profiles.typical_cycle_length_days`,
  /// `profiles.typical_period_length_days`.
  /// Issue #128 adds `care_notes`, `visit_prep_items`,
  /// `sync_state.cursor_care_notes`, `sync_state.cursor_visit_prep_items`,
  /// `care_notes.profile_id_index`, `visit_prep_items.profile_id_index`.
  /// Issue #220 adds `day_entries.pms`. Issue #186 adds `health_sync_state`,
  /// `observations.exported_to_platform_at`. Issue #525 adds
  /// `sync_state.cursor_profile_guardians`. Issue #255 adds
  /// `profiles.bbt_unit`, `profiles.weight_unit`. Issue #259 adds
  /// `profiles.tracking_preferences`. Issue #635 adds
  /// `profile_guardians.server_version`, `profiles.access_revoked_at`.
  /// Issue #625 adds `observations.day_entry_id_index`,
  /// `observations.profile_id_index`. Issue #637 adds
  /// `day_entries.pms_unconfirmed`, `profiles.units_unconfirmed`. Issue
  /// #597 adds `sync_state.cursor_deleted_profiles`. Every version step
  /// also reports its own `schema_version.v<N>` label (Issue #637,
  /// LLA-015) right after `PRAGMA user_version` advances inside that
  /// same step's transaction — a hook that throws there proves the
  /// version write rolled back along with the rest of the step, exactly
  /// like every DDL call above it.
  @visibleForTesting
  Future<void> Function(String completedStep)? migrationStepHook;

  /// Advances `PRAGMA user_version` to [version] (Issue #637, LLA-015).
  /// Always the LAST statement inside a version step's own `transaction()`
  /// call, right after that step's own `migrationStepHook` call — so
  /// SQLite commits or rolls back the DDL and the version bump together,
  /// and a hook that throws (simulating a kill) rolls this back with
  /// everything else the step did. See [onUpgradeSteps]'s doc comment for
  /// why this is necessary: Drift itself only writes the final
  /// `user_version` once, after the whole (possibly multi-version)
  /// `onUpgrade` call returns.
  ///
  /// `PRAGMA user_version = <n>` takes no bind parameter in SQLite, so
  /// [version] is interpolated directly — always a trusted `int` literal
  /// from this file, never external input.
  Future<void> _advanceSchemaVersion(int version) async {
    await customStatement('PRAGMA user_version = $version');
    await migrationStepHook?.call('schema_version.v$version');
  }

  /// Whether [table] already has [column] (Issue #637, LLA-015). Several
  /// steps below add a column to a table that an EARLIER step in the same
  /// method might have just created from scratch via `m.createTable` —
  /// which always builds from the *current* table class, so it already
  /// declares every column that class has today, this new one included.
  /// Every such site used to guard itself with `if (from >= K)` instead —
  /// "does this device's history predate the version whose createTable
  /// step would have included this column for free" — which is a safe
  /// proxy only as long as one `onUpgrade` call always walks a device's
  /// *entire* real history start to finish. [_advanceSchemaVersion]
  /// breaks that assumption on purpose: after a resume, `from` can now
  /// land exactly on a version whose createTable step ran moments ago, in
  /// an EARLIER, already-committed part of the very same overall upgrade
  /// journey (just not this exact `onUpgrade` invocation) — so `from` no
  /// longer reliably distinguishes "this device's table predates this
  /// journey" from "this table was just created, this run, with the
  /// column already on it". Checking the real, current schema instead of
  /// reasoning about `from` is correct under either history.
  Future<bool> _hasColumn(String table, String column) async {
    final rows =
        await customSelect("PRAGMA table_info($table)").get();
    return rows.any((row) => row.data['name'] == column);
  }

  /// Step-by-step migration steps, one `if (from < n)` block per version.
  ///
  /// Drift 2.34.3 does **not** wrap `onUpgrade` in a transaction: the
  /// runner (`drift/src/runtime/executor/helpers/engines.dart`,
  /// `_runMigrations`) calls `beforeOpen` directly and only writes the new
  /// `user_version` — via `DynamicVersionDelegate.setSchemaVersion`, the
  /// underlying `PRAGMA user_version` write — ONCE, after `beforeOpen`
  /// (and so the whole `onUpgrade` call inside it) returns without error.
  /// Without the explicit `transaction()` around each step below, a
  /// failure after the first `addColumn` would leave `user_version`
  /// unmoved with half-applied DDL, and the next open would fail again on
  /// the already-present column — quarantining the install forever. Each
  /// step's own `transaction()` prevents that within the step, but a
  /// multi-version upgrade chains many of these one after another in a
  /// single `onUpgrade` call — this method's own doc history is the
  /// chain — and a device upgrading across several versions at once
  /// commits each earlier step's DDL in full before Drift ever gets a
  /// chance to write the final `user_version`. A kill between two
  /// already-committed steps (LLA-015, issue #637) would otherwise leave
  /// the DDL from every step *before* the crash applied, but
  /// `user_version` still at the version the device started from — so the
  /// next launch replays those same already-applied `addColumn`/
  /// `createTable` calls and fails on a duplicate. [_advanceSchemaVersion]
  /// closes that gap: it is the last statement inside every step's own
  /// `transaction()`, so `PRAGMA user_version` advances to that step's
  /// target version atomically with that step's DDL — SQLite's
  /// `user_version` is itself part of the enclosing transaction, so
  /// either both commit or both roll back together. A kill between steps
  /// then leaves `user_version` at exactly the last step that actually
  /// finished, and the next open's `from` starts there instead of
  /// wherever the device originally was — every earlier `if (from < n)`
  /// guard skips cleanly, and only the interrupted step (whose whole
  /// transaction rolled back, DDL included) re-runs, from scratch, safely.
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
        await _advanceSchemaVersion(2);
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
        await _advanceSchemaVersion(3);
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
        await _advanceSchemaVersion(4);
      });
    }
    if (from < 5) {
      await transaction(() async {
        await m.addColumn(profiles, profiles.mode);
        await migrationStepHook?.call('profiles.mode');
        await _advanceSchemaVersion(5);
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
        // would be a duplicate-column error. [_hasColumn] (LLA-015) is the
        // real, current-schema check for that — see its own doc comment
        // for why `from >= 2` alone stopped being a safe proxy once a
        // step can resume from a version another, already-committed step
        // of this same journey just reached.
        if (!await _hasColumn('sync_state', 'cursor_observations')) {
          await m.addColumn(syncState, syncState.cursorObservations);
          await migrationStepHook?.call('sync_state.cursor_observations');
        }
        await _advanceSchemaVersion(6);
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
        // adding it again here would be a duplicate-column error.
        // [_hasColumn] (LLA-015) checks the real, current schema.
        if (!await _hasColumn('observations', 'import_id')) {
          await m.addColumn(observations, observations.importId);
          await migrationStepHook?.call('observations.import_id');
        }
        await _advanceSchemaVersion(7);
      });
    }
    if (from < 8) {
      await transaction(() async {
        // Plain (non-unique, non-partial) indexes — no column changes, so
        // unlike every block above there is no "already got it for free
        // from createTable" case to guard against; each is a fresh
        // `CREATE INDEX IF NOT EXISTS`.
        await customStatement(kDayEntriesProfileDateIndexSql);
        await migrationStepHook?.call('day_entries.profile_date_index');
        await customStatement(kDayEntriesDirtyIndexSql);
        await migrationStepHook?.call('day_entries.dirty_index');
        await customStatement(kDayEntriesUpdatedAtIndexSql);
        await migrationStepHook?.call('day_entries.updated_at_index');
        await customStatement(kProfileGuardiansProfileIndexSql);
        await migrationStepHook?.call('profile_guardians.profile_id_index');
        await _advanceSchemaVersion(8);
      });
    }
    // Issue #188's v9 step lives whole (its own `from < 9` check
    // included) in [_upgradeToV9] so this method's branch count stays
    // under the CRAP gate as versions accumulate.
    await _upgradeToV9(m, from);
    // Issue #218's v10 step and issue #128's v11 step, same shape.
    await _upgradeToV10(m, from);
    await _upgradeToV11(m, from);
    // Issue #220's v12 step, same shape again.
    await _upgradeToV12(m, from);
    // Issue #296's v13 step, same shape again.
    await _upgradeToV13(m, from);
    // Issue #186's v14 step, same shape again.
    await _upgradeToV14(m, from);
    // Issue #525's v15 step, same shape again.
    await _upgradeToV15(m, from);
    // Issue #255's v16 step, same shape again.
    await _upgradeToV16(m, from);
    // Issue #259's v17 step, same shape again.
    await _upgradeToV17(m, from);
    // Issue #635's v18 step, same shape again.
    await _upgradeToV18(m, from);
    // Issue #625's v19 step, same shape again.
    await _upgradeToV19(m, from);
    // Issue #637/#597's v20 step, same shape again.
    await _upgradeToV20(m, from);
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
    // Issue #218 extends the same unconditional re-assert to the four
    // issue #197 read-path indexes: now that the schema-verification
    // harness can start from a v8/v9 fixture (whose createAll-only
    // reconstruction never ran the real `onCreate`), the `from < 8`
    // block is skipped on those upgrades and nothing else would create
    // them there. `CREATE INDEX IF NOT EXISTS` keeps this a no-op for
    // every real device, which got all four from its own `onCreate` or
    // its own `from < 8` step.
    await customStatement(kDayEntriesProfileDateIndexSql);
    await customStatement(kDayEntriesDirtyIndexSql);
    await customStatement(kDayEntriesUpdatedAtIndexSql);
    await customStatement(kProfileGuardiansProfileIndexSql);
    // Issue #625 extends the same unconditional re-assert to the two v19
    // observations indexes, for the identical reason: a schema-verification
    // fixture that starts at v19 or later via `createAll` alone never ran
    // the real `onCreate` or the `from < 19` step below, so nothing else
    // would create them there. A no-op for every real device.
    await customStatement(kObservationsDayEntryIndexSql);
    await customStatement(kObservationsProfileIndexSql);
  }

  /// The v9 upgrade step (Issue #188): the `profile_modes` and
  /// `cycle_overrides` tables plus their two `sync_state` pull cursors.
  /// Kept as its own method (the `from < 9` guard included) so
  /// [onUpgradeSteps]'s branch count stays under the CRAP gate as
  /// per-version blocks accumulate.
  Future<void> _upgradeToV9(Migrator m, int from) async {    if (from >= 9) return;
    await transaction(() async {
      await m.createTable(profileModes);
      await migrationStepHook?.call('profile_modes');
      await m.createTable(cycleOverrides);
      await migrationStepHook?.call('cycle_overrides');
      // Same `sync_state` gotcha as `cursor_observations` (v6), same
      // [_hasColumn] (LLA-015) real-schema check.
      if (!await _hasColumn('sync_state', 'cursor_profile_modes')) {
        await m.addColumn(syncState, syncState.cursorProfileModes);
        await migrationStepHook?.call('sync_state.cursor_profile_modes');
      }
      if (!await _hasColumn('sync_state', 'cursor_cycle_overrides')) {
        await m.addColumn(syncState, syncState.cursorCycleOverrides);
        await migrationStepHook?.call('sync_state.cursor_cycle_overrides');
      }
      await _advanceSchemaVersion(9);
    });
  }

  /// The v10 upgrade step (Issue #218): the three onboarding cycle-fact
  /// columns on `profiles`. Same standalone-method shape as [_upgradeToV9]
  /// so [onUpgradeSteps]'s branch count stays under the CRAP gate.
  Future<void> _upgradeToV10(Migrator m, int from) async {
    if (from >= 10) return;
    await transaction(() async {
      // `profiles` has existed since v1 on every real device, so these
      // addColumns are always safe regardless of `from`.
      await m.addColumn(profiles, profiles.lastPeriodStart);
      await migrationStepHook?.call('profiles.last_period_start');
      await m.addColumn(profiles, profiles.typicalCycleLengthDays);
      await migrationStepHook?.call('profiles.typical_cycle_length_days');
      await m.addColumn(profiles, profiles.typicalPeriodLengthDays);
      await migrationStepHook?.call('profiles.typical_period_length_days');
      await _advanceSchemaVersion(10);
    });
  }

  /// The v11 upgrade step (Issue #128): the `care_notes` and
  /// `visit_prep_items` tables, their two `sync_state` pull cursors, and a
  /// `profile_id` index on each new table. Same shape as [_upgradeToV9]
  /// (including the `sync_state` gotcha: `m.createTable(syncState)` in the
  /// `from < 2` block already declares the new cursor columns on the
  /// *current* `SyncState` class — see [_hasColumn]'s doc comment, LLA-015).
  Future<void> _upgradeToV11(Migrator m, int from) async {
    if (from >= 11) return;
    await transaction(() async {
      await m.createTable(careNotes);
      await migrationStepHook?.call('care_notes');
      await m.createTable(visitPrepItems);
      await migrationStepHook?.call('visit_prep_items');
      if (!await _hasColumn('sync_state', 'cursor_care_notes')) {
        await m.addColumn(syncState, syncState.cursorCareNotes);
        await migrationStepHook?.call('sync_state.cursor_care_notes');
      }
      if (!await _hasColumn('sync_state', 'cursor_visit_prep_items')) {
        await m.addColumn(syncState, syncState.cursorVisitPrepItems);
        await migrationStepHook?.call('sync_state.cursor_visit_prep_items');
      }
      await customStatement(kCareNotesProfileIndexSql);
      await migrationStepHook?.call('care_notes.profile_id_index');
      await customStatement(kVisitPrepItemsProfileIndexSql);
      await migrationStepHook?.call('visit_prep_items.profile_id_index');
      await _advanceSchemaVersion(11);
    });
  }

  /// The v12 upgrade step (Issue #220): the first-class `pms` marker on
  /// `day_entries`. `day_entries` has existed since v1 on every real
  /// device, so the addColumn is always safe regardless of `from`; the
  /// column's own default (`false`) back-fills every already-stored row,
  /// exactly like the server migration's `add column ... default false`.
  ///
  /// Issue #637, LLA-039: also adds `pms_unconfirmed` (schema v20's
  /// column, added here — not there — so its "does this row's `pms`
  /// predate real data" backfill runs in the exact same transaction as
  /// `pms`'s own addColumn, atomically). This block only ever runs for a
  /// device whose `from` is genuinely below 12 (its own `if (from >= 12)
  /// return;` guard above), so every row already in `day_entries` at
  /// this point unconditionally just received the SQL default — no
  /// further `from` check is needed here, and none would survive an
  /// interrupted-and-resumed journey anyway (see `_upgradeToV20`'s doc
  /// comment for why `from` alone cannot answer this once a step can
  /// resume mid-journey: coupling the backfill to this exact addColumn's
  /// own transaction, rather than to a later step's `from` snapshot,
  /// avoids that pitfall entirely). A device that already had `pms`
  /// before v20 shipped (this block never runs for it) gets no marker at
  /// all — its `pms` values are real, synced data, not a residual
  /// default.
  Future<void> _upgradeToV12(Migrator m, int from) async {
    if (from >= 12) return;
    await transaction(() async {
      await m.addColumn(dayEntries, dayEntries.pms);
      await migrationStepHook?.call('day_entries.pms');
      await m.addColumn(dayEntries, dayEntries.pmsUnconfirmed);
      await migrationStepHook?.call('day_entries.pms_unconfirmed');
      await customStatement('UPDATE day_entries SET pms_unconfirmed = 1');
      await migrationStepHook?.call('day_entries.pms_unconfirmed_backfill');
      await _advanceSchemaVersion(12);
    });
  }

  /// The v13 upgrade step (Issue #296): `transferred_to_user_id` on
  /// `profiles`, the ownership-transfer target the health-sync minor gate
  /// requires. `profiles` has existed since v1 on every real device, so
  /// the addColumn is always safe regardless of `from`; a fresh local row
  /// is always NULL, and only a remote apply (a real transfer's synced
  /// profile) ever fills it — matching the server migration's own backfill
  /// rule ("the current owner of a transferred profile is exactly who
  /// accepted its last transfer"), which only the server's row carries.
  Future<void> _upgradeToV13(Migrator m, int from) async {
    if (from >= 13) return;
    await transaction(() async {
      await m.addColumn(profiles, profiles.transferredToUserId);
      await migrationStepHook?.call('profiles.transferred_to_user_id');
      await _advanceSchemaVersion(13);
    });
  }

  /// The v14 upgrade step (Issue #186, sync mechanics): the device-local
  /// `health_sync_state` anchor table and `observations.exported_to_platform_at`
  /// (the round-trip-write marker). `observations` has existed since v6, so
  /// the addColumn is safe regardless of `from` (the `from < 6` block's
  /// `createTable` builds it from the *current* `Observations` class, which
  /// already declares the column, so a device upgrading straight from
  /// before v6 gets it for free — matching the `import_id` gotcha the
  /// `from < 7` block documents). `health_sync_state` is a fresh table,
  /// created exactly once.
  Future<void> _upgradeToV14(Migrator m, int from) async {
    if (from >= 14) return;
    await transaction(() async {
      await m.createTable(healthSyncState);
      await migrationStepHook?.call('health_sync_state');
      if (!await _hasColumn('observations', 'exported_to_platform_at')) {
        await m.addColumn(observations, observations.exportedToPlatformAt);
        await migrationStepHook?.call('observations.exported_to_platform_at');
      }
      await _advanceSchemaVersion(14);
    });
  }

  /// The v15 upgrade step (Issue #525): `cursor_profile_guardians` on
  /// `sync_state`. Same `sync_state` gotcha as every other cursor column
  /// added since v6 (`cursor_observations`, `cursor_profile_modes`,
  /// `cursor_cycle_overrides`, `cursor_care_notes`,
  /// `cursor_visit_prep_items`): the `from < 2` block's
  /// `m.createTable(syncState)` builds the table from the *current*
  /// `SyncState` class, which already declares this column — so a device
  /// upgrading straight from v1 has it by the time it reaches here, and
  /// only a device that already had `sync_state` (from >= 2) needs the
  /// explicit `addColumn`.
  Future<void> _upgradeToV15(Migrator m, int from) async {
    if (from >= 15) return;
    await transaction(() async {
      if (!await _hasColumn('sync_state', 'cursor_profile_guardians')) {
        await m.addColumn(syncState, syncState.cursorProfileGuardians);
        await migrationStepHook?.call('sync_state.cursor_profile_guardians');
      }
      await _advanceSchemaVersion(15);
    });
  }

  /// The v16 upgrade step (Issue #255): `bbt_unit` + `weight_unit` on
  /// `profiles` — the per-profile display-unit preferences for numeric
  /// measurements. `profiles` has existed since v1 on every real device, so
  /// the addColumns are always safe regardless of `from`; the columns' own
  /// defaults (`'celsius'`/`'kg'`) back-fill every already-stored row,
  /// exactly like the server migration's `add column ... not null default`.
  /// Presentation only — each `observations` row keeps the unit it was
  /// entered/imported in (`observations.unit`); the client converts at read
  /// time (`lib/domain/models/measurement_unit.dart`).
  ///
  /// Issue #637, LLA-039: also adds `units_unconfirmed` (schema v20's
  /// column, added here for the same reason `pms_unconfirmed` is added in
  /// `_upgradeToV12` rather than in `_upgradeToV20` — see that step's doc
  /// comment). This block only ever runs for a device whose `from` is
  /// genuinely below 16, so every row already in `profiles` at this point
  /// unconditionally just received both SQL defaults.
  Future<void> _upgradeToV16(Migrator m, int from) async {
    if (from >= 16) return;
    await transaction(() async {
      await m.addColumn(profiles, profiles.bbtUnit);
      await migrationStepHook?.call('profiles.bbt_unit');
      await m.addColumn(profiles, profiles.weightUnit);
      await migrationStepHook?.call('profiles.weight_unit');
      await m.addColumn(profiles, profiles.unitsUnconfirmed);
      await migrationStepHook?.call('profiles.units_unconfirmed');
      await customStatement('UPDATE profiles SET units_unconfirmed = 1');
      await migrationStepHook?.call('profiles.units_unconfirmed_backfill');
      await _advanceSchemaVersion(16);
    });
  }

  /// The v17 upgrade step (Issue #259): `tracking_preferences` on
  /// `profiles` — the synced tracking-preferences document. `profiles` has
  /// existed since v1 on every real device, so the addColumn is always safe
  /// regardless of `from`; the column is nullable with no default, so every
  /// existing row reads as "never customized" — the all-defaults state —
  /// until the profile's guardians curate it (the server migration adds the
  /// same-shaped jsonb column the same way).
  Future<void> _upgradeToV17(Migrator m, int from) async {
    if (from >= 17) return;
    await transaction(() async {
      await m.addColumn(profiles, profiles.trackingPreferences);
      await migrationStepHook?.call('profiles.tracking_preferences');
      await _advanceSchemaVersion(17);
    });
  }

  /// The v18 upgrade step (Issue #635): `server_version` on
  /// `profile_guardians` (LLA-035) and `access_revoked_at` on `profiles`
  /// (LLA-041). `profiles` has existed since v1 on every real device, so
  /// its addColumn is always safe regardless of `from`. `profile_guardians`
  /// mirrors the `sync_state`/`observations` gotcha documented elsewhere in
  /// this file: the `from < 3` block's `m.createTable(profileGuardians)`
  /// builds the table from the *current* `ProfileGuardians` class, which
  /// already declares `serverVersion` — so a device upgrading straight
  /// from v1 or v2 gets the column for free as part of that createTable,
  /// and adding it again here would be a duplicate-column error. Only a
  /// device that already had `profile_guardians` *before* this version
  /// (from >= 3) is missing the column and needs the explicit `addColumn`
  /// below. Neither column needs a real backfill: a fresh local row's
  /// `server_version` reads `0` (lower than any real remote value,
  /// matching a never-synced row's treatment everywhere else) and
  /// `access_revoked_at` reads `null` (never evicted), which is exactly
  /// the pre-#635 behavior for every row already on the device.
  Future<void> _upgradeToV18(Migrator m, int from) async {
    if (from >= 18) return;
    await transaction(() async {
      if (!await _hasColumn('profile_guardians', 'server_version')) {
        await m.addColumn(profileGuardians, profileGuardians.serverVersion);
        await migrationStepHook?.call('profile_guardians.server_version');
      }
      await m.addColumn(profiles, profiles.accessRevokedAt);
      await migrationStepHook?.call('profiles.access_revoked_at');
      await _advanceSchemaVersion(18);
    });
  }

  /// The v19 upgrade step (Issue #625, LLA-101): two plain indexes on
  /// `observations` — no column changes, same shape as the `from < 8` block
  /// above (issue #197), which is the last time this codebase added a
  /// plain index rather than a column or table. Each is a fresh
  /// `CREATE INDEX IF NOT EXISTS`, so there is no "already got it for free
  /// from createTable" case to guard against.
  Future<void> _upgradeToV19(Migrator m, int from) async {
    if (from >= 19) return;
    await transaction(() async {
      await customStatement(kObservationsDayEntryIndexSql);
      await migrationStepHook?.call('observations.day_entry_id_index');
      await customStatement(kObservationsProfileIndexSql);
      await migrationStepHook?.call('observations.profile_id_index');
      await _advanceSchemaVersion(19);
    });
  }

  /// The v20 upgrade step: `sync_state.cursor_deleted_profiles` (Issue
  /// #597), plus catching up `day_entries.pms_unconfirmed` /
  /// `profiles.units_unconfirmed` (Issue #637, LLA-039) for a device that
  /// never ran `_upgradeToV12`/`_upgradeToV16` — one that was already past
  /// v12/v16 before v20 shipped. Those two steps add the columns
  /// themselves (see their own doc comments for why: coupling each
  /// column's "does this row's value predate real data" backfill to the
  /// exact transaction that added the underlying `pms`/`bbt_unit`/
  /// `weight_unit` column, rather than deciding it here from `from`,
  /// which cannot tell a device that reached v12/v16 in an earlier,
  /// already-committed call of an interrupted-and-resumed journey from
  /// one that reached it in this very call — see [_hasColumn]'s doc
  /// comment for the identical reasoning behind that guard). So this step
  /// only needs [_hasColumn] guards: a device that ran `_upgradeToV12`/
  /// `_upgradeToV16` (in this call or an earlier one) already has both
  /// marker columns; a device that skipped them (already past v12/v16
  /// when its upgrade journey began, so its `pms`/`bbt_unit`/`weight_unit`
  /// are real synced data, never a residual default) gets the columns
  /// added here with **no** backfill — they stay implicit-null
  /// (confirmed), so `row_codec.dart` pushes those fields normally from
  /// the start. `sync_state` mirrors every other cursor column's gotcha
  /// (only a device that already had `sync_state` before this version
  /// needs the explicit addColumn — one upgrading straight from v1 gets
  /// it for free from the `from < 2` block's `createTable`, which builds
  /// from the *current* `SyncState` class).
  ///
  /// Both `_unconfirmed` columns are nullable rather than
  /// non-nullable-with-default (see `Profiles.unitsUnconfirmed`'s doc
  /// comment) purely so every existing test fixture that constructs a
  /// `Profile`/`DayEntry` directly keeps compiling without passing them.
  /// Every local write that sets `pms`/`bbt_unit`/`weight_unit`
  /// (`storage_local_writes.dart`) also clears its marker back to
  /// `false`, so a row the user edits after the upgrade — including one
  /// that merely carries a still-unconfirmed value through an unrelated
  /// full-row edit — is trusted and pushes normally from that point on;
  /// a genuinely untouched row stays protected until a real remote
  /// delivery confirms it (`storage_remote_apply.dart`).
  Future<void> _upgradeToV20(Migrator m, int from) async {
    if (from >= 20) return;
    await transaction(() async {
      if (!await _hasColumn('day_entries', 'pms_unconfirmed')) {
        await m.addColumn(dayEntries, dayEntries.pmsUnconfirmed);
        await migrationStepHook?.call('day_entries.pms_unconfirmed');
      }
      if (!await _hasColumn('profiles', 'units_unconfirmed')) {
        await m.addColumn(profiles, profiles.unitsUnconfirmed);
        await migrationStepHook?.call('profiles.units_unconfirmed');
      }
      if (!await _hasColumn('sync_state', 'cursor_deleted_profiles')) {
        await m.addColumn(syncState, syncState.cursorDeletedProfiles);
        await migrationStepHook?.call('sync_state.cursor_deleted_profiles');
      }
      await _advanceSchemaVersion(20);
    });
  }

  /// Hard-deletes every row in every table, the `sync_state` row included —
  /// the web build's wipe-local-data action and the web half of device
  /// reset (KTD16). This is a wipe, not a sync-domain soft delete:
  /// tombstones go too. Native device reset deletes the file instead.
  Future<void> wipeAllData() async {
    await transaction(() async {
      // observations references day_entries(id) and profiles(id); the two
      // Issue #188 tables and the two Issue #128 tables reference
      // profiles(id): all of them must be emptied before their parents or
      // the FK fails the whole wipe.
      await delete(visitPrepItems).go();
      await delete(careNotes).go();
      await delete(cycleOverrides).go();
      await delete(profileModes).go();
      await delete(observations).go();
      await delete(dayEntries).go();
      // profile_guardians references profiles(id): it must be emptied
      // before profiles or the FK fails the whole wipe.
      await delete(profileGuardians).go();
      await delete(profiles).go();
      await delete(appSettings).go();
      await delete(syncState).go();
      await delete(healthSyncState).go();
    });
    // Issue #203: reclaim unused pages after wiping all data.
    await vacuum();
  }

  /// Reclaims unused disk space and defragments the database file (Issue #203).
  /// Must be run outside of a transaction.
  Future<void> vacuum() async {
    await customStatement('VACUUM');
  }

  /// Sweeps tombstoned rows older than [retentionHorizon] (or [olderThan] if
  /// provided) whose `dirty` flag is false (Issue #203).
  Future<int> sweepTombstones({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) =>
      storage.sweepTombstones(
        retentionHorizon: retentionHorizon,
        olderThan: olderThan,
      );

  /// Runs periodic maintenance: sweeps tombstoned rows and reclaims disk space
  /// with a VACUUM (Issue #203).
  Future<int> runMaintenance({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) =>
      storage.runMaintenance(
        retentionHorizon: retentionHorizon,
        olderThan: olderThan,
      );

  /// Returns the active SQLite journal mode (`wal`, `memory`, `delete`, etc.).
  Future<String> getJournalMode() async {
    final row = await customSelect('PRAGMA journal_mode').getSingle();
    return row.data.values.first.toString().toLowerCase();
  }

  /// Returns the active SQLite synchronous mode name (`NORMAL`, `FULL`, `OFF`, `EXTRA`).
  Future<String> getSynchronousMode() async {
    final row = await customSelect('PRAGMA synchronous').getSingle();
    final val = row.data.values.first;
    return switch (val) {
      0 || '0' || 'OFF' => 'OFF',
      1 || '1' || 'NORMAL' => 'NORMAL',
      2 || '2' || 'FULL' => 'FULL',
      3 || '3' || 'EXTRA' => 'EXTRA',
      _ => val.toString(),
    };
  }
}
