/// Hand-written [NotificationPreferencesService] fake (Issue #5, U6),
/// matching `test/support/fake_sync_engine.dart`'s convention: a
/// controllable per-profile stream plus a call recorder, so UI tests never
/// touch Supabase.
library;

import 'dart:async';

import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';

class FakeNotificationPreferencesService
    implements NotificationPreferencesService {
  final Map<String, StreamController<CaregiverAlertPreferences>>
      _controllers = {};
  final Map<String, CaregiverAlertPreferences> _stored = {};

  int saveCalls = 0;
  Object? nextSaveError;

  StreamController<CaregiverAlertPreferences> _controllerFor(
          String profileId) =>
      _controllers.putIfAbsent(
        profileId,
        () => StreamController<CaregiverAlertPreferences>.broadcast(),
      );

  /// Test seam: seeds the stored value without going through [save].
  void seed(String profileId, CaregiverAlertPreferences prefs) {
    _stored[profileId] = prefs;
    _controllerFor(profileId).add(prefs);
  }

  @override
  Stream<CaregiverAlertPreferences> watchFor(String profileId) {
    final controller = _controllerFor(profileId);
    // Emit the current (or default) value to a fresh subscriber, matching
    // the production service's "fetch on first listen" behavior.
    scheduleMicrotask(
      () => controller.add(_stored[profileId] ?? CaregiverAlertPreferences.off),
    );
    return controller.stream;
  }

  @override
  Future<void> save(String profileId, CaregiverAlertPreferences prefs) async {
    saveCalls++;
    final error = nextSaveError;
    if (error != null) {
      nextSaveError = null;
      throw error;
    }
    _stored[profileId] = prefs;
    _controllerFor(profileId).add(prefs);
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
