/// Unit tests for FlutterLocalNotificationsScheduler (Issue #43).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  IOSFlutterLocalNotificationsPlugin.registerWith();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  bool? mockIosEnabled;

  setUp(() {
    calls.clear();
    mockIosEnabled = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'checkPermissions') {
        if (mockIosEnabled != null) {
          return <String, dynamic>{
            'isEnabled': mockIosEnabled!,
            'isAlertEnabled': mockIosEnabled!,
            'isBadgeEnabled': mockIosEnabled!,
            'isSoundEnabled': mockIosEnabled!,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
            'isCarPlayEnabled': false,
          };
        }
        return null;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('FlutterLocalNotificationsScheduler iOS permission probing (Issue #43)', () {
    test('reports denied when iOS permissions are disabled', () async {
      mockIosEnabled = false;
      final scheduler = FlutterLocalNotificationsScheduler();
      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.denied);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
    });

    test('reports available when iOS permissions are enabled', () async {
      mockIosEnabled = true;
      final scheduler = FlutterLocalNotificationsScheduler();
      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.available);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
    });

    test('defaults to available when checkPermissions returns null (unsupported/headless)', () async {
      mockIosEnabled = null;
      final scheduler = FlutterLocalNotificationsScheduler();
      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.available);
    });
  });
}
