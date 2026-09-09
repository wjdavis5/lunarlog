# Clue import — category/option mapping spec

Issue #190. This is the spec `lib/domain/import/clue/` implements: what
Clue's export shape actually is, how each category/option maps onto
lunarlog's data model, the cycle-reconstruction rule, the escape hatch for
anything unrecognised, and — since no real Clue export exists or may be
committed to this repo (no real health data) — exactly which parts of this
spec are still assumption-based and need a real export to confirm.

Related issues: #199 (the `observations.raw` escape hatch this parser
targets), #247 (spotting-as-its-own-category and the `superHeavy`/
not-bleeding flow states this parser's output already assumed — **merged**,
see the note below), #240 (the `observations` table this parser's output
is shaped for), #172 (the bulk-write step that will actually consume this
parser's output — out of scope here), #134 (lunarlog-internal taxonomy
migrations — see "Not Clue-side renames" below).

**Reusing #140's `ImportPlan` (added after this spec was written):** issue
#140 shipped restore-from-file import for the app's own export format —
`lib/domain/import/account_import.dart`'s `planImport`/`ImportPlan` and
`lib/data/import/account_importer.dart`'s `AccountImporter` — with a merge
policy (additive, same-date tag/flow/note merge, observation dedup by
`(profileId, localDate, category, code)`, transactional apply) that has
nothing file-export-specific about it: it operates on the same
`ImportedProfile`/`ImportedDayEntry`/`ImportedObservation` shapes this
Clue parser's own output (once #172 maps a `ClueDatapoint` stream into
those shapes) can be adapted into. #172's write path should build an
`ImportPlan` from the Clue parser's output and apply it through the same
`AccountImporter`, rather than inventing a second merge/write path — the
only new work #172 needs is the `ClueDatapoint` -> `ImportedProfile`
adapter (respecting the sequencing note below).

