/// Reminder planning (KTD7, R12): pure, testable core that decides WHICH
/// local notifications should be pending, from each active profile's live
/// prediction.
///
/// Posture (settled): near-term only — an "upcoming" reminder two days
/// before an estimate, and "late" reminders pre-armed daily for a bounded
/// window (iOS delivers local notifications with no Dart callback, so a
/// same-day re-arm loop cannot be relied on; each reschedule arms the next
/// [kLatePreArmDays] days ahead). Every body/title is generic — no profile
/// names, no dates (lock-screen privacy).
library;

import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

/// Days before the estimate the "upcoming period" reminder fires.
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

enum ReminderKind { upcoming, late }

class PlannedReminder {
  const PlannedReminder({
    required this.profileId,
    required this.fireOn,
    required this.kind,
  });

  final String profileId;
  final LocalDate fireOn;
  final ReminderKind kind;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.profileId == profileId &&
      other.fireOn == fireOn &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(profileId, fireOn, kind);
}

/// Plans reminders from the active profiles' [ActivePrediction]s, filtered
/// by each profile's care-mode [ReminderPreset] (Issue #131, R12).
///
/// Profiles without a live estimate ([NotEnoughHistory]) produce nothing —
/// no partial signals. Issue #221/A2-12 folded the old "paused past sixty
/// days" dead end into [ActivePrediction] itself (flagged
/// [ActivePrediction.unusuallyLongCycle]), so that state now plans
/// reminders exactly like any other active estimate — never go silent. A
/// profile with no entry in [presets] gets [ReminderPreset.all], so callers
/// that carry no mode information (and the pre-#131 tests) keep the exact
/// plan they always produced. The result is sorted by fire date and capped
/// at [kMaxPendingReminders].
List<PlannedReminder> planReminders({
  required LocalDate today,
  required Map<String, ActivePrediction> predictions,
  Map<String, ReminderPreset> presets = const {},
}) {
  final planned = <PlannedReminder>[];
  for (final entry in predictions.entries) {
    final prediction = entry.value;
    final preset = presets[entry.key] ?? ReminderPreset.all;
    // Upcoming: estimate − 2 days, only if still in the future.
    final upcomingOn =
        prediction.estimatedNextStart.addDays(-kUpcomingReminderOffsetDays);
    if (preset.upcoming && upcomingOn.difference(today) > 0) {
      planned.add(PlannedReminder(
        profileId: entry.key,
        fireOn: upcomingOn,
        kind: ReminderKind.upcoming,
      ));
    }
    // Late: pre-arm a bounded daily window starting today.
    if (preset.late && prediction.isLate) {
      for (var i = 0; i < kLatePreArmDays; i++) {
        planned.add(PlannedReminder(
          profileId: entry.key,
          fireOn: today.addDays(i),
          kind: ReminderKind.late,
        ));
      }
    }
  }
  planned.sort((a, b) => a.fireOn.compareTo(b.fireOn));
  return planned.take(kMaxPendingReminders).toList(growable: false);
}
