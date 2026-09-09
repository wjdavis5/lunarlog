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
the cycle wheel is #209), Calendar (`logging/month_calendar.dart`), Insights (a
placeholder hosting `overview/cycle_history_section.dart` until #223 lands the
real Analysis tab), and More (`settings/settings_screen.dart`, unmodified,
including its own app bar). Today is the default/first tab. Each tab is built
lazily the first time it's selected and then kept alive under an
`IndexedStack`, so switching tabs preserves that tab's own state without
starting every tab's live streams and animations up front.

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
