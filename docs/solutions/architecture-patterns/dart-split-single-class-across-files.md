---
title: Split a large single Dart class across files with same-library part-mixins
date: '2026-09-10'
category: architecture-patterns
module: Dart architecture file splits
problem_type: architecture_pattern
component: development_workflow
severity: low
applies_when:
  - a single Dart class has grown large enough that one file mixes several concerns
  - a refactor must split that class across files without changing its public API
  - a plan or brief prescribes plain part files for the split
  - you must prove a refactor is a pure move rather than a rewrite
tags:
  - dart
  - refactoring
  - part-files
  - mixins
  - pure-move
  - verification
  - architecture-split
related_components:
  - lib/data/db/storage.dart
  - lib/data/db/storage_local_writes.dart
  - lib/data/db/storage_remote_apply.dart
  - lib/data/db/storage_queries.dart
---

# Split a large single Dart class across files with same-library part-mixins

## Context

Issue #434 split `lib/data/db/storage.dart`, which had grown to 3038 lines around one `LunarLogStorage` class plus private top-level helpers. The coordinator brief prescribed the obvious mechanism: keep `storage.dart` as the library and move groups of the class's members into plain `part` files (`part 'storage_local_writes.dart';` and so on).

That mechanism does not exist in Dart. `part`/`part of` shares a library's **top-level** namespace, not a class's **member** namespace: a class's methods and fields must all live inside the one `class { ... }` body in the file that declares the class. A part file can hold top-level functions, classes, and variables, but it cannot hold `LunarLogStorage`'s members. The brief's constraint — "do NOT convert `LunarLogStorage` into mixins/composition" — could not be satisfied alongside its own goal of one class split across files.

## Guidance

Split the class into mixins declared in `part` files, then compose the class from them with a `with` clause. This keeps one library, one private namespace, and one import path — the properties a pure move needs.

Shape (from the merged `lib/data/db/storage.dart`):

```dart
// storage.dart — the library. Keeps the header doc, imports/exports,
// part directives, the class's fields/constructor/clock, and the class
// declaration itself.
library;

import '...';
export '...' show LocalRowCounts, RemoteProfileRow, /* ... */ RetryableSyncApplyError, SyncTable;

part 'storage_local_writes.dart';
part 'storage_queries.dart';
part 'storage_remote_apply.dart';

class LunarLogStorage
    with
        LunarLogStorageQueries,
        LunarLogStorageLocalWrites,
        LunarLogStorageRemoteApply {
  LunarLogStorage(this.db, {DateTime Function()? clock, UlidGenerator? ulid}) /* ... */;

  @override
  final LunarLogDatabase db;
  @override
  final UlidGenerator _generator;
  @override
  DateTime _now() => /* ... */;
}
```

Each part starts `part of 'storage.dart';` and declares one mixin of moved members:

```dart
// storage_remote_apply.dart
part of 'storage.dart';

mixin LunarLogStorageRemoteApply
    on LunarLogStorageQueries, LunarLogStorageLocalWrites {
  Future<bool> applyRemoteProfile(RemoteProfileRow remote) => /* ... */;
  // ...the remote-apply members, moved verbatim
}
```

Rules that make this work:

1. **The `on` clause must name mixins applied before it.** `LunarLogStorageRemoteApply` depends on members from `LunarLogStorageQueries` and `LunarLogStorageLocalWrites`, so both precede it in the class's `with` list. `LunarLogStorageQueries` has no `on` clause and comes first.
2. **Private access survives because parts share the library.** The mixins read the class's private field `_generator` and call its private helper `_now()` (whose body in `storage.dart` reads `_clock` and `_clockOffset`). Declare the few members a mixin needs as abstract stubs in the mixin (`LunarLogDatabase get db;`, `UlidGenerator get _generator;`, `DateTime _now();`) and `@override` them in the class.
3. **Do not use extension methods for the moved members.** An extension member is not a class member, so call sites such as `storage.upsertProfile(...)` stop compiling and test subclasses cannot `@override` it. Per the PR #442 attempt, extensions produced 89 analyzer errors at unchanged call sites; mixins preserve every signature as a real instance member.
4. **Do not rename or re-sign anything.** The point is that importers and tests compile unchanged. `storage.dart` stays the single import path and keeps its `export ... show ...` re-exports.

**Verify the move mechanically, not by reading the diff.** A part-mixins refactor rewrites the class declaration and wraps bodies, so a rename-aware diff can hide a dropped or edited member. Compare the original against the union of the new files as a **line multiset**: every non-empty line of the original must appear with the same multiplicity in the new files. Fetch the original from the **pre-split** revision — `git show main:<path>` while the refactor is still on its branch, or the branch-point commit (`git merge-base HEAD origin/main`, or the known base SHA) once `main` may have advanced past it. Do not use a post-merge `main`: it already holds the split, so the comparison would trivially report zero differences.

