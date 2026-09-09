/// Reminder planning (KTD7, R12): pure, testable core that decides WHICH
/// local notifications should be pending, from each active profile's live
/// prediction.
///
/// Posture (settled): near-term only — an "upcoming" reminder a configured
/// number of days before an estimate, a PMS-watch reminder on the same
/// shape, "late" reminders pre-armed daily for a bounded window, and a
/// daily log nudge (Issue #136, R10/R11). iOS delivers local notifications
/// with no Dart callback, so a same-day re-arm loop cannot be relied on;
/// each reschedule arms the next bounded window ahead. Every body/title is
/// generic — no profile names, no dates (lock-screen privacy).
///
/// Issue #136 (per-type configuration): each profile's
/// [ReminderConfig] decides which types are armed, each type's own
/// fire time-of-day, and each estimate-relative type's lead days. When a
/// profile carries no stored config, `ReminderConfig.fromPreset` derives
/// the pre-#136 defaults from its care-mode [ReminderPreset] — the plan is
/// byte-identical to what the two hardcoded kinds produced.
///
/// Transition-driven, not pre-computed (Issue #136): the coordinator
/// replans on every prediction emission (becoming active, becoming late,
/// any estimate shift — however small) and every app resume, and every
/// replan re-derives fire dates from the *live* estimate through
/// [planReminders]. There is no fixed pre-computed date to go stale: an
/// estimate that moves re-arms the plan around where the estimate now is.
library;

import 'dart:convert';

import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart'
    show QuietHours;
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

export 'package:lunarlog/domain/notifications/reminder_config.dart'
    show ReminderKind;

/// Days before the estimate the "upcoming period" reminder fired pre-#136.
/// Kept (value unchanged) for callers and tests that reference it; the
/// adjustable default it became is
/// [kUpcomingDefaultLeadDays].
const int kUpcomingReminderOffsetDays = 2;

/// Grace past the estimate before "late" (mirrors [kLateGraceDays]).
const int kLateGraceDays = 2;

/// Late reminders are pre-armed this many days ahead at every reschedule.
const int kLatePreArmDays = 7;

/// Hard cap on pending lunarlog notifications (iOS allows 64 per app).
const int kMaxPendingReminders = 60;

/// Generic content only (KTD7): these exact strings are what the lock
/// screen shows — never a profile name, date, or health detail.
const String kReminderTitle = 'A reminder from Lunarlog';
const String kReminderBody = 'Open Lunarlog to see what it is about.';

/// Eviction priority under the [kMaxPendingReminders] cap (Issue #136):
/// lower is kept longer. The documented eviction order is late over
/// upcoming over PMS-watch over log-nudge — the daily nudge, the most
/// reproducible of the four, is the first thing dropped when the cap
/// binds.
int evictionPriority(ReminderKind kind) => switch (kind) {
      ReminderKind.late => 0,
      ReminderKind.upcoming => 1,
      ReminderKind.pms => 2,
      ReminderKind.log => 3,
    };

