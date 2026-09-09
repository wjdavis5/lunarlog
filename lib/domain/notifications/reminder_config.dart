/// Per-type, per-profile local reminder configuration (Issue #136, R10/R11).
///
/// Pure Dart (R14/R16) with no Flutter and no Supabase types crossing this
/// boundary. This is the *device holder's own* local reminder configuration
/// — the caregiver alert path (`lib/domain/notifications/
/// notification_preferences.dart`, Issue #5) is a different, server-backed
/// model and is deliberately left untouched; the one piece reused from it
/// is [QuietHours] itself, so "quiet hours" means exactly one thing in the
/// app.
///
/// Persistence posture (Issue #136, "decide deliberately"): reminder
/// configs are **device-local by design**, stored through the
/// device-local `SettingsStore` (`ReminderConfigService`) and never synced.
/// They are scheduling preferences about *this device's* nagging, not
/// health data; syncing them would put them under the sync conflict
/// machinery for no data-loss benefit. This is the same deliberate call
/// the cycle-omission list made (also device-local, also noted as a
/// tension with the sync-first direction). Revisit only if a user actually
/// wants their reminder schedule to follow them across devices.
library;

import 'dart:convert';

import '../models/local_date.dart';
import '../models/profile_mode.dart';
import 'notification_preferences.dart' show QuietHours;
import 'reminder_presets.dart';

/// Days before the estimate the "upcoming period" (period-due) reminder
/// fires by default. The pre-#136 hardcoded offset (`scheduling.dart`'s
/// `kUpcomingReminderOffsetDays`) becomes this config default — the value
/// the app has always used, now adjustable.
const int kUpcomingDefaultLeadDays = 2;

/// Days before the estimate the PMS-watch reminder fires by default.
/// Longer than the period-due lead by construction: PMS-watch exists to
/// give earlier notice than the due reminder, not to duplicate it.
const int kPmsDefaultLeadDays = 4;

/// The default fire time-of-day for every reminder type, in minutes since
/// local midnight: 09:00 — the pre-#136 hardcoded hour
/// (`notification_scheduler.dart`'s `hour = 9`), now adjustable per type.
const int kDefaultReminderTimeMinutes = 9 * 60;

/// How many days ahead the daily log nudge is pre-armed at every replan
/// (mirrors `scheduling.dart`'s `kLatePreArmDays` posture: iOS delivers
/// local notifications with no Dart callback, so each replan arms a
/// bounded window rather than relying on a same-day re-arm).
const int kLogNudgePreArmDays = 7;

/// How many days the "Not yet" notification action suppresses a profile's
/// late reminders (Issue #136).
const int kNotYetSnoozeDays = 3;

/// Inclusive bounds for a configured lead-days value.
const int kMinLeadDays = 0;
const int kMaxLeadDays = 7;

/// Inclusive bounds for a configured time-of-day (minutes since local
/// midnight). The upper bound is 23:59, not 1439 == 24:00.
const int kMinTimeOfDayMinutes = 0;
const int kMaxTimeOfDayMinutes = 23 * 60 + 59;

int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

/// One reminder type's configuration: whether it is on, when it fires
/// (minutes since local midnight), and — for the estimate-relative types —
/// how many days before the estimate.
class ReminderTypeConfig {
  const ReminderTypeConfig({
    required this.enabled,
    this.leadDays,
    required this.timeOfDayMinutes,
  });

  /// The defaults for the types that are on out of the box (the pre-#136
  /// behavior: upcoming at estimate − 2 days and the late window, both at
  /// 9 AM). PMS-watch and the log nudge ship off.
  static const ReminderTypeConfig upcoming = ReminderTypeConfig(
    enabled: true,
    leadDays: kUpcomingDefaultLeadDays,
    timeOfDayMinutes: kDefaultReminderTimeMinutes,
  );
  static const ReminderTypeConfig pms = ReminderTypeConfig(
    enabled: false,
    leadDays: kPmsDefaultLeadDays,
    timeOfDayMinutes: kDefaultReminderTimeMinutes,
  );
  static const ReminderTypeConfig late = ReminderTypeConfig(
    enabled: true,
    timeOfDayMinutes: kDefaultReminderTimeMinutes,
  );
  static const ReminderTypeConfig log = ReminderTypeConfig(
    enabled: false,
    timeOfDayMinutes: kDefaultReminderTimeMinutes,
  );

