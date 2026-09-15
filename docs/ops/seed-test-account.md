# Seeding a test account with realistic sample data (issue #710)

An **operator-run, never-shipped-in-the-app** Dart CLI that populates a
fabricated test account (the Apple review account is one allowlisted
member) with 18 months of realistic sample data. It signs in as the account
and writes through the **real `sync_push` RPC and the real sharing RPCs**,
so every server-side invariant (CHECKs, triggers, RLS, role ladders) is
exercised exactly as the app exercises it, and a fresh device install syncs
the data down without rejections.

```
dart run tool/seed_test_accounts/main.dart [--months 18] [--seed 42]
    [--reset-and-reseed] [--state-file .seed-state.json]
    [--emit-pgtap supabase/tests/seed_sync_push_sample_test.sql]
```

All names, notes, and values are fabricated. Never point this tool at a
real person's account.

## Environment keys (names only — values live in `.env`, never committed)

| Key | Meaning |
| --- | --- |
| `SUPABASE_URL` | Selects the environment. `http://127.0.0.1:54321` is the local stack (demo keys are used automatically). |
| `SUPABASE_PUBLISHABLE_KEY` | Required for a non-local URL (local falls back to the public demo key). |
| `SUPABASE_SECRET_KEY` | Required for a non-local URL. Used **only** to create a missing account or add a password identity to an allowlisted account that has none — never for any data write. |
| `LUNARLOG_SEED_ACCOUNT_EMAIL` | The target account to seed. Must be in the allowlist. |
| `LUNARLOG_SEED_PARTNER_EMAIL` | The fabricated sharing partner. Must be in the allowlist and differ from the target. |
| `LUNARLOG_SEED_ALLOWLIST` | Comma-separated fabricated test-account emails. The tool refuses to run — before any network call at all — unless both emails are members. |
| `LUNARLOG_SEED_PASSWORD` | Shared fabricated password for both accounts. |
| `LUNARLOG_SEED_PASSWORD_<SLUG>` | Optional per-account override, where `<SLUG>` is the uppercased email with non-alphanumerics replaced by `_` (e.g. `LUNARLOG_SEED_PASSWORD_SEED_E2E_LOCAL_EXAMPLE_COM`). |

## Account bootstrap

If the target (or partner) email does not exist, the tool creates it via
the admin API with the configured password. If the account exists but has
no password identity (e.g. an Apple-sign-in-only review account), the tool
**adds** one — additive, so Apple sign-in keeps working. If the account
already has a password identity that does not match the configured one, the
tool refuses rather than overwrite it.

## Reset / re-run semantics

- A gitignored local state file (`.seed-state.json` at the repo root)
  records what the tool created per target account: user ids, current and
  retired profile ids, partner email, and the run config (months, seed).
- On re-run, the tool first verifies every **live** profile the target (and
  the partner) can see — RLS-scoped `profiles` + `profile_guardians` reads
  as the account — is a tool-created id from the state file. If any row was
  not created by the tool, it **refuses** and touches nothing.
- Otherwise it resets by calling `public.delete_profile_data(p_profile_id)`
  (the owner RPC: full purge including co-guardians' rows, prediction
  connections, and the notification outbox) for each tool-created profile,
  then re-seeds with fresh profile ids. The prior ids are tombstoned by the
  RPC and recorded in the state file as `retiredProfileIds`.
- A re-run with a **different** `--months`/`--seed` than the state file
  records is refused unless `--reset-and-reseed` is passed explicitly.
- `--months` is clamped to a minimum of 12; the default is 18.
- Determinism: with a fixed clock and `--seed`, the payload is
  byte-identical (pinned by `test/tool/seed/`). At runtime the real clock
  is used, so each run's ULIDs and dates differ while the shapes stay the
  same.

## What gets seeded

Two profiles per target account:

- **Adult self profile** ("Maya"): `relationship: self`, birth year ~1988,
  care mode `standard`, life-stage mode `tracking`, °C / kg.
- **Teen profile** ("Riley"): `relationship: daughter`, birth year ~2012,
  minor, care mode `teen`, life-stage mode `tracking`, **°F / lb** (both
  display units are exercised).

