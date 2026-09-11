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
/// Issue #178 completes the Clue "Your Cycle" catalogue on the same
/// per-type model: `periodStartingSoon` (the same estimate anchor at a
/// longer lead than the due reminder), `fertileWindowSoon` (anchored to
/// the next still-ahead fertile window from #143's estimation), and
/// `cycleStatisticChange` (event-driven — plans only on the date the
/// coordinator observed a meaningful displayed-statistic change, see
/// `lib/domain/notifications/statistic_change.dart`). All three ship off.
///
/// Issue #183 completes the "Your Birth Control" catalogue the same way,
/// anchored on issue #260's recorded-method vocabulary instead of the
/// cycle estimate: `birthControlPill` (daily), `birthControlPatch`
/// (weekly), `birthControlRing` (every 28 days), and `birthControlShot`
/// (every 84 days) plan from the profile's `profile_modes` effective dates
/// — the due dates the method itself defines, at the type's configured
/// time-of-day. The implant and both IUD flavors have no kind: they are
/// not user-administered on a schedule, so no adherence reminder exists
/// for them (the issue's own cadence table). All four kinds ship off.
///
/// Transition-driven, not pre-computed (Issue #136): the coordinator
/// replans on every prediction emission (becoming active, becoming late,
/// any estimate shift — however small) and every app resume, and every
/// replan re-derives fire dates from the *live* estimate through
/// [planReminders]. There is no fixed pre-computed date to go stale: an
/// estimate that moves re-arms the plan around where the estimate now is.
library;

import 'dart:convert';

import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/birth_control_reminder_kind.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart'
    show QuietHours;
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

export 'package:lunarlog/domain/notifications/reminder_config.dart'
    show ReminderCadence, ReminderKind;

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

/// How many days ahead the daily pill adherence reminder (Issue #183) is
/// pre-armed at every replan — the same posture as the log nudge's
/// [kLogNudgePreArmDays]: iOS delivers local notifications with no Dart
/// callback, so each replan arms a bounded daily window.
const int kBirthControlPillPreArmDays = 7;

/// How many forward due dates the anchored birth-control kinds (Issue
/// #183: patch, ring, shot) are pre-armed with at every replan. Cadence
/// periods are long (7/28/84 days), so a single-occurrence arm would go
/// silent the first time the app stays closed past one due date; three
/// occurrences keep the reminder alive across skipped opens while staying
/// a small, bounded share of the [kMaxPendingReminders] cap.
const int kBirthControlPreArmOccurrences = 3;

/// How many forward occurrences the tracking reminder (log nudge, Issue
/// #463) pre-arms at non-daily cadences (weekly/fortnightly/monthly).
/// Daily keeps [kLogNudgePreArmDays] (7).
const int kLogNudgeCadencePreArmOccurrences = 4;

/// Generic content only (KTD7): these exact strings are what the lock
/// screen shows — never a profile name, date, or health detail.
const String kReminderTitle = 'A reminder from Lunarlog';
const String kReminderBody = 'Open Lunarlog to see what it is about.';

