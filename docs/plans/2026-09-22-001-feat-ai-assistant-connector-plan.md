---
title: AI-Assistant Connector (Issue #117) - Ideation & Plan
type: feat
date: 2026-09-22
issue: wjdavis5/lunarlog#117
artifact_contract: ce-unified-plan/v1
artifact_readiness: needs-owner-decision
product_contract_source: issue-117
execution: docs
---

# AI-Assistant Connector — Ideation & Plan (Issue #117)

Date: 2026-09-22 · Branch: `opencode-deepseek/117-connector-plan` · Epic: none (unplanned backlog idea)

All paths repo-relative. Every claim below was re-verified against this
checkout (tip `ebded9e9`) rather than copied from the issue. The issue is a
backlog idea, filed 2026-09-20 ("needs ideation before implementation — auth
model, minors' data exposure, scope of what is queryable") and explicitly
**parked** by the owner on 2026-09-20 ("not dispatchable and not in the
human-review queue; any future scoping must start with auth model and
minors'-data exposure"). This document is the ideation pass the issue asks
for. It recommends a v1 and a set of alternatives, but **it must not be
dispatched until the owner decisions in "Owner decisions needed" are
answered** — the sibling per-viewer lens plan was `ready-for-implementation`
because the owner had already ruled; this one is not.

## Owner decisions needed (crisp)

These are the questions a coder cannot answer. Each is framed as a choice, not
an essay. Defaults proposed in this plan are in brackets.

1. **Minors: may the connector ever return a minor profile's data?**
   - (a) **Never** — a profile whose minor status resolves true is excluded
     from every tool, for every token. [safest]
   - (b) **Primary guardian + explicit per-profile opt-in** — the token's
     account must be that profile's accepted `primary_guardian`, and the
     operator must tick an explicit per-profile consent that names the
     assistant. [this plan's recommendation]
   - (c) Primary guardian only, no extra opt-in.
2. **Which assistant(s) ship in v1?** (a) Claude, (b) ChatGPT, (c) both, (d) a
   local/stdio bridge only. [this plan recommends "both facades, one HTTP
   contract" — see D-7]
3. **Notes: counts-only forever, or expose non-private note *text* once #849's
   per-note private flag lands?** [this plan recommends counts-only in v1 and
   never guardian notes; note text only if #849 ships and only when the note is
   not marked private]
4. **Who may mint a connector token?** (a) any signed-in account, (b) only a
   profile's `primary_guardian`/owner, (c) any account that is an accepted
   guardian somewhere. [this plan recommends any signed-in account, because the
   token's reach is already bounded by RLS — but see Q1]
5. **Does the connector ship in store builds, or web/server-side only behind a
   flag until issue #21 is updated?** A store build that offers the connector
   changes the Play Data safety "Data shared" section and the App Store privacy
   policy; choosing (b) lets the server work land before the store paperwork.
   [this plan recommends (b) until #21 lands]
6. **Approve the new third-party recipient.** The assistant provider
   (Anthropic and/or OpenAI) receives the tool results. This requires a new
   `PRIVACY.md` §4 table row and a §2 disclosure; it is a new data recipient,
   not a new category the app collects. [must be owner-approved]
7. **Token invalidation on credential events.** Should "Sign out everywhere",
   a password change, or adding a passkey revoke all connector tokens? [this
   plan recommends: not automatically — the token is not a session — but
   provide a "Revoke all" action and auto-revoke on account deletion]
8. **Default profile scope.** Does a token see every profile RLS already makes
   visible, or must each profile be granted individually? [this plan
   recommends: every RLS-visible *adult* profile; minors scoped by Q1]
9. **Is Cloudflare in the data path acceptable?** The recommended MCP URL is
   `app.lunarlog.app/mcp` served by Cloudflare (D-7). If not, clients point
   directly at the Supabase function URL and Cloudflare is out of the path.

## Context

lunarlog's differentiator is a synced, multi-guardian household record
(`README.md` "Family sharing"; `PRIVACY.md` §1). Issue #117 asks whether a
read-only AI-assistant connector — "an assistant can answer questions about a
household's logged data" — is worth building, and if so, on what security
model. Nothing exists today:

- No connector, token, MCP, or OpenAPI code anywhere in `lib/`,
  `supabase/functions/`, or the migrations (grep for `mcp`/`connector` under
  `lib/` and `supabase/` finds only unrelated tooling references).
- The only server read surfaces an external party could call are the
  PostgREST tables and the SECURITY DEFINER RPCs, all of which require a
  **Supabase session JWT** — there is no token that lets a non-app client read
  a bounded projection.
- The only existing "share a profile's derived data with another party"
  feature is the prediction connection, which is a one-way, server-computed
  snapshot barred for minor profiles
  (`supabase/migrations/20260913019000_prediction_minor_gate_durable.sql`;
  `PRIVACY.md:124`). The connector is a materially larger surface: the
  assistant receives whatever the connected account can see.

The three questions the issue names are answered in the three "Question"
sections below. The rest of the document is the implementation shape if the
owner approves a v1.

### What the authorization model is today (verified)

- **Every content table's SELECT policy is `is_profile_guardian(profile_id,
  auth.uid())` with no role predicate.** `day_entries`
  (`supabase/migrations/20260904010000_multi_guardian_schema.sql:289-293`),
  and the same shape on `observations` and the care-note/prep tables. The
  helper checks only `status = 'accepted'`
  (`20260904010000_multi_guardian_schema.sql:99-113`, hardened so it only ever
  answers about the calling user in
  `20260915010000_db_integrity_bundle.sql:118-134`). **Role constrains writes
  only** — the insert/update policies are role-gated
  (`20260904010000_multi_guardian_schema.sql:295-310`).
- **So a `viewer` reads everything** — flow, all tags, observations, shared
  notes, every guardian's care notes. The owner confirmed this is intended
  (`PRIVACY.md:119`; issue #849's 2026-09-20 decision).
- **There is no per-note private flag in the tree.** Grep for
  `note_private`/`is_private` finds no column in `supabase/migrations/` and no
  field in `lib/`. Issue #849's proposal for a `full`/`status` visibility tier
  was **not approved**; the owner's 2026-09-20 decision instead scoped the one
  privacy control to a per-note "private" flag the subject may set on her own
  note — and that re-scoped flag is not built either
  (`docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:96-104`).
- **The lens.** The viewer-dependent axis is being added by #850:
  `GuardianLens.subject` vs `GuardianLens.guardian`, resolved from
  `ProfileGuardian.isSubject` (`lib/domain/sharing/guardian_lens.dart:52-59`;
  `lib/domain/models/profile_guardian.dart:96`). Presentation only — it
  changes no permission (`docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:71-74`).
- **"Counts, not content" is the established household-facing discipline.**
  The activity feed shows a flow *label*, a tag *count*, and a note
  *boolean*, never note text or tag codes
  (`lib/ui/sharing/activity_feed_screen.dart:301-327`). The connector should
  inherit this rule, not invent a new one.

### Existing Edge Function auth posture (verified)

The repo already has three shapes to copy from:

| Function | `verify_jwt` | How it authenticates | How it authorizes |
| :--- | :--- | :--- | :--- |
| `feedback-notify` | `true` (`supabase/config.toml:437-444`) | Platform proves *someone* signed in | Handler re-reads the caller's JWT with the anon key (`supabase/functions/feedback-notify/index.ts:249-256`) and checks ticket ownership itself |
| `delete-account` | `true` (`supabase/config.toml:417-421`) | Platform proves a JWT | Handler resolves the caller, then runs `delete_account_data()` on a **user-scoped** client so RLS/`auth.uid()` hold (`supabase/functions/delete-account/index.ts:483-486,876-891`) |
| `feedback-reply` / `push-dispatch` | `false` (`supabase/config.toml:446-465`) | Handler validates a shared-secret header it owns (`supabase/functions/feedback-reply/index.ts:31-33,66-70`) | Caller is a trusted webhook/cron |

All four are built as `handleX(req, deps)` + `buildDeps(env, clientFactory)`,
so `deno test` covers them with fakes
(`supabase/functions/feedback-notify/index.ts:241-287`; `deno.json`'s test
include, `supabase/functions/deno.json:5-7`). `verify_jwt = true` proves only
"some signed-in user", never *which rows* they may touch
(`feedback-notify/index.ts:1-31`) — a connector token is not a Supabase JWT,
so `verify_jwt = false` plus a handler-owned check is the matching shape.

Two facts bound the auth design:

- **A connector token must never be the Supabase session.** The session is a
  full account credential that works against every table/RPC the RLS policies
  expose; handing it to an assistant is strictly worse than handing it a
  bounded read-only projection. The app's own browser threat model already
  treats session-token theft as total compromise for the rows that account
  can reach (`docs/web/security-posture.md:59-79,171-185`).
- **No OAuth authorization server exists.** `[auth.oauth_server] enabled =
  false` and `allow_dynamic_registration = false` (`supabase/config.toml:409-415`);
  the project's JWT expiry is 600 s (`supabase/config.toml:167-172`). Any MCP
  OAuth flow is new work, not a reuse of Supabase's.

---

## Question 1 — Auth model

**Recommendation: a per-account, revocable, scoped opaque connector token,
minted from Settings behind the device gate, presented as a bearer to a new
read-only Edge Function that executes every query under the account's own
RLS context. The Supabase session and the service role are never handed out,
and no content is ever read under service-role privileges.**

### D-1 — The credential is an opaque, hashed, account-scoped token, not a JWT and not a session.

A new table `public.connector_tokens`:

| column | type | notes |
| :--- | :--- | :--- |
| `id` | `uuid` PK | |
| `user_id` | `uuid` → `auth.users on delete cascade` | the account the token acts as |
| `token_hash` | `text not null unique check (token_hash ~ '^[0-9a-f]{64}$')` | SHA-256 of the secret; **the plaintext is never stored** |
| `label` | `text` (≤ 80) | operator-facing name ("Claude on my laptop") |
| `scopes` | `text[] not null default '{read}'` | v1 has exactly one scope, `read`; future action tools add values |
| `allowed_profile_ids` | `text[]` | null = every RLS-visible adult profile; set = only these (see Q8/Q1) |
| `last_used_at` | `timestamptz` | updated by the resolver |
| `created_at` / `expires_at` / `revoked_at` | `timestamptz` | `expires_at` nullable (no expiry by default); revoke is a timestamp, never a delete |

The hash-at-rest pattern is already the repo's: `guardian_invitations.token_hash`
is `^[0-9a-f]{64}$` and never selected by export
(`supabase/migrations/20260904010000_multi_guardian_schema.sql:142-144`;
`supabase/migrations/20260921100000_account_consents.sql:324-346`). A signed
JWT was rejected because minting one needs either the project's signing key or
a symmetric `SUPABASE_JWT_SECRET`, neither of which the app should depend on;
an opaque random secret resolved server-side needs neither and is revocable
instantly.

### D-2 — The Edge Function is the host, and `verify_jwt = false`.

A new `supabase/functions/mcp-connector/` directory, registered in
`supabase/config.toml` the way the other four are
(`supabase/config.toml:437-465`), with `verify_jwt = false` because the caller
is not a Supabase user. The handler reads `Authorization: Bearer <token>`,
hashes it, and resolves it — exactly the "handler owns its own auth" shape
`feedback-reply`/`push-dispatch` already use. The function is built as
`handleMcpConnector(req, deps)` + `buildDeps(env, clientFactory)`, and its
directory is added to `deno.json`'s `test.include`
(`supabase/functions/deno.json:5-7`).

### D-3 — RLS is the authorization boundary; the service role never reads content.

This is the load-bearing decision. The function's only service-role use is:

1. resolve `token_hash` → `{ user_id, scopes, allowed_profile_ids, revoked, expires }`
   via a service-role-only RPC (`resolve_connector_token`),
2. invoke **one** SECURITY DEFINER RPC, `connector_exec(token_hash, tool, params)`,
   whose `EXECUTE` is revoked from `authenticated`/`anon` (the
   `rehome_stray_day_entries` precedent, `supabase/functions/delete-account/index.ts:53-62`).

`connector_exec` re-resolves the token itself (so the Edge Function's
resolution is for producing HTTP errors, not for authorization), then runs the
whitelisted read query **as the account**:

```sql
-- inside connector_exec, after resolving v_uid from the token hash
perform set_config('role', 'authenticated', true);
perform set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text,
  true
);
-- then the tool's SELECTs; auth.uid() == v_uid, every RLS policy applies
```

Because the query executes with `role = authenticated` and `auth.uid() = v_uid`,
the existing `is_profile_guardian(...)` SELECT policies and every future
tightening apply unchanged. There is no second authorization model to audit,
and no path where the function can return a row the account could not see in
the app. **Alternative rejected:** minting a short-lived JWT with the mapping
in a custom claim — it needs a signing key the app should not own and creates a
second credential type to rotate. **Alternative flagged for the coder:** if the
impersonation mechanism proves fragile, a "claim-carrying JWT signed inside
`connector_exec` and re-presented to PostgREST" is the fallback, but it must
still resolve the account server-side from the token, never from client input.

### D-4 — Mint, rotate, revoke — all server-side, all behind the device gate.

The client never generates a token and never writes the table:

- `create_connector_token(p_label text, p_profile_ids text[] default null)`
  generates `gen_random_bytes(32)` → base64url, stores its hash, returns the
  plaintext **once**. This is a SECURITY DEFINER RPC that derives the owner
  from `auth.uid()` (the `record_minimum_age_acknowledgement` shape,
  `supabase/migrations/20260921100000_account_consents.sql:150-161`).
- `rotate_connector_token(p_id uuid)` mints a new secret for the same row
  (or mints a new row and revokes the old — coder's choice) and returns the
  new plaintext once.
- `revoke_connector_token(p_id uuid)` sets `revoked_at = now()`.
- `revoke_all_connector_tokens()` for Q7.

**Settings UI:** a new tile under the Account section (mounted beside the
existing provider/delete tiles, `lib/ui/account/account_section.dart`). Every
create/rotate/revoke action runs `gate.reauthenticate()` first, exactly like
the add/remove-provider flows (`account_section.dart:659-698`;
`lib/gate_controller.dart:862`), and the plaintext is shown once in a
copy-to-clipboard dialog with a "you will not see this again" note. Because
the token is minted on the device that holds the session, it inherits the
device-credential gate without inventing a new one.

### D-5 — Token lifecycle is disclosed, exported, and deleted.

- **Export:** `export_account_data()` gains a top-level `connector_tokens`
  array with `id`, `label`, `scopes`, `allowed_profile_ids`, `created_at`,
  `last_used_at`, `expires_at`, `revoked_at` — **never `token_hash`**, exactly
  as `guardian_invitations`' hash is never selected
  (`supabase/migrations/20260921100000_account_consents.sql:324-346`). The
  existing `schema_version: 1` stays 1 for a purely additive key
  (`account_consents.sql:564-582`).
- **Deletion:** `delete_account_data()` deletes the caller's own
  `connector_tokens` rows explicitly, the way it deletes `account_consents`
  (`account_consents.sql:589-601`), in addition to the `auth.users` cascade.
- **Revocation is effective immediately** because the resolver rejects
  `revoked_at is not null`/expired rows on every call; there is no cached
  session to expire.

---

## Question 2 — Minors' data exposure

**Recommendation: the connector sees exactly what the token's account sees
through RLS — a guardian's lens is "everything except notes marked private",
a subject's lens is her own record — but v1 layers stricter defaults on top:
no minor profile is exposed unless the account is that profile's accepted
`primary_guardian` *and* an explicit per-profile opt-in exists, no private
note is ever exposed, and no free-text note is exposed at all by default
(counts only), mirroring the guardian card's "counts, not content".**

### D-6 — RLS is the ceiling, not the default.

RLS today already means a guardian reads everything and a `viewer` reads
everything (`20260904010000_multi_guardian_schema.sql:99-113,289-293`;
`PRIVACY.md:119`). If the connector simply inherited RLS, a `caregiver` or
`viewer` account could point Claude at a 14-year-old's full note history the
moment they connected, which is a larger transfer than the app has ever
performed. The connector therefore **narrows** below RLS with a second,
explicit gate. RLS remains the backstop (nothing RLS forbids can leak), but
the product does not push the entire RLS surface to a third party by default.

### D-7 — Minor gate: primary guardian + explicit per-profile opt-in.

A profile is treated as a minor by the same rule `PRIVACY.md` §5 states: the
profile's `birth_year` when present (minor until 18), falling back to the
stored minor flag (`PRIVACY.md:118`;
`supabase/migrations/20260920100000_minor_status_birth_year_authoritative.sql`).
When a tool is asked about such a profile, `connector_exec` requires **all**
of:

1. the token's account is an accepted `primary_guardian` on that profile
   (`is_guardian_with_roles(profile_id, uid, array['primary_guardian'])`,
   `20260904010000_multi_guardian_schema.sql:115-130`), and
2. an explicit opt-in row exists — a new `connector_profile_grants`
   (`token_id`, `profile_id`, `granted_at`) written only through a
   device-gated RPC and surfaced in Settings with copy that names the
   assistant and the minor's profile, and
3. the minor profile is in the token's `allowed_profile_ids` (or that column
   is null and the grant above satisfies it).

A minor profile with no grant is **omitted from `list_profiles` entirely**,
not merely blanked, so the assistant cannot even learn it exists. This mirrors
the prediction connection's server-side minor refusal, which is re-checked at
redemption because the minor flag can change in between
(`PRIVACY.md:124`;
`20260913019000_prediction_minor_gate_durable.sql`), and the Play declaration's
"minor profiles are never shared" posture (`PRIVACY.md:122`).

### D-8 — Private notes never; no note text at all in v1.

- **When #849's per-note private flag lands** (it does not exist yet —
  `docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:96-104`),
  a note the subject marked private must be excluded by the same RLS/backstop
  rule, and the connector's note projection must be written so it cannot
  surface it. Until then there is nothing to distinguish, so the connector
  must not assume "no private flag exists" in its query shape.
- **In v1 the connector exposes no note text at all** — not shared day notes,
  not guardian notes, not care notes, not merge disclosures. This is stricter
  than #849 (which keeps only the *subject's own marked-private* note from
  guardians), and it is the rule the guardian card already follows: a note is
  a boolean ("has a note"), never its content
  (`lib/ui/sharing/activity_feed_screen.dart:301-327`). This removes the
  entire class of "the assistant quoted my diary" before it can happen, and it
  is the cheapest thing to relax later (Q3).

### D-9 — Counts, not content, throughout.

Every tool returns counts and coarse labels only: flow-level *counts* per
level, tag *counts* (never tag codes), symptom *counts* per category, cycle
*lengths* and an *estimate date/range with its confidence tier*. No note text,
no tag codes, no raw observation values, no timestamps finer than a date. The
projection is deliberately the same shape as the app's own household surfaces.

---

## Question 3 — Scope of what is queryable

**Recommendation: a small, fixed, read-only tool set — profile list, cycle
summary, next estimate with confidence, symptom trend over a window, last
logged — never raw table or SQL access, no writes in v1, with a per-token
rate limit and an audit log.**

### D-10 — Five tools, whitelisted in the database, no dynamic SQL.

The tool surface is a closed `case` inside `connector_exec`; `params` is
validated against each tool's declared keys. There is no `run_sql` tool, no
arbitrary `select`, and no table name ever comes from the client. Each tool
returns a JSON object and a `profile_id`; the profile is checked by RLS
(and D-7's minor gate) before any row is read.

| Tool | Input | Output (counts/facts only) |
| :--- | :--- | :--- |
| `list_profiles` | — | for each RLS-visible, grant-eligible profile: `id`, `display_name`, `is_minor`, caller's `role`, `last_logged_date`; minor profiles without a grant are omitted |
| `cycle_summary` | `profile_id`, `window_days` | `cycle_count`, `avg_cycle_length_days`, `median_cycle_length_days`, `avg_period_length_days`, `basis` (n cycles) |
| `next_period_estimate` | `profile_id` | `estimate_start` (date), `estimate_end` (range end or null), `confidence_tier` — the same tier the app shows (`supabase/migrations/20260915140000_prediction_projection_confidence_tier.sql:54-168`) |
| `symptom_trend` | `profile_id`, `window_days` | per-category `days_logged` counts; no codes, no values |
| `flow_summary` | `profile_id`, `window_days` | flow-day counts by level label; no per-day rows |
| `last_logged` | `profile_id` | `local_date`, `days_since` |

`next_period_estimate` is the only derived value, and it carries the same
"estimate, not a diagnosis" framing and confidence tier the app already
shows. A fertility/ovulation tool is deliberately **not** in v1: the base
product's own framing is a period estimate, and adding an ovulation tool to
an external assistant raises a bigger `PRIVACY.md` question than #117 asks
(open question for the owner; `PRIVACY.md:18`).

### D-11 — Read-only. No writes in v1, ever.

The connector token's only scope is `read`. There is no tool that logs,
edits, deletes, revokes a guardian, or spends a share. This is both the
product decision and the security decision: an assistant with write access to
a minor's health record is a category of risk the issue does not ask to
accept. Writes, if ever wanted, are a separate owner decision and a separate
token scope.

### D-12 — Rate limiting and an audit log live in Postgres.

Edge Functions are stateless per invocation, so neither a limit nor an audit
trail can live in function memory. A new `connector_call_log` table records
`token_id`, `user_id`, `tool`, `profile_id` (nullable for `list_profiles`),
`at`, and `outcome` — **never any argument content or result content**. It
backs two things:

- a **sliding-window rate limit** (e.g. N calls/minute and M calls/day per
  token) computed by a count over the log; the exact caps are a coder/owner
  call (open question), and the check runs inside `connector_exec` before the
  tool query.
- the operator's own **"connector activity"** view in Settings (which tools
  ran, when) and support forensics.

Rows are purged by the existing nightly `enforce_retention()` job with its own
window (the `day_entry_history` 90-day precedent,
`supabase/migrations/20260915200000_nightly_retention_job.sql:209`), so the
log cannot accumulate forever.

---

## Transport choice (D-13)

**Recommendation: remote MCP over HTTPS at `https://app.lunarlog.app/mcp`,
with the Supabase Edge Function as the host and authorization boundary, plus
an OpenAPI manifest at the same origin for ChatGPT Actions — one HTTP
contract, two facades.** A local stdio bridge is the fallback for clients
that cannot do remote MCP with a static bearer.

| Option | Shape | Why / why not |
| :--- | :--- | :--- |
| **Remote MCP over HTTPS (recommended)** | The client speaks MCP (Streamable HTTP) to `app.lunarlog.app/mcp`; a thin Cloudflare Worker/Pages Function proxies JSON-RPC to the `mcp-connector` Edge Function, carrying `Authorization` through | Stable URL, one origin, aligns with #831's `app.lunarlog.app` hosting; MCP is the direction Claude/others are converging on. Caveat: many MCP clients expect OAuth 2.1 discovery, and this project has no auth server (`supabase/config.toml:409-415`) — v1 depends on the connector token as a static bearer, which the recommended client mix must accept (Q2). Adding a minimal OAuth facade is v1.1 if not. |
| **ChatGPT-style OpenAPI manifest** | `/openapi.json` (OpenAPI 3.1) + bearer/API-key auth; GPT Actions call the same REST routes | Works with ChatGPT today and with any OpenAPI tool-caller; no MCP transport work. But it is provider-specific and does not serve Claude, so it is a facade over the same function, not the primary. |
| **Local stdio bridge** | A small Deno/Node script the user runs; it speaks stdio MCP to the client and HTTPS to the Edge Function with the bearer | Highest compatibility (Claude Desktop), no hosting, no OAuth. But it makes the user install and run code, which is a worse default for a store app and a support burden. Keep as a documented fallback. |

**Cloudflare in the data path:** the recommended URL routes through
Cloudflare, which terminates TLS and therefore sits in the data path. The
authorization boundary is still the Supabase Edge Function; the Worker is a
dumb proxy that must not log bodies or headers. If the owner is not
comfortable with that, clients point at
`https://dleexnnevuuddcgcpztq.supabase.co/functions/v1/mcp-connector` directly
(Q9) — no new infrastructure, no third party in the path, at the cost of a
less stable URL. Either way the Cloudflare web app's strict CSP
(`docs/web/security-posture.md:208-218`) is unaffected: the connector is a
server endpoint, not a browser surface.

**Hosting tie-in (#831):** `app.lunarlog.app` is the deployed web origin
(Cloudflare Pages project `lunarlog-app`, `docs/web/security-posture.md:296-319`;
owner checklist `:337-351`; `docs/ops/supabase-go-live.md:85-105`). Reusing
that origin gives the connector a stable, already-provisioned domain and
keeps the number of externally trusted origins at one. The Worker (or a Pages
Function route) is added alongside the existing deploy, and the owner
checklist grows one item: a route/hostname binding for `/mcp` and the
`/openapi.json` + MCP discovery documents.

---

## Privacy and store-declaration impact

### PRIVACY.md changes (required in the same change as the feature)

The connector is a **new third-party recipient**, so the policy cannot ship
silently. Required edits:

- **§2.A or a new §2.F "AI-Assistant Connector (Optional)"** — what the
  connector is, that it is opt-in per account, that it is read-only, that it
  returns counts/estimate facts and never note text, and that it is created
  behind the device gate (`PRIVACY.md:25-36`).
- **§3 (How We Use Your Information)** — a bullet naming the connector as a
  user-directed read of your own data, not a new collection purpose
  (`PRIVACY.md:71-79`).
- **§4 (Third-Party Service Providers)** — a new table row for the assistant
  provider (Anthropic and/or OpenAI), purpose "optional AI-assistant connector
  you connect", data received "the tool results you request — cycle counts,
  the period estimate and its confidence tier, symptom counts, and last-logged
  dates — plus your account's connector identifier; never note text", location
  "governed by that provider's privacy policy" (`PRIVACY.md:86-95`). This is
  the row the owner must approve (Q6).
- **§5 (Minors)** — the connector never exposes a minor profile unless the
  account is that profile's `primary_guardian` and an explicit per-profile
  opt-in exists; no private note; no note text
  (`PRIVACY.md:114-125`).
- **§6 (Security)** — connector tokens are random secrets, stored only as a
  SHA-256 hash, revocable immediately, never the Supabase session; every query
  runs under the account's RLS (`PRIVACY.md:129-142`).
- **§7 (Export/Retention/Deletion)** — token *metadata* is in "Export my
  data" (never the secret); deleting the account deletes the tokens; the
  connector audit log is aged out by the nightly retention job
  (`PRIVACY.md:146-156`).
- **§9 (Store Declarations)** — the connector is user-directed but the
  assistant provider's servers are a recipient, which changes the Play
  "Data shared" statement if the connector is in a store build
  (`PRIVACY.md:174-181`).
- **§10 change history + the "Last Updated" line** — a dated entry
  (`PRIVACY.md:189-229`).

### Store-declaration impact (issue #21)

Issue #21 is the open checklist that App Store Connect App Privacy and Play
Data safety match `PrivacyInfo.xcprivacy`
(`ios/Runner/PrivacyInfo.xcprivacy`; #21 body). Consequences:

- **Google Play Data safety has an explicit "Data shared with third parties"
  section.** If a store build can connect an assistant, "no data shared"
  becomes false and this section must name the assistant provider and the data
  category (health info), purpose (app functionality), and whether it is
  optional. The Play **Health apps declaration**
  (`docs/ops/play-health-declaration.md`) is filed per permission/data type
  and may need a submission-time update too.
- **App Store Connect** does not have a separate "shared" nutrition label in
  the same way, but guideline 5.1.2 requires the privacy policy to name data
  sharing; the §4 row above is the required disclosure. The privacy policy URL
  already points at the served copy (#831).
- **This is why Q5 matters:** if the connector is server/web-only and not
  compiled into a store build in v1, #21 is untouched until the connector
  actually reaches a store binary. If it ships in a store build, #21 cannot be
  closed until the Play declaration is updated.

---

## Numbered decisions (summary)

- **D-1** Opaque, hashed, account-scoped `connector_tokens`; never a JWT or a
  session.
- **D-2** New read-only `mcp-connector` Edge Function, `verify_jwt = false`,
  handler-owned bearer validation.
- **D-3** RLS is the authorization boundary; service role never reads content;
  tool queries run as the account inside one SECURITY DEFINER RPC.
- **D-4** Mint/rotate/revoke are server-side RPCs behind the device gate; the
  secret is returned once.
- **D-5** Token metadata is exported; the hash is not; tokens are deleted with
  the account and revocable immediately.
- **D-6** The connector narrows below RLS's default read breadth.
- **D-7** Minor profiles require accepted-`primary_guardian` **and** an
  explicit per-profile opt-in; ungranted minor profiles are omitted entirely.
- **D-8** Private notes never; no note text at all in v1.
- **D-9** Counts, not content, throughout.
- **D-10** Five whitelisted read tools; no raw SQL/table access.
- **D-11** Read-only; no writes in v1.
- **D-12** Rate limit + audit log live in Postgres, purged by the nightly
  retention job.
- **D-13** Remote MCP over HTTPS at `app.lunarlog.app/mcp`, Edge Function host,
  OpenAPI manifest for ChatGPT, stdio bridge as fallback.

## KTDs

- **KTD1 — Opaque hashed token, not a JWT.** No signing key to own or rotate;
  revocable instantly; matches `guardian_invitations.token_hash`
  (`20260904010000_multi_guardian_schema.sql:142-144`).
- **KTD2 — RLS impersonation inside one SECURITY DEFINER RPC** (D-3), rejected
  JWT minting. `react`-free, no second authorization model; every existing and
  future policy applies unchanged. Fallback (signed JWT re-presented to
  PostgREST) is coder's to prove if the mechanism is fragile.
- **KTD3 — Edge Function DI shape** (`handleMcpConnector`/`buildDeps`,
  `deno test` with fakes) matching all four existing functions
  (`feedback-notify/index.ts:241-287`); directory added to
  `supabase/functions/deno.json:5-7`.
- **KTD4 — Counts-not-content projection** copied from the activity feed
  (`lib/ui/sharing/activity_feed_screen.dart:301-327`), not reinvented.
- **KTD5 — Minor gate enforced server-side and durable**, mirroring the
  prediction connection's re-checked minor refusal
  (`20260913019000_prediction_minor_gate_durable.sql`).
- **KTD6 — One origin.** The connector URL is on `app.lunarlog.app`, the origin
  #831 already provisions (`docs/web/security-posture.md:314-319`); no new
  domain.
- **KTD7 — Rate limit and audit in Postgres**, because Edge Functions hold no
  state between invocations (D-12).
- **KTD8 — Disclosures move with the feature.** `PRIVACY.md` §2/§3/§4/§5/§6/§7/§9
  and, if in a store build, #21's Play declaration land in the same PR as the
  code that makes them true — the #831 non-negotiable applied to this feature.

## Dependencies and adjacent outcomes

- **#849 (per-note private flag) is OPEN and not built.** Its 2026-09-20 owner
  decision scopes the one privacy control to a per-note private flag on the
  subject's own note; no `is_private`/`note_private` column exists
  (`docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:96-104`).
  D-8 is written so it holds with or without #849.
- **#850 (guardian lens) is the sibling presentation pass.** It supplies the
  subject/guardian distinction and the "counts, not content" card rule the
  connector borrows (`lib/domain/sharing/guardian_lens.dart:52-59`).
- **#831 (web hosting) supplies the origin.** `app.lunarlog.app` / Cloudflare
  Pages is the transport tie-in (D-13); its owner checklist grows a route item.
- **#21 (store declarations) gates a store-build launch**, not the server work
  (Q5).
- **#802 (`is_subject`)** is the durable marker the lens reads
  (`supabase/migrations/20260920120000_profile_subject_membership.sql:70-78`).
- **#800 / `PRIVACY.md` §5** are the transparency posture the minor gate must
  remain consistent with (`PRIVACY.md:114-125`).
- **Existing RPCs reused, not duplicated:** `is_profile_guardian`,
  `is_guardian_with_roles`, `enforce_retention()`,
  `export_account_data()`, `delete_account_data()`.

## Units of work

Each unit is sized for one coder (≤ ~400 changed lines including tests) and
carries its own tests. Ordered so each lands green on its own; U1-U5 are
server/client and inert until U6 exposes a URL, so they can merge before the
owner decisions that gate shipping.

- **U1 — Server: `connector_tokens` + lifecycle RPCs (~350).**
  New migration: the table (D-1), RLS (`select`/`delete` own rows only; no
  client `insert`/`update` grants), and `create_connector_token` /
  `rotate_connector_token` / `revoke_connector_token` /
  `revoke_all_connector_tokens` SECURITY DEFINER RPCs deriving the owner from
  `auth.uid()`. Tests: `supabase/tests/connector_tokens_test.sql` — table
  shape, hash format, RLS (another user's rows invisible), mint returns a
  plaintext that hashes to the stored value, rotate invalidates the old hash,
  revoke is immediate, no `authenticated` insert/update grant. Regenerate
  `supabase/database.types.ts`.

- **U2 — Server: read tools + minor gate + rate limit + audit (~400).**
  New migration: `connector_profile_grants`, `connector_call_log`,
  `resolve_connector_token`, and `connector_exec` implementing D-3, D-7, D-9,
  D-10, D-12 (the `set_config` RLS impersonation, the five tools, the minor
  intersection, the sliding-window limit, the audit insert). `EXECUTE` revoked
  from `authenticated`/`anon`. Tests:
  `supabase/tests/connector_exec_test.sql` — a `viewer` gets counts but never
  note text; a minor profile is absent without a grant and present with one
  only for a `primary_guardian`; an ungranted minor is omitted from
  `list_profiles`; a foreign `profile_id` returns nothing; the rate limit
  trips; the audit row carries no content; `connector_exec` is not executable
  by `authenticated`.

- **U3 — Edge: `mcp-connector` function + tests + deploy (~400).**
  `supabase/functions/mcp-connector/index.ts` with
  `handleMcpConnector(req, deps)` / `buildDeps(env, clientFactory)`; bearer
  parsing, `resolve_connector_token` lookup, `connector_exec` invocation, and
  the JSON-RPC MCP envelope (`tools/list`, `tools/call`) plus optional REST
  routes for the OpenAPI facade. `[functions.mcp-connector]` in
  `supabase/config.toml` (`verify_jwt = false`); add the directory to
  `supabase/functions/deno.json`; add the deploy to
  `.github/workflows/supabase-migrate.yml` (beside the existing
  `supabase functions deploy feedback-notify feedback-reply push-dispatch`
  step, `supabase-migrate.yml:339`). Tests:
  `supabase/functions/mcp-connector/index.test.ts` — missing/malformed bearer,
  unknown/revoked/expired token, unknown tool, valid call returns the RPC
  result, and logs never contain a token or tool result.

- **U4 — Client: Settings token management (~400).**
  Domain seam `lib/domain/connectors/connector_token_service.dart` (pure Dart,
  no Supabase/Flutter types, mirroring
  `lib/domain/account/account_deletion_service.dart`) and a concrete
  Supabase implementation; a Settings tile group in the Account section with
  create (label + copy-once dialog), rotate, per-token revoke, revoke-all, and
  a per-profile grant toggle for minor profiles. Every action re-runs
  `gate.reauthenticate()` first (`account_section.dart:693-698`). Tests:
  `test/domain/connectors/connector_token_service_test.dart` and
  `test/ui/account/connector_tokens_test.dart` — the plaintext is shown once
  and not after a rebuild, revoke is optimistic-confirmed, a declined
  credential performs no action, and the tile group is absent in an
  unconfigured build (`AppConfig.hasSupabase`, `lib/config.dart:65-67`).

- **U5 — Server: export/delete integration (~200).**
  Re-emit `export_account_data()` with the `connector_tokens` metadata key
  (never `token_hash`) and `delete_account_data()` with the explicit token +
  grant + call-log delete and counts. Tests: extend
  `export_account_data`/`delete_account_data` pgTAP coverage — the export
  contains metadata and no hash; deletion removes every connector row and the
  call log. `supabase/database.types.ts` regenerated.

- **U6 — Hosting + discovery (~250).**
  A Cloudflare Worker (or Pages Function route) at `app.lunarlog.app/mcp`
  proxying to the Edge Function with no body/header logging; serve
  `/openapi.json` and an MCP discovery document; wire it into the existing
  web deploy path (`docs/web/security-posture.md:296-319`) and extend the
  owner checklist (`docs/ops/supabase-go-live.md:85-105`). Tests: a script
  assertion that the route exists and the proxy config carries no logging, in
  the shape of `.github/scripts/check-web-build-output.sh`; a manual
  end-to-end MCP handshake against a local stack (recorded in
  `docs/ops/supabase-go-live.md`).

- **U7 — Docs + disclosures (~200).**
  `PRIVACY.md` §2-§10 edits, `AGENTS.md` (new function, dashboard/owner items,
  store-declaration note), `docs/ops/play-health-declaration.md` note, and
  the #21 checklist update if the connector ships in a store build. Tests: the
  docs are reviewed against the diff; no separate automated gate.

## Test plan

- **Server (pgTAP):** `supabase/tests/connector_tokens_test.sql` (U1),
  `connector_exec_test.sql` (U2), export/delete extensions (U5). Run with
  `db reset --local` + `test db --local` per AGENTS.md's Migration Flow; the
  existing `sync_push`/RLS suites must stay green.
- **Edge (Deno):** `mcp-connector/index.test.ts` (U3), run by the
  `edge-functions` CI job via `deno.json`'s `test.include`.
- **Client (Flutter):** the domain and widget tests in U4; `flutter analyze`,
  `flutter test`, and `dart run tool/quality_gate.dart`.
- **Manual / device (per `docs/ops/supabase-go-live.md`):** a real assistant
  (Claude and/or ChatGPT) connecting with a real token; a revoked token
  failing; a minor profile refused without a grant; a non-minor profile
  returning counts and no note text; a token never able to reach a table or
  RPC directly.
- **Release gate:** if the connector ships in a store build, #21's Play Data
  safety update must be filed before the production-track dispatch — the
  existing `play-store-release.yml` production gate is the enforcement point
  (`docs/ops/play-health-declaration.md:118`).

## Out of scope

- Write/action tools of any kind (D-11).
- Raw table, arbitrary SQL, or dynamic tool-name access (D-10).
- A fertility/ovulation tool (a separate owner decision; the base product's
  framing is a period estimate).
- A full MCP OAuth 2.1 authorization server; v1 uses the connector token as a
  static bearer, and an OAuth facade is a v1.1 candidate (D-13, Q2).
- Push/notification or outbox changes.
- A household roll-up across profiles (the #803 class of feature).
- Any change to RLS policies or grants on existing tables.

## Open questions

**Owner's** (must be answered before implementation; the plan cannot decide
these):

1. **Minors: primary-guardian opt-in only, or never?** (the crisp form of
   Question 2).
2. **Which assistant(s) in v1?** Claude / ChatGPT / both / local bridge only.
3. **Notes:** counts-only forever, or non-private note text once #849 lands?
4. **Who may mint a token?** Any signed-in account / only a profile's primary
   guardian or owner / any guardian.
5. **Store builds:** ship the connector in a store build, or server/web-only
   behind a flag until #21's declarations are updated?
6. **Approve the new third-party recipient** (Anthropic and/or OpenAI) and the
   `PRIVACY.md` §4 disclosure.
7. **Auto-revoke tokens** on "Sign out everywhere", password change, or adding
   a passkey?
8. **Default profile scope:** every RLS-visible adult profile, or per-profile
   opt-in for everyone?
9. **Cloudflare in the data path** at `app.lunarlog.app/mcp`, or the direct
   Supabase function URL?

**Coder's** (resolvable in implementation, called out in the PR rather than
blocking):

1. The exact RLS-impersonation mechanism in `connector_exec` (KTD2) and the
   fallback if `set_config` proves fragile.
2. Rate-limit window and caps (D-12).
3. Audit-log retention window.
4. The precise MCP JSON-RPC/tool schema and the OpenAPI shape.
5. Rotation semantics: new row + revoke old, or re-hash in place.
6. Whether `list_profiles` exposes `display_name` or an opaque id only.
