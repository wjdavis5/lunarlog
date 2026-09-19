/// Device-local key-value settings (interface). Backs later units'
/// last-active profile, relock toggle and web-modal acknowledgment; small
/// by design — values are plain strings.
library;

abstract interface class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);

  /// Emits the current value (null when unset) and again on every change.
  Stream<String?> watch(String key);
}

/// Settled setting key names.
abstract final class SettingsKeys {
  static const String lastActiveProfile = 'last_active_profile';
  static const String relockEnabled = 'relock_enabled';

  /// The operator-selected foreground inactivity relock timeout (issue
  /// #762): a stringified whole-minute count, one of `'2'`, `'15'`, or
  /// `'60'` (see `relockTimeoutFromStored`/`storedRelockTimeout` in
  /// `lib/gate_controller.dart`, the single codec for this key). Absent —
  /// or any unrecognized value, so a future value can never wedge the
  /// gate — reads as 1 hour, the issue's default posture. Device-local by
  /// design, the same display-preference posture as [relockEnabled].
  static const String relockTimeout = 'relock_timeout';

  /// How many consecutive times the Android OS has refused
  /// `POST_NOTIFICATIONS` — the automatic ask in `initialize()` plus every
  /// "Turn on reminders" tap (Issue #168). Persisted so a permanently-
  /// denied user's next launch remembers the count instead of restarting
  /// it at zero, which used to make the very first post-restart tap a
  /// silent re-ask (the OS no longer shows a dialog past two refusals, so
  /// that tap did nothing) instead of opening notification settings. A
  /// stringified non-negative int; absent (or unparsable) reads as `0`.
  static const String androidNotificationDeniedAttempts =
      'android_notification_denied_attempts';

  /// `'true'` once the operator has made an explicit "Turn on reminders" ask
  /// on Darwin (issue #863). Darwin's own notification dialog is one-shot
  /// per install: once the OS has recorded a decision, a repeat
  /// `requestPermissions()` silently no-ops. The scheduler uses this flag to
  /// tell "never asked yet — show the prompt" apart from "already decided —
  /// open notification settings instead", which `checkPermissions()` alone
  /// cannot (a not-yet-asked permission and a denied one both read as
  /// disabled). Device-local; absent reads as never asked.
  static const String darwinNotificationPermissionRequested =
      'darwin_notification_permission_requested';
  static const String webModalAcknowledged = 'web_modal_acknowledged';
  static const String firstRunNoticeShown = 'first_run_notice_shown';

  /// Whether the user has acknowledged the minimum-age statement (13+ policy,
  /// Issue #269). Recorded locally so it is not re-prompted every launch.
  static const String minimumAgeAcknowledged = 'minimum_age_acknowledged';

  /// Email of a sign-up whose confirmation link has not been opened on
  /// this device yet (AS10). Device-local; cleared (set to the empty
  /// string) once a signed-in session arrives.
  static const String awaitingConfirmationEmail =
      'awaiting_confirmation_email';

  /// Email that asked for a passwordless sign-in link whose link or code
  /// has not produced a session on this device yet (#2 U4; KTD3). Same
  /// lifecycle as [awaitingConfirmationEmail]: device-local; cleared (set
  /// to the empty string) once a signed-in session arrives.
  static const String awaitingMagicLinkEmail = 'awaiting_magic_link_email';

  /// ISO-8601 timestamp of the newest feedback reply the operator has seen
  /// in Support history (Issue #6, U8). The Settings history tile compares
  /// this against the newest reply it can see and shows an unread badge
  /// when that reply is newer.
  static const String feedbackLastSeenAt = 'feedback_last_seen_at';

  /// This install's stable push-registration device id (Issue #5, U7; R19).
  /// Generated once and persisted so a token refresh upserts the same
  /// `push_devices` row instead of creating a new one.
  static const String pushDeviceId = 'push_device_id';

  /// The single profile id this device's OS health store (HealthKit/Health
  /// Connect) may ever be written for (Issue #153). Device-local; defaults
  /// to unset (health sync off for every profile) until the operator picks
  /// one deliberately in Settings — never inferred or defaulted to the
  /// first profile. At most one value at a time by construction (this is a
  /// single key, not a set); `HealthSyncBinding`
  /// (`lib/domain/health/health_sync_binding.dart`) is the only writer.
  /// Cleared (set to the empty string) by `unbind()`, matching
  /// [awaitingConfirmationEmail]'s empty-string-means-cleared convention.
  static const String healthStoreProfileId = 'health_store_profile_id';

  /// The health-sync forward-only cursor (Issue #193): epoch milliseconds
  /// (UTC) of the newest day-entry/observation write the OS health store
  /// has been brought in line with, or unset when health sync has never
  /// been granted on this device. Written only by
  /// `lib/data/health/health_flow_write_service.dart`: first stamped with
  /// the grant instant (the moment `requestWriteAuthorization` completes —
  /// the issue's "forward-only from the moment permission is granted", so
  /// pre-grant days are never backfilled), then advanced to the newest
  /// processed row's `updatedAt` after a fully successful pass. Cleared
  /// alongside [healthStoreProfileId] whenever the binding goes away (the
  /// write coordinator calls the service's unbind path on any bound-profile
  /// transition), so re-binding re-grants from that new moment. Device-local
  /// scheduling metadata — a timestamp, never health content.
  static const String healthSyncWrittenThroughMs = 'health_sync_written_through_ms';

