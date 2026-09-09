# Plan — Intensity/severity model for tracked observations (Issue #256)

Date: 2026-09-09 · Branch: `feat/256-intensity-model` · Epic: Tracking Model (P1)

## Context

Issue #256 asks for an intensity/severity axis for tracked observations, and
closes the one shipped defect the gap produced: the caregiver-alert trigger's
`v_is_high_severity := new.flow = 'heavy'` proxy
(20260906220000_notification_outbox.sql, whose own header documented it as a
forced substitute).

The issue ships "(b) plus (a)" per A1-38. Half of it is **already landed**:

- **(a) Clue-shaped gradation in the option vocabulary** — delivered by #247
  (flow levels incl. `super_heavy`) and #249 (pain's `pain_free`…
  `migraine_with_aura`, energy's four-level scale).
- **(b) storage** — `observations.intensity` (nullable smallint, CHECK 1-5)
  landed with the #240 foundation: the server column
  (`observations_intensity_check`, tombstone-clearing backstop), the
  `sync_push` key allowlist / parse / insert / update / collision-clearing
  paths, the local Drift column (`lib/data/db/tables.dart`, schema v12, dump
  `drift_schemas/drift_schema_v12.json` — no schema bump needed or made
  here), the sync codec, and the JSON export/import round-trip.

What this PR adds is the part nothing yet implements: the **severity
consumers** — the trigger predicate replacement, the observations-side
trigger, and the day-sheet graded input.

## Key technical decisions

- **No Drift schema bump.** The intensity column, its validation
  (`lib/domain/limits.dart` bounds, `storage.dart` ArgumentError), and the
  wire codec all exist; this PR changes no local table. The "FULL schema-bump
  procedure" is therefore not triggered.
- **Severity-bearing categories = `array['pain']`** (the issue's own
  example), a named constant in both trigger functions and inlined in the
  two WHEN clauses (a WHEN cannot see plpgsql constants — four literal
  sites, each pointing at the others). Extending the set is a deliberate
  migration edit, never a client-side guess.
- **Day_entries arm** (`enqueue_caregiver_alerts()` create-or-replaced from
  its 20260908200000 body): `v_is_high_severity` is now the flow case
  (`heavy`/`super_heavy`, preserved verbatim — a heavy day with no graded
  pain still alerts) **OR** an EXISTS over live observations for the same
  (profile_id, local_date) with `intensity >= 4` on a severity-bearing
  category. `intensity >= 4` is null-rejecting, which *is* the legacy
  semantics: `intensity IS NULL` means "no severity recorded", never "low".
- **Observations arm** (`enqueue_observation_high_severity_alerts()` + AFTER
  INSERT/UPDATE triggers): a graded pain row can land without any
  day_entries content change, so the day_entries trigger alone misses it.
  The fan-out reuses issue #125's plumbing verbatim (per-kind cadence —
  always `high_severity` — daily digest hold, daily ceiling, coalescing
  window), plus #167's bulk-import guard and the writer exclusion
  (`last_modified_by_user_id` falling back to `logged_by_user_id`; the
  observations table has no `user_id` of its own). The
  `alert_on_cycle_start_only` narrowing is evaluated against the day's
  stored day_entries cycle-start state (re-derived with the same #6
  [d-2, d-1] merge window), since an observation carries no flow. No
  `alert_on_high_severity` term: this trigger only emits high_severity
  events, and both narrowing states pass such events on the day_entries
  trigger too.
- **UPDATE WHEN clause**: fire when the row is severe AND what was logged
  actually changed (payload diff against OLD, revive included) — a no-op
  resave never re-pages anyone (#7's rationale, observations side); a
  downgrade out of severity fires nothing (the event is "severe pain
  logged", never "severity changed").
- **Double-alert containment**: one user action can fire both triggers by
  design ("in addition to" per the issue); #125's coalescing window
  collapses same-(recipient, profile, kind) pushes, and the ceiling bounds
  the rest.
- **The old workaround comment dies with the replaced body.** Merged
  migrations are never edited in place; `create or replace` removes the Q1
  text from the live function, and this migration's header supersedes it.
  "Same migration as intensity" is satisfied as closely as the timeline
  allows — intensity landed first (#240), this is the earliest possible
  follow-up.
- **Day sheet (AC: at least pain exposes a graded input).** Selecting a
  pain-category chip reveals a per-code 1-5 selector (+ Clear) under the
  Pain section; the choice rides the autosave into an upsert of the day's
  `category: 'pain'`, same-code observations row with `intensity` — the
  spotting-toggle's post-save sync pattern. Clear tombstones the graded row
  (ungraded = "no severity recorded"). An existing/imported grade seeds the
  selector on open (highest per code) and an autosave directed at something
  else never touches a row the operator did not. A selected code with no
  grade writes no observation row. The reusable `IntensitySelector`
  component remains issue #234 (blocked by this one).

## Implementation units

- U1 `supabase/migrations/20260909220000_high_severity_intensity.sql` — the
  predicate replacement + observations trigger/WHEN clauses + comments.
- U2 `supabase/tests/notification_outbox_test.sql` — Groups F/G: the four
  AC cases (neither / high-intensity-only / heavy-flow-only / both), legacy
  null semantics, below-threshold and wrong-category rows, preference
  ladder, writer exclusion, cadence off, no-op resave, crossing/downgrade,
  tombstone, bulk-import guard, cycle-start narrowing, structural guards.
- U3 `lib/ui/logging/day_sheet.dart` (+ ARB) — `_painIntensity` state,
  loader, post-save sync, `_painIntensityRow` selectors, `kGradedIntensities`.
- U4 `test/ui/logging_test.dart` — grade persists; ungraded writes nothing;
  reopen seeds / raise updates / Clear tombstones; imported grade survives
  unrelated autosaves.

## Acceptance criteria (issue ACs → where proven)

- `observations.intensity` exists (nullable smallint 1-5) — landed with
  #240; `supabase/tests/observations_test.sql` round-trips it.
- Pain exposes a graded intensity input in the day sheet — U3/U4.
- Trigger predicate = heavy flow OR graded severity observation — U1, pgTAP
  Group F.
- Workaround removed as part of the change — U1 (function body replaced;
  merged migration file untouched per the house rule).
- pgTAP heavy-flow-only / high-intensity-only / both / neither — U2 Group F.
- Legacy `intensity = null` unambiguous ("no severity recorded") — U1
  comments + U2 (null row never classifies the day; Clear test on the
  client).

## Explicitly out of scope

- #234 (reusable IntensitySelector), #238 (HealthKit severity export),
  `flow = 'heavy'`-proxy consumers outside the caregiver-alert trigger
  (none exist), retiring the `day_entries.tags` mirror, widening the
  severity-bearing category set beyond `pain`.
