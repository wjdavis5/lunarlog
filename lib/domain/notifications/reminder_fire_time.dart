/// Reminder fire-time computation (issue #215): the exact instant a planned
/// reminder must fire at, derived from its [PlannedReminder]-shaped inputs.
///
/// Extracted verbatim out of
/// `lib/data/notifications/notification_scheduler.dart` (the
/// flutter_local_notifications adapter, which is excluded from the
/// coverage/CRAP gates because the plugin cannot run under `flutter test`) —
/// the same treatment `buildFirebaseOptions()` got in
/// `firebase_push_token_source.dart`, except this function now lives in the
/// non-excluded domain layer, so its unit tests count toward the gates'
/// denominator instead of silently shrinking it.
library;

import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart' show PlannedReminder;
import 'package:timezone/timezone.dart' as tz;

/// Computes the exact [tz.TZDateTime] for a reminder on [fireOn] at
/// [minuteOfDay] (minutes since local midnight; default 09:00 — the
/// pre-#136 hardcoded hour) in the given [location].
tz.TZDateTime calculateReminderFireAt({
  required LocalDate fireOn,
  required tz.Location location,
  int minuteOfDay = kDefaultReminderTimeMinutes,
}) {
  return tz.TZDateTime(
    location,
    fireOn.year,
    fireOn.month,
    fireOn.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
  );
}

/// One planned reminder resolved against a specific instant (issue #171):
/// the exact [fireAt] it would fire at, and whether that instant has already
/// passed.
class ResolvedReminderFireTime {
  const ResolvedReminderFireTime({
    required this.reminder,
    required this.fireAt,
    required this.isPast,
  });

  final PlannedReminder reminder;

  /// The exact instant [reminder] would fire at, in the scheduling location.
  final tz.TZDateTime fireAt;

  /// Whether [fireAt] is at or before the instant this was resolved against.
  ///
  /// A past-dated local notification is never delivered — iOS's
  /// `UNCalendarNotificationTrigger` simply drops a trigger whose date has
  /// already passed — so arming one is a silent no-op that also consumes a
  /// day of the reminder's bounded pre-arm window.
  final bool isPast;

  @override
  String toString() => 'ResolvedReminderFireTime(${reminder.kind.name} '
      '@ $fireAt${isPast ? ', past' : ''})';
}

/// Resolves every reminder in [reminders] to the instant it would fire at
/// against [now], marking each already-past slot (issue #171).
///
/// The planner deliberately pre-arms forward windows that *start from today*
/// (`planReminders`), so a replan running after a type's configured fire
/// time-of-day still yields today's slot. Resolving here — where the real
/// clock is authoritative, after the plan was built — lets the scheduler
/// skip those slots in one place rather than handing a past [DateTime] to
/// `zonedSchedule`.
///
/// A recurring reminder is not lost by the skip: the planner's bounded
/// window already contains the next occurrence (tomorrow's late/log/pill
/// slot, or the next cadence date of an anchored kind), so it still fires at
/// its next slot. A single-occurrence kind (upcoming, period-starting-soon,
/// PMS-watch, fertile-window-soon, statistic-change) has no such sibling —
/// its slot is simply dropped, which is correct: the moment it described is
/// over.
///
/// [isPast] treats a slot exactly at [now] as already due (`!isAfter`), not
/// only strictly before it: a notification requested for the very instant it
/// is scheduled is already due and is not delivered.
List<ResolvedReminderFireTime> resolveReminderFireTimes({
  required Iterable<PlannedReminder> reminders,
  required tz.Location location,
  required tz.TZDateTime now,
}) {
  final resolved = <ResolvedReminderFireTime>[];
  for (final reminder in reminders) {
    final fireAt = calculateReminderFireAt(
      fireOn: reminder.fireOn,
      location: location,
      minuteOfDay: reminder.timeOfDayMinutes,
    );
    resolved.add(ResolvedReminderFireTime(
      reminder: reminder,
      fireAt: fireAt,
      isPast: !fireAt.isAfter(now),
    ));
  }
  return resolved;
}
