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
  Future<void> register(String deviceId, String token, {required String platform});

  Future<void> remove(String deviceId);
}
