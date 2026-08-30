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
}
