---
title: Localization Scaffolding - Plan
type: feat
date: 2026-09-07
issue: wjdavis5/lunarlog#160
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-160
execution: code
---

# Localization Scaffolding - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written after implementation to record what shipped and
why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** Give lunarlog its first localization infrastructure —
  `flutter_localizations` + `intl`, `l10n.yaml`, a committed
  `lib/l10n/app_en.arb` with generated accessors, delegates and
  `supportedLocales` on both `MaterialApp`s, string extraction for the four
  highest-traffic screens (calendar, day sheet, overview, settings),
  locale-derived month/weekday names replacing the hand-rolled
  `kMonthNames`/`kWeekdayLabels` constants, an explicit first-day-of-week
  seam replacing the `weekday % 7` arithmetic, and a shared intl-backed
  date helper (`lib/ui/l10n/dates.dart`) that issue #198 builds on.
- **Means:** App-layer only. No schema, no migration, no server change, no
  domain change — `lib/domain` stays pure Dart (constraint), so the
  formatter and every name lookup live UI-side.
- **Authority hierarchy:** Issue #160 owns intent; the coordinator brief
  (`docs/coordinator/briefs/160.md`) owns scope for this wave — it
  explicitly defers the RTL/`Directionality` root change, the
  `EdgeInsetsDirectional` conversion pass, and the persisted
  first-day-of-week Settings override, and it binds the extracted English
  copy to be character-identical to the previous inline literals.
- **Stop conditions honored:** No RTL flips and no
  `app_lifecycle.dart` `Directionality` change (tracked in the issue text,
  not in this wave); no behavior change beyond locale plumbing; widget
  tests asserting extracted strings keep passing against identical copy.

---

## Key Technical Decisions

- **KTD1 — Generated Dart is committed, and excluded from the quality
  gate like other generated code.** `l10n.yaml` configures gen-l10n with
  `nullable-getter: false` so `AppLocalizations.of(context)` is non-null
  at every call site; the outputs (`lib/l10n/app_localizations*.dart`)
  are committed per the repo's convention for generated code. They are
  added to `tool/quality/exclusions.dart`'s generated-code globs (a
  `lib/l10n/app_localizations.*\.dart$` pattern alongside the existing
  `**/*.g.dart` rule) because the suffix glob cannot reach them — gen-l10n
  names its outputs after the ARB template. Their guard is
  `test/ui/l10n_test.dart`'s copy-parity suite (KTD5), which exercises
  every getter anyway.

- **KTD2 — Month and weekday names come from intl's date symbols, not
  from ARB keys and not from `MaterialLocalizations`.** Twelve
  `monthJanuary`-style ARB keys per locale would duplicate what intl
  already compiles; `MaterialLocalizations` has no bare month-name
  accessor (its `formatMonthYear` carries the year). `dates.dart`'s
  `monthNames`/`shortMonthNames`/`narrowWeekdayInitials` read
  `DateFormat(...).dateSymbols` for the ambient locale — every locale
  intl ships becomes available the day a locale is added to
  `supportedLocales`, with no per-locale name bookkeeping. The old
  `kMonthNames`/`kWeekdayLabels` constants are deleted outright; the four
  remaining importers (`overview_panel.dart`, `late_resolver.dart`,
  `cycle_history_section.dart`, `month_calendar.dart` itself) now derive
  names through the helper. `dayCellSemanticLabel` (public, pure, and
  called with no widget tree by `forecast_calendar_test.dart`) gained an
  optional `monthNames` parameter defaulting to the `en` list, so its
  direct tests run unchanged while the calendar passes its
  locale-derived names.

- **KTD3 — The first day of the week is an explicit, overridable seam,
  not derived yet.** `kFirstDayOfWeek` (a `DateTime` weekday constant,
  `DateTime.sunday` today) plus pure `leadingBlanksFor(year, month,
  {firstDayOfWeek})` and `weekdayHeaderLabels({locale, firstDayOfWeek})`
  in `month_calendar.dart` replace the baked `weekday % 7` arithmetic.
  Sunday keeps today's layout bit-for-bit (Dart's `%` is non-negative for
  a positive divisor, so `(weekday - firstDay) % 7` reproduces the old
  values); a locale-derived default and the persisted Settings override
  the issue names are follow-on work, and both grid consumers already
  honor the seam. Directly unit-tested, mirroring
  `dayCellSemanticLabel`/`canDrivePageController`'s public-pure-seam
  discipline.

- **KTD4 — `lib/ui/l10n/dates.dart` is standalone by design.** The
  #198 coordination point must be importable without the rest of the l10n
  machinery: it depends only on `intl` (plus `BuildContext` for
  `calendarLocale`), never on `AppLocalizations`. It exposes the brief's
  named forms — `formatShortDayDate` ("Tue 8 Sep"),
  `formatWeekdayDayDateYear` ("Tue 8 Sep 2026"), and
  `relativeDayLabel` ("Today · Tue 8 Sep" / "Yesterday" / "Tomorrow",
  civil-day comparison, caller-overridable relative words so a future
  locale passes its own ARB strings in) — plus `formatMonthDayYear` /
  `formatMonthDay` for the surfaces that previously formatted from
  `kMonthNames`. Because a bare `DateFormat(..., 'en')` throws
  `LocaleDataException` outside a localized app, every entry point lazily
  runs `initializeDateFormatting()` from
  `intl/date_symbol_data_local.dart` (synchronous and idempotent) — the
  module works from a pure unit test with no widget tree at all.

