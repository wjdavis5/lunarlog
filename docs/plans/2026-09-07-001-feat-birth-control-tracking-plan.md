# Plan — Birth-control tracking: six methods and per-day intake (Issue #260)

Date: 2026-09-07 · Branch: `feat/260-birth-control` · Epic: Tracking Model (P1)

## Context

Issue #260 asks for Clue's dual birth-control model: per-day intake
observations across six methods (pill, shot, implant, patch, ring, IUD)
and a profile-level current-method attribute with effective dates. Both
storage surfaces already exist:

- **Per-day intake** rides #240's `observations` child table —
  `category`/`code` are stored-never-rejected free text there, so a
  `birth_control_*` category family needs **no DDL**.
- **The profile-level current method** rides #188's
  `profile_modes.birth_control_method` (+ `birth_control_started_on`/
  `birth_control_stopped_on`), landed deliberately free-text with the
  migration header stating "*#260 owns that vocabulary*".

Dependencies #240 and #188 are landed. This issue therefore adds **no
migration, no Drift schema bump, no sync_push change**: the tables,
column grants, key allowlists (containment guards), row codec, and pull
cursors already carry every column the feature uses. A server-side
closed CHECK on the vocabulary would reject a future re-pinned option
string exactly the way #240 decided codes must never be rejected — the
canonical vocabulary lives client-side instead, and pgTAP pins the
*semantics* over the existing schema (`supabase/tests/birth_control_test.sql`,
test-only, +22 assertions; full suite 1443 green).

## Key decisions

- **The canonical vocabulary is a domain module:**
  `lib/domain/birth_control.dart`. `BirthControlMethod` is the closed
  set lunarlog writes into `profile_modes.birth_control_method` — the
  issue's six tracked methods (`pill`, `shot`, `implant`, `patch`,
  `ring`, `hormonal_iud`/`copper_iud` covering the IUD category) plus
  the non-tracked answers #216's selector could already store
  (`none`, `condom`, `other`). `toDb()` refuses to store the read-only
  `unknown` degradation, so an unrecognised value can never be silently
  replaced by a placeholder on a naive round-trip.
- **Legacy reads stay total.** Pre-#260 the first-run selector stored
  localized English labels ("Pill", "Hormonal IUD", …) and one draft id
  (`injection`); `fromDb` maps all of them onto canonical members and
  degrades anything else to `unknown` — never throws, never drops a
  stored answer.
- **The six intake categories** (`birth_control_pill/shot/implant/
  patch/ring/iud`) are the family's only members. The IUD category
  deliberately does not carry the hormonal/copper flavor (Clue tracks
  one IUD category; the flavor stays on the profile-level method, which
  #216's question already captured). Non-pill methods are presence-based:
  a logged row carries a null `code` — no invented placeholder options
  (the `kUnverifiedTagCategories` house rule).
- **Pill adherence** is `PillAdherence` (`taken`/`late`/`missed`) — the
  issue's AC2, with the exact strings documented as **pending pre-ship
  verification against a real Clue export** (A1-29's unverified
  confidence). Stored-never-rejected makes a later re-pinning a
  vocabulary-only change.
- **Same-day semantics stay the #240 model.** A server-side collapse of
  a day's intake rows to one winner would invent birth-control-specific
  semantics inside the generic observations resolver; instead the pgTAP
  file proves both properties: identical (category, code) collisions
  resolve newer-wins/loser-tombstones, and *distinct* codes coexist
  (the consumer disambiguates).
- **AC4 independence is pinned, both directions**: a
  `p_profile_modes` method change leaves every observation row's count
  and `updated_at` untouched, and an intake push never touches the
  stored method or its effective dates. A missed pill day is not a
  method change (A1-29's explicit "do not infer" warning).
- **The AC5 consumption seam** is
  `birthControlMethodInEffectOn()` — a pure resolver over the raw
  `profile_modes` values (method + started/stopped dates, start day
  inclusive, stop day exclusive) that returns null for
  unrecorded/none/untracked/unparseable methods and for dates outside
  the effective window. #233 (predictions), #183 (reminders), and #152
  (clinical export) read it instead of re-parsing the row; the reminder
  hookup itself remains #183's.
- **The selector stores ids, not labels.** `birthControlStoredValue`
  now returns the canonical id; `birthControlChoiceForStored` parses
  through the same total read. Labels remain ARB-localized
  (`birthControl*`); new ARB keys are the three adherence values with
  the A1-29 caveat embedded in their descriptions.

## Units

- **U1 — vocabulary module**: `lib/domain/birth_control.dart` (pure
  Dart, layering-clean) + `test/domain/birth_control_test.dart`.
- **U2 — selector wiring**: `lib/ui/profiles/birth_control_choices.dart`
  + its test; call sites in first-run, profile dialogs, and the picker
  screen; `test/ui/profiles_test.dart` / `test/ui/first_run_test.dart`
  expectations updated to the stored id.
- **U3 — copy**: `lib/l10n/app_en.arb` adherence values +
  `flutter gen-l10n`.
- **U4 — pgTAP**: `supabase/tests/birth_control_test.sql` (test-only;
  no migration).

## Explicitly out of scope

- Reminder hookup (#183) — the seam above is all #260 leaves.
- Birth-control-aware prediction adaptation (#233) and the clinical
  export medications section (#152) — consumers of U1's resolver.
- Intake-logging UI (the issue's ACs are storage/consumption-facing;
  no screen ships here).
- Clue importer normalization of the flattened `birth_control` type
  onto the family categories — Clue's option strings are unverified;
  the pass-through mapping (#190) stays until a real export pins them.
- `export_account_data()`/local JSON export coverage of
  `profile_modes` — #188's own documented follow-up, untouched here.