```python
import subprocess, glob
from collections import Counter

PRE_SPLIT = 'main'   # the refactor branch's base, e.g. the merge-base with origin/main
orig = subprocess.run(['git', 'show', f'{PRE_SPLIT}:lib/data/db/storage.dart'],
                      capture_output=True, text=True, encoding='utf-8').stdout
new = ''
for f in glob.glob('lib/data/db/storage*.dart'):   # includes storage.dart itself
    new += open(f, encoding='utf-8').read() + '\n'
ol = Counter(l.rstrip() for l in orig.splitlines() if l.strip())
nl = Counter(l.rstrip() for l in new.splitlines() if l.strip())
missing = {l: c - nl[l] for l, c in ol.items() if nl[l] < c}
print('missing original lines:', missing)   # expect only the `class ... {` line
```

In the #434 split, the only original line that differed was `class LunarLogStorage {` (replaced by the `with` form); everything else — every method body, comment, and `R*`/`KTD*` requirement tag — appeared with identical multiplicity.

Then run the repo's gates from the worktree: `flutter analyze`, `flutter test`, `dart run tool/quality_gate.dart`.

## Why This Matters

The architecture-split epic (#100, open) has several oversized files to split, and a brief that prescribes an impossible mechanism wastes a dispatch at best and invites a wrong-mechanism rewrite at worst. Knowing the correct mechanism up front — and knowing it is not the "obvious" plain-part one — is the difference between a one-shot pure move and a multi-attempt churn.

The line-multiset check matters for the same reason: "the tests pass" proves behavior survived, but not that the move was faithful. Mixin application silently shadows on name collisions (the later mixin wins), so two mixins that accidentally define the same helper would compile and pass while one definition quietly disappeared. The multiset check makes the drop visible.

The public-API constraint is what rules out the alternatives: extensions break call sites, and extracting collaborators into separate classes changes both private-member access and the class's API. Same-library part-mixins are the only mechanism that keeps `LunarLogStorage` one class with one import path.

Contrast with a test-file split: when the file is a suite of top-level `group`/`test` calls rather than one class, the plain split works — one file per concern plus a non-`_test` support library for shared fixtures (the sibling `test/data/sync_engine_test.dart` split in PR #441; that original file was since removed). The mixin mechanism is specifically for the single-class case.

## When to Apply

- A Dart file has grown large because one class holds several concerns and you want to split it by concern.
- The refactor must be a pure move: no public API change, no importer edits, no test edits.
- A brief or plan says to use plain `part` files to move class members — correct it to part-mixins before dispatch.
- You need to prove a move is faithful, not merely behavior-preserving: use the line-multiset check.
- The file is a test suite of top-level groups rather than one class: a plain per-concern file split is correct, and no mixin is needed.

## Examples

1. **The #434 storage split (merged in PR #442).** 3038 lines became `storage.dart` (123 lines) plus `storage_local_writes.dart` (1122), `storage_remote_apply.dart` (1142), and `storage_queries.dart` (707). The class declaration at `lib/data/db/storage.dart:98` is `class LunarLogStorage with LunarLogStorageQueries, LunarLogStorageLocalWrites, LunarLogStorageRemoteApply`; the mixins are declared at `storage_queries.dart:22` (no `on`), `storage_local_writes.dart:207` (`on LunarLogStorageQueries`), and `storage_remote_apply.dart:11` (`on LunarLogStorageQueries, LunarLogStorageLocalWrites`). Zero importer or test edits; `flutter analyze` clean, full `flutter test` green, quality gate PASS.

2. **The sibling test split (merged in PR #441) as the contrasting case.** `test/data/sync_engine_test.dart` (1889 lines, one `main()` with six `group`s; the original file, removed by this split) became six `*_test.dart` files under `test/data/sync_engine/` plus a non-`_test` `sync_engine_support.dart` for shared fixtures. Because the members are top-level `group`/`test` calls, no class is involved and no mixin is needed.

3. **The wrong mechanism, measured.** Applying the brief literally as extensions produced 89 analyzer errors at unchanged call sites and left test subclasses unable to `@override` the moved methods — the signal that the mechanism, not the code, was wrong.

## Related

- Issue #434 (closed — split `lib/data/db/storage.dart`, PR #442, merged)
- Issue #437 (closed — split `test/data/sync_engine_test.dart`, PR #441, merged)
- Issue #100 (open — the architecture-split epic this belongs to)
- `docs/solutions/workflow-issues/sequential-pr-merge-conflict-resolution.md` (the corpus's only other doc; a different area — coordinator git workflow)
