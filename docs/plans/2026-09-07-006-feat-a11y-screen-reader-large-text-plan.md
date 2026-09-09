# Plan — a11y: screen-reader and large-text pass over calendar, day sheet, and overview (Issue #138)

Date: 2026-09-07 · Branch: `feat/138-a11y-pass` · Epic: a11y-l10n (P1)

## Context

Issue #138 is the first accessibility pass over the app's three
meaning-carrying surfaces: the month calendar, the day sheet, and the
overview. It builds on the seams those surfaces just gained — #276/#133's
`dayCellSemanticLabel` (predicted-vs-logged was already semantic), #341's
autosave day sheet, and #340's `AppLocalizations` ARB scaffolding (which
this pass follows: every string it adds goes through ARB, no new
hardcoded literals). The issue's own comment (B-23) supplies the
day-cell label spec:

```
Semantics(
  button: selectable,
  selected: isToday,
  label: '<weekday> <d> <month>, <flow state>,
          <symptoms logged|no symptoms>,
          <today|future, not yet loggable|read-only>',
)
```

plus: `ExcludeSemantics` the blank leading cells; full day names on the
weekday header (letter stays the visual child); replace the whole-cell
`Opacity(0.35)` on plain future days with an `onSurface`-alpha text
colour on the number only; size the number circle from
`textScaler.scale(20)` (34px floor) and the markers row from
`scale(12)` (14px floor); keep a 48dp cell row minimum.

## What shipped

### Calendar (`lib/ui/logging/month_calendar.dart`)

1. **Cell semantics** — each cell is now a `Semantics` node *wrapping*
   its `InkWell` (`button: tapHandler != null`, `selected: isToday`,
   `label: dayCellSemanticLabel(...)`, `onTap:` the same handler the
   visible `InkWell` uses, `excludeSemantics: true`). Wrapping (not the
   old inner placement) matters: an inert cell — read-only with no
   entry, no tap handler — has no `InkWell` tap semantics for a label
   to merge into, and its label previously dissolved up into the grid's
   scroll node. Screen-reader activation and finger taps run one code
   path.
2. **`dayCellSemanticLabel` rewrite** — date now carries its weekday
   (`Wednesday, August 5`), a logged bleed names its level
   (`Medium flow`) plus symptom presence (`symptoms logged`/
   `no symptoms`), symptom-only days say `logged symptoms`, bare logged
   days say `logged, no symptoms`, and status is appended (`today`,
   `future date, not yet loggable`, `read-only`). Every predicted-day
   fragment keeps a "predicted/estimated" word, so no forecast state
   can sound logged. All fragments come from new ARB keys
   (`calendarCell*`); `fertileWindowLabel` reuses the care mode's own
   phrase, lowercased mid-label exactly as before.
3. **Weekday header** — each column keeps its narrow initial visually
   but carries the full day name (`dates.fullWeekdayNames`, new
   intl-backed helper next to `narrowWeekdayInitials`) as its
   `Semantics` label: "S S M T W T F" announces as Sunday…Saturday.
4. **Blank cells** — the leading blanks are `ExcludeSemantics`d and
   keyed (`calendar-leading-blank-<y>-<m>-<i>`) for test lookup.
5. **Dim, not `Opacity`** — the plain-future-day dim is now
   `onSurface.withValues(alpha: kFutureDayTextAlpha)` (0.38) on the
   day-number text only. `futureCellOpacity` stays the decision
   function (`< 1` means dimmed); a whole-cell 0.35 layer dragged the
   today ring and markers under usable contrast.
6. **Text-scale-aware geometry** (`dayCellMetricsFor`, pure) — circle
   `= clamp(scale(20), 34, cellWidth)`, markers row
   `= max(14, scale(12))`, row height `= max(cellWidth, 48, content)`
   feeding `GridView.childAspectRatio` from each page's own
   `LayoutBuilder` width. At 1.0x this is pixel-identical to the old
   square cells (`max(cellWidth, …)` picks the historic height); at 2.0x
   the row grows to fit the 40px circle and 24px markers. Every cell
   keeps a ≥48dp-tall touch target.
