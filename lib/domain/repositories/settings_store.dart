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
}