- **KTD5 — Copy parity is test-enforced, not review-enforced.** The
  constraint "ARB values identical to current copy" is guarded by
  `test/ui/l10n_test.dart`, which captures `AppLocalizations` under a
  delegate-bearing `MaterialApp` and asserts every extracted string —
  including the plural forms and the assembled privacy-policy dialog
  body — against the exact inline literal it replaced. A future ARB edit
  that changes English copy breaks a named test, not a screenshot.

- **KTD6 — Test pump trees register the delegates at their
  `MaterialApp`.** The four screens now read `AppLocalizations.of(context)`,
  which throws without delegates; every existing test that mounts them
  (directly or transitively) gained
  `localizationsDelegates: AppLocalizations.localizationsDelegates` /
  `supportedLocales: AppLocalizations.supportedLocales` on its
  `MaterialApp` — 22 pump sites across eight test files, assertions
  untouched. `AppLocalizations.localizationsDelegates` includes the
  Global material/cupertino/widgets delegates, so Material's own widget
  copy (`Cancel` etc.) stays English-equivalent under `en`. Tests that
  pump `LunarLogApp` or `LockScreen` need nothing: both `MaterialApp`s
  now carry the delegates themselves (asserted in `l10n_test.dart`).

- **KTD7 — Registration covers both `MaterialApp`s, and only `en` is
  supported.** `lib/app.dart`'s and `lib/ui/gate/lock_screen.dart`'s
  `MaterialApp`s register
  `AppLocalizations.localizationsDelegates`/`supportedLocales`
  (`[Locale('en')]` today). The lock screen renders above the app content
  in the shell's stack, so it must carry its own. Adding a locale =
  adding an ARB and extending the supported list — nothing else moves.

- **KTD8 — What was *not* extracted (declared follow-on).** The shared
  `kEstimateDisclaimer` constant (rendered by six surfaces —
  `today_card`, `late_resolver`, `overview_panel`, `analysis_tab`,
  `cycle_history_section`, `month_calendar` — through one `const`, so
  extracting it means converting all six call sites off a `const` in one
  pass); the day-sheet semantic-label phrasing inside the pure
  `dayCellSemanticLabel` family (month names within them *are*
  locale-derived; the surrounding phrases stay English literals until
  those helpers gain a context); care-mode copy (`careModeCopyFor` is
  domain); the tag taxonomy's `display` strings (its doc comment already
  reserves per-locale override); and every screen outside the four
  targets. Measured at PR time: `lib/ui` holds 424 `Text(` call sites,
  of which 177 still open with a string literal (down from 216 on
  `origin/main`); the four extracted screens retain only two
  literal-opening `Text(`s, both day-of-month numerals (`'${date.day}'`)
  that are not translatable copy.

---

## Implementation Units

- **U1 — Dependencies and generation.** `flutter_localizations` (SDK) and
  `intl` (pinned `0.20.3` exactly, matching the SDK's own pin) in
  `pubspec.yaml`; `generate: true`; `l10n.yaml`; `lib/l10n/app_en.arb`
  (83 messages, `@`-metadata with descriptions); committed
  `app_localizations.dart`/`app_localizations_en.dart`.
- **U2 — Both `MaterialApp`s register delegates + `supportedLocales`**
  (`lib/app.dart`, `lib/ui/gate/lock_screen.dart`).
- **U3 — `lib/ui/l10n/dates.dart`** (KTD4) with
  `test/ui/l10n/dates_test.dart` covering every format, the name lists,
  the seam (KTD3), and `calendarLocale`'s fallbacks.
- **U4 — Calendar screen.** `month_calendar.dart`: names and header label
  through the helper and `calendarMonthYearLabel`; all chrome, legend,
  layer, keep-logging, month-picker, and future-explainer copy through
  `AppLocalizations` (the explainer band keeps its exact assembled shape
  via two ARB variants — with and without the cycle-day clause — and an
  ICU plural for day/days).
- **U5 — Day sheet.** `day_sheet.dart`: flow chips through
  `localizedFlowLabel` (`flowLabel` stays as the `en` fallback for the
  activity feed, outside the four screens); delete dialog, future-date
  line, note field, error copy, read-only headings.
- **U6 — Overview screen.** `overview_panel.dart`: history link,
  quick-log and exclusion snackbars, long-cycle prompt, reminder hint;
  `_estimateDateText` takes the ambient locale. `late_resolver.dart` and
  `cycle_history_section.dart` re-pointed off `kMonthNames` (names only —
  their remaining copy is follow-on).
- **U7 — Settings screen.** `settings_screen.dart`: app bar, both
  feedback/support tiles, relock switch, health section, privacy tile and
  both dialogs (the policy body round-trips through the parity test).
- **U8 — Tests and gates.** The 22 delegate registrations (KTD6);
  `test/ui/l10n_test.dart` (parity, both-`MaterialApp` registration, and
  the issue's non-English-locale criterion — `SettingsScreen` under a
  `fr` device locale resolves to `en` without crashing);
  `tool/quality/exclusions.dart` gains the gen-l10n glob (KTD1).

## Verification

`flutter analyze` clean; full `flutter test` suite (2091 pre-existing
tests plus the new `l10n_test.dart`/`dates_test.dart`) green;
`dart run tool/quality_gate.dart` passes (90% floor + CRAP gate) with the
gen-l10n outputs excluded as generated code. Every test that asserted on
extracted English copy still asserts the same strings — the ARB values
are the previous literals, enforced by the parity suite.

## Out of Scope (tracked in the issue / follow-on)

RTL directionality at the shell root and the `EdgeInsetsDirectional`
pass (explicitly deferred by the brief); locale-derived or user-override
first day of week beyond the seam (Settings persistence tracked);
translation beyond `en` (Clue's 15 languages); the remaining 177
literal-arg `Text(` sites across `lib/ui`; `kEstimateDisclaimer` and the
shared-constant surfaces; semantic-label phrasing.