Content per profile: 18 months of cycles (26–32 day length, 4–6 day
periods, all writable flow levels; spotting as its own observation
category, never a flow), two `cycle_overrides` (one `excluded_from_average`,
one `manual_start`), a current in-progress cycle starting ~2 weeks ago,
daily BBT with a biphasic curve and a few excluded outliers, weekly weight
with slow drift, graded pain observations (intensity mostly ≤ 3 with a
couple of 4s), symptom/mood observations using real taxonomy codes, the
#456 perimenopause cluster occasionally on the adult, PMS days
(`pms: true` plus taxonomy tags), occasional notes, ~6 care notes, ~10
visit-prep items (some checked — the server stamps who/when from the
caller), and one `upsert_reminder_window` per profile computed from the
generated cycle math. `notification_preferences` is deliberately never
written (default-off keeps the outbox clean).

Sharing (via the second fabricated account): a `co_parent` guardian on the
adult profile and a `caregiver` on the teen profile (invitation created by
the owner, accepted by the partner within the same run — the client
generates the raw token and sends only its SHA-256), plus one prediction
connection on the **adult profile only** (the teen counts as a minor via
`profile_counts_as_minor` — sharing it is refused by design, so the tool
never attempts it).

## Local validation flow

Docker must be running. From the repo root:

```
npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor
npx supabase@2.116.0 db reset --local
```

Notes:

- `db reset` **wipes `auth.users`**, so the tool re-bootstraps the accounts
  on every run — that is expected and is exactly what the bootstrap path is
  for.
- With `SUPABASE_URL=http://127.0.0.1:54321`, the tool uses the local stack's
  public demo keys automatically; to use the per-install keys
  `npx supabase@2.116.0 status` prints instead, set
  `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY` explicitly.

Then run with obviously-fabricated local emails (never print passwords):

```
# in .env (gitignored):
#   SUPABASE_URL=http://127.0.0.1:54321
#   LUNARLOG_SEED_ALLOWLIST=seed.e2e.local@example.com,seed.partner.local@example.com
#   LUNARLOG_SEED_ACCOUNT_EMAIL=seed.e2e.local@example.com
#   LUNARLOG_SEED_PARTNER_EMAIL=seed.partner.local@example.com
#   LUNARLOG_SEED_PASSWORD=<fabricated>

dart run tool/seed_test_accounts/main.dart
```

Success looks like `rejected == []` on every `sync_push` call plus a
read-back line reporting the seeded row counts. Re-running the same command
exercises the reset path (guard → `delete_profile_data` → re-seed).

**Do not create `supabase/seed.sql`**: `supabase/config.toml`'s `[db.seed]`
points at it, so adding one would feed **every** `db reset` — the seeder is
deliberately an explicit, operator-run command instead.

## Cloud flow

Only after local validation passes: point `SUPABASE_URL` (plus the real
`SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_SECRET_KEY`) at the project and
run the same command with the allowlisted review-account emails. The tool's
safety gates (allowlist, foreign-profile guard, state file) are identical
against the cloud project.

## Expected post-state (what the app shows)

Sign in on a device as the seeded account (Apple sign-in still works; the
added password identity works too):

- **Profile switcher**: "Maya" (self) and "Riley" (teen) profiles.
- **Calendar / month view** (Maya, Riley): 18 months of daily entries —
  bleed days with flow levels, PMS-flagged days, symptom dots, notes.
- **Day sheet** (Maya): °C BBT field with a biphasic chart (a few points
  excluded), kg weight field on weekly days, graded pain chips, spotting
  toggle on spotting days, perimenopause cluster chips on occasional days.
- **Day sheet** (Riley): the same in °F and lb.
- **Insights / predictions**: cycle statistics from ~18 completed cycles
  with one excluded outlier cycle, one manual-start correction, and an
  in-progress cycle (~2 weeks in).
- **Manage guardians** (as the target): the partner as `co_parent` on Maya
  and `caregiver` on Riley.
- **Prediction sharing**: one active prediction connection on Maya (none
  on Riley — minors are never shared).
- **Visit prep / care notes**: ~6 care notes and a ~10-item checklist with
  some items checked.

## The fresh-install device check (final verification)

The last verification step is a **manual device check** (AC #3 — it cannot
be automated here): install a fresh build, sign in as the seeded account,
and confirm the first sync pulls everything down without rejections — both
profiles appear, the calendar shows the seeded history, and Manage
guardians shows the partner. Sign in as the partner account and confirm it
sees the shared profiles with the right roles and the shared prediction.
Use fabricated accounts only — never real family data.
