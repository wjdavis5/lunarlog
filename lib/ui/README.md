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
