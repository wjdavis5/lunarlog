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
  static const String webModalAcknowledged = 'web_modal_acknowledged';
  static const String firstRunNoticeShown = 'first_run_notice_shown';

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
}
