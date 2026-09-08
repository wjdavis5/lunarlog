/// Caregiver alert preferences domain model (Issue #5, U6; R1-R4).
///
/// Pure Dart with no Flutter and no Supabase types crossing this boundary,
/// matching `lib/domain/models/profile_guardian.dart`'s shape.
library;

/// How a guardian wants one alert type delivered (Issue #125):
/// [immediate] (the pre-#125 behaviour), [dailyDigest] (held for one push
/// per day at [CaregiverAlertPreferences.digestTimeMinutes]), or [off].
enum AlertCadence {
  immediate,
  dailyDigest,
  off;

  /// The string `notification_preferences.<kind>_cadence` stores.
  String toDb() => switch (this) {
        immediate => 'immediate',
        dailyDigest => 'daily_digest',
        off => 'off',
      };

  /// Maps a stored cadence back; `null` (a pre-#125 row, or a projection
  /// that predates the columns) is [immediate], preserving that row's
  /// existing behaviour exactly.
  static AlertCadence fromDb(String? value) => switch (value) {
        null => immediate,
        'immediate' => immediate,
        'daily_digest' => dailyDigest,
        'off' => off,
        _ => throw ArgumentError.value(value, 'value', 'unknown alert cadence'),
      };

  String get label => switch (this) {
        immediate => 'Immediately',
        dailyDigest => 'Daily digest',
        off => 'Off',
      };
}

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
    this.logCadence = AlertCadence.immediate,
    this.cycleStartCadence = AlertCadence.immediate,
    this.highSeverityCadence = AlertCadence.immediate,
    this.digestTimeMinutes,
    this.missedEntryThreshold = MissedEntryThreshold.off,
    this.quietHours,
    this.timeZone,
  });

  /// The stored default for a profile with no preference row (R4).
  static const CaregiverAlertPreferences off = CaregiverAlertPreferences();

  final bool alertOnLog;
  final bool alertOnCycleStartOnly;
  final bool alertOnHighSeverity;

  /// Per-kind delivery cadence (Issue #125). Each defaults to
  /// [AlertCadence.immediate] so a guardian who never touches the cadence
  /// settings keeps the pre-#125 behaviour, and so [off]'s all-off default
  /// stays the default. Cadence is the guardian's own choice - two
  /// guardians on the same profile can differ.
  final AlertCadence logCadence;
  final AlertCadence cycleStartCadence;
  final AlertCadence highSeverityCadence;

  /// The chosen local time for the daily digest, in minutes since local
  /// midnight (0-1439). Null falls back to the server-side default of
  /// 08:00 local. Also governs when daily-ceiling overflow is delivered:
  /// an all-immediate guardian's excess events roll into a digest at this
  /// time too (Issue #125).
  final int? digestTimeMinutes;

  final MissedEntryThreshold missedEntryThreshold;
  final QuietHours? quietHours;

  /// IANA zone name (e.g. `America/New_York`); null means quiet hours never
  /// resolve (KTD5).
  final String? timeZone;

  /// Structural identity for [==]/[hashCode]: records compare by value, so
  /// equality stays one branch however many fields this class gains.
  (bool, bool, bool, AlertCadence, AlertCadence, AlertCadence, int?,
          MissedEntryThreshold, QuietHours?, String?)
      get _identity => (
            alertOnLog,
            alertOnCycleStartOnly,
            alertOnHighSeverity,
            logCadence,
            cycleStartCadence,
            highSeverityCadence,
            digestTimeMinutes,
            missedEntryThreshold,
            quietHours,
            timeZone,
          );

  /// `clear` (the copyWith `clearX` flags win) > `next` > `current`, for
  /// the nullable fields.
  static T? _pick<T>(T? current, T? next, bool clear) =>
      clear ? null : (next ?? current);

  CaregiverAlertPreferences copyWith({
    bool? alertOnLog,
    bool? alertOnCycleStartOnly,
    bool? alertOnHighSeverity,
    AlertCadence? logCadence,
    AlertCadence? cycleStartCadence,
    AlertCadence? highSeverityCadence,
    int? digestTimeMinutes,
    bool clearDigestTime = false,
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
        logCadence: logCadence ?? this.logCadence,
        cycleStartCadence: cycleStartCadence ?? this.cycleStartCadence,
        highSeverityCadence: highSeverityCadence ?? this.highSeverityCadence,
        digestTimeMinutes:
            _pick(this.digestTimeMinutes, digestTimeMinutes, clearDigestTime),
        missedEntryThreshold: missedEntryThreshold ?? this.missedEntryThreshold,
        quietHours: _pick(this.quietHours, quietHours, clearQuietHours),
        timeZone: _pick(this.timeZone, timeZone, clearTimeZone),
      );

  @override
  bool operator ==(Object other) =>
      other is CaregiverAlertPreferences && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  @override
  String toString() => 'CaregiverAlertPreferences(log: $alertOnLog, '
      'cycleStartOnly: $alertOnCycleStartOnly, '
      'highSeverity: $alertOnHighSeverity, '
      'logCadence: $logCadence, cycleStartCadence: $cycleStartCadence, '
      'highSeverityCadence: $highSeverityCadence, '
      'digestTime: $digestTimeMinutes, '
      'missedEntry: $missedEntryThreshold, quietHours: $quietHours, '
      'timeZone: $timeZone)';
}
