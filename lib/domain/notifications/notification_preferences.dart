/// Caregiver alert preferences domain model (Issue #5, U6; R1-R4).
///
/// Pure Dart with no Flutter and no Supabase types crossing this boundary,
/// matching `lib/domain/models/profile_guardian.dart`'s shape.
library;

/// How many days of silence trigger a missed-entry check-in reminder, or
/// [off] to disable it entirely (R3, R4 - off is the default).
enum MissedEntryThreshold {
  off,
  oneDay,
  twoDays,
  threeDays;

  /// `null` for [off]; otherwise the day count `notification_preferences
  /// .missed_entry_days` stores.
  int? toDb() => switch (this) {
        off => null,
        oneDay => 1,
        twoDays => 2,
        threeDays => 3,
      };

  static MissedEntryThreshold fromDb(int? value) => switch (value) {
        null => off,
        1 => oneDay,
        2 => twoDays,
        3 => threeDays,
        _ => throw ArgumentError.value(
            value, 'value', 'unknown missed-entry threshold'),
      };
}

/// A daily quiet-hours window in the recipient's own local time
/// (KTD5). [startMinutes]/[endMinutes] are minutes since local midnight
/// (0-1439). A window where start equals end is treated as empty (no quiet
/// hours) by [contains].
class QuietHours {
  const QuietHours({required this.startMinutes, required this.endMinutes});

  final int startMinutes;
  final int endMinutes;

  bool get isEmpty => startMinutes == endMinutes;

  /// Whether [minutesSinceMidnight] falls inside this window, handling both
  /// a same-day window (start < end) and one that wraps past midnight
  /// (start > end, e.g. 22:00-07:00).
  bool contains(int minutesSinceMidnight) {
    if (isEmpty) return false;
    if (startMinutes < endMinutes) {
      return minutesSinceMidnight >= startMinutes &&
          minutesSinceMidnight < endMinutes;
    }
    return minutesSinceMidnight >= startMinutes ||
        minutesSinceMidnight < endMinutes;
  }

  /// Null-safe: a null [window] contains nothing.
  static bool containsIn(QuietHours? window, int minutesSinceMidnight) =>
      window?.contains(minutesSinceMidnight) ?? false;

  QuietHours copyWith({int? startMinutes, int? endMinutes}) => QuietHours(
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is QuietHours &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);

  @override
  String toString() => 'QuietHours($startMinutes-$endMinutes)';
}

/// One guardian's full alert configuration for one profile (R3). The
/// all-off default ([off]) is what a missing `notification_preferences` row
/// means (R4) - nothing is enqueued for a guardian who never configured
/// anything.
class CaregiverAlertPreferences {
  const CaregiverAlertPreferences({
    this.alertOnLog = false,
    this.alertOnCycleStartOnly = false,
    this.alertOnHighSeverity = false,
    this.missedEntryThreshold = MissedEntryThreshold.off,
    this.quietHours,
    this.timeZone,
  });

  /// The stored default for a profile with no preference row (R4).
  static const CaregiverAlertPreferences off = CaregiverAlertPreferences();

  final bool alertOnLog;
  final bool alertOnCycleStartOnly;
  final bool alertOnHighSeverity;
  final MissedEntryThreshold missedEntryThreshold;
  final QuietHours? quietHours;

  /// IANA zone name (e.g. `America/New_York`); null means quiet hours never
  /// resolve (KTD5).
  final String? timeZone;

  CaregiverAlertPreferences copyWith({
    bool? alertOnLog,
    bool? alertOnCycleStartOnly,
    bool? alertOnHighSeverity,
    MissedEntryThreshold? missedEntryThreshold,
    QuietHours? quietHours,
    bool clearQuietHours = false,
    String? timeZone,
    bool clearTimeZone = false,
  }) =>
      CaregiverAlertPreferences(
        alertOnLog: alertOnLog ?? this.alertOnLog,
        alertOnCycleStartOnly:
            alertOnCycleStartOnly ?? this.alertOnCycleStartOnly,
        alertOnHighSeverity: alertOnHighSeverity ?? this.alertOnHighSeverity,
        missedEntryThreshold: missedEntryThreshold ?? this.missedEntryThreshold,
        quietHours: clearQuietHours ? null : (quietHours ?? this.quietHours),
        timeZone: clearTimeZone ? null : (timeZone ?? this.timeZone),
      );

  @override
  bool operator ==(Object other) =>
      other is CaregiverAlertPreferences &&
      other.alertOnLog == alertOnLog &&
      other.alertOnCycleStartOnly == alertOnCycleStartOnly &&
      other.alertOnHighSeverity == alertOnHighSeverity &&
      other.missedEntryThreshold == missedEntryThreshold &&
      other.quietHours == quietHours &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(
        alertOnLog,
        alertOnCycleStartOnly,
        alertOnHighSeverity,
        missedEntryThreshold,
        quietHours,
        timeZone,
      );

  @override
  String toString() => 'CaregiverAlertPreferences(log: $alertOnLog, '
      'cycleStartOnly: $alertOnCycleStartOnly, '
      'highSeverity: $alertOnHighSeverity, '
      'missedEntry: $missedEntryThreshold, quietHours: $quietHours, '
      'timeZone: $timeZone)';
}