  /// Per-profile local reminder configuration (Issue #136, R10/R11), as
  /// the JSON document `encodeReminderConfigs` produces: a versioned map
  /// of profile id -> `ReminderConfig` JSON. Device-local **by design**
  /// and never synced — these are scheduling preferences about this
  /// device's own notifications, not health data (see
  /// `lib/domain/notifications/reminder_config.dart`'s library doc for
  /// the deliberate call and its recorded tension with the sync-first
  /// direction). Absent (or unparsable) means every profile falls back to
  /// its care-mode preset defaults — the exact pre-#136 plan.
  static const String reminderConfigs = 'reminder_configs';

  /// Per-profile late-reminder snoozes (Issue #136), as the JSON document
  /// `encodeLateSnoozes` produces: profile id -> the ISO date through
  /// which the profile's "Not yet" notification action has suppressed the
  /// late window. Device-local, same posture as [reminderConfigs].
  static const String reminderLateSnoozes = 'reminder_late_snoozes';

  /// Per-profile statistic baselines (Issue #178), as the JSON document
  /// `encodeStatisticBaselines`
  /// (`lib/domain/notifications/statistic_change.dart`) produces: profile
  /// id -> the last-observed displayed-statistic snapshot. Device-local,
  /// same posture as [reminderConfigs]; it is detection state for the
  /// `cycleStatisticChange` reminder, not health data.
  static const String reminderStatisticBaselines =
      'reminder_statistic_baselines';

  /// Per-profile statistic-change signals (Issue #178), as the JSON
  /// document `encodeStatisticChangeSignals` produces: profile id -> the
  /// ISO date a meaningful displayed-statistic change was last observed.
  /// Device-local, same posture as [reminderConfigs].
  static const String reminderStatisticChangeSignals =
      'reminder_statistic_change_signals';

  /// Issue #568 (b): set to `'true'` once
  /// `migrateOmittedCyclesToCycleOverrides` (`lib/domain/prediction/
  /// cycle_history.dart`) has copied every profile's device-local omission
  /// list (the pre-#568 `omittedCycles.<profileId>` keys) into
  /// `cycle_overrides` rows, so the one-time migration never re-scans
  /// every profile's old list on a later launch. The migration itself is
  /// also idempotent per-date (`CycleOverridesRepository.setExcludedFromAverage`
  /// is a no-op for an already-excluded date), so this flag is purely a
  /// fast-path — a device that somehow ran the migration twice would still
  /// converge on the same result.
  static const String cycleOverridesMigratedFromOmissionList =
      'cycle_overrides_migrated_from_omission_list';

  /// Per-profile "recently used tags" (Issue #234), as the JSON document
  /// `encodeTagRecents` produces: profile id -> most-recent-first taxonomy
  /// codes, capped per profile (`kTagRecentsCap`). Backs
  /// `CategoryPicker`'s "Recent" row. Device-local **by design** — a
  /// per-device logging-UI shortlist, not health data — and never synced,
  /// the same posture as [reminderConfigs].
  static const String tagRecents = 'tag_recents';

  /// The device-local appearance override (issue #137): one of `'system'`,
  /// `'light'`, or `'dark'`, parsed by `themeModeFromStored`
  /// (`lib/ui/theme/appearance.dart`). Absent — or any unrecognized value,
  /// so a future value can never wedge the app on a light-only build —
  /// reads as "follow the system appearance", the issue's own default
  /// posture. Device-local **by design**: appearance is a property of the
  /// display this device happens to be on, not of the account, the same
  /// posture as [relockEnabled].
  static const String themeMode = 'theme_mode';

  /// The calendar grid's week-start day (Issue #226): `'sunday'` (the
  /// historical default) or `'monday'`, parsed by
  /// `CalendarFirstDay.fromStored`
  /// (`lib/domain/calendar_preferences.dart`). Device-local by design —
  /// the same display-preference posture as [themeMode]; the month
  /// calendar watches this key and re-lays-out its grid live.
  static const String calendarFirstDayOfWeek = 'calendar_first_day_of_week';

  /// The compact date-order preference (Issue #226): `'system'` (the
  /// locale's own order — the pre-#226 behaviour), `'day_month'` ("5 Sep"),
  /// or `'month_day'` ("Sep 5"), parsed by
  /// `DateFormatPreference.fromStored`
  /// (`lib/domain/calendar_preferences.dart`). Consumed by
  /// `lib/ui/l10n/dates.dart`'s short-date helpers, so the day sheet's
  /// date header and every relative-day label follow it. Device-local,
  /// same posture as [themeMode].
  static const String dateFormat = 'date_format';
}
