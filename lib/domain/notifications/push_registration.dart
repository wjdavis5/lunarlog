/// Push registration contracts (Issue #5, U7; R11, R17-R19).
///
/// Pure Dart - the firebase_messaging adapter lives in
/// `lib/data/notifications/firebase_push_token_source.dart`; the
/// Supabase-backed registry in
/// `lib/data/notifications/supabase_push_device_registry.dart`.
library;

/// Reads and observes this device's FCM token, and reports message taps.
abstract interface class PushTokenSource {
  /// The current registration token, or null when push is unavailable for
  /// this platform/build.
  Future<String?> currentToken();

  /// Emits a new token whenever FCM rotates it.
  Stream<String> tokenRefreshes();

  /// Emits the `profile_id` from a tapped notification's data payload, or
  /// null when the payload carried none (e.g. a notification this app did
  /// not send).
  Stream<String?> taps();
}

/// Writes this device's registration to the server (R19). [deviceId] is a
/// stable identifier the composition root generates once and persists
/// locally (`lib/app.dart`) - passing the same id on every call is what
/// makes a token refresh replace this device's row rather than duplicate it.
abstract interface class PushDeviceRegistry {
  /// Registers/refreshes this device's row. Round-2 review #1: must be
  /// robust to a stale row left behind by a previous account on this same
  /// install whose deregistration failed (e.g. an offline sign-out) - a
  /// plain upsert conflicting on [deviceId] silently no-ops in that case
  /// (RLS denies the UPDATE half of the upsert since the existing row's
  /// `user_id` is not the caller, and there is no INSERT fallback once the
  /// conflict target already exists), permanently blocking the next account
  /// from ever registering while the previous account keeps receiving this
  /// device's alerts. Implementations must reassign such a row to the
  /// caller rather than leaving it silently unclaimed.
  Future<void> register(String deviceId, String token, {required String platform});

  Future<void> remove(String deviceId);

  /// Removes every row belonging to the currently signed-in user, across
  /// every device - not just [deviceId] (round-2 review #9). Used on a
  /// "sign out everywhere" style flow: `signOut(scope: global)` revokes
  /// every device's *session*, but nothing else stops another device's
  /// `push_devices` row (and its FCM token) from surviving and continuing
  /// to receive a minor's caregiver alerts after the account's owner
  /// explicitly asked to be signed out everywhere. A no-op when signed out.
  Future<void> removeAllForCurrentUser();
}
