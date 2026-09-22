---
title: Extract one role from a god class into its own class behind a delegating shim
date: '2026-09-22'
category: architecture-patterns
module: storage role extraction (#551 problem 1)
problem_type: architecture_pattern
component: development_workflow
severity: low
applies_when:
  - a large class already declares role interfaces but still holds every implementation
  - one role's members can move into a collaborator without changing any consumer
  - existing consumers and tests must keep compiling against the original class
  - the extraction is the first of several and should set a repeatable recipe
tags:
  - dart
  - refactoring
  - god-class
  - role-interfaces
  - delegation
  - storage
  - pure-move
  - verification
related_components:
  - lib/data/db/storage.dart
  - lib/data/db/storage_roles.dart
  - lib/data/db/sync_cursor_storage.dart
  - lib/data/db/storage_queries.dart
  - lib/data/db/storage_local_writes.dart
  - lib/data/sync/supabase_sync_engine.dart
---

# Extract one role from a god class into its own class behind a delegating shim

## Context

Issue #551 problem 1 introduced role interfaces over `LunarLogStorage`
(`SyncCursorStore`, `SyncDirtyStore`, `SyncApplyStore`, ...), but it moved no
members: the class still held every implementation and merely `implements`
the interfaces. The next step ("part 1, step 2") had to actually extract a
role implementation out of the god class, without breaking the very large set
of consumers and tests that construct `LunarLogStorage` and call its public
surface.

The smallest role pair — `SyncCursorStore` + `SyncDirtyStore` (dubbed
`SyncMetadataStore`) — came out first. The method bodies lived across three
`part`-mixins (`storage_queries.dart`, `storage_local_writes.dart`) plus two
members directly on the class (`setClockOffset`, the `_clockOffset` field),
so the extraction had to move members out of mixins, not just out of one
class body, and had to share mutable state (the clock offset) that a second
object would otherwise duplicate.

## Guidance

The recipe is mechanical. Follow it role by role.

1. **Declare the narrow combined role first (if the role pair is consumed
   together).** Add `SyncMetadataStore implements SyncCursorStore,
   SyncDirtyStore` to the roles file, and make the widest role extend it
   (`SyncEngineStore implements SyncMetadataStore, SyncApplyStore`). Do not
   type any consumer against the concrete class — the storage-boundary guard
   forbids it outside `lib/data/db/` and `lib/composition/`.

2. **Create the collaborator as a `part` of the same library.** It gets the
   same drift database plus the shared mutable state: `class
   SyncCursorStorage implements SyncMetadataStore { SyncCursorStorage(this.db,
   this._clock); ... }`. Being a `part` keeps every table/data type and
   private top-level helper in scope with no new imports.

3. **Promote shared private helpers to library top-level instead of copying
   them.** `_count` was a private method inside a mixin yet used by both a
   staying method (`countAllRows`) and moving methods (`dirtyCount`,
   `isEmpty`); it became a top-level `_countRows(db, table, column, [where])`.
   For shared *state*, promote a tiny holder object rather than duplicating:
   the clock offset and injected clock became `StorageClock` (with `now()`,
   `offset`, `setOffset()`), one instance constructed by the class and handed
   to the collaborator, so the offset stamped on local writes and the offset
   read by the tombstone sweep can never drift.

4. **Move the bodies verbatim; keep doc comments with them.** `git show
   HEAD~1:...` and a line-multiset comparison (see the sibling
   `dart-split-single-class-across-files.md`) is the cheap proof the move was
   faithful, not merely compiling.

5. **Keep the class implementing the role by delegating.** Add a small mixin
   in the new part that `implements SyncMetadataStore`, declares `abstract
   SyncMetadataStore get syncMetadata;`, and forwards each member. The class
   mixes it in (before any mixin whose `on` clause needs the role) and
   provides the getter `SyncMetadataStore get syncMetadata => _syncMetadata;`.
   Because delegation methods are real members, every existing call site and
   `@override` in tests is untouched.

6. **Update `on` clauses when a mixin consumed a moved member.** `sweepTombstones`
   used `_now()` in `LunarLogStorageLocalWrites`; after moving, `runMaintenance`
   forwards to `syncMetadata.sweepTombstones(...)` via a new `abstract
   SyncMetadataStore get syncMetadata;` stub. `storage_remote_apply.dart`
   called `readSyncState()`, so its mixin gained `LunarLogStorageSyncMetadata`
   in its `on` clause and that mixin is applied before it.

7. **Switch consumers to the narrow role where they only need it.** The sync
   engine's cursor/dirty/clock calls now go through an optional `SyncMetadataStore
   syncMetadata` parameter defaulting to the existing `SyncEngineStore`
   (so tests construct it unchanged), and the composition root
   (`lib/app_root.dart`) passes `db.storage.syncMetadata`. Leave the apply
   half on the wide role until its own extraction.

8. **Add a focused test on a real drift database** and keep the boundary
   guard green. A new concrete-storage reference somewhere else in `lib/`
   (here `DriftLocalRowCountRepository`) will make the guard fail; give it its
   own role (`LocalRowCountStore`) rather than widening the allowlist.

## Why This Matters

The value of a role interface is that consumers can depend on it and a
collaborator can replace the god object; declaring interfaces without moving
implementations captures none of that. But extracting naively — a new class
constructed independently, or a second copy of the clock offset — silently
changes behaviour: two clock copies diverge the moment one is updated, and
the delegation shim is what makes the extraction observable as a pure move
instead of a rewrite of every call site.

The shared-helper decision is the crux. Copying `_countRows` or re-declaring
`_clockOffset` compiles and passes tests while introducing a latent
divergence; promoting one library-level helper and one `StorageClock`
instance is what makes the collaborator genuinely behaviour-identical.

## When to Apply

- A class `implements` role interfaces but still holds the bodies; extract
  the narrowest role first to set the pattern.
- The role's members need state the class already owns (a clock, a counter,
  a cache): promote a shared holder, do not duplicate.
- Existing tests must keep compiling unchanged — a delegating shim, not a
  constructor-signature change, is the seam.
- A mixin's `on` clause or an abstract stub needs the moved member: add the
  delegating mixin to the `on` clause and apply it before the dependent mixin.

## Examples

1. **#551 part 1, step 2 (this change).** `SyncCursorStorage` was created in
   `lib/data/db/sync_cursor_storage.dart` (`part of 'storage.dart'`),
   implementing `SyncMetadataStore` over the same `LunarLogDatabase` and a
   shared `StorageClock`. `LunarLogStorage` mixed in `LunarLogStorageSyncMetadata`
   (18 one-line forwards) and kept `clockOffset` by reading the shared clock.
   `_count` became `_countRows`; `_countAllRowCounts` is shared by
   `countAllRows` and `isEmpty`. `SupabaseSyncEngine` gained an optional
   `syncMetadata` parameter defaulting to `storage`; `lib/app_root.dart`
   passes `db.storage.syncMetadata`. New test
   `test/data/sync_cursor_storage_test.dart` (10 cases, real `NativeDatabase.memory()`)
   covers the cursor singleton, the clock offset, the dirty scans and
   maintenance. `flutter analyze` clean; `test/architecture`, `test/data/sync*`,
   `test/data/sync_engine`, `test/data/db_test.dart` and the composition test
   all green.

2. **The boundary guard catches the sibling PR.** Part 3 landed
   `DriftLocalRowCountRepository` typed against the concrete class after part
   1 branched; merging them turned the guard red. The fix was a new
   `LocalRowCountStore` role, not an allowlist entry — the same move the guard
   exists to force.

## Related

- Issue #551 (open — split `LunarLogStorage` into role stores; problem 1)
- PR #1058 (`#551 part 1` — role interfaces, no members moved)
- PR #1052 (`#551 part 2` — remote-apply skeleton), merged into this branch
- `docs/solutions/architecture-patterns/dart-split-single-class-across-files.md`
  (the sibling `part`-mixin split, and its line-multiset verification recipe)
