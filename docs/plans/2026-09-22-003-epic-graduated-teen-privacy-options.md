---
title: Graduated Privacy for Older Teens (Issue #1048) — Options for the Owner
type: options
date: 2026-09-22
issue: wjdavis5/lunarlog#1048
status: awaiting-owner-decision
---

# Graduated Privacy for Older Teens — Options (Issue #1048)

Date: 2026-09-22 · Branch: `opencode-deepseek/1048-graduated-privacy-plan` · Epic: Sharing
All paths repo-relative. Every claim below was re-verified against this
checkout (tip `ebded9e9`, `origin/main`). Where a fact lives only in the
still-open PR #1049, that is stated explicitly — it is not in this
checkout.

## Why this document exists, and what it is not

Issue #1048 is a **placeholder epic**: it carries background material and
asks the owner for two decisions before any design work. This document is
the analysis those decisions need. It is deliberately an *options*
document:

- It does **not** recommend softening the standing default. The owner's
  2026-09-20 decision on #849 ("Parents are responsible for the health and
  well being of their children. That is one of the core tenets of this
  application… The default is that parents / guardians will be able to see
  everything, except for notes") **is** the default, and this document
  takes it as given.
- It lays out what each candidate model would mean mechanically, who it
  would expose to which risk, and which decisions only the owner can make.
  The two questions are restated verbatim-style in §5.

One naming caveat up front, because it is the most likely source of
confusion: **the app already has a "teen mode", and it gives no privacy
whatsoever.** `ProfileMode.teen` (`lib/domain/models/profile_mode.dart:41-45`)
is a care mode — "presentation, not permission" (:3-8) — that changes
vocabulary and reminder defaults only. The "Teen-mode suggestion" dialog
that fires when a minor joins her own profile
(`lib/ui/sharing/subject_teen_mode_offer.dart:35-42`) writes that mode; it
grants nothing. Any graduated-privacy work in this epic is a *new* axis,
separate from `profiles.mode`, exactly the way #188's lifecycle modes were
kept separate from #131's care modes (see
`docs/plans/2026-09-09-001-feat-profile-modes-cycle-overrides-plan.md`
"Orthogonality (binding)"). Do not re-use `ProfileMode.teen` for privacy.

---

## 1. The standing default, restated precisely

### 1.1 The decision

The owner's 2026-09-20 comment on #849, in full effect:

> Parents are responsible for the health and well being of their children.
> That is one of the core tenets of this application. The default is that
> parents / guardians will be able to see everything, except for notes —
> those can remain private to the child. … As it stands for now, parents
> see everything except for notes that are marked private.

The same comment declined the earlier `full`/`status` per-membership tier
("**No `full` / `status` visibility tier now**"), deferred the
"who may lower a level" question to this epic, and kept the per-note
private flag as the one privacy control.

### 1.2 What each guardian role sees today

**Read scope is identical for every accepted role.** `PRIVACY.md:119`
("Guardian Roles & Read Visibility") states the standing commitment:

> While write capabilities are governed by guardian role (a `viewer` cannot
> log or edit entries, and only primary guardians or co-parents can edit
> profile settings), all accepted guardians on a profile have full read
> visibility over logged cycle entries, symptoms, observations, tags, and
> shared notes.

That sentence is literally true of the schema. The SELECT policy on
`day_entries` is `day_entries_select_guardians`
(`supabase/migrations/20260904010000_multi_guardian_schema.sql:289-293`),
whose predicate `public.is_profile_guardian(profile_id, auth.uid())`
(`supabase/migrations/20260915010000_db_integrity_bundle.sql:118-134`)
returns true for **any accepted membership, regardless of role**. The same
shape governs `observations`, `profile_modes`, `cycle_overrides`,
`care_notes`, `visit_prep_items`, and `guardian_notes`. There is no
role-based read filter anywhere.

**Write scope does differ by role** (`lib/domain/models/profile_guardian.dart:38-41`):

| Role | `canLog` | `canEditProfile` | `canManageGuardians` | `canDeleteProfile` |
|---|---|---|---|---|
| `primary_guardian` | yes | yes | yes | yes |
| `co_parent` | yes | yes | yes | no |
| `caregiver` | yes | no | no | no |
| `viewer` | **no** | no | no | no |

