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
for a screen-reader user (`RestoreErrorScreen` does not do this yet — a #187
follow-up). `InlineError` always wraps its message in that same
live region so assistive technology hears the failure the moment it happens,
without the person needing to move focus onto it. `EmptyState`'s illustration
slot is deliberately unwired today — #164 (UX-11) owns the bundled
illustration set and when to introduce it.

## Navigation (issue #182)

Once a profile is active, `ProfileHomeGate` (`profiles/profile_home_gate.dart`)
mounts `AppShell` (`components/app_shell.dart`): a Material 3 bottom
`NavigationBar` with four destinations — Today (`overview/overview_panel.dart`;
the cycle wheel is #209), Calendar (`logging/month_calendar.dart`), Insights
(`insights/analysis_tab.dart`'s `AnalysisTab`, issue #223 — the nav-bar label
stays "Insights" per #182, the screen's own heading reads "Analysis"), and
More (`settings/settings_screen.dart`, unmodified, including its own app bar).
Today is the default/first tab. Each tab is built lazily the first time it's
selected and then kept alive under an `IndexedStack`, so switching tabs
preserves that tab's own state without starting every tab's live streams and
animations up front.

`AnalysisTab` (issue #223, A2-18/A2-19) renders the headline cycle statistics
`ActivePrediction` already computed but nothing in the UI rendered before this
issue — average cycle length, average period length, and a variability/tier
line, all routed through the same `CareModeCopy` decision `OverviewPanel` uses
so `irregular` mode shows a number-free summary instead of raw digits — the
same R17 disclaimer, an honest not-enough-history `EmptyState` below three
valid cycles, and `overview/cycle_history_section.dart`'s existing
`CycleHistorySection` mounted below the headline as this tab's scrollable
history list. `OverviewPanel` (Today) still embeds that same
`CycleHistorySection` too — removing it from there is a follow-up, left alone
here since #209 is concurrently rewriting that file. `AnalysisTab` builds its
sections as a list precisely so #135 (statistics/trends) can append another
entry once it lands, rather than reshaping the widget.

The app bar shared by Today/Calendar/Insights (not shown on More, which is
Settings' own screen) carries the active profile name as a tappable switcher
opening the existing profile picker, the `SyncStatusGlyph`
(`account/sync_status_tile.dart`), and a Settings action that just switches to
the More tab. `ProfileDetailScreen` (`profiles/profile_detail_screen.dart`)
remains only for the archived-profile read-only view, still pushed explicitly
from the picker.

`routes.dart` centralizes named-route construction: `buildNamedRoute` pairs a
`kRoute*` constant (`lib/observability/route_names.dart`) with a
`MaterialPageRoute`, and `kAppRoutes`/`pushNamedScreen` cover the handful of
parameterless destinations reused across more than one push site. This app
never calls `Navigator.pushNamed` (see `app.dart`'s `onGenerateRoute` note) —
every push is a direct `Navigator.of(context).push(...)`; the sites the #182
pass migrated build their route through one of these two so a route name
lives in exactly one place (a few older pushes in `lib/ui/sharing/` still
hand-roll theirs — tracked as a follow-up).