7. **Legend wrap fix** — the sweep exposed a real latent overflow at
   1.5x: the legend stays expanded below `kLegendCollapseTextScale`
   (1.6) and its chip `Row`s overflowed phone widths ("Super heavy flow
   (5 marks)"). Legend labels are now `Flexible` and wrap. The one
   inline legend literal moved to ARB (`calendarLegendSuperHeavy`).

### Day sheet (`lib/ui/logging/day_sheet.dart`)

8. **Chip group + selected** — every flow `ChoiceChip`, the spotting
   `FilterChip`, and every category `FilterChip` is wrapped in the new
   `groupedChipSemantics` (`label: '<group>, <chip>'`, `button`,
   `enabled`, `selected`, `onTap` sharing the chip's write path,
   `excludeSemantics: true`): a chip announces "Flow, Medium, selected",
   "Pain, Cramps", never a bare "Medium". The spotting chip's visible
   label now reads `flowLevelSpotting` from ARB (same string).
9. **Headings** — the flow section gained the visible heading the
   read-only variant already had (`daySheetFlowLabel`), and every
   section heading (plus the date title) is `Semantics(header: true)`
   for heading navigation.
10. **ARed flow levels** — `localizedFlowLabel` reads
    `flowLevelNotBleeding`/`flowLevelSuperHeavy` from ARB instead of
    inline `en` literals (issue #247 leftovers, strings verbatim).

### Overview (`cycle_wheel.dart`, `today_card.dart`)

11. **Wheel labels via ARB** — `cycleWheelSemanticsLabel` takes
    `AppLocalizations`; the centre label and the spoken phase use
    `cycleWheelCenter*`/`cycleWheelPhasePeriodDay` (historical strings
    verbatim — the centre label keeps its middle dot, the spoken phrase
    its comma). Status → estimate → disclaimer order was already the
    tree order and is now pinned by test.
12. **Confidence chip** — the bare tier word ("Learning") is announced
    as `futureExplainerConfidence(tier)` ("Estimate confidence:
    learning."), reusing the explainer's ARB key rather than adding a
    near-duplicate.

### Attribution badge + Manage Guardians

13. **Badge** — one `Semantics(container: true)` focus stop announcing
    "Logged by Dad", the icon excluded, and the text wraps instead of
    ellipsizing at 200% (the one fact the badge exists for must not
    truncate).
14. **Guardians tile** — the title `Row` is a `Wrap`, so a long name
    plus "(you)" flows instead of overflowing at 200%. Role badges
    (tile subtitle) and the invite/revoke actions were already
    labelled (tooltils + FAB label) and are now pinned by test.

### AC: no semantic label reaches a crash report or notification

`lib/observability/scrub.dart` is allowlist-shaped — a breadcrumb or
event keeps only allowlisted keys, and nothing in
`lib/observability/` references any label helper added here.
Notifications use the fixed generic `kReminderTitle`/`kReminderBody`
(`lib/data/notifications/scheduling.dart`). The label functions are
UI-layer only.

## Tests

- `test/ui/a11y_pass_test.dart` (new): calendar cell labels/flags
  (logged/predicted/today/read-only), weekday full names, blank-cell
  exclusion, `dayCellMetricsFor` pure tests, 48dp/touch-target and
  circle-growth widget assertions, the 1.0x/1.5x/2.0x no-overflow sweep
  over calendar, day sheet, TodayCard, mounted `OverviewPanel`, and
  Manage Guardians (long name + "(you)"), day-sheet chip group/selected
  semantics (including activation through the semantics tap), headers,
  note-field label, read-only reason, wheel label/order/confidence
  chip, guardians role announcement.
- `test/ui/forecast_calendar_test.dart`: label expectations updated to
  the new spec shape (weekday-prefixed, flow state + symptoms +
  loggability); the `Opacity` assertions replaced by the dim text
  colour + no-`Opacity`-remains assertions.
- `test/ui/today_card_test.dart`: wheel label tests take `l10n`; pump
  registers delegates.
- `test/ui/caregiver_attribution_badge_test.dart`: one-node semantics,
  icon excluded, no ellipsis at 200%.
- `test/ui/l10n/dates_test.dart`: `fullWeekdayNames` Sunday-first.
- `test/ui/l10n_test.dart`: parity entries for every literal moved into
  ARB (`flowLevelNotBleeding`, `flowLevelSuperHeavy`,
  `calendarLegendSuperHeavy`, the four `cycleWheel*` keys) — all
  verbatim.

## Not done / known limits

- **Manual VoiceOver and TalkBack passes** (an AC) — no physical
  devices in this environment; must be run before store-listing
  claims. The widget tests prove the labels exist, not that the
  experience works.
- **Cell width on 320dp-wide devices** — 7 columns cap width at
  ~44.6dp there (height minimum is 48dp everywhere, and width ≥48dp on
  ≥352dp viewports). Widening further needs a column-count or layout
  change; noted rather than papered over.
- **`InlineError` live regions** for async failures — tracked in #187
  (B-20), deliberately not duplicated here.
- **Calendar symptom-layer chips** keep native chip selected semantics
  (no per-chip group wrapper); their group is reachable via the
  section's tooltip. The day sheet — the AC's target — is fully
  grouped.
- **Pre-existing un-localized copy** (Manage Guardians' visible strings,
  `CareModeCopy`, disclaimers) is untouched — out of scope, and this
  pass adds no new literals.
