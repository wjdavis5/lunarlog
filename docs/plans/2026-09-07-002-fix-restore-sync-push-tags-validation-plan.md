---
title: Restore is_valid_tags_array Validation Inside sync_push - Plan
type: fix
date: 2026-09-07
issue: https://github.com/wjdavis5/lunarlog/issues/96
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Restore `is_valid_tags_array` Validation Inside `sync_push` - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths below are repo-relative.

**Scope:** Issue #96 only. The sibling tag-*element-length* bound issue referenced
in #96's "Suggested fix" is explicitly out of scope here (see Scope Boundaries).

---

## Goal Capsule

- **Objective:** Put the explicit `public.is_valid_tags_array(v_tags)` call back
  into the live `public.sync_push` body, so the RPC — the security boundary the
  client actually calls — enforces the "array of at most 32 strings" rule itself
  instead of delegating it entirely to the `day_entries_tags_check` table
  constraint.
- **Means:** One new forward migration that `create or replace`s `sync_push` from
  the current body with only the tags-validation branch changed, plus pgTAP
  coverage that proves the RPC rejects invalid tags *independently of* the table
  CHECK.
- **Definition of done:** `supabase test db --local` passes with new assertions
  that fail against the pre-fix function body.

---

## Problem Frame

Issue #96 reports that `20260904020000_sync_push_and_invitations.sql` rewrote
`sync_push` and silently dropped the `is_valid_tags_array` call that
`20260903170000_tags_string_array_check.sql` had added three days earlier,
leaving only a `jsonb_typeof(v_tags) <> 'array'` type check. The issue classifies
this as P3 contract-integrity cleanup with **no behavioral difference**, because
the `day_entries_tags_check` table constraint still rejects the row at DML time.

Two findings from repo research revise that framing:

**1. The issue points at a superseded migration.** `20260904020000` is no longer
the live definition. `sync_push` has been `create or replace`d twice since:
`20260906160000_profile_subject_metadata.sql:80` and then
`20260906200000_same_date_tag_merge.sql:65`. The **current** body is the one in
`20260906200000`, and its tags branch (lines 312-315) still carries only the weak
type check:

```
v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);
if jsonb_typeof(v_tags) <> 'array' then
  raise exception 'tags is not an array';
end if;
```