  final bool enabled;

  /// Days before the predicted start this reminder fires. Only the
  /// estimate-relative types (upcoming, PMS-watch) carry one; the late
  /// window and the daily log nudge have no estimate anchor, so this is
  /// null (and ignored) for them.
  final int? leadDays;

  /// Fire time-of-day, minutes since local midnight (0-1439).
  final int timeOfDayMinutes;

  ReminderTypeConfig copyWith({
    bool? enabled,
    int? leadDays,
    int? timeOfDayMinutes,
  }) =>
      ReminderTypeConfig(
        enabled: enabled ?? this.enabled,
        leadDays: leadDays ?? this.leadDays,
        timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
      );

  /// The lead days the planner should use: this config's value for the
  /// estimate-relative types, or [fallback] when unset (the late window
  /// and the log nudge have no estimate anchor).
  int effectiveLeadDays(int fallback) => leadDays ?? fallback;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        if (leadDays != null) 'leadDays': leadDays,
        'timeOfDay': timeOfDayMinutes,
      };

  /// Tolerant decode: a malformed or out-of-range stored value falls back
  /// to the matching type default field-by-field rather than throwing —
  /// a hand-edited or partially-written store must never take reminders
  /// down.
  static ReminderTypeConfig fromJson(
    Map<String, Object?> json,
    ReminderTypeConfig defaults,
  ) =>
      ReminderTypeConfig(
        enabled: json['enabled'] is bool
            ? json['enabled'] as bool
            : defaults.enabled,
        leadDays: json['leadDays'] is int
            ? _clampInt(
                json['leadDays'] as int, kMinLeadDays, kMaxLeadDays)
            : defaults.leadDays,
        timeOfDayMinutes: json['timeOfDay'] is int
            ? _clampInt(json['timeOfDay'] as int, kMinTimeOfDayMinutes,
                kMaxTimeOfDayMinutes)
            : defaults.timeOfDayMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderTypeConfig &&
      other.enabled == enabled &&
      other.leadDays == leadDays &&
      other.timeOfDayMinutes == timeOfDayMinutes;

  @override
  int get hashCode => Object.hash(enabled, leadDays, timeOfDayMinutes);

  @override
  String toString() =>
      'ReminderTypeConfig(enabled: $enabled, leadDays: $leadDays, '
      'timeOfDayMinutes: $timeOfDayMinutes)';
}

/// One profile's full local reminder configuration (Issue #136): the four
/// reminder types plus an optional daily quiet-hours window.
class ReminderConfig {
  const ReminderConfig({
    this.upcoming = ReminderTypeConfig.upcoming,
    this.pms = ReminderTypeConfig.pms,
    this.late = ReminderTypeConfig.late,
    this.log = ReminderTypeConfig.log,
    this.quietHours,
  });

  /// The configuration a profile carries when its operator has never
  /// opened the reminder settings: exactly the pre-#136 behavior, with
  /// which types are on derived from the profile's care-mode
  /// [ReminderPreset] (`reminderPresetFor`) — see [fromPreset].
  static const ReminderConfig standard = ReminderConfig();

  final ReminderTypeConfig upcoming;
  final ReminderTypeConfig pms;
  final ReminderTypeConfig late;
  final ReminderTypeConfig log;

  /// Local quiet hours: a fire that would land inside the window shifts to
  /// the window's end boundary instead of being dropped (R10; see
  /// [shiftQuietHours]). Null = no quiet hours.
  final QuietHours? quietHours;