Server-side, the `day_entries` INSERT/UPDATE policies require
`primary_guardian`/`co_parent`/`caregiver`
(`20260904010000_multi_guardian_schema.sql:296-310`), so a `viewer` writes
nothing — the client capability flags mirror that exactly.

**Presentation differs; permission does not.** The guardian *lens*
(`lib/domain/sharing/guardian_lens.dart:31-59`) resolves whether the viewer
sees the subject's own-voice screen or the guardian logistics view, from
`ProfileGuardian.isSubject` (`lib/domain/models/profile_guardian.dart:88-96`)
plus accepted membership. The file states plainly that this "changes no
permission, and a viewer still cannot write" (`guardian_lens.dart:12-13`).
So the lens axis that a graduated-privacy model would build on already
exists — but today it is purely presentational.

**The subject's own membership is caregiver-equivalent.** A subject
(`is_subject = true`, issue #802) can log, but cannot manage guardians,
edit the profile, or delete it (`PRIVACY.md:121`; the server re-checks the
role pairing — `lib/ui/sharing/invite_guardian_dialog.dart:52-64`). She is
inside the same full-visibility read scope as everyone else.

### 1.3 The one privacy control today

The per-note **private flag** is the entire privacy surface the owner
approved, and it ships separately (issue #849's re-scoped v1), in the
still-open **PR #1049** ("feat(sharing): per-note private flag on the
subject's day note (#849)", base `main`). As of this checkout it is **not**
in `origin/main`.

The shape, because it is the template every model below would generalise
(all line numbers in `supabase/migrations/20260921130000_day_entry_note_private.sql`
on branch `opencode-deepseek/849-rescope-private-notes`):

- A `day_entries.note_private boolean not null default false` column
  (lines 51-52), granted to `authenticated` (line 57).
- A BEFORE INSERT/UPDATE guard, `enforce_day_entry_note_private()`
  (lines 129-163): a note may be born private, may flip `false → true`
  only while still empty, and may never be made private after it was
  shared, nor ever cleared back.
- Three helpers: `is_profile_subject(profile_id, user_id)`
  (lines 63-78), `profile_has_subject(profile_id)` (lines 83-97), and the
  single masking point `mask_day_entry_note(row, viewer)` (lines 102-116),
  which returns the row with `note` forced to JSON `null` when the note is
  private, the profile has a designated subject, and the viewer is not
  that subject. **Every role other than the subject is masked.**
- Masking is applied in `sync_pull` (line 2887 — the only path by which
  any client reads `day_entries`), in `sync_push`'s declined-server-copy
  handback (line 1286), and in `export_account_data()` (lines 3085-3087).
- The migration's own header (lines 24-28) is explicit: "RLS alone cannot
  transform a column, so these RPCs are the enforceable shape."

That last point is load-bearing for this whole epic and is restated as a
cross-cutting risk in §2.5.

### 1.4 The honest bottom line

Today, with or without #1049:

- **A guardian of any role reads everything the subject logs**, with no
  sharing tier. The only difference between roles is whether they can
  write.
- **A subject cannot restrict a parent's view of symptoms, flow, or tags
  at all.** Once #1049 lands, she can hide the text of an individual day
  note, chosen at the moment she writes it. Nothing else.
- **The only way to keep an older teen's diary private today is to not
  share the profile** — the fork the epic's TL;DR names.

---

## 2. Three candidate models

The three models are not mutually exclusive in principle (B is roughly A
with finer grain; C is a *trigger* for either A or B), but each is written
below as a self-contained, pick-one option so the trade-offs are legible.

A shared vocabulary used throughout: a **level** is how much of a
profile's content one membership can read. `full` is today's behaviour.
`status` means timing/logistics only — period timing, and derived
calendar facts — never symptoms, flow, tags, or note text. The exact
`status` definition (what counts as "logistics") is itself a decision, not
assumed here.

### 2.1 Model A — a status-only level (`full` / `status`)

**Concept.** A per-membership level orthogonal to role, as the original
#849 proposal sketched it. A `status` guardian reads `profiles`,
`profile_guardians`, and a timing-only projection; never content. `full`
is the default. No per-category choices, no automatic trigger.

**Server-side (RLS / masking).**

- A new column on `profile_guardians` (e.g. `visibility_level` over
  `('full','status')`, default `full`). Membership state today is writable
  *only* through SECURITY DEFINER RPCs (`20260904010000_multi_guardian_schema.sql:315-317`),
  so changing a level would go through the same invitation/management
  functions, not a direct table UPDATE.
- The `#849` masking helpers generalise: `mask_day_entry_note` becomes (or
  is joined by) a content mask that nulls `flow`, `tags`, and `note` for a
  `status` viewer. Because `observations` is a **separate table** that
  #849 does not mask, `sync_pull` would need an equivalent mask on the
  `observations` page, and on `profile_tag_registry`, `day_entry_history`,
  and `day_entry_merge_events` (a legend, an audit trail, and retained
  merge text can each leak the content being withheld).
- A **timing-only projection** (period/fertile/ovulation/PMS days,
  confidence tier, last-logged recency) served as its own SECURITY DEFINER
  read, rather than `status` filtering row content it should never receive.
- Caregiver-alert suppression for `status` members on the outbox/scheduling
  path (`alert_on_log`, high-severity), since an alert body would otherwise
  reveal that an entry with a severity happened.
- The write ladder is unchanged: a `status` membership is about *reading*,
  and the proposal limited `status` to `viewer` in v1.

**Client-side (lenses / UI).**

- The guardian lens (`guardian_lens.dart`) is the natural seam. A `status`
  viewer would render a timing-only projection card — essentially today's
  GuardianLens but with content-bearing widgets removed — so the lens
  likely grows a `status` variant or the projection becomes a separate
  screen the lens routes to.
- An invite preset ("Status only — sees period timing, never entries or
  notes") alongside the existing `coParent`/`caregiver`/`viewer`/`subject`
  presets (`lib/ui/sharing/invite_guardian_dialog.dart:46-65`).
- A "What my guardians can see" transparency screen (the proposal's own
  item), and a level control in Manage Guardians
  (`lib/ui/sharing/manage_guardians_screen.dart`).
- **No subject-controlled toggle in A** unless the owner decides the
  subject may lower a level (that is decision 2, §3).

**PRIVACY.md.** §5's "Guardian Roles & Read Visibility" (`:119`) is the
sentence that changes — from an unconditional "all accepted guardians
have full read visibility" to a level-dependent statement. §2.A should
name the level as part of the sharing model. §5's "Guardian Notes Are
Visible To The Child" (`:123`) has to be reconciled: a `status` guardian
receiving a guardian note would contradict it. Change History entry
required.

**Risks.**

- *Well-being tenet.* This is the model that most cleanly keeps the
  guardian, not the child, holding the lever (the parent chooses to give
  *others* a status view), so it is the least in tension with the tenet —
  **unless** the subject may lower the parent's level, at which point the
  tenet tension is decision 2's (§3), not the model's.
- *Coercion.* If a subject can lower a guardian, a guardian can pressure
  her. If only a guardian can lower another guardian, one guardian can
  unilaterally cut another out.
- *A hidden health problem.* `status` still reveals cycle timing, which
  can betray a missed or irregular cycle even with symptoms hidden. It is
  a real reduction, not a full isolation.
- *Leak surface.* As §2.5 explains, the mask is RPC-enforced; a determined
  `status` guardian using PostgREST directly can still read raw rows until
  the enforcement gap is closed.

### 2.2 Model B — per-category toggles the subject controls

**Concept.** The subject chooses, per guardian or per level, which
*categories* are visible: cycle timing, flow, symptoms/observations, tags,
day-note text, guardian notes. Finest grain; largest surface.

**Server-side.**

- Visibility state becomes per-category, not a single enum — a JSON map on
  the membership, or one column per category. Each category must be masked
  consistently across its table(s): `day_entries` (flow, tags, note),
  `observations` (a separate table — the biggest new work), `notes`,
  `day_entry_history`, `day_entry_merge_events`, `profile_tag_registry`.
- `sync_pull` computes a projection per caller per category; the write
  path's declined-row handback and `export_account_data` need the same
  treatment for each category (the #849 pattern, multiplied).
- The subject-vs-guardian authority question (§3) has to be enforced
  server-side for each category transition, or it is trivially bypassed by
  pushing a row.
- More enumeration-parity and allowlist maintenance (the `#181` derived
  allowlists) with each category added.

**Client-side.** A subject-facing "What I share" settings surface with
per-guardian per-category controls; a live transparency preview; the
guardian lens renders whatever the projection allows. This is a
substantially larger UI than A.

**PRIVACY.md.** §5 rewritten around "you choose what each guardian sees";
§2.A enumerates the categories; likely §1 as well. Change History.

**Risks.**

- *Coercion.* Highest of the three: the subject holds a switch that a
  guardian may pressure her to flip, in either direction ("show me, or
  else" / "hide it and I'll punish you"), and the app cannot tell the
  difference.
- *Hidden health problem.* Highest: the subject can hide symptoms
  selectively, which is exactly the scenario the owner's tenet centres on.
- *Configuration risk.* A confusing toggle can over-share by default, and
  a subject may not understand what a category reveals (tags often encode
  symptoms indirectly).
- *Support/complexity.* Many independent states, many parties, and no
  clear "who is right" when a guardian and subject disagree about a
  setting.

### 2.3 Model C — age-based automatic softening at 16/17

**Concept.** No human action: at a threshold age the profile's guardians
automatically move to a softer level (or `status`). The rule is the
calendar, not a person.

**Server-side.**

- Derive age from `profiles.birth_year` using the existing conservative
  rule (`Profile.isMinorAsOfYear` → `deriveMinorStatus`,
  `lib/domain/models/profile.dart:130-142`; `PRIVACY.md:118`: "a minor is
  a minor until 18", year-only, so the birthday boundary is fuzzy). The
  *server* must compute the identical transition deterministically — the
  mask has to know the caller's effective level.
- **A profile with no birth year has no computable age.** The stored
  `is_minor` flag is only a fallback and does not soften. So C silently
  does nothing for a stored-flag-only profile unless a second rule is
  defined. That inconsistency is a decision, not a detail.
- The transition has **no actor**: nobody taps a button, so there is no
  natural invitation into an audit trail. A notice to both parties (and
  the ability to see when it happened) would be new.
- An override ("this 17-year-old still needs full visibility") is a
  separate decision if the owner wants one; without it, C is absolute.

**Client-side.** Mostly notification and transparency UI: tell the
subject and guardians when a birthday changed the level, and have the
guardian lens honour it. No picker.

**PRIVACY.md.** §5 states the age rule and what softens at it; §1; Change
History.

**Risks.**

- *Well-being tenet, sharpest form.* The parent's own stated tenet is
  overridden by a birthday, with no human in the loop.
- *Maturity ≠ age.* A 17-year-old with a serious condition loses symptom
  visibility exactly like a healthy one; a 15-year-old who needs privacy
  gets none.
- *Unverified input driving a permission.* The app never verifies a birth
  year — it is user-entered (`profile.dart:122-128`) — so C makes a
  privacy control depend on data that may be wrong or stale.
- *Standing design principle.* The codebase deliberately holds "mode is
  chosen, never computed: nothing derives a mode from birth year or
  `isMinor`" (`profile_mode.dart:3-8`; `profile.dart:80-86`, the health-
  sync minor gate excepted). C deliberately breaks that principle for a
  *permission*. That is a legitimate choice, but the owner should make it
  knowingly rather than as a side effect.
- *Coercion.* Lower than A/B because no one holds the switch — but a
  guardian can still pressure a subject about what the calendar is about
  to do, and a subject cannot opt *out* of softening if she wants to keep
  sharing.

### 2.4 The models side by side

| | A — status level | B — per-category toggles | C — age-based automatic |
|---|---|---|---|
| Who decides | a guardian sets a level (subject only if §3 says so) | the subject | the calendar |
| Grain | one level per membership | per category per guardian | one threshold, global |
| New server work | level column + content mask + timing projection + alert suppression | all of A plus a mask per category, `observations` included | A or B's masking, plus server-side age derivation + transition notices |
| New client work | invite preset + projection card + transparency screen | subject settings surface + per-category preview | transition notices + transparency |
| Child hides a health problem | limited (timing still visible) | highest | high (automatic, no override by default) |
| Coercion surface | medium | highest | lowest |
| Well-being tenet | preserved unless §3 gives the subject the lever | most in tension | tenet overridden by date |
| PRIVACY.md §5 | rewrite read-visibility bullet | rewrite around subject choice | rewrite with age rule |

### 2.5 Cross-cutting risks (apply to any model)

1. **Enforcement is RPC-only, not SQL-enforced.** #849's own header says
   "RLS alone cannot transform a column, so these RPCs are the enforceable
   shape" (PR #1049 migration lines 24-28), and the `day_entries` SELECT
   policy still admits any accepted guardian
   (`20260904010000_multi_guardian_schema.sql:289-293`). So a level that
   says "guardians cannot see X" is true of **the app's own read path**,
   not of the database. A guardian who calls PostgREST directly can read
   the raw row. For the per-note flag this is a contained gap; for a
   whole *status* tier it is the difference between a privacy promise and
   a speed bump. Closing it means column-level security (Postgres column
   grants) or moving all reads fully behind RPCs — a bigger change than
   the models themselves, and arguably the real prerequisite for any
   *enforceable* level.
2. **Masked rows must never clobber stored content on write.** #849
   already had to add an UPDATE-path guard so a guardian holding a masked
   copy cannot wipe the subject's text (PR #1049 migration header
   lines 37-40). Every model adds columns with the same data-loss mode
   and needs the same guard.
3. **Realtime is already safe** — `day_entries`/`profiles` are deliberately
   never published to `supabase_realtime`
   (`supabase/migrations/20260905100000_realtime_publication.sql:24, 228-230`),
   so no level model can leak through the websocket as long as that
   invariant holds. Worth pinning in any implementation.
4. **The tenet is the owner's, and it is not just a preference.** The
   issue body quotes it as one of the application's core tenets. Any
   model that lets the subject override a parent's access must be an
   explicit owner choice, not an emergent property of a settings screen.
5. **No medical service.** The app has no duty or mechanism to alert a
   parent to a hidden health signal. A model that hides symptoms does not
   add a safety net elsewhere; that is a product gap to accept or solve
   separately.

### 2.6 The store / COPPA angle

- **COPPA is not triggered by this epic.** COPPA's line is under 13. The
  app's floor is already 13 with a recorded parental-authorisation
  acknowledgement (`PRIVACY.md:117`). Softening the experience for 16- and
  17-year-olds moves no data category and changes no collection, so no
  new COPPA obligation arises from A, B, or C. The COPPA exposure is set
  by the existing 13+ floor, not by the level model.
- **No new App Privacy / Data Safety category.** The data stays within
  the same guardian set and no new third party is introduced, so the
  Apple App Privacy answers and the Google Play Data safety answers
  (`docs/ops/play-health-declaration.md`) do not gain a category. But a
  *read-scope* change is still a privacy-policy change and must be
  reflected in `PRIVACY.md` and, if wording shifted, reviewed against the
  Health declarations.
- **The real store risk is the written promise.** `PRIVACY.md:119` states
  the read scope as fact to users and to Apple/Google. Any model must
  ship the policy update with it, or the app misdescribes itself. This is
  the cheapest thing to get right and the most embarrassing to get wrong.
- **Age assurance.** C acts on an age the app never verifies. That is not
  a store violation today, but it is a stated-privacy-claim-vs-actual-
  behaviour gap if a birth year is wrong, and it should be named in the
  policy if C is chosen.

---

## 3. Decision 2 — "who may lower a level?" as a decision table

Definitions used here: **lower a level** = make a membership *more
private* (less visible). **Raise** = make it more visible again. The
original #849 proposal was: the primary guardian sets levels; the subject
may lower `caregiver`/`viewer` guardians but not the parent; the parent
lowering her own level is a visible act of trust. The parent-vs-other-
guardian asymmetry is the question this epic exists to resolve.

| Authority model | Subject may lower the **primary guardian's** access? | Subject may lower a `caregiver`/`viewer`/`co_parent`? | Does a parent differ from other guardians? | What it implies |
|---|---|---|---|---|
| **Subject alone** | Yes | Yes | No — the subject may lower anyone, including the parent | Maximal autonomy; directly in tension with the well-being tenet; a parent can be cut off from a symptom with no recourse |
| **Primary guardian alone** | No | No (the primary decides) | Yes — the parent is the sole authority | Preserves the tenet fully; gives the 17-year-old no privacy she can assert, which is the epic's entire premise; co-parents are at the primary's mercy |
| **Both must agree** | Yes, but only with the parent's agreement | Yes, but only with the parent's agreement | Yes — the parent holds a veto | No unilateral action; the subject can be permanently blocked if the parent refuses; "agreeing to give the subject *less* exposure" arguably needs only her, while *raising* it back needs both |
| **Any guardian** | Yes (any guardian may lower any membership, including the parent's) | Yes | No — every guardian is symmetric | Least coherent; lets one guardian unilaterally cut another (including the parent) out; contains no authority model at all unless it is narrowed to "each guardian may lower only her *own* access" (a self-service variant, which is different from lowering someone else's) |

**Parent-vs-other-guardian sub-question, in plain terms.** If the answer
is "the parent differs", the model needs to say *how*:

- Can the parent be lowered at all, or only down to `status` (i.e. the
  parent always retains timing plus a safety floor)?
- Is `co_parent` treated as "the parent" or as "other guardians"?
- Does a lowering require the subject to be an accepted subject
  membership of that profile at all (i.e. only she can act, not an
  unrelated operator)?

**Paired sub-question (raising).** A model that lets the subject lower a
level but not raise it back creates a ratchet (the #849 per-note flag has
exactly this ratchet, deliberately: once shared, never retroactively
private; once private, never cleared). The owner should decide whether
raising requires the guardian's agreement, both parties' agreement, or is
simply disallowed.

The choice of model in §2 constrains the answer: A and C make sense with
several rows here; B makes sense mainly with "subject alone" or "both must
agree"; C makes the table largely moot (the calendar acts, not a party)
apart from an override decision.

---

## 4. What is common to every model — and is it worth building now?

Candidates for "common ground that could be built without deciding":

1. **A `visibility_level` column with a single default value** (`full`).
   Schema + `sync_push` allowlist (the #181 derived-allowlist recipe) +
   a Drift migration/schema dump + RLS, all with one legal value and zero
   behaviour.
2. **A generalised content-mask function**, refactoring #849's
   `mask_day_entry_note` into `mask_day_entry_content(row, viewer, level)`.
3. **A "What my guardians can see" transparency screen**, which today
   could only restate the standing default.
4. **Closing the enforcement gap** of §2.5 item 1 (RLS permits raw reads;
   masking is RPC-only).

**Verdict: no — do not build the common part now.** Plainly:

- **(1) is speculative schema.** The three models need *different* shapes
  (A: per-membership enum; B: per-membership per-category state; C:
  computed from `birth_year`, not stored per membership at all). Committing
  to a single-valued column before the model is chosen locks in a key that
  at least one model would have to undo. It also adds a migration, a
  Drift version, a `sync_push` key, `database.types.ts` drift, and pgTAP
  coverage for something no user can exercise — precisely the kind of
  dead scaffolding a placeholder epic should not produce.
- **(2) is a refactor with no caller.** #849's mask is a clean, working
  single-purpose function. Generalising it before a second caller exists
  buys nothing and risks obscuring the one masking path that already
  ships.
- **(3) is not blocked, but it is not groundwork either.** It could be
  built now because it would only *describe* today's behaviour. That makes
  it an independent UX unit, not a prerequisite for any model; building it
  inside this epic would be scope creep on a placeholder. The one real
  fact it would state — `PRIVACY.md:119`'s full-read-visibility sentence —
  already exists, so the promise the #849 decision asked for ("the §5
  viewer-semantics sentence… is cheap") is already satisfied.
- **(4) is worth tracking on its own merits**, because it qualifies *any*
  privacy claim the app makes, including #849's per-note flag. But it is
  a database-security change, not teen-privacy groundwork, and it should
  not be smuggled into this epic.

Net: **keep #1048 a placeholder.** Nothing is blocked by waiting, and the
only genuinely reusable asset — the #849 masking pattern and the evidence
that it works — already exists and ships in PR #1049. Revisit the schema
only after decision 1 and decision 2 are answered.

---

## 5. The two decisions

Both are the owner's; neither is made by this document. They are coupled:
a **No** on decision 1 makes decision 2 moot.

### Decision 1 — Do you want graduated privacy for older teens at all?

Pick one:

- **(1a) No.** The 2026-09-20 default stands unchanged: every accepted
  guardian reads everything except a note the subject marks private.
  Close #1048 as a considered non-goal. *Most consistent with the stated
  well-being tenet.*
- **(1b) Yes — Model A (status-only level).** At what age, and is the
  level set by a guardian or the subject (see decision 2)?
- **(1c) Yes — Model B (per-category toggles the subject controls).**
  At what age does the subject gain the toggles?
- **(1d) Yes — Model C (automatic softening by age).** At which age — 16,
  17, or 18? Does anything soften for a profile with no birth year?

If **Yes**, say also *what* softens at the boundary: cycle timing too, or
symptoms/notes/tags only. (A "status" level that still shows timing is not
the same privacy as one that hides the calendar.)

### Decision 2 — Who may lower a level, and does the parent differ from other guardians?

Pick one authority model (§3): **subject alone / primary guardian alone /
both must agree / any guardian.** Then answer: **does the primary guardian
(parent) differ from other guardians?** If yes, say how (may the parent be
lowered at all, or only to a service/safety floor; is `co_parent` treated
as parent or other; must the actor be the profile's own subject?). Finally,
does **raising** a level back follow the same authority, or is lowering a
one-way ratchet as in #849?

---

## Appendix — verified references

| Claim | Source (this checkout, `ebded9e9`) |
|---|---|
| All accepted guardians have full read visibility | `PRIVACY.md:119` |
| SELECT on `day_entries` is any accepted membership | `supabase/migrations/20260904010000_multi_guardian_schema.sql:289-293` |
| `is_profile_guardian` ignores role | `supabase/migrations/20260915010000_db_integrity_bundle.sql:118-134` |
| Write roles exclude `viewer` | `supabase/migrations/20260904010000_multi_guardian_schema.sql:296-310` |
| Role capability flags | `lib/domain/models/profile_guardian.dart:38-41` |
| Subject membership is caregiver-equivalent | `lib/ui/sharing/invite_guardian_dialog.dart:52-64`; `PRIVACY.md:121` |
| Guardian lens is presentation only | `lib/domain/sharing/guardian_lens.dart:12-13, 31-59` |
| `teen` care mode is presentational | `lib/domain/models/profile_mode.dart:3-8, 41-45` |
| Teen-mode offer writes a care mode | `lib/ui/sharing/subject_teen_mode_offer.dart:35-42` |
| Minor-until-18 derivation | `lib/domain/models/profile.dart:130-142`; `PRIVACY.md:118` |
| 13+ floor and parental acknowledgement | `PRIVACY.md:117` |
| Realtime never publishes `day_entries` | `supabase/migrations/20260905100000_realtime_publication.sql:24, 228-230` |
| Per-note flag shape (open PR #1049, not merged) | `supabase/migrations/20260921130000_day_entry_note_private.sql` on `opencode-deepseek/849-rescope-private-notes` |
| "Mode is chosen, never computed" caution | `lib/domain/models/profile_mode.dart:3-8`; `lib/domain/models/profile.dart:80-86` |
| Product positioning / audience | `docs/product/positioning.md:11-37` |
| #849 outcome (no tier) | `docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:36-39` |