/// Eviction priority under the [kMaxPendingReminders] cap (Issue #136,
/// widened by Issue #178 and Issue #183): lower is kept longer. The
/// documented eviction order is late over upcoming over
/// period-starting-soon over PMS-watch over fertile-window-soon over
/// statistic-change over the birth-control cadences over the log nudge —
/// the daily nudge, the most reproducible of them all, is still the first
/// thing dropped when the cap binds, and the event-driven
/// statistic-change nudge ranks below the date-anchored kinds because its
/// signal can be re-observed (a later replan over the same change) while
/// a past date anchor cannot. The birth-control cadences rank below the
/// cycle kinds (a missed estimate is scarcer than a dose that recurs
/// tomorrow) but above the bare log nudge, whose content the dose
/// reminder would otherwise shadow on every shared fire date.
int evictionPriority(ReminderKind kind) => switch (kind) {
      ReminderKind.late => 0,
      ReminderKind.upcoming => 1,
      ReminderKind.periodStartingSoon => 2,
      ReminderKind.pms => 3,
      ReminderKind.fertileWindowSoon => 4,
      ReminderKind.cycleStatisticChange => 5,
      ReminderKind.birthControlPill ||
      ReminderKind.birthControlPatch ||
      ReminderKind.birthControlRing ||
      ReminderKind.birthControlShot =>
        6,
      ReminderKind.log => 7,
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
/// no partial signals — except the prediction-independent types (the daily
/// log nudge and, Issue #178, the event-driven statistic-change nudge),
/// which a profile with *no* estimate still gets when its config enables
/// them (a nudge is most valuable exactly when history is thin). Issue
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
/// [statisticChangeSignals] (Issue #178) carries, per profile, the date a
/// meaningful displayed-statistic change was observed by the coordinator
/// (`lib/domain/notifications/statistic_change.dart`). The
/// `cycleStatisticChange` kind plans a single reminder on that date when
/// enabled; a signal dated before [today] is stale and plans nothing.
///
/// [birthControlModes] (Issue #183) carries, per profile, the raw
/// `profile_modes` birth-control state ([BirthControlState]) the
/// coordinator last observed on its row stream. The birth-control kinds
/// plan only while the method in effect on [today] (via
/// [birthControlMethodInEffectOn]) matches the kind's cadence — pill/
/// patch/ring/shot — so a method change re-routes the reminder at the
/// next replan and nothing stale keeps firing for the old method. The
/// anchored kinds (patch/ring/shot) additionally need a recorded
/// `started_on` to anchor their due dates on; without one they plan
/// nothing rather than inventing an anchor. All birth-control kinds are
/// prediction-independent: a profile with no estimate still gets its
/// enabled adherence reminder.
///
/// Same-day duplicates coalesce per profile: after quiet-hours shifting,
/// at most one reminder per profile per fire date survives, the winner
/// decided by the eviction priority (late over upcoming over
/// period-starting-soon over PMS-watch over fertile-window-soon over
/// statistic-change over the birth-control cadences over log-nudge). The
/// result is sorted by fire date and capped at [kMaxPendingReminders],
/// evicting in the same priority order.
List<PlannedReminder> planReminders({
  required LocalDate today,
  required Map<String, ActivePrediction> predictions,
  Map<String, ReminderPreset> presets = const {},
  Map<String, ReminderConfig> configs = const {},
  Map<String, LocalDate> lateSnoozes = const {},
  Map<String, LocalDate> statisticChangeSignals = const {},
  Map<String, BirthControlState> birthControlModes = const {},
}) {
  final planned = <PlannedReminder>[];
  // The prediction-independent types plan even without a prediction (a
  // config entry can name a profile the prediction stream has nothing for
  // yet).
  final ids = {...predictions.keys, ...configs.keys, ...birthControlModes.keys};
  for (final id in ids) {
    final preset = presets[id] ?? ReminderPreset.all;
    final config = configs[id] ?? ReminderConfig.fromPreset(preset);
    planned.addAll(_planProfile(
      profileId: id,
      today: today,
      prediction: predictions[id],
      config: config,
      snoozeUntil: lateSnoozes[id],
      statisticSignal: statisticChangeSignals[id],
      birthControlState: birthControlModes[id],
    ));
  }
  return _coalesceAndCap(planned);
}

/// One profile's plan: the prediction-independent types (log nudge,
/// statistic-change signal, birth-control adherence — Issue #183), then —
/// when a live prediction exists — the estimate-relative types.
List<PlannedReminder> _planProfile({
  required String profileId,
  required LocalDate today,
  required ActivePrediction? prediction,
  required ReminderConfig config,
  required LocalDate? snoozeUntil,
  required LocalDate? statisticSignal,
  required BirthControlState? birthControlState,
}) {
  final planned = <PlannedReminder>[];
  if (config.log.enabled) {
    planned.addAll(_planLogNudge(
      profileId: profileId,
      today: today,
      config: config.log,
      quietHours: config.quietHours,
    ));
  }
  // Issue #178: the statistic-change reminder is event-driven — it plans
  // only on the date the coordinator observed a meaningful change, never
  // as a forward window. A stale (past) signal plans nothing.
  if (config.cycleStatisticChange.enabled &&
      statisticSignal != null &&
      !statisticSignal.isBefore(today)) {
    planned.add(_planOne(
      profileId,
      ReminderKind.cycleStatisticChange,
      statisticSignal,
      config.cycleStatisticChange.timeOfDayMinutes,
      config.quietHours,
    ));
  }
  // Issue #183: the method-cadence adherence kinds, anchored on the
  // profile's recorded birth-control method rather than on any estimate.
  planned.addAll(_planBirthControl(
    profileId: profileId,
    today: today,
    config: config,
    state: birthControlState,
  ));
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

/// Plans the tracking reminder (log nudge, Issue #463).
///
/// At [ReminderCadence.daily] (the default), pre-arms [kLogNudgePreArmDays]
/// consecutive days starting from [today], preserving legacy scheduling and IDs.
///
/// At non-daily cadences ([ReminderCadence.weekly], [ReminderCadence.fortnightly],
/// [ReminderCadence.monthly]), pre-arms [kLogNudgeCadencePreArmOccurrences]
/// future occurrences starting from [ReminderTypeConfig.anchorDate] (or
/// [today] if no anchor is set).
List<PlannedReminder> _planLogNudge({
  required String profileId,
  required LocalDate today,
  required ReminderTypeConfig config,
  required QuietHours? quietHours,
}) {
  final cadence = config.cadence;
  if (cadence == ReminderCadence.daily) {
    return [
      for (var i = 0; i < kLogNudgePreArmDays; i++)
        _planOne(
          profileId,
          ReminderKind.log,
          today.addDays(i),
          config.timeOfDayMinutes,
          quietHours,
        ),
    ];
  }

  final anchor = config.anchorDate ?? today;
  final planned = <PlannedReminder>[];

  if (cadence == ReminderCadence.weekly ||
      cadence == ReminderCadence.fortnightly) {
    final intervalDays = cadence == ReminderCadence.weekly ? 7 : 14;
    final offsetDays = today.difference(anchor);
    final k =
        offsetDays <= 0 ? 0 : (offsetDays + intervalDays - 1) ~/ intervalDays;
    for (var i = 0; i < kLogNudgeCadencePreArmOccurrences; i++) {
      planned.add(_planOne(
        profileId,
        ReminderKind.log,
        anchor.addDays((k + i) * intervalDays),
        config.timeOfDayMinutes,
        quietHours,
      ));
    }
  } else if (cadence == ReminderCadence.monthly) {
    final monthsDiff =
        (today.year - anchor.year) * 12 + (today.month - anchor.month);
    final candidate = anchor.addMonths(monthsDiff);
    final startOffset =
        candidate.isBefore(today) ? monthsDiff + 1 : monthsDiff;
    for (var i = 0; i < kLogNudgeCadencePreArmOccurrences; i++) {
      planned.add(_planOne(
        profileId,
        ReminderKind.log,
        anchor.addMonths(startOffset + i),
        config.timeOfDayMinutes,
        quietHours,
      ));
    }
  }

  return planned;
}

/// The birth-control adherence kinds (Issue #183). A profile plans a kind
/// only while the method in effect matches it; the pill pre-arms a daily
/// window and the other three anchor their due dates on the method's
/// recorded start date (start day + n × cadence, n ≥ 1 — the start day
/// itself is the day the operator acted, not a change day).
List<PlannedReminder> _planBirthControl({
  required String profileId,
  required LocalDate today,
  required ReminderConfig config,
  required BirthControlState? state,
}) {
  final method = _birthControlMethodInEffect(state, today);
  if (method == null) return const [];
  final kind = birthControlReminderKindFor(method);
  if (kind == null) return const [];
  final typeConfig = config.typeConfig(kind);
  if (!typeConfig.enabled) return const [];
  final cadenceDays = birthControlCadenceDays(method)!;
  final startedOn = _tryParseIso(state!.startedOn);
  if (kind == ReminderKind.birthControlPill) {
    // The pill needs no anchor: while the method is in effect every day
    // is a dose day, so the reminder pre-arms the same bounded daily
    // window the log nudge does (a method recorded as started today is in
    // effect from today — `birthControlMethodInEffectOn` guarantees
    // startedOn ≤ today here).
    return [
      for (var i = 0; i < kBirthControlPillPreArmDays; i++)
        _planOne(
          profileId,
          kind,
          today.addDays(i),
          typeConfig.timeOfDayMinutes,
          config.quietHours,
        ),
    ];
  }
  if (startedOn == null) {
    // A cadence without a recorded start date has no knowable due date —
    // plan nothing rather than inventing an anchor (the settings row says
    // what is missing).
    return const [];
  }
  final offsetDays = today.difference(startedOn);
  // Smallest n ≥ 1 whose due date (startedOn + n × cadence) is today or
  // later: ceil(offsetDays / cadence), floored at 1. A due date already
  // past is not re-fired retroactively.
  var firstN = (offsetDays + cadenceDays - 1) ~/ cadenceDays;
  if (firstN < 1) firstN = 1;
  return [
    for (var i = 0; i < kBirthControlPreArmOccurrences; i++)
      _planOne(
        profileId,
        kind,
        startedOn.addDays((firstN + i) * cadenceDays),
        typeConfig.timeOfDayMinutes,
        config.quietHours,
      ),
  ];
}

/// Resolves the method in effect on [today] from a raw state, failing
/// closed: a malformed effective date (storage validates ISO shape, but a
/// hand-edited or future-schema value must never take reminder planning
/// down) degrades to "no method in effect".
BirthControlMethod? _birthControlMethodInEffect(
  BirthControlState? state,
  LocalDate today,
) {
  if (state == null) return null;
  try {
    return birthControlMethodInEffectOn(
      storedMethod: state.method,
      startedOn: state.startedOn,
      stoppedOn: state.stoppedOn,
      date: today,
    );
  } on ArgumentError {
    return null;
  }
}

/// Tolerant `yyyy-MM-dd` parse: null (or a malformed value) degrades to
/// null instead of throwing — see [_birthControlMethodInEffect].
LocalDate? _tryParseIso(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return LocalDate.fromIso(raw);
  } on ArgumentError {
    return null;
  }
}

/// The cadence in days between due dates for [method]'s adherence kind
/// (Issue #183's table: pill daily, patch weekly, ring monthly — the
/// 28-day ring cycle — and injection every 12 weeks = 84 days), or null
/// for the methods with no kind.
int? birthControlCadenceDays(BirthControlMethod method) => switch (method) {
      BirthControlMethod.pill => 1,
      BirthControlMethod.patch => 7,
      BirthControlMethod.ring => 28,
      BirthControlMethod.shot => 84,
      BirthControlMethod.none ||
      BirthControlMethod.implant ||
      BirthControlMethod.hormonalIud ||
      BirthControlMethod.copperIud ||
      BirthControlMethod.condom ||
      BirthControlMethod.other ||
      BirthControlMethod.unknown =>
        null,
    };

/// The prediction-anchored types: period-due, period-starting-soon,
/// PMS-watch, and fertile-window-soon fire only when their configured
/// moment is still in the future; the late window pre-arms a bounded daily
/// run starting today.
List<PlannedReminder> _planEstimateRelative({
  required String profileId,
  required LocalDate today,
  required ActivePrediction prediction,
  required ReminderConfig config,
  required bool snoozed,
}) {
  final planned = _planEstimateAnchored(
    profileId: profileId,
    today: today,
    prediction: prediction,
    config: config,
  );
  planned.addAll(_planFertileWindowSoon(
    profileId: profileId,
    today: today,
    prediction: prediction,
    config: config,
  ));
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

/// The estimate-anchored kinds (Issue #136's upcoming and PMS-watch plus
/// Issue #178's period-starting-soon): each fires at
/// `estimatedNextStart − leadDays` when enabled and still ahead of
/// [today]. Period-starting-soon anchors on the same estimate at its own,
/// longer lead — a separate reminder, not a second lead time of the due
/// one (Clue ships the two as independently configurable reminders).
List<PlannedReminder> _planEstimateAnchored({
  required String profileId,
  required LocalDate today,
  required ActivePrediction prediction,
  required ReminderConfig config,
}) {
  final planned = <PlannedReminder>[];
  final estimate = prediction.estimatedNextStart;
  final anchored = <(ReminderKind, ReminderTypeConfig, int)>[
    (
      ReminderKind.upcoming,
      config.upcoming,
      config.upcoming.effectiveLeadDays(kUpcomingDefaultLeadDays)
    ),
    (
      ReminderKind.periodStartingSoon,
      config.periodStartingSoon,
      config.periodStartingSoon
          .effectiveLeadDays(kPeriodStartingSoonDefaultLeadDays)
    ),
    (
      ReminderKind.pms,
      config.pms,
      config.pms.effectiveLeadDays(kPmsDefaultLeadDays)
    ),
  ];
  for (final (kind, typeConfig, leadDays) in anchored) {
    final fireOn = estimate.addDays(-leadDays);
    if (typeConfig.enabled && fireOn.compareTo(today) > 0) {
      planned.add(_planOne(
        profileId,
        kind,
        fireOn,
        typeConfig.timeOfDayMinutes,
        config.quietHours,
      ));
    }
  }
  return planned;
}

/// Issue #178 (Clue item 4): anchored to the next *still-ahead* fertile
/// window, derived by #143's own `fertileWindowFor` over the forecast —
/// never a second window formula here. The first forecast cycle whose
/// soon-moment is future wins; a window already started (or wholly past,
/// like `estimateFertileWindow`'s next-cycle window by mid-cycle) plans
/// nothing. No window ahead of the lead ⇒ no reminder: the kind cannot
/// fire against absent data.
List<PlannedReminder> _planFertileWindowSoon({
  required String profileId,
  required LocalDate today,
  required ActivePrediction prediction,
  required ReminderConfig config,
}) {
  final typeConfig = config.fertileWindowSoon;
  if (!typeConfig.enabled) return const [];
  final fertileLead =
      typeConfig.effectiveLeadDays(kFertileWindowSoonDefaultLeadDays);
  for (final cycle in prediction.forecast) {
    final window = fertileWindowFor(
      start: cycle.start,
      tier: cycle.tier,
    );
    final fireOn = window.windowStart.addDays(-fertileLead);
    if (fireOn.compareTo(today) > 0) {
      return [
        _planOne(
          profileId,
          ReminderKind.fertileWindowSoon,
          fireOn,
          typeConfig.timeOfDayMinutes,
          config.quietHours,
        ),
      ];
    }
  }
  return const [];
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