So the regression is real and still present, but the fix must be rebased onto
`20260906200000`'s body, not `20260904020000`'s — otherwise the same-date tag
merge (issue #3 U4) and the `birth_year`/`relationship` handling (issue #4 U1)
would be silently reverted, which is exactly the failure mode #96 is about.

**2. It is no longer behavior-neutral — there is a live laundering hole.**
`20260906200000` introduced `public.merge_tag_arrays`, which unions tags via
`jsonb_array_elements_text`. That function **coerces non-string JSON scalars to
their text form**. Because tags validation runs *before* the same-date resolver,
an invalid `tags` value that collides with an existing live entry on the same
`(profile_id, local_date)` is silently converted into a valid one and **lands**:

- `tags: [1, 2]` colliding with a live row → `merge_tag_arrays` yields
  `["1", "2", ...]` → passes `day_entries_tags_check` → **row accepted**.
- `tags: [{"a":1}]` → element becomes the JSON text `{"a": 1}` → **accepted as a
  string tag**.
- A 33-element array colliding with a live row → `merge_tag_arrays` caps the
  union at 32 → **accepted**.

Without a collision, the table CHECK still rejects all three. So the backstop
#96 relies on has a hole precisely on the merge path, and only since
`20260906200000`. Restoring the RPC-level check closes it, because the check runs
before the merge.

This upgrades the change from "contract tidiness" to "closes a real validation
bypass", and it is why the plan carries behavioral test scenarios rather than
only a source-level assertion.

> **Confidence note.** Finding 2 was derived by reading `merge_tag_arrays`
> against `jsonb_array_elements_text`'s documented scalar-to-text behavior; no
> local Postgres was available to execute it while planning. Verification step 6
> (red-before-green) settles it empirically: if the collision-path assertions in
> U2 pass *before* U1 is applied, this finding is wrong, the issue's
> "no behavior change" framing was right, and only the R5 backstop-independent
> assertion is load-bearing. The rest of the plan holds either way.

---

## Requirements

- **R1** — `sync_push`'s day-entry branch rejects any non-tombstone `tags` value
  that is not a JSONB array of at most 32 string elements, at the RPC level,
  **before** the same-date resolver runs.
- **R2** — The rejection surfaces through the existing per-row mechanism: the row
  appears in the response's `rejected` array as the opaque
  `{"id": …, "rejected": true}`; the batch is not aborted and sibling valid rows
  still land.
- **R3** — The fix ships as a **new forward migration**; no merged migration is
  edited in place (AGENTS.md "Migration Flow", rule 7 and the
  "don't edit a merged migration in place" rule).
- **R4** — Every other behavior of the current `sync_push` is preserved
  byte-for-byte in intent: the same-date tag union and 32-cap (R7/R11, issue #3
  U4), `flow`/`note` last-writer-wins, guardian role checks, attribution
  stamping, the profile-repointing guard, the advisory lock, the transient-error
  re-raise list, the key allow-lists, and the `revoke`/`grant` privilege shape.
- **R5** — pgTAP proves RPC-level enforcement **independently of**
  `day_entries_tags_check`, so a future migration that drops or weakens the table
  constraint cannot make the suite silently vacuous.
- **R6** — The collision/laundering path is covered by regression tests that fail
  against the pre-fix body.
- **R7** — Repo test-count bookkeeping stays accurate (`plan(N)` in the touched
  suite, and the per-file/total counts recorded in `AGENTS.md`).

---

## Key Technical Decisions

**KTD1 — Rebase onto `20260906200000`'s body, not the one #96 names.**
Copy the current `sync_push` definition from
`supabase/migrations/20260906200000_same_date_tag_merge.sql:65-458` and change
only the tags branch. Rationale: `create or replace` is a whole-body replacement,
so authoring against `20260904020000` would revert two later migrations. This is
the same trap #96 documents, and `20260906200000`'s own header (lines 14-23)
records having had to do exactly this rebase. Governs R3, R4.

**KTD2 — Keep the validation where it already is (before the resolver), not after
the merge.** The check replaces the existing `jsonb_typeof` branch in place. It
must not move below the same-date resolver: validating the *post-merge* value
would accept the coerced output of `merge_tag_arrays` and leave the laundering
hole open. Governs R1, R6.

**KTD3 — Call `public.is_valid_tags_array(v_tags)` rather than inlining the
rule.** The function already exists
(`supabase/migrations/20260903170000_tags_string_array_check.sql:7-22`), is
`immutable`/`parallel safe`, and is what `day_entries_tags_check` itself calls.
Reusing it keeps both enforcement layers on a single definition, which is the
defense-in-depth property #96 asks for — a future change to the rule updates one
place and both layers follow. Governs R1.

**KTD4 — Raise plainly, without an explicit `errcode`, matching the neighboring
row validations.** #96's suggested fix proposes
`using errcode = '22023'`. Varying from it deliberately: every sibling
row-level validation in this function (`'row is not an object'`,
`'id is not a ULID'`, `'local_date is not an ISO calendar date'`,
`'flow is not a known level'`, `'tags is not an array'`) raises with no errcode
and is caught by the block's `when others` handler, which is what produces the
opaque per-row rejection. An errcode would be invisible to callers (it never
escapes the handler) while breaking local consistency. Use the original #40
message text — `'tags must be an array of strings (max 32)'` — for continuity
with `20260903170000:237`. Critically, `22023` must **not** be added to the
transient re-raise list (`40P01`/`40001`/`55P03`); doing so would turn a bad row
into an aborted batch. Governs R1, R2.

**KTD5 — Prove RPC-level enforcement by removing the backstop inside the test
transaction.** The existing tags assertions in
`supabase/tests/sync_push_test.sql:418-431` already push `[1, 2]` and
`["valid", 123]` and expect two rejections — and they pass *today*, via the table
CHECK. They therefore cannot detect this regression and will not detect its
recurrence. The new coverage drops `day_entries_tags_check` inside the suite's
existing `begin; … rollback;` transaction, re-runs the same push, and asserts the
rows are still rejected. This is the only assertion shape that distinguishes the
two layers. Governs R5.

**KTD6 — No data backfill.** `20260903170000:30-36` already sanitized existing
rows, and `day_entries_tags_check` has been enforcing at the table level
continuously since. The only rows that could have slipped through are
merge-path-laundered ones, which are *valid* string arrays by the time they are
stored — there is nothing malformed at rest to repair. Governs R4.

---

## High-Level Technical Design

Where the two enforcement layers sit today versus after the fix, on the two
paths a day-entry write can take:

```mermaid
flowchart TD
    A["sync_push: day entry row, deleted_at is null"] --> B["v_tags := coalesce(row -> 'tags', '[]')"]
    B --> C{"jsonb_typeof(v_tags) = 'array'?"}
    C -- no --> R1["raise -> per-row rejected"]
    C -- yes --> NEW{"NEW: is_valid_tags_array(v_tags)?"}
    NEW -- no --> R2["raise -> per-row rejected"]
    NEW -- yes --> D{"same-date live row collides?"}
    D -- no --> E["insert/update day_entries"]
    D -- yes --> F["merge_tag_arrays(...)<br/>coerces scalars to text, caps at 32"]
    F --> E
    E --> G{"day_entries_tags_check"}
    G -- fail --> R3["23514 -> per-row rejected"]
    G -- pass --> H["row lands"]

    style NEW fill:#2d6a4f,color:#fff
    style F fill:#7f1d1d,color:#fff
    style R2 fill:#2d6a4f,color:#fff
```

The hole this closes: without the green `NEW` gate, any invalid `tags` reaching
the red `merge_tag_arrays` node is rewritten into a form that satisfies the table
CHECK, so the `G` backstop never fires. The new gate is upstream of the merge, so
both paths are covered.

---

## Implementation Units

### U1. New migration restoring the RPC-level tags check

**Goal:** `public.sync_push` validates tags with `is_valid_tags_array` again,
with every other behavior of the current definition unchanged.

**Requirements:** R1, R2, R3, R4. Implements KTD1, KTD2, KTD3, KTD4.

**Dependencies:** none.

**Files:**
- `supabase/migrations/<generated>_restore_sync_push_tags_validation.sql` (create)

Create the file with `npx supabase@2.116.0 migration new restore_sync_push_tags_validation`
— per AGENTS.md "Migration Flow" step 1, do not hand-name it. Verify the generated
`YYYYMMDDHHMMSS_` prefix sorts **after** `20260906240000_account_deletion_notifications.sql`
(the current tip); today's date makes this automatic, but rule 7 in AGENTS.md
makes it a required check, not an assumption.

**Approach:**

1. Write a header comment naming issue #96, stating that it restores the
   validation `20260903170000` added and `20260904020000` dropped, that it is
   rebased onto `20260906200000`'s body per the "don't edit a merged migration in
   place" rule, and — importantly for the next reader — that it also closes the
   `merge_tag_arrays` coercion path described in this plan's Problem Frame.
2. Copy the `create or replace function public.sync_push(...)` body verbatim from
   `supabase/migrations/20260906200000_same_date_tag_merge.sql:65-452`.
3. Make exactly one change, in the non-tombstone `else` branch at lines 312-315:
   keep `v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);`, then replace the
   `jsonb_typeof(v_tags) <> 'array'` guard with
   `if not public.is_valid_tags_array(v_tags) then raise exception 'tags must be an array of strings (max 32)'; end if;`.
   `is_valid_tags_array` already returns false for a non-array, so the type check
   is subsumed, not merely supplemented — do not keep both.
4. Leave the tombstone branch (`v_tags := '[]'::jsonb`) untouched: tombstones
   carry no payload and `'[]'` is trivially valid.
5. Update the `comment on function public.sync_push(jsonb, jsonb)` to append the
   restored string-only tags validation (issue #96) to the existing text, keeping
   the rest of that comment intact.
6. Re-issue the trailing
   `revoke execute … from public, anon;` / `grant execute … to authenticated;`
   pair exactly as `20260906200000:457-458` does. `create or replace` preserves
   privileges, so this is belt-and-braces, but the house convention repeats it and
   `sync_push_test.sql:395-397` asserts that shape.

**Patterns to follow:** `supabase/migrations/20260906200000_same_date_tag_merge.sql`
is the closest precedent — a forward migration that `create or replace`s
`sync_push` to change exactly one block, with a header explaining the rebase.
`supabase/migrations/20260903170000_tags_string_array_check.sql:236-238` is the
exact statement being restored. Match the repo's lower-case SQL keyword style and
keep `security invoker` + `set search_path = ''`.

**Execution note:** Write the U2 assertions first and watch them fail against the
current function body before applying this migration. Because the table CHECK
masks RPC-level rejection on the non-collision path, a test written after the fix
can pass for the wrong reason — seeing red first is what proves the coverage is
load-bearing.

**Test scenarios:** covered by U2 (this unit ships no test file of its own).

**Verification:** After `db reset --local`, the stored function definition
contains the validator call, and the migration applies cleanly from scratch in
filename order. See the Verification Contract for exact commands.

---

### U2. pgTAP coverage proving RPC-level enforcement and closing the merge path

**Goal:** Assertions that fail against the pre-fix body and pass after U1, and
that cannot be made vacuous by a future change to `day_entries_tags_check`.

**Requirements:** R1, R2, R5, R6, R7. Implements KTD5.

**Dependencies:** U1 (author the assertions first, apply U1 to turn them green).

**Files:**
- `supabase/tests/sync_push_test.sql` (modify — extend the existing
  "tags string-only validation (Issue #40)" block at lines 412-439; bump
  `select plan(105);` at line 4 by the number of assertions added)

**Approach:**

Extend the existing tags block rather than starting a new file — it already sets
up `user_a`, the profile at `tests.ulid(1)`, and the `r`/`ts` temp-table
scaffolding these assertions need. Add three groups:

1. **Backstop-independent proof (R5).** Inside the suite's existing transaction,
   drop `day_entries_tags_check`, re-authenticate as `user_a`, push a day entry
   with `tags: [1, 2]`, assert it is still rejected, then re-add the constraint so
   later assertions in the file run against the normal schema. The `drop`/`add`
   needs table-owner rights, so reset to the superuser role around it
   (`tests.clear_authentication()` / `reset role`) and re-authenticate afterwards;
   the file-level `rollback` makes this safe regardless.
2. **Collision-path laundering regressions (R6).** These are the assertions that
   fail today. For each, seed a live entry for `tests.ulid(1)` on a fresh
   `local_date` with valid tags, then push a *different* ULID for the same
   `(profile_id, local_date)` carrying invalid tags at a newer timestamp.
3. **Cap regression on the same path.** Same shape, with a 33-element array.

**Test scenarios:**

- Non-string tags with the table CHECK dropped: pushing
  `tags: '[1, 2]'::jsonb` for a new day entry returns that row's id in
  `rejected` (length 1) and stores no row. *Fails pre-fix* — with the backstop
  gone, nothing rejects it. Proves R5.
- Non-string tags on a colliding write: given a live entry `E1` at `t1` with
  `tags: ["a"]` on date `D`, pushing entry `E2` at `t2` (`t2 > t1`) on date `D`
  with `tags: '[1, 2]'::jsonb` rejects `E2`, leaves `E1` live with `tags` still
  exactly `["a"]`, leaves `E1.updated_at` at `t1`, and stores no row for `E2`.
  *Fails pre-fix* — today `E2` lands and `E1` is tombstoned, with the survivor
  carrying the coerced `["1", "2", "a"]`. Proves R1, R6.
- Nested-value tags on a colliding write: same setup with
  `tags: '[{"a": 1}]'::jsonb` rejects the incoming row and leaves the existing
  row's tags untouched. *Fails pre-fix* — the object is coerced to the JSON text
  `{"a": 1}` and stored as a tag. Proves R1, R6.
- Over-cap tags on a colliding write: same setup with a 33-element string array
  rejects the incoming row and leaves the existing row's tags untouched. *Fails
  pre-fix* — `merge_tag_arrays` caps the union at 32 and the row lands. Proves
  R1, R6.
- Over-cap tags with no collision: pushing a 33-element string array on a date
  with no live entry is rejected (unchanged behavior — previously via the table
  CHECK, now via the RPC). Guards against the fix accidentally *loosening* the
  non-collision path.
- Batch isolation (R2): a single `sync_push` batch containing one invalid-tags
  row and one valid-tags row rejects exactly one row and lands the valid one.
  The existing assertion at `sync_push_test.sql:427-431` already covers this
  shape; confirm it still passes rather than duplicating it.
- Tombstone rows are unaffected: a row with `deleted_at` set and a bogus `tags`
  value is still accepted (the tombstone branch zeroes `tags` before validation
  and never reads the incoming value).
- No regression in the merge suite: `same_date_tag_merge_test.sql:285-307`
  ("colliding write against a 32-tag entry is not rejected") must still pass —
  its incoming array is exactly 32 valid strings, so `is_valid_tags_array`
  accepts it. Confirm, do not modify.

**Verification:** `supabase test db --local` is green, and every assertion in
groups 1-3 is red when run against the function body without U1 applied.

---

### U3. Update the migration and test inventories in `AGENTS.md`

**Goal:** The repo's documented schema history and pgTAP counts stay accurate, as
AGENTS.md is the stated single source of project context.

**Requirements:** R7.

**Dependencies:** U1, U2 (needs the final filename and assertion count).

**Files:**
- `AGENTS.md` (modify — the "Schema (`supabase/migrations/`)" paragraph and the
  "Database tests (`supabase/tests/`)" paragraph)

**Approach:** Add one sentence to the schema paragraph describing the new
migration and naming issue #96, in the same voice as the surrounding entries.
Update `sync_push_test.sql`'s per-file count and the leading total (currently
`565`) by the number of assertions U2 adds. Do not restructure or reflow the
paragraphs — they are long, and a wholesale rewrite would bury the change in
review.

**Test expectation: none** — documentation only, no behavioral change.

**Verification:** The counts stated in `AGENTS.md` match `select plan(N)` across
`supabase/tests/*.sql`, and the new migration filename appears in the schema
paragraph.

---

## Verification Contract

Run from the repo root. The Supabase CLI is not installed globally; the repo
pins `2.116.0` (`.github/workflows/ci.yml:188`, README, AGENTS.md).

**1. Start the local stack (database-only services, matching CI):**

```bash
npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor
```

**2. Apply every migration from scratch, in filename order:**

```bash
npx supabase@2.116.0 db reset --local
```

Proves the new migration applies cleanly after `20260906240000` and that nothing
in the copied body is malformed.

**3. Confirm the live function body actually carries the validator (the exact
check issue #96 asks for):**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -tAc \
  "select pg_get_functiondef('public.sync_push(jsonb,jsonb)'::regprocedure) like '%is_valid_tags_array%';"
```

Must print `t`. Against the pre-fix body it prints `f`. Port `54322` is from
`supabase/config.toml:34`.

**4. Confirm the merge helper and same-date resolver survived the
create-or-replace (guards against KTD1's revert trap):**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -tAc \
  "select pg_get_functiondef('public.sync_push(jsonb,jsonb)'::regprocedure) like '%merge_tag_arrays%'
       and pg_get_functiondef('public.sync_push(jsonb,jsonb)'::regprocedure) like '%birth_year%';"
```

Must print `t`.

**5. Run the full pgTAP suite:**

```bash
npx supabase@2.116.0 test db --local
```

All files green, including `sync_push_test.sql`, `same_date_tag_merge_test.sql`,
`guardian_sync_push_test.sql`, and `rls_isolation_test.sql`.

**6. Prove the new assertions are load-bearing (red-before-green).** Before
applying U1 — or by re-applying `20260906200000`'s body over the fixed one on a
scratch stack — run step 5 and confirm the U2 assertions in groups 1-3 fail.
A green run at this step means the tests are passing via the table CHECK and do
not actually cover R1.

**7. Migration-push dry run (no credentials required for the parse):**

```bash
npx supabase@2.116.0 db push --dry-run
```

**8. Tear down:**

```bash
npx supabase@2.116.0 stop --no-backup
```

**9. CI:** the `db-tests` job in `.github/workflows/ci.yml:178-203` runs steps 1,
5, and 8 on the PR. No Flutter/Dart code changes here, so `flutter analyze`,
`flutter test`, and `dart run tool/quality_gate.dart` are unaffected — but they
still run in CI and must stay green.

**10. Before the deploy run merges to `main`:** per AGENTS.md "Migration Flow"
step 5, call the Supabase MCP `get_advisors` tool against project
`dleexnnevuuddcgcpztq` and confirm no new security or RLS findings. This
migration touches no RLS policy and no `security definer` function, so a clean
result is expected; the check is required regardless.

---

## Definition of Done

- [ ] A new migration exists whose timestamp sorts after `20260906240000`, and it
      `create or replace`s `sync_push` with `is_valid_tags_array` restored (R1, R3).
- [ ] The migration was authored from `20260906200000`'s body: `merge_tag_arrays`,
      the same-date resolver, `birth_year`/`relationship`, guardian role checks,
      attribution stamping, the advisory lock, and the `revoke`/`grant` pair are
      all present and unchanged (R4, verification steps 3-4).
- [ ] No merged migration file was edited (R3) — `git diff` touches no existing
      file under `supabase/migrations/`.
- [ ] pgTAP proves RPC-level rejection with `day_entries_tags_check` dropped (R5).
- [ ] pgTAP proves the collision path rejects non-string, nested, and over-cap
      tags, and that the pre-existing row is left untouched (R6).
- [ ] The new assertions were observed failing against the pre-fix body
      (verification step 6) (R6).
- [ ] `npx supabase@2.116.0 test db --local` is green (R2, R4).
- [ ] `select plan(N)` in `sync_push_test.sql` and the counts in `AGENTS.md`
      match the assertions actually present (R7).

---

## Scope Boundaries

**In scope:** restoring `is_valid_tags_array` to the live `sync_push` body, the
pgTAP coverage that makes that restoration verifiable, and the AGENTS.md
bookkeeping those two require.

### Deferred to Follow-Up Work

- **Per-element tag length bound.** #96's suggested fix assumes this lands in the
  same migration ("it is already being modified for the element-length bound
  suggested in the sibling tag-length issue"). That sibling issue is not #96 and
  is not planned here. If both are implemented together later, they should share
  one `create or replace`; implementing #96 alone first is still correct — the
  next migration simply rebases onto this one's body, as this one rebases onto
  `20260906200000`.
- **Hardening `merge_tag_arrays` itself.** The coercion described in the Problem
  Frame is a property of `jsonb_array_elements_text`. This plan closes the only
  path that currently reaches it with invalid input (validation now runs first),
  which is sufficient. Making the helper reject rather than coerce is a separate,
  larger change touching issue #3 U4's tested behavior.
- **Stale pgTAP totals elsewhere in the docs.** `README.md` records the suite
  size in two places with two different, already-stale numbers (355 and 373)
  against AGENTS.md's 565. Reconciling those predates this issue; U3 updates only
  the AGENTS.md counts it changes.
- **The unset `SUPABASE_ACCESS_TOKEN` deploy blocker.** AGENTS.md records that
  every `supabase-migrate.yml` run has failed at "Check deploy credentials", so
  this migration will not reach the cloud project until that is provisioned. Out
  of scope, already tracked in AGENTS.md.

**Non-goals:** no data backfill (KTD6); no change to the table constraint; no
change to the client-side Dart sync path — the RPC contract is unchanged from the
caller's perspective for every input that was previously accepted.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Copying the wrong `sync_push` body reverts issue #3 U4 or issue #4 U1 | Medium — six migrations define this function and #96 names a superseded one | High — silent feature regression, exactly the failure class #96 documents | KTD1 pins the source to `20260906200000`; verification step 4 asserts `merge_tag_arrays` and `birth_year` survive; `same_date_tag_merge_test.sql` and `guardian_sync_push_test.sql` fail loudly if reverted |
| New tests pass via the table CHECK and prove nothing | High if written naively — the existing tags assertions have this exact defect | Medium — the regression could recur undetected | KTD5's drop-the-constraint assertion; the red-before-green requirement in verification step 6 |
| Clients that currently rely on the laundering path start seeing rejections | Low — it requires a same-date collision *and* malformed tags, which a correct client never sends | Low — rejected rows are already a normal, handled sync outcome | The laundered result was silently wrong data; rejecting is the intended contract. Flag it in the PR description as an intentional behavior change, since #96 itself predicts "no behavior change" |
| Migration filename sorts before the current tip | Low — today's date sorts naturally after `20260906240000` | High — would never apply in order on a from-scratch environment | U1 requires generating the name via the CLI and explicitly verifying the prefix (AGENTS.md rule 7) |
| `plan(N)` not bumped | Medium — easy to forget | Low — pgTAP fails loudly and immediately | Caught by verification step 5 |

**Dependencies:** Docker (for the local Supabase stack) and network access to
fetch `supabase@2.116.0`. No new database extensions, no new dependencies,
no schema/DDL changes beyond the function replacement.

---

## System-Wide Impact

- **Client (Flutter/Dart):** none. The RPC signature, response shape, and the
  opaque `{"id": …, "rejected": true}` rejection format are unchanged. Any input
  previously accepted on the non-collision path is still accepted.
- **Other RPCs:** none. `merge_tag_arrays`, `day_entries_tags_check`, and
  `is_valid_tags_array` are all untouched; only `sync_push`'s body changes.
- **Security posture:** strictly improved — validation moves back inside the
  security boundary and stops depending on a table constraint that the merge path
  could route around.
- **Deploy:** one additional migration in the (currently blocked) push backlog.
  Forward-only, no `down` migration, consistent with the rest of the repo.

---

## Sources & Research

- Issue #96 (`gh issue view 96 --repo wjdavis5/lunarlog`) — origin report.
- `supabase/migrations/20260903170000_tags_string_array_check.sql` — defines
  `is_valid_tags_array` (lines 7-22), the table CHECK (38-41), and the original
  RPC-level call (236-238).
- `supabase/migrations/20260904020000_sync_push_and_invitations.sql` — the rewrite
  that dropped it (the migration #96 names; since superseded).
- `supabase/migrations/20260906160000_profile_subject_metadata.sql:80` and
  `supabase/migrations/20260906200000_same_date_tag_merge.sql:65` — the two later
  redefinitions; the latter is the current live body (tags branch at 312-315,
  resolver at 361-411, `merge_tag_arrays` at 35-54).
- `supabase/tests/sync_push_test.sql:4` (`plan(105)`), `:412-439` (existing tags
  block) — the coverage that currently passes via the table CHECK.
- `supabase/tests/same_date_tag_merge_test.sql:285-307` — the 32-tag collision
  case that must keep passing.
- `supabase/tests/rls_isolation_test.sql:125-132` — existing table-level
  non-array and over-32 rejection coverage.
- `AGENTS.md` — "Migration Flow" (CLI-generated names, filename sort order, the
  don't-edit-merged rule, `get_advisors` before deploy) and the migration/test
  inventories updated by U3.
- `.github/workflows/ci.yml:178-203` — the `db-tests` job and its exact commands.
- `supabase/config.toml:32-34` — local database port `54322`.

No external/web research was needed: the change is entirely local to this repo's
migration history and pgTAP suite, and the relevant Postgres behavior
(`jsonb_array_elements_text` coercing scalars to text) was confirmed by reading
`merge_tag_arrays` against the existing merge tests rather than from documentation.
