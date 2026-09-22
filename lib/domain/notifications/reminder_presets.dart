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
  /// establishing) and `irregular` (the late banner is silenced outright).
  /// Issue #850: the retired `caregiver` mode no longer suppresses anything
  /// here — a guardian device has no local reminders at all (a later unit
  /// gates it on the per-viewer lens), so the legacy wire value plans
  /// exactly like `standard`.
  final bool late;

  /// Every reminder type enabled — the pre-#131 behavior, and the fallback
  /// for callers that carry no preset (existing callers, older tests).
  static const ReminderPreset all =
      ReminderPreset(upcoming: true, late: true);

  /// Every reminder type disabled. Issue #850: no longer a mode's
  /// out-of-the-box posture (a guardian's device is gated on the lens, not
  /// a preset), but kept as the explicit "plan nothing" value callers and
  /// tests compose by hand.
  static const ReminderPreset none =
      ReminderPreset(upcoming: false, late: false);
}

/// The preset for [mode], composed with the irregular-framing flag
/// (Issue #853). A switch expression naming every mode (no `_`
/// wildcard): adding a [ProfileMode] without a preset is a compile error.
/// [irregularFraming] composes the same way the copy registry does: the
/// base mode's preset, minus the "late" nags — overdue framing is wrong
/// rather than useful for a profile whose framing treats variation as
/// expected (teen + flag, or any mode + flag). Issue #850: the legacy
/// `caregiver` wire value plans like `standard` — guardian reminder
/// suppression is a per-viewer lens concern now, not a mode.
ReminderPreset reminderPresetFor(
  ProfileMode mode, {
  bool irregularFraming = false,
}) {
  final base = switch (mode) {
      // The default experience is unchanged: both reminder types on.
      ProfileMode.standard => ReminderPreset.all,
      ProfileMode.teen => const ReminderPreset(upcoming: true, late: false),
      ProfileMode.caregiver => ReminderPreset.all,
      ProfileMode.irregular => const ReminderPreset(upcoming: true, late: false),
    };
  if (!irregularFraming) return base;
  return ReminderPreset(upcoming: base.upcoming, late: false);
}
