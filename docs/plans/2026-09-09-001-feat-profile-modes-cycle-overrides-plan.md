# Plan — profile_modes and cycle_overrides storage, RLS, and sync (Issue #188)

Date: 2026-09-09 · Branch: `feat/188-modes-storage` · Epic: Modes (P1)

## Context

Issue #188 asks for the foundational storage of Clue's life-stage mode
axis (Period Tracking / Conceive / Pregnancy / Perimenopause /
Postpartum) plus manual cycle-boundary corrections, so that #192
(Pregnancy mode), #196 (Perimenopause), #204 (Conceive), #233
(birth-control-aware predictions), #260 (birth-control tracking), and
#132 (omit-from-average / manual cycle correction) have something to
build against. Storage, RLS, and sync only — no mode-picker UI (that is
#192/#196/#204's surface, and the issue's mode-switcher acceptance
criterion lands with them).

**Orthogonality (binding):** this axis is separate from #131's care
modes (`profiles.mode`: standard/teen/caregiver/irregular). #131 varies
vocabulary by *who reads*; this varies *what is computed* by *life
stage*. Both are per-profile, both sync, they compose, and the two enums
are never merged. Nothing in this plan touches `profiles.mode`; the
migration header, `profile_modes`'s table comment, and
`lib/domain/models/lifecycle_mode.dart`'s doc comment all state it.

## What shipped

### Server — `supabase/migrations/20260909000000_profile_modes_and_cycle_overrides.sql`

1. `public.profile_modes` (the issue's DDL, verbatim shape): PK
   `profile_id`, `mode` CHECK over the 5-value set (the issue's
   authoritative enum — D-11's sketch omitted `conceive`), optional
   `mode_started_on`, birth-control columns (`birth_control_method`
   bounded at 64 chars, deliberately not a closed set — #260 owns that
   vocabulary), `health_sync_consent` default false (D-29's distinct
   consent). **No `deleted_at`**: the row is created lazily on first
   write and dies with its profile; an absent row means `tracking`.
2. `public.cycle_overrides` (the issue's DDL): composite PK
   `(id, profile_id)`, ULID id check, `cycle_start_date`,
   `excluded_from_average`, `manual_start`, `note_id` (a bounded
   placeholder for #132's notes table, the `import_id` precedent),
   `deleted_at` tombstones cleared of payload by
   `cycle_overrides_tombstone_payload_check` (the #224 structural
   backstop) while keeping `cycle_start_date` as identity.
3. RLS enabled + forced on both; policies: read = any accepted guardian,
   write = `primary_guardian`/`co_parent` only (the issue's write
   ladder — stricter than day_entries, where a caregiver writes); no
   DELETE policy or grant; minimal column grants (no `server_version`).
4. `set_server_version` + `touch_sync_signal` triggers on both (no new
   Realtime publication; `reconcile_realtime_publication()` gains both
   tables on the must-never-be-published list); pull-path
   `server_version` indexes, `cycle_overrides (profile_id,
   cycle_start_date)` read index, and an FK-cascade `profile_id` index.
5. `sync_push` re-emitted (rebased verbatim on the 180000 body, with the
   3-arg overload dropped first, the #240 technique) gaining
   `p_profile_modes jsonb default '[]'` and `p_cycle_overrides jsonb
   default '[]'`:
   - profile_modes: strict LWW keyed on `profile_id`; every optional
     column guarded by `v_row ? 'key'` on update (a pre-birth-control
     client's mode switch preserves stored birth-control state and
     consent); an equal-timestamp push is declined with the server copy
     resolved back (idempotent switching).
   - cycle_overrides: the day_entries accept/decline shape (newer wins,
     tombstone-wins ties, identical-tombstone no-op) minus any
     same-date resolver; a tombstone clears the payload columns
     unconditionally (the guards apply only to live writes).
   - both branches enforce the write ladder and require the profile to
     exist; a mode switch never touches `day_entries`/`observations`.
6. `delete_account_data()` re-emitted with two count-only deletes on
   owned profiles (R7 scoping — shared-profile rows survive a
   caregiver's deletion).
7. `export_account_data()` deliberately untouched (#240's observations
   precedent: client-synced tables are the local export's
   responsibility) — noted in the PR's "Not done".

### pgTAP — `supabase/tests/profile_modes_cycle_overrides_test.sql` (85 tests)

Schema shape, round trip, older-arity calls, the write ladder (RPC
opaque-rejection + direct RLS 42501/no-op semantics), reads, mode-switch
safety + idempotence, old-client omission safety, CHECK enforcement,
tombstone payload clearing + structural backstop, the 501-row cap, and
`delete_account_data()`'s new counts. `sync_push_test.sql`'s
`has_function_privilege` literal and `account_deletion_test.sql`'s
idempotency document updated for the new signature/keys.

### Client

- Drift schema v8: `ProfileModes` (one row per profile) and
  `CycleOverrides` tables + `cursor_profile_modes`/
  `cursor_cycle_overrides` on `sync_state`; `wipeAllData` ordering; a
  real-v7-fixture upgrade test in `db_test.dart` and a per-version
  Issue #188 column-family test in `schema_migration_test.dart`;
  `drift_schemas/drift_schema_v8.json` +
  `test/data/db/generated_migrations/` regenerated.
- `LunarLogStorage`: `upsertProfileMode`/`getProfileMode`/`watch`,
  `upsertCycleOverride`/`softDeleteCycleOverride`/reads, `readDirty*`
  keyset paging, `markPushed`, dirty-count/mark-all-dirty/isEmpty, and
  the `applyRemote*`/`applyResolved`/`applyRemoteRows` LWW + retryable
  referential guard paths.
- Row codec: `encodeProfileMode`/`encodeCycleOverride`,
  `decodeProfileMode` (closed-set `LifecycleMode` normalisation —
  unknown/absent degrades to `tracking`, never throws a pull),
  `decodeCycleOverride`, table-name map, resolved-row dispatch.
- Engine/transport: `SyncTable.profileModes`/`cycleOverrides`, push
  keyset chain, pull table order, per-table cursors, write-subscription
  tables; `PushBatch` and the Supabase RPC params extended.
- Domain: `lib/domain/models/lifecycle_mode.dart` (`LifecycleMode`
  enum + the orthogonality statement) and
  `lib/domain/models/cycle_override.dart` (minimal model); limits
  constants mirroring the new CHECKs.

## Verification

- pgTAP: `db reset --local` + `test db --local` — 1000/1000 pass
  (915 pre-existing + 85 new).
- Flutter: `flutter analyze` clean; `flutter test` green; quality gate
  (`dart run tool/quality_gate.dart`) green.
- Codegen: `build_runner build --delete-conflicting-outputs` committed
  (`db.g.dart`), plus the drift schema dump/generate pair.

## Out of scope (follow-ups)

- Mode-picker UI, prediction recompute triggers, the pregnancy-exit
  exclude flow (#192/#196/#204; the issue's UI acceptance criteria).
- Export: neither `export_account_data()` nor the local JSON export
  includes the new tables yet (see "Not done" in the PR).
- #132's consumer and #260's method vocabulary.