  /// The defaults for [mode]: the preset decides which of the always-on
  /// types start enabled (the pre-#136 [ReminderPreset] behavior — e.g.
  /// `teen`/`irregular` ship with the late nudge off), and every other
  /// field takes the type's stock default. A profile with no stored
  /// config gets this, so a pre-#136 profile plans exactly as it always
  /// did.
  static ReminderConfig fromPreset(ReminderPreset preset) => ReminderConfig(
        upcoming: preset.upcoming
            ? ReminderTypeConfig.upcoming
            : ReminderTypeConfig.upcoming.copyWith(enabled: false),
        pms: ReminderTypeConfig.pms,
        late: preset.late
            ? ReminderTypeConfig.late
            : ReminderTypeConfig.late.copyWith(enabled: false),
        log: ReminderTypeConfig.log,
      );

  /// The defaults for a profile of [mode].
  static ReminderConfig fromMode(ProfileMode mode) =>
      fromPreset(reminderPresetFor(mode));

  ReminderConfig copyWith({
    ReminderTypeConfig? upcoming,
    ReminderTypeConfig? pms,
    ReminderTypeConfig? late,
    ReminderTypeConfig? log,
    QuietHours? quietHours,
    bool clearQuietHours = false,
  }) =>
      ReminderConfig(
        upcoming: upcoming ?? this.upcoming,
        pms: pms ?? this.pms,
        late: late ?? this.late,
        log: log ?? this.log,
        quietHours: clearQuietHours ? null : (quietHours ?? this.quietHours),
      );

  /// The type config for [kind]. Exhaustive switch (no `_` wildcard):
  /// adding a kind without a config mapping is a compile error.
  ReminderTypeConfig typeConfig(ReminderKind kind) => switch (kind) {
        ReminderKind.upcoming => upcoming,
        ReminderKind.pms => pms,
        ReminderKind.late => late,
        ReminderKind.log => log,
      };

  ReminderConfig withTypeConfig(ReminderKind kind, ReminderTypeConfig c) =>
      switch (kind) {
        ReminderKind.upcoming => copyWith(upcoming: c),
        ReminderKind.pms => copyWith(pms: c),
        ReminderKind.late => copyWith(late: c),
        ReminderKind.log => copyWith(log: c),
      };

  Map<String, Object?> toJson() => {
        'upcoming': upcoming.toJson(),
        'pms': pms.toJson(),
        'late': late.toJson(),
        'log': log.toJson(),
        if (quietHours != null) ...{
          'quietStart': quietHours!.startMinutes,
          'quietEnd': quietHours!.endMinutes,
        },
      };