**Row-id reuse trade-off (Issue #140 review round 2, item 3):** when
`AccountImporter` writes a brand-new (`add`-outcome) day entry or
observation, it reuses the imported row's own `id` from the file as the
local row id — instead of always minting a fresh ULID — whenever that id
is a syntactically valid ULID and nothing already occupies the slot it
would claim ((profileId, localDate) for a day entry; (profileId, localDate,
category, code) for an observation). The payoff: two devices signed into
the same account that both import the same file (a Clue export routed
through this adapter, or the app's own account-export file) converge on
the SAME row id for the same logical entry, so a later sync sees one row,
not two independently-generated rows racing on the server's
`day_entries_profile_source_source_id_uq` partial unique index. The cost
is a (astronomically unlikely, but non-zero) collision: if the reused id
happens to already exist locally as an unrelated row — a ULID isn't
scoped to this device, so nothing but the 2^80 randomness space rules this
out — `LunarLogStorage.upsertDayEntry`/`upsertObservation`'s own `id:`
path treats it as a revival and overwrites *that* row's fields, not just
inserts a new one. This adapter inherits the same trade-off for free (it
never mints its own row ids either), and should not try to route around it
— the alternative (always minting a fresh id) reintroduces the
cross-device duplicate-row problem item 3 exists to close.

**Sequencing — #247 before #172 (resolved):** #247 has merged
(`lib/domain/import/clue/clue_flow_level_mapping.dart`'s `flowLevelFromClue`),
so converting a `ClueFlowLevel` to the app's own `FlowLevel` is now
**lossless** — the "`ClueFlowLevel` — interim collapse rules" section
below describes lossy collapses that no longer happen; it is kept for
history, not as current guidance. **#172 (the bulk-write step) may now
consume this parser's output** — the constraint that blocked it is gone.

## What's in scope here, and what isn't

This issue is the parser and mapping spec only: bytes in
(`measurements.json`, or a whole encrypted export zip), a typed
`ClueDatapoint` stream out. It does **not**:

- write to the local database or Supabase (that's #172),
- show any import UI (that's #140),
- implement #199's post-import summary screen or `validateTagCodes`
  relaxation (this parser's `ClueUnknownDatapoint` is the *input* that
  screen will need to summarise, not the screen itself),
- implement #247's `FlowLevel.superHeavy`/spotting-split/not-bleeding
  changes to the app's own enum — this parser defines its own
  `ClueFlowLevel` (see below) so its output already matches what #247
  will ship, without depending on that still-open issue's unmerged enum.

### Not Clue-side renames

Issue #190's own body mentions `fatigue→tired`, an `energetic`/`calm`/
`acne` re-parenting, and legacy notes about `cravings` — none of those
are implemented in `clue_option_map.dart`, and that is deliberate, not a
gap: they are **lunarlog-internal taxonomy migrations owned by #134**,
not renames Clue's own export format calls for. This parser's job is
mapping Clue's `type`/option strings onto lunarlog's *current*
`observations.category`/`code` shape as it exists today; reshaping that
taxonomy further (folding `energy`'s `fatigue` option into a `tired`
code, or wherever #134 lands) is #134's concern, applied uniformly to
every `observations` row regardless of source, not something this
importer should special-case for Clue-sourced rows only.

## `measurements.json`'s actual shape

The zip's `measurements.json` root is a **bare JSON array**, one element
per `(day, category)` — not one element per day:

```json
{"date": "2026-01-01", "type": "period", "value": {"option": "light"}}
```

`value` is `{"option": "..."}` for single-select categories (`period`,
`spotting`, `discharge`) and a list of those for multi-select ones
(`pain`, `feelings`, ...). `bbt` is the exception: its `value` is a
numeric object (`{"celsius": 36.6, "excluded": false}`), never an
`option`. The parser (`clue_export_parser.dart`) itself does **not**
group by date — it stays a flat stream, each datapoint carrying its own
`date`. `clue_cycle_reconstruction.dart`'s `groupClueDatapointsByDate`
does that grouping (sorted by date) for any caller that needs it — the
bulk-write step included — so that acceptance need is met by this
module, not deferred to every caller reimplementing it.

## `ClueFlowLevel` — mapping to `FlowLevel` (Issue #247: now lossless)

`ClueFlowLevel`'s ordinals **do not** line up with the app's own
`FlowLevel` (`lib/domain/models/flow_level.dart`: `none, spotting,
notBleeding, light, medium, heavy, superHeavy` — Clue spotting is its own
`observations` category here, never a flow level) — never convert
between the two by `.index`; use
`lib/domain/import/clue/clue_flow_level_mapping.dart`'s
`flowLevelFromClue`.

**Historical note — this section used to describe two lossy interim
collapses, both now obsolete now that #247 has merged:**

- `ClueFlowLevel.superHeavy` → `FlowLevel.superHeavy` (used to collapse
  to `FlowLevel.heavy` before #247 shipped that value).
- `ClueFlowLevel.notBleeding` → `FlowLevel.notBleeding` (used to collapse
  to `FlowLevel.none` — re-conflating an explicit "not bleeding today"
  assertion with a day nothing was logged for at all — before #247
  shipped a state distinct from "unlogged").

The "Sequencing — #247 before #172" note above is resolved for the same
reason: #172 (the bulk-write step) can now consume this parser's output
without turning either of those collapses into permanent data loss,
because neither collapse happens anymore.

## Category/option mapping table

| Clue category | export `type` | Confidence | lunarlog target | Notes |
|---|---|---|---|---|
| Period | `period` | HIGH | `ClueFlowLevel` (flow, not an observation) | `light\|medium\|heavy\|very_heavy\|none`; `very_heavy` → `superHeavy`; `none` → `notBleeding` (a positive assertion, never dropped) |
| Spotting | `spotting` | HIGH | `observations.category = 'spotting'` | own category per #247, not a flow level; excluded from episode derivation entirely |
| Pain | `pain` | HIGH | `observations.category = 'pain'` | `period_cramps→cramps`, `lower_back→back_pain`, `pain_free` = negative assertion; other options (`breast_tenderness`, `headache`, `ovulation`, `migraine`, `migraine_with_aura`) pass through verbatim |
| Feelings | `feelings` | HIGH (+MEDIUM: `sensitive`, `mood_swings`) | `observations.category = 'feelings'` | all options pass through verbatim |
| Sex life | `sex_life` | HIGH (+MEDIUM: `protected_sex`, `unprotected_sex`) | `observations.category = 'sex_life'` | `no_sex_today` = negative assertion |
| Energy | `energy` | HIGH | `observations.category = 'energy'` | all options pass through verbatim |
| PMS | `pms` | option set undocumented | `observations.category = 'pms'` | pass-through |
| Digestion | `digestion` | HIGH | `observations.category = 'digestion'` | `bloated→bloating`, `nauseous`/`nauseated→nausea` |
| Discharge | `discharge` | HIGH | `observations.category = 'discharge'` | `none` = negative assertion |
| BBT | `bbt` (+`temperature` type alias, LOW) | HIGH shape / LOW value-key | `ClueNumericDatapoint(category: 'bbt')` | see "BBT numerics" below |
| Collection method | `collection_method` | option set undocumented | `observations.category = 'collection_method'` | pass-through |
| Social life | `social_life` | HIGH | `observations.category = 'social_life'` | pass-through |
| Craving | `craving` | HIGH | `observations.category = 'craving'` | pass-through |
| Mind (legacy Mental) | `mind` | not in real-data attested list | `observations.category = 'mind'` | pass-through |
| Motivation (legacy) | `motivation` | MEDIUM, 2 parsers | `observations.category = 'motivation'` | historic exports only; likely folded into Mind today |
| Sleep (duration) | `sleep` | MEDIUM, single parser | `observations.category = 'sleep'` | bucketed duration strings, pass-through |
| Exercise | `exercise` | HIGH+legacy | `observations.category = 'exercise'` | pass-through, all 7 options |
| Stool (legacy Poop) | `stool` | HIGH | `observations.category = 'stool'` | pass-through |
| Leisure | `leisure` | option set undocumented | `observations.category = 'leisure'` | pass-through — any option, known or not |
| Hair | `hair` | HIGH (support docs) | `observations.category = 'hair'` | pass-through |
| Skin | `skin` | MEDIUM, single parser | `observations.category = 'skin'` | pass-through |
| Medication | `medication` | HIGH | `observations.category = 'medication'` | pass-through |
| Appointments | `appointments` | option strings unconfirmed | `observations.category = 'appointments'` | pass-through |
| Ailments | `ailments` | HIGH | `observations.category = 'ailments'` | pass-through |
| Custom tags | `tags` | HIGH | `observations.category = 'tags'` | raw free text, **never** snake_cased or normalised — this parser applies no transform to any option string unless the mapping table above explicitly renames it, so `tags` needs no special case to get this right |
| Birth control | `birth_control` | MEDIUM, option strings unattested | `observations.category = 'birth_control'` | pass-through |
| Tests | `tests` | MEDIUM | `observations.category = 'tests'` | pass-through |
| Cervical mucus | `mucus` | claimed by 2 community parsers only, not in Clue's own category list | `observations.category = 'mucus'` | **assumption**: kept as its own category rather than folded into `discharge`, since no source documents them as the same export `type` — flag if a real export shows otherwise |

Categories with **no export `type` at all** (Meditation, Partying, Breasts
& chest, Hot flashes/perimenopause, Urine, Vulva & vagina, Supplements,
Sleep quality): not represented in `measurements.json` per any source
consulted for #190. A `type` string this table doesn't recognise —
whether one of these or a genuinely new Clue category — escapes to the
`ClueUnknownDatapoint` hatch below rather than being guessed at.

## Negative assertions — never a positive symptom

`period/none`, `pain/pain_free`, `sex_life/no_sex_today`, and
`discharge/none` are all **positive assertions of absence**, not missing
data. Every one of them decodes to an explicit state:

- `period/none` → `CluePeriodDatapoint(level: ClueFlowLevel.notBleeding)`,
  never simply "no period datapoint that day."
- The other three → `ClueObservationDatapoint(isNegativeAssertion: true)`,
  keeping the category and code (`pain_free`, `no_sex_today`, `none`)
  rather than dropping the row.

An importer that drops these or treats every option as "something
happened" fabricates periods, pain, and sexual activity the user
explicitly logged as absent.

## The escape hatch (Issue #199)

Two situations escape to `ClueUnknownDatapoint`, carrying the entire
original `{date, type, value}` row as `raw` for `observations.raw jsonb`:

1. **Unknown `type`** — a `type` string not in the mapping table above and
   not `period`/`bbt`/`temperature`. Weight is the clearest example: no
   source names a weight datapoint's shape at all, so it is deliberately
   *absent* from the mapping table rather than guessed at, and lands here
   automatically.
2. **Unknown value shape** — a known `type` whose `value` doesn't match
   what that type expects (`bbt` with none of its attested numeric keys;
   an option-based type whose `value` is neither `{option}` nor a list of
   those).

An **unknown option within a known type** (e.g. a `pain` option this
table has never seen) is *not* this escape hatch — lunarlog's
`Observation.code` is free text, never validated against a closed set
(see that model's own doc comment), so the option passes through
verbatim as `code` with no wrapping needed. The hatch is reserved for
`type`/`value` shapes we cannot place at all.

## Cycle/period reconstruction

Clue's export carries **no cycle-boundary field at all** — Read Your
Body, who ship a production Clue importer, confirm this and reconstruct
episodes from bleeding patterns themselves, exactly as this parser does
(`clue_cycle_reconstruction.dart`):

- A bleed day is a `CluePeriodDatapoint` at `light`/`medium`/`heavy`/
  `superHeavy` — `notBleeding` and every non-period datapoint (spotting
  included) are excluded from the bleed-date set.
- Episodes are the maximal runs of those bleed dates, reusing
  `lib/domain/episodes/episodes.dart`'s existing `deriveEpisodes` **as
  is**: a one-day gap merges into a single episode, a two-day-or-more gap
  splits. This already matches Clue's own reconstruction rule ("one
  skipped day tolerated"), so no new gap-merging logic was needed —
  only excluding spotting from the input set before handing it off.
- A **spotting-only run** never becomes an episode: since spotting is
  never added to the bleed-date set, a run of only spotting days simply
  never enters `deriveEpisodes`'s input — there is no separate "reject a
  spotting-only run" check to write, because spotting was never eligible
  to begin with.

**Same-day rule (Issue #190 review):** an export can carry more than one
`period` row for the same date (an edit/merge history artifact — Clue's
own UI only ever lets a user set one flow level per day). When that
happens, `clue_cycle_reconstruction.dart`'s `highestCluePeriodLevel`
picks the **highest bleed level** among that date's rows —
`ClueFlowLevel.notBleeding` never wins over a real bleed level, whichever
order the rows appear in, so a stray `period/none` row can never erase a
bleed entry logged for the same day. Combined with
`groupClueDatapointsByDate`, a caller reconstructing a single per-day
flow value (rather than this module's own bleed-date set, which is
already resilient to duplicates) has a documented rule to apply rather
than an unspecified one.

## BBT numerics

`bbt`'s value is a numeric object, not an option: `clue_export_parser.dart`
tries `celsius`, then `fahrenheit`, then `temperature`, then `value` (in
that order — `kClueBbtValueKeys`), taking the first key present and
numeric. The matched key name is carried through as `unit` **unverified**
— no conversion is applied, since which physical unit `temperature`/
`value` denote is unattested (see the LOW-confidence item below). A
`type: "temperature"` row is treated identically to `bbt` (a LOW-confidence
alias — see below). `value.excluded` decodes 1:1 to `ClueNumericDatapoint
.excluded`. Numeric parsing is defensive: a JSON number or a numeric
string both parse (`"36.9"` → `36.9`).

## Zip decryption — dependency decision

Clue's export is delivered as an **AES/ZipCrypto-encrypted zip** (the
one-time password from the export email unlocks it). Before adding any
dependency, `archive` (pub.dev, pure Dart) was evaluated against this
project's Dart 3.13 SDK:

- **Version:** `archive` 4.2.0 (latest on pub.dev at the time of this
  issue), analyzed against Dart 3.13.1 per its own pub.dev score page —
  compatible with this repo's `^3.13.2` SDK constraint.
- **Encryption support:** `ZipDecoder().decodeBytes(bytes, password: ...)`
  supports both legacy ZipCrypto and AES-256 encrypted entries (per the
  package's own CHANGELOG: "Add Zip AES-256 decryption" at 3.3.7, "Fix
  ZIP decryption for ZipCrypto format" at 3.3.3, refined further at 3.5.0
  and 3.6.0). A wrong password does not always fail at `decodeBytes`
  itself — for an AES-encrypted entry the failure surfaces lazily, only
  once the entry's bytes are actually read — so
  `clue_zip_reader.dart`'s `extractClueZipEntry` wraps the whole
  decode-and-read sequence, not just the decode call, to turn either
  failure into one `ClueZipException`.
- **Decision:** `archive: 4.2.0` was added to `pubspec.yaml`, pinned
  exactly (not `^`) since this is a security-sensitive decode path — a
  deliberate bump later, not a routine `pub upgrade`. It is pure Dart —
  no network calls, no FFI/native code — so no native dependency was
  needed, and the parser is implemented against the real encrypted-zip
  path end-to-end, not just an already-extracted `measurements.json`
  fallback.
- **The `posix` hedge can be relaxed:** `pubspec.lock` lists `posix` as a
  transitive dependency of `archive`, which could look like a native
  dependency slipping in despite the "pure Dart" claim above. It isn't
  reachable from this code: `posix` is only imported by
  `archive`'s own `lib/src/io/posix_io.dart`, which is only reachable
  through `archive_io.dart` (the `dart:io`-dependent half of the
  package's public API) — and `clue_zip_reader.dart` imports only
  `package:archive/archive.dart`, never `archive_io.dart`. `dart:io`
  purity (R14/R16) holds for this module regardless of what shows up in
  the lockfile's transitive closure.
- **Testing:** no real Clue export exists or may be committed to this
  repo, so `test/domain/import/clue/clue_zip_reader_test.dart` builds a
  small in-memory password-protected zip with the same package's own
  `ZipEncoder` and proves this module's own wiring (finding
  `measurements.json` by name, surfacing a wrong password, surfacing a
  missing entry) — it is not a test of `archive`'s cryptography itself,
  which is out of scope to re-verify here.

## Legacy `.cluedata` (out of scope for this issue)

An older Android backup format, root an object with a `data` array (one
element **per day**, not per datapoint), `period` a plain string rather
than `{option}`, and spotting a `period` option rather than its own
category (MEDIUM confidence, single source). Explicitly out of scope for
this issue's first pass. The datapoint model here does not structurally
block adding it later: a future `.cluedata` reader would produce the same
`ClueDatapoint` types, just from a different intermediate shape — the
mapping tables in `clue_option_map.dart` would need a parallel entry
point rather than a rewrite.

## Needs a real export to confirm (LOW confidence, load-bearing)

These four items — called out in Issue #190 as needing a real Clue
export (a test account's own export, or a donated sample) before this
importer ships to users — are handled tolerantly here, not resolved:

1. **`date` field format** — bare `YYYY-MM-DD` vs. a `Z`-suffixed ISO
   datetime, and whether any entry lacks the `Z` suffix. Handled: both
   formats parse via `slice(0, 10)` semantics, no timezone conversion.
2. **`bbt`'s numeric value key** — `celsius` vs. `temperature` vs.
   `celsius|fahrenheit|value` (sources conflict). Handled: all four tried
   in order; the matched key name is carried through as `unit`
   unconverted rather than assumed to be Celsius.
3. **Weight's entire datapoint shape** — completely unattested by any
   source. Handled: any `type: "weight"` (or anything else unattested)
   falls through to `ClueUnknownDatapoint(reason: unknownType)` rather
   than being guessed at.
4. **Whether free-text daily notes are present anywhere in the export** —
   unverified; two community parsers synthesize notes from unmapped tags
   instead of reading a dedicated field. Handled: no note field is
   assumed; an export that does carry one would currently surface it as
   an unmapped `type` (escape hatch) until a real export confirms its
   shape and a dedicated mapping is added.

This issue is expected to be labeled `needs-human-review` for exactly
these four items.
