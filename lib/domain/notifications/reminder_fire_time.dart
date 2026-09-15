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
