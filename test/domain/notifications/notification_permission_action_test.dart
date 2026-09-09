/// Unit tests for issue #168's pure permission-action decision.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/notification_permission_action.dart';

void main() {
  group('nextNotificationPermissionAction', () {
    test('requests when never denied', () {
      expect(nextNotificationPermissionAction(0),
          NotificationPermissionAction.request);
    });

    test('still requests after exactly one denial (Android allows a second '
        'ask before it stops showing the dialog)', () {
      expect(nextNotificationPermissionAction(1),
          NotificationPermissionAction.request);
    });

    test('opens settings once denied twice', () {
      expect(nextNotificationPermissionAction(2),
          NotificationPermissionAction.openSettings);
    });

    test('stays at openSettings for any further count', () {
      expect(nextNotificationPermissionAction(3),
          NotificationPermissionAction.openSettings);
      expect(nextNotificationPermissionAction(10),
          NotificationPermissionAction.openSettings);
    });
  });
}
