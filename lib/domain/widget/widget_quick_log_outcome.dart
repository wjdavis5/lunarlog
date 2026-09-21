/// What happened to a home-screen widget quick-log tap (issue #1016): the
/// executor's result, surfaced to the app shell so a gated widget write is
/// acknowledged the same way the in-app "Period started today" button is
/// (`overviewLoggedSnackbar` + Undo, #856) instead of silently landing.
///
/// The executor used to resolve to `void` — correct and gated (issue #141),
/// but invisible. This type is the outcome channel: exactly one value is
/// emitted per execution that reached the write stage, while a latched
/// intent still waiting on the device gate emits nothing (it has not
/// resolved yet).
///
/// Three real outcomes, mirroring the three the user can tell apart:
///
/// * [WidgetQuickLogLogged] — today's entry was created or raised to the
///   quick-log flow. Carries the pre-write [WidgetQuickLogLogged.previous]
///   so the shell's Undo can restore exactly what was there (the same
///   helper the in-app path calls).
/// * [WidgetQuickLogAlreadyLogged] — today already carries a flow at or
///   above the quick-log level, so nothing was written (never downgrade).
/// * [WidgetQuickLogDropped] — the intent was refused at write time: the
///   operator's re-verified role may not log, the profile is gone or
///   archived, or the write itself failed. No entry changed.
library;

import '../models/day_entry.dart';
import '../models/local_date.dart';

/// The result of one widget quick-log execution. Sealed: the shell's
/// routing switch names every case (no wildcard), so a future outcome
/// cannot silently fall through to "no feedback".
sealed class WidgetQuickLogOutcome {
  const WidgetQuickLogOutcome({required this.profileId});

  /// The profile the tap named — the target the shell navigates to (for
  /// the two outcomes that actually resolved against a live profile).
  final String profileId;
}

/// The widget tap created or raised today's entry for [profileId].
class WidgetQuickLogLogged extends WidgetQuickLogOutcome {
  const WidgetQuickLogLogged({
    required super.profileId,
    required this.date,
    required this.previous,
  });

  /// The civil date the write targeted (the executor's own `today` seam),
  /// so Undo restores the right row without re-deriving a wall-clock date.
  final LocalDate date;

  /// Today's entry before the write — null when the tap is what created
  /// it, non-null when it was raised from a lighter flow. Undo deletes on
  /// null and restores this otherwise, exactly like the in-app path.
  final DayEntry? previous;

  @override
  String toString() =>
      'WidgetQuickLogLogged(<${profileId.length}-char profile id>, $date, '
      'previous: ${previous == null ? 'none' : 'present'})';
}

/// The tap was a no-op: [profileId] already has a flow at or above the
/// quick-log level, so the existing (possibly hand-logged heavier) value
/// was left untouched.
class WidgetQuickLogAlreadyLogged extends WidgetQuickLogOutcome {
  const WidgetQuickLogAlreadyLogged({required super.profileId});

  @override
  String toString() =>
      'WidgetQuickLogAlreadyLogged(<${profileId.length}-char profile id>)';
}

/// The tap was refused before any write: role re-verification failed, the
/// profile no longer exists (or is archived), or the write threw.
class WidgetQuickLogDropped extends WidgetQuickLogOutcome {
  const WidgetQuickLogDropped({required super.profileId});

  @override
  String toString() =>
      'WidgetQuickLogDropped(<${profileId.length}-char profile id>)';
}