  /// Tolerant decode from [ReminderTypeConfig.fromJson]'s fallbacks: any
  /// malformed field degrades to that type's stock default rather than
  /// throwing or silently disabling reminders.
  static ReminderConfig fromJson(Map<String, Object?> json) {
    Map<String, Object?> section(String key, ReminderTypeConfig defaults) =>
        json[key] is Map<String, Object?>
            ? json[key] as Map<String, Object?>
            : const {};
    final quietStart = json['quietStart'];
    final quietEnd = json['quietEnd'];
    return ReminderConfig(
      upcoming: ReminderTypeConfig.fromJson(
          section('upcoming', ReminderTypeConfig.upcoming),
          ReminderTypeConfig.upcoming),
      pms: ReminderTypeConfig.fromJson(
          section('pms', ReminderTypeConfig.pms), ReminderTypeConfig.pms),
      late: ReminderTypeConfig.fromJson(
          section('late', ReminderTypeConfig.late), ReminderTypeConfig.late),
      log: ReminderTypeConfig.fromJson(
          section('log', ReminderTypeConfig.log), ReminderTypeConfig.log),
      quietHours: quietStart is int && quietEnd is int
          ? QuietHours(startMinutes: quietStart, endMinutes: quietEnd)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderConfig &&
      other.upcoming == upcoming &&
      other.pms == pms &&
      other.late == late &&
      other.log == log &&
      other.quietHours == quietHours;

  @override
  int get hashCode => Object.hash(upcoming, pms, late, log, quietHours);

  @override
  String toString() =>
      'ReminderConfig(upcoming: $upcoming, pms: $pms, late: $late, '
      'log: $log, quietHours: $quietHours)';
}

/// The reminder kinds (Issue #136), canonical here so both the
/// configuration and the planner (`scheduling.dart`, which re-exports this
/// name for its existing callers) share one closed set:
///
/// * [upcoming] — the period-due reminder, estimate − leadDays.
/// * [pms] — the PMS-watch reminder, estimate − (longer) leadDays.
/// * [late] — the pre-armed daily window once the cycle runs late.
/// * [log] — the daily log nudge, prediction-independent.
enum ReminderKind { upcoming, pms, late, log }

/// Encodes a [ReminderConfig] map as the JSON string the settings store
/// keeps — the same document shape [decodeReminderConfigs] parses.
String encodeReminderConfigs(Map<String, ReminderConfig> configs) =>
    jsonEncode({
      'v': 1,
      'profiles': {
        for (final entry in configs.entries)
          entry.key: entry.value.toJson(),
      },
    });

/// Decodes a stored `reminder_configs` value. Anything malformed — not a
/// map, an unparseable string, a profile section that isn't a map — yields
/// an empty map (the profile then falls back to its preset defaults) rather
/// than throwing: a bad store value must never take reminders down.
Map<String, ReminderConfig> decodeReminderConfigs(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  final profiles = decoded['profiles'];
  if (profiles is! Map<String, Object?>) return const {};
  return {
    for (final entry in profiles.entries)
      if (entry.value is Map<String, Object?>)
        entry.key: ReminderConfig.fromJson(entry.value as Map<String, Object?>),
  };
}

/// Encodes the per-profile late-snooze map (`profileId -> last snoozed-on
/// ISO date`) as the JSON string the settings store keeps.
String encodeLateSnoozes(Map<String, LocalDate> snoozes) => jsonEncode({
      'v': 1,
      'snoozes': {
        for (final entry in snoozes.entries) entry.key: entry.value.iso,
      },
    });

/// Decodes a stored late-snooze value; malformed dates and malformed
/// payloads degrade to "not snoozed" (empty map).
Map<String, LocalDate> decodeLateSnoozes(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  final snoozes = decoded['snoozes'];
  if (snoozes is! Map<String, Object?>) return const {};
  return {
    for (final entry in snoozes.entries)
      if (entry.value is String && _isIsoDate(entry.value as String))
        entry.key: LocalDate.fromIso(entry.value as String),
  };
}

bool _isIsoDate(String value) {
  if (value.length != 10) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}

/// A fire at ([fireOn], [minuteOfDay]) that lands inside a quiet-hours
/// window shifts to the window's end boundary instead of being dropped
/// (R10) — [QuietHours.contains] decides membership, exactly as the
/// caregiver path's quiet hours do. A window that wraps past midnight
/// (e.g. 22:00-07:00) shifts an evening fire to the *next day's* boundary;
/// an early-morning fire already inside the window's tail shifts to the
/// same day's boundary.
({LocalDate date, int minuteOfDay}) shiftQuietHours(
  LocalDate fireOn,
  int minuteOfDay,
  QuietHours? quietHours,
) {
  if (quietHours == null || !quietHours.contains(minuteOfDay)) {
    return (date: fireOn, minuteOfDay: minuteOfDay);
  }
  // Inside the window: the boundary is the window's end. For a
  // same-day window (start < end) that end is later today. For a
  // wrapping window (start > end) the end is tomorrow morning when the
  // fire sits in the evening side (>= start), and later this morning
  // when it sits in the post-midnight tail.
  final nextDay = quietHours.startMinutes > quietHours.endMinutes &&
      minuteOfDay >= quietHours.startMinutes;
  return (
    date: nextDay ? fireOn.addDays(1) : fireOn,
    minuteOfDay: quietHours.endMinutes,
  );
}
