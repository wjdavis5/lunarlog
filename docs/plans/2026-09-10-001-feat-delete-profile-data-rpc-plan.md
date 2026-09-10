# Plan — `delete_profile_data()` RPC to purge a single profile (Issue #264)

Date: 2026-09-10 · Branch: `feat/264-delete-profile-rpc` · Epic: Privacy & Compliance (P2)

## Context

Issue #264: a profile can only ever be tombstoned (`sync_push` sets
`deleted_at`); there is no DELETE grant on `public.profiles` for
`authenticated`, and the only hard-delete RPC, `delete_account_data()`, is
all-or-nothing on the caller's whole account. A parent who wants one child's
record gone — after an ownership transfer, on the child's request, or because
it was created in error — has no path short of deleting their entire account,
and the tombstoned profile and its entries remain on the server for every
guardian indefinitely.

This is the server-side half only, per the dispatch brief: one migration
(`20260910110000_delete_profile_data.sql`) plus its pgTAP suite
(`delete_profile_data_test.sql`). The client confirmation UI named in the
issue's last AC belongs to whichever issue owns the profile-management screen
(issue Assumption: the RPC ships first).

Dependency #159 (provenance `source`/`source_id` columns,
`20260908170000_import_provenance.sql`) is landed, so the `p_source` variant
ships with the base RPC as the issue requires.

## Product contract

1. `public.delete_profile_data(p_profile_id text, p_source text default null)`
   hard-deletes ONE profile and everything attached to it, returning
   per-table deleted-row counts in the `delete_account_data()` shape.
2. Authority: only the profile's **accepted `primary_guardian`** — the same
   rung `sync_push` already requires for tombstone-deletion/archival. A
   nonexistent profile and an unauthorized caller raise the identical
   (enumeration-safe) `42501`.
3. With no `p_source`, the purge removes: `day_entries`, `observations`,
   `profile_modes` (the #188 mode row), `cycle_overrides`, `care_notes`,
   `visit_prep_items`, `profile_reminder_windows`,
   `missed_entry_alert_state`, `notification_preferences`,
   `notification_outbox`, `guardian_invitations`, `profile_guardians`
   (co-guardians' memberships — and their own entries on this profile — die
   with it, the issue's explicit, deliberate behavior), `import_jobs`,
   `ownership_transfers`, `prediction_connections`, `prediction_projections`,
   the profile's `sync_signals` row (via `touch_sync_signal()`'s existence
   check), and the `profiles` row itself. Per-user tables (`settings`,
   `push_devices`, `feedback_tickets`) survive; `delete_account_data()` is
   untouched.
4. With `p_source`, only rows carrying that exact `source` value on the
   profile go (`day_entries`, `observations`, `import_jobs`); the profile and
   every guardian row survive, and a full purge remains available afterwards.
5. Not idempotent: a second call on a purged profile raises (unlike
   `delete_account_data()`), because the authority row is gone with the
   profile.

## Key technical decisions

- **SECURITY DEFINER, `authenticated`-only.** An authenticated caller holds
  no DELETE grant on `public.profiles` (the tombstone path is `sync_push`).
  `revoke execute ... from public, anon; grant ... to authenticated` — the
  `delete_account_data()` grant shape. RLS and every existing grant/policy
  are untouched.
- **Explicit counted deletes, then the profile row.** Mirrors
  `delete_account_data()`: the FK cascades would remove the same rows
  regardless; the explicit deletes exist so the returned counts are exact.
  Order only matters for counts: `observations` before `day_entries` (the
  latter would cascade the former), and `prediction_projections` before
  `prediction_connections` (deleting a connection fires
  `prediction_connections_projection_gc()`, which would remove the
  projection row first and zero the count).
- **`p_source` matches exactly per table, no cross-table translation.**
  `day_entries.source`/`import_jobs.source` use
  manual/clue_import/healthkit/health_connect/file_import;
  `observations.source` uses manual/apple_health/health_connect/wearable/
  clue_import. The RPC validates against the union (a typo raises
  `22023` instead of silently deleting nothing) and matches each table's
  own column exactly. A healthkit purge kills the apple_health observations
  riding its day_entries via the FK cascade; `'apple_health'` exists as a
  call for independently-shaped observation provenance.
- **`sync_signals` is counted, not deleted.** The profiles delete's AFTER
  trigger runs `touch_sync_signal()`, whose existence check removes the row
  (`realtime_publication_test.sql` proves the branch); counting it first
  keeps the returned document complete without racing the trigger.

## Implementation units

- **U1 — Migration** `supabase/migrations/20260910110000_delete_profile_data.sql`
  (sorts after the current tip `20260910000000_high_severity_intensity.sql`):
  the function, its comment, and the revoke/grant.
- **U2 — pgTAP** `supabase/tests/delete_profile_data_test.sql`, 71
  assertions in five groups: A function shape + RLS-never-weakened (no new
  table DELETE grants); B no-JWT refusals; C authority matrix (co_parent,
  caregiver, viewer, invited-but-not-accepted, revoked, outsider,
  nonexistent profile — all raising the identical error and deleting
  nothing); D full purge (exact returned jsonb, all 17 per-table zeros, the
  co-guardian's own entry gone with the profile, co-guardian's own /
  outsider's other-profile data byte-identical, per-user tables intact,
  non-idempotency); E `p_source` variant (authority, `22023` validation,
  zero-match zeros, exact healthkit counts, survival of manual/other-source
  rows and guardians, full purge still available).

## Acceptance criteria (issue ACs → where proven)

- RPC exists, SECURITY DEFINER, authenticated-only, accepted
  primary_guardian-only → test group A/C.
- Hard delete cascades all named tables + sync_signals → group D.
- Per-table counts in the `delete_account_data()` shape → group D exact-jsonb.
- Non-primary-guardian rejected with authorization error → group C.
- `p_source` variant scopes to `source = 'healthkit'`, other data intact →
  group E.
- pgTAP mirrors `account_deletion_test.sql`, incl. co-guardian's own entries
  removed → groups D (test 31) and the byte-identical survival asserts.
- Client "delete this profile" confirmation UI → **not done here**
  (server-only dispatch; belongs to the profile-management-screen issue).

## Explicitly out of scope

Client UI; co-guardian notification before a purge (issue Assumption: rides
the caregiver-alert infrastructure as a follow-up); any change to
`delete_account_data()`; retiring or changing any RLS policy/grant.
