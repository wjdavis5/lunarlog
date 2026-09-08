/// Care-mode reminder presets (Issue #131, R12): which reminder types are
/// on out of the box, per profile mode.
///
/// Prospective only (KTD10): presets are consulted at the next coordinator
/// replan and never rewrite saved entries or past (already-delivered)
/// reminders. Mode remains presentation, not permission — a preset decides
/// what a mode *nags about*, never what anyone may read or write.
///
/// Pure Dart (R14/R16).
library;

import '../models/profile_mode.dart';

/// Which [ReminderKind]s a mode arms by default.
class ReminderPreset {
  const ReminderPreset({required this.upcoming, required this.late});

  /// The "upcoming period" reminder (estimate − 2 days).
  final bool upcoming;

  /// The pre-armed daily "late" window. Off for the modes where overdue
  /// framing is wrong rather than useful: `teen` (regularity is still
  /// establishing), `irregular` (the late banner is silenced outright), and
  /// `caregiver` (a guardian's device should not be nagged the way the
  /// person whose cycle it is would be — Issue #131).
  final bool late;

  /// Every reminder type enabled — the pre-#131 behavior, and the fallback
  /// for callers that carry no preset (existing callers, older tests).
  static const ReminderPreset all =
      ReminderPreset(upcoming: true, late: true);

  /// Every reminder type disabled — `caregiver`'s out-of-the-box posture.
  static const ReminderPreset none =
      ReminderPreset(upcoming: false, late: false);
}

/// The preset for [mode]. A switch expression naming every mode (no `_`
/// wildcard): adding a [ProfileMode] without a preset is a compile error.
ReminderPreset reminderPresetFor(ProfileMode mode) => switch (mode) {
      // The default experience is unchanged: both reminder types on.
      ProfileMode.standard => ReminderPreset.all,
      ProfileMode.teen =>
        const ReminderPreset(upcoming: true, late: false),
      ProfileMode.caregiver => ReminderPreset.none,
      ProfileMode.irregular =>
        const ReminderPreset(upcoming: true, late: false),
    };
