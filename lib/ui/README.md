UI layer — screens, widgets, navigation, and theme.

## Empty and error states (issue #187)

`lib/ui/components/empty_state.dart` (`EmptyState`) and
`lib/ui/components/inline_error.dart` (`InlineError`) are the shared
components for "there's nothing here" and "that just failed" — reach for
them instead of a bespoke icon+text column or a raw red `Text`. The rule for
which failure treatment to use: **inline error** (`InlineError`) for a
retryable failure tied to one specific in-place action — a save, a delete, an
export, a linked-account operation — so the person sees the failure right
next to the control they just used and can retry it without losing context;
**a `SnackBar`** for a transient background event that isn't tied to any one
field or control (e.g. a background sync hiccup); and **a full screen** only
when the app genuinely cannot continue at all (e.g. `RestoreErrorScreen`),
in which case it must still announce its message the way `InlineError` does
(`Semantics(liveRegion: true, container: true)`) rather than sitting silent
for a screen-reader user. `InlineError` always wraps its message in that same
live region so assistive technology hears the failure the moment it happens,
without the person needing to move focus onto it. `EmptyState`'s illustration
slot is deliberately unwired today — #164 (UX-11) owns the bundled
illustration set and when to introduce it.

## Navigation (issue #182)

Once a profile is active, `ProfileHomeGate` (`profiles/profile_home_gate.dart`)
mounts `AppShell` (`components/app_shell.dart`): a Material 3 bottom
`NavigationBar` with four destinations — Today (`overview/overview_panel.dart`,
topped by the #209 cycle wheel/Today card), Calendar (`logging/month_calendar.dart`), Insights
(`insights/analysis_tab.dart`'s `AnalysisTab`, issue #223 — the nav-bar label
stays "Insights" per #182, the screen's own heading reads "Analysis"), and
More (`settings/settings_screen.dart`, unmodified, including its own app bar).
Today is the default/first tab. Each tab is built lazily the first time it's
selected and then kept alive under an `IndexedStack`, so switching tabs
preserves that tab's own state without starting every tab's live streams and
animations up front.

Issue #313's tab-switch seam, `components/app_shell_scope.dart`'s
`AppShellScope` (an `InheritedWidget` wrapping the shell's whole `Scaffold`),
lets any widget mounted inside the shell switch tabs itself:
`AppShellScope.maybeOf(context)` returns the current `AppTab` plus a
`select(AppTab)` callback, or null when no shell is mounted above the calling
context (`ProfileDetailScreen`'s archived read-only view, and any test tree
that pumps a tab's content directly) — callers must treat null as "nowhere
to switch to", not a bug. `AppTab`/`AppShellScope` live in their own file
rather than `app_shell.dart` itself (though that file still re-exports both)
so `overview_panel.dart` can depend on the seam without a mutual import
between the two files — the same reason `kEstimateDisclaimer` moved out of
`overview_panel.dart` into `estimate_copy.dart` (see that file's doc
comment). `OverviewPanel`'s "See cycle history" link (below) is the seam's
first caller.

`AnalysisTab` (issue #223, A2-18/A2-19) renders the headline cycle statistics
`ActivePrediction` already computed but nothing in the UI rendered before this
issue — average cycle length, average period length, and a variability/tier
line, all routed through the same `CareModeCopy` decision `OverviewPanel` uses
so `irregular` mode shows a number-free summary instead of raw digits — the
same R17 disclaimer, an honest not-enough-history `EmptyState` below three
valid cycles, and `overview/cycle_history_section.dart`'s existing
`CycleHistorySection` mounted below the headline as this tab's scrollable
history list. Issue #314: this is now `CycleHistorySection`'s *only* mount —
`OverviewPanel` (Today) used to embed the same section too (left open by
#223 since #209 was concurrently rewriting that file), rendering it twice
and running two `CycleHistoryService.watch` subscriptions per profile;
Today links here instead now (see below). `AnalysisTab` builds its sections
as a list precisely so #135 (statistics/trends) can append another entry
once it lands, rather than reshaping the widget.

The app bar shared by Today/Calendar/Insights (not shown on More, which is
Settings' own screen) carries the active profile name as a tappable switcher
opening the existing profile picker, the `SyncStatusGlyph`
(`account/sync_status_tile.dart`), and a Settings action that just switches to
the More tab. `ProfileDetailScreen` (`profiles/profile_detail_screen.dart`)
remains only for the archived-profile read-only view, still pushed explicitly
from the picker — it mounts `OverviewPanel` directly, outside any `AppShell`,
so `OverviewPanel`'s own "See cycle history" link hides itself there
(`AppShellScope` is never mounted above it, and there is no Insights tab on
that screen to link to). That would otherwise leave an archived profile with
no cycle-history surface at all (a regression of issue #132), so
`ProfileDetailScreen`'s Overview tab mounts a read-only `CycleHistorySection`
of its own directly below `OverviewPanel` whenever the screen is archived,
keeping the history card available there without the omit/include
affordances.

## Today card and cycle wheel (issue #209)

`components/cycle_wheel.dart` (`CycleWheel`) is the ring visualization of
the current cycle — an elapsed-days progress arc, the predicted-bleed band
at the top of the ring, today's marker, and a centre label ("Cycle day N"
or "Period · day N"). Its geometry (`cycleWheelFraction`) and screen-reader
label (`cycleWheelSemanticsLabel`) are exposed as pure top-level functions
so the math and the Semantics text are unit-testable without pumping a
widget; the `CustomPainter` itself stays a thin dispatcher over per-layer
helper methods to keep the quality gate's per-method CRAP score down.
Colours come from the theme — plain `ColorScheme` roles for the base
ring/elapsed arc, `LunarLogColors.predictedBand`/`predictedBorder` (issue
#176) for the band — never literals.

`components/today_card.dart` (`TodayCard`) wraps the wheel with the
next-period estimate, a compact confidence chip (`LunarLogColors`'
`confidenceHigh`/`confidenceLearning`/`confidenceIrregular`), the R17
disclaimer, and the primary "Period started today" one-tap action —
omitted entirely (not merely disabled) when the caller's effective role
can't log. `OverviewPanel` mounts it at the top of its active-estimate
card, in place of what used to be a standalone phase headline,
next-period-estimate line, and disclaimer `Text` — moved into `TodayCard`
rather than duplicated, so each still renders exactly once per card. The
tier caption, late resolver/status line, and long-cycle prompt below it
are unchanged. The one-tap write itself goes through the same
`DayEntriesRepository` upsert `OverviewPanel`'s day sheet already uses;
`lib/domain/logging/quick_log.dart`'s `quickLogFlowLevel` is the pure rule
that keeps a second tap (or a day already logged heavier via the full day
sheet) from ever downgrading an existing flow level — the upsert's own
(profileId, date) identity is what keeps a second tap from ever creating a
second entry.

Issue #314: below the active/not-enough card, `OverviewPanel` renders a
"See cycle history" `TextButton` (`ValueKey('overview-see-history-link')`)
that switches the shell to Insights via the tab-switch seam above —
`AppShellScope.maybeOf(context)?.select(AppTab.insights)` — instead of
mounting its own copy of `CycleHistorySection` the way it used to. The link
renders nothing when no `AppShellScope` is present.

`components/today_log_fab.dart` (`TodayLogFab`) is the shell-level "Log
today" `FloatingActionButton.extended` (issue #209 item 4a): it floats over
the Today and Calendar tabs only, opens the day sheet for today's date
directly (the same entry point the overview's late resolver "Log it"
already opens), and hides itself for a `viewer`-role guardian.

`routes.dart` centralizes named-route construction: `buildNamedRoute` pairs a
`kRoute*` constant (`lib/observability/route_names.dart`) with a
`MaterialPageRoute`, and `kAppRoutes`/`pushNamedScreen` cover the handful of
parameterless destinations reused across more than one push site. This app
never calls `Navigator.pushNamed` (see `app.dart`'s `onGenerateRoute` note) —
every push is a direct `Navigator.of(context).push(...)`; the sites the #182
pass migrated build their route through one of these two so a route name
lives in exactly one place (a few older pushes in `lib/ui/sharing/` still
hand-roll theirs — tracked as a follow-up).