/// A deterministic 31-bit notification id derived from the reminder's
/// identity (profile, kind, fire date, time-of-day). Two plans with the
/// same reminders produce the same ids — unlike a plan-index id, which
/// would silently renumber whenever a sibling reminder appeared or
/// vanished. FNV-1a: stable across processes and runs, unlike Dart's
/// seeded `Object.hash`.
int stableReminderId(String key) {
    var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

class PlannedReminder {
  const PlannedReminder({
    required this.profileId,
    required this.fireOn,
    required this.kind,
    this.timeOfDayMinutes = kDefaultReminderTimeMinutes,
  });

  final String profileId;
  final LocalDate fireOn;
  final ReminderKind kind;

  /// Fire time-of-day, minutes since local midnight — the type's
  /// configured time after quiet-hours shifting (R10).
  final int timeOfDayMinutes;

  /// The notification id the scheduler uses for this reminder. Derived
  /// from the reminder's full identity (see [stableReminderId]), so a
  /// replan that yields the same reminder reuses the id rather than
  /// renumbering it.
  int get id => stableReminderId(
      '$profileId|${kind.name}|${fireOn.iso}|$timeOfDayMinutes');

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.profileId == profileId &&
      other.fireOn == fireOn &&
      other.kind == kind &&
      other.timeOfDayMinutes == timeOfDayMinutes;

  @override
  int get hashCode => Object.hash(profileId, fireOn, kind, timeOfDayMinutes);

  @override
  String toString() =>
      'PlannedReminder($profileId ${fireOn.iso} ${kind.name} '
      '@$timeOfDayMinutes)';
}

/// Plans reminders from the active profiles' [ActivePrediction]s, filtered
/// by each profile's care-mode [ReminderPreset] (Issue #131, R12) and, when
/// present, its stored [ReminderConfig] (Issue #136, R10/R11).
///
/// Profiles without a live estimate ([NotEnoughHistory]) produce nothing —
/// no partial signals — except the prediction-independent daily log nudge,
/// which a profile with *no* estimate still gets when its config enables
/// it (a nudge is most valuable exactly when history is thin). Issue
/// #221/A2-12 folded the old "paused past sixty days" dead end into
/// [ActivePrediction] itself (flagged
/// [ActivePrediction.unusuallyLongCycle]), so that state now plans
/// reminders exactly like any other active estimate — never go silent.
///
/// A profile with no entry in [presets] gets [ReminderPreset.all], and one
/// with no entry in [configs] gets `ReminderConfig.fromPreset(preset)` —
/// so callers that carry no mode or config information (and the pre-#136
/// tests) keep the exact plan they always produced. A profile whose
/// [lateSnoozes] entry is on or after [today] (the "Not yet" action's
/// three-day snooze) contributes no late reminders.
///
/// Same-day duplicates coalesce per profile: after quiet-hours shifting,
/// at most one reminder per profile per fire date survives, the winner
/// decided by the eviction priority (late over upcoming over PMS-watch
/// over log-nudge). The result is sorted by fire date and capped at
/// [kMaxPendingReminders], evicting in the same priority order.
List<PlannedReminder> planReminders({
  required LocalDate today,
  required Map<String, ActivePrediction> predictions,
  Map<String, ReminderPreset> presets = const {},
  Map<String, ReminderConfig> configs = const {},
  Map<String, LocalDate> lateSnoozes = const {},
}) {
  final planned = <PlannedReminder>[];
  // The log nudge plans even without a prediction (its config entry can
  // name a profile the prediction stream has nothing for yet).
  final ids = {...predictions.keys, ...configs.keys};
  for (final id in ids) {
    final preset = presets[id] ?? ReminderPreset.all;
    final config = configs[id] ?? ReminderConfig.fromPreset(preset);
    planned.addAll(_planProfile(
      profileId: id,
      today: today,
      prediction: predictions[id],
      config: config,
      snoozeUntil: lateSnoozes[id],
    ));
  }
  return _coalesceAndCap(planned);
}

/// One profile's plan: the prediction-independent types (log nudge), then
/// — when a live prediction exists — the estimate-relative types.
List<PlannedReminder> _planProfile({
  required String profileId,
  required LocalDate today,
  required ActivePrediction? prediction,
  required ReminderConfig config,
  required LocalDate? snoozeUntil,
}) {
  final planned = <PlannedReminder>[];
  if (config.log.enabled) {
    for (var i = 0; i < kLogNudgePreArmDays; i++) {
      planned.add(_planOne(
        profileId,
        ReminderKind.log,
        today.addDays(i),
        config.log.timeOfDayMinutes,
        config.quietHours,
      ));
    }
  }
  if (prediction == null) return planned;
  final snoozed = snoozeUntil != null && snoozeUntil.compareTo(today) >= 0;
  planned.addAll(_planEstimateRelative(
    profileId: profileId,
    today: today,
    prediction: prediction,
    config: config,
    snoozed: snoozed,
  ));
  return planned;
}

/// The prediction-anchored types: period-due and PMS-watch fire only when
/// their configured moment is still in the future; the late window
/// pre-arms a bounded daily run starting today.
List<PlannedReminder> _planEstimateRelative({
  required String profileId,
  required LocalDate today,
  required ActivePrediction prediction,
  required ReminderConfig config,
  required bool snoozed,
}) {
  final planned = <PlannedReminder>[];
  final estimate = prediction.estimatedNextStart;
  final upcomingOn =
      estimate.addDays(-config.upcoming.effectiveLeadDays(kUpcomingDefaultLeadDays));
  if (config.upcoming.enabled && upcomingOn.compareTo(today) > 0) {
    planned.add(_planOne(
      profileId,
      ReminderKind.upcoming,
      upcomingOn,
      config.upcoming.timeOfDayMinutes,
      config.quietHours,
    ));
  }
  final pmsOn =
      estimate.addDays(-config.pms.effectiveLeadDays(kPmsDefaultLeadDays));
  if (config.pms.enabled && pmsOn.compareTo(today) > 0) {
    planned.add(_planOne(
      profileId,
      ReminderKind.pms,
      pmsOn,
      config.pms.timeOfDayMinutes,
      config.quietHours,
    ));
  }
  if (config.late.enabled && prediction.isLate && !snoozed) {
    for (var i = 0; i < kLatePreArmDays; i++) {
      planned.add(_planOne(
        profileId,
        ReminderKind.late,
        today.addDays(i),
        config.late.timeOfDayMinutes,
        config.quietHours,
      ));
    }
  }
  return planned;
}

/// Builds one reminder with its quiet-hours shift applied (R10): a fire
/// landing inside the window moves to the boundary instead of being
/// dropped.
PlannedReminder _planOne(
  String profileId,
  ReminderKind kind,
  LocalDate fireOn,
  int minuteOfDay,
  QuietHours? quietHours,
) {
  final shifted = shiftQuietHours(fireOn, minuteOfDay, quietHours);
  return PlannedReminder(
    profileId: profileId,
    fireOn: shifted.date,
    kind: kind,
    timeOfDayMinutes: shifted.minuteOfDay,
  );
}

/// Orders by eviction priority, then fire date, then time-of-day.
int _byEvictionOrder(PlannedReminder a, PlannedReminder b) {
  final byPriority =
      evictionPriority(a.kind).compareTo(evictionPriority(b.kind));
  if (byPriority != 0) return byPriority;
  final byDate = a.fireOn.compareTo(b.fireOn);
  if (byDate != 0) return byDate;
  return a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes);
}

/// The delivery order the scheduler presents: by fire moment.
int _byFireOrder(PlannedReminder a, PlannedReminder b) {
  final byDate = a.fireOn.compareTo(b.fireOn);
  if (byDate != 0) return byDate;
  final byTime = a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes);
  if (byTime != 0) return byTime;
  return a.profileId.compareTo(b.profileId);
}

/// Coalesces same-day duplicates (highest eviction priority wins), caps at
/// [kMaxPendingReminders] in the same priority order, and re-sorts into
/// fire order for scheduling.
List<PlannedReminder> _coalesceAndCap(List<PlannedReminder> planned) {
  planned.sort(_byEvictionOrder);
  final seen = <String>{};
  final coalesced = <PlannedReminder>[];
  for (final reminder in planned) {
    final key = '${reminder.profileId}|${reminder.fireOn.iso}';
    if (seen.add(key)) coalesced.add(reminder);
  }
  final kept = coalesced.take(kMaxPendingReminders).toList(growable: false);
  kept.sort(_byFireOrder);
  return kept;
}
