/// Domain interface and typed failures for caregiver alert preferences
/// (Issue #5, U6; R1-R4).
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary, mirroring
/// `lib/domain/sharing/sharing_service.dart`.
library;

import 'notification_preferences.dart';

/// Typed failures for reading or saving preferences, mirroring
/// `SharingFailure`'s shape (R11-of-#6 precedent: never a raw provider
/// message reaches the UI).
sealed class NotificationPreferencesFailure implements Exception {
  const NotificationPreferencesFailure();

  const factory NotificationPreferencesFailure.unauthorized() =
      NotificationPreferencesUnauthorizedFailure;
  const factory NotificationPreferencesFailure.network() =
      NotificationPreferencesNetworkFailure;
  const factory NotificationPreferencesFailure.other() =
      NotificationPreferencesOtherFailure;

  String get userFacingMessage;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class NotificationPreferencesUnauthorizedFailure
    extends NotificationPreferencesFailure {
  const NotificationPreferencesUnauthorizedFailure();
  @override
  String get userFacingMessage =>
      'You do not have permission for this action.';
  @override
  String toString() => 'NotificationPreferencesFailure.unauthorized';
}

final class NotificationPreferencesNetworkFailure
    extends NotificationPreferencesFailure {
  const NotificationPreferencesNetworkFailure();
  @override
  String get userFacingMessage => 'Network error. Please check your connection.';
  @override
  String toString() => 'NotificationPreferencesFailure.network';
}

final class NotificationPreferencesOtherFailure
    extends NotificationPreferencesFailure {
  const NotificationPreferencesOtherFailure();
  @override
  String get userFacingMessage =>
      'Failed to save notification preferences. Please try again.';
  @override
  String toString() => 'NotificationPreferencesFailure.other';
}

/// Contract for reading and writing a guardian's own caregiver alert
/// preferences for one profile.
abstract interface class NotificationPreferencesService {
  /// Emits the stored preferences for [profileId], and the all-off default
  /// ([CaregiverAlertPreferences.off]) when no row exists yet (R4). Re-emits
  /// after a successful [save].
  Stream<CaregiverAlertPreferences> watchFor(String profileId);

  /// Upserts [prefs] as the caller's own row for [profileId]. Throws
  /// [NotificationPreferencesFailure].
  Future<void> save(String profileId, CaregiverAlertPreferences prefs);
}
