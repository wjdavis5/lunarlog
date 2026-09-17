/// Unit tests for the permission-availability mapping (issue #215),
/// extracted from `notification_scheduler.dart`'s `checkAvailability()` into
/// a pure domain function. The adapter's own platform-probe tests
/// (`test/data/notification_scheduler_test.dart`) still drive the probes
/// through the plugin's method channel; these pin the mapping itself.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';

void main() {
  group('notificationAvailabilityFromPlatformProbe', () {
    test('an explicit false is the only answer that reads as denied', () {
      expect(
        notificationAvailabilityFromPlatformProbe(false),
        NotificationAvailability.denied,
      );
    });

    test('an enabled probe reads as available', () {
      expect(
        notificationAvailabilityFromPlatformProbe(true),
        NotificationAvailability.available,
      );
    });

    test('a null probe reads as available, never denied', () {
      // null = no platform implementation resolved, an inconclusive answer,
      // or no probe run at all: the OS remains the enforcement boundary, so
      // an unavailable probe must not brick reminder coordination.
      expect(
        notificationAvailabilityFromPlatformProbe(null),
        NotificationAvailability.available,
      );
    });
  });
}
