/// Unit tests for [NotificationPermissionGate] (issue #287): pins the
/// "exactly one OS permission request in flight at a time" property the
/// gate exists to guarantee between [FirebasePushTokenSource]'s
/// `FirebaseMessaging.instance.requestPermission()` and
/// [FlutterLocalNotificationsScheduler]'s Android/Darwin requests, using
/// fakes for both sources — neither real plugin call can run under
/// `flutter test` (see each class's own doc comment), so this exercises the
/// gate itself directly, the same way `push_registration_coordinator_test.dart`
/// exercises `PushRegistrationCoordinator` against a fake `PushTokenSource`
/// rather than the real Firebase-backed one.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_permission_gate.dart';

void main() {
  group('NotificationPermissionGate.guard', () {
    test(
        'two requests fired without awaiting either first never overlap -- '
        'the second does not start until the first finishes (issue #287\'s '
        'core property)', () async {
      final gate = NotificationPermissionGate();
      final events = <String>[];
      final firebaseGate = Completer<void>();
      final localGate = Completer<void>();

      // Stand in for FirebaseMessaging.instance.requestPermission() and
      // AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()
      // respectively -- both real calls the issue found racing.
      Future<String> fakeFirebaseRequestPermission() async {
        events.add('firebase start');
        await firebaseGate.future;
        events.add('firebase end');
        return 'firebase-granted';
      }

      Future<bool> fakeAndroidRequestNotificationsPermission() async {
        events.add('android start');
        await localGate.future;
        events.add('android end');
        return true;
      }

      // Fired together, exactly as `_startPushRegistration` (app_root.dart)
      // and `_scheduleReminderStart` (app.dart) do -- two independent
      // widgets, no `await` between them.
      final firebaseResult = gate.guard(fakeFirebaseRequestPermission);
      final androidResult =
          gate.guard(fakeAndroidRequestNotificationsPermission);

      // Only the first-queued request has actually started yet.
      await Future<void>.delayed(Duration.zero);
      expect(events, ['firebase start']);

      // Let the first finish; only then does the second begin.
      firebaseGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['firebase start', 'firebase end', 'android start']);

      localGate.complete();
      expect(await firebaseResult, 'firebase-granted');
      expect(await androidResult, isTrue);
      expect(events, [
        'firebase start',
        'firebase end',
        'android start',
        'android end',
      ]);
    });

    test('an unguarded pair of the same two fakes DOES overlap -- '
        'falsification coverage proving the test above is actually '
        'exercising the gate, not an incidental ordering', () async {
      final events = <String>[];
      final firebaseGate = Completer<void>();
      final localGate = Completer<void>();

      Future<void> fakeFirebaseRequestPermission() async {
        events.add('firebase start');
        await firebaseGate.future;
        events.add('firebase end');
      }

      Future<void> fakeAndroidRequestNotificationsPermission() async {
        events.add('android start');
        await localGate.future;
        events.add('android end');
      }

      unawaited(fakeFirebaseRequestPermission());
      unawaited(fakeAndroidRequestNotificationsPermission());
      await Future<void>.delayed(Duration.zero);

      expect(events, ['firebase start', 'android start'],
          reason: 'without a gate, both requests are in flight at once');

      firebaseGate.complete();
      localGate.complete();
    });

    test('a queued request still runs even though an earlier one on the '
        'same gate threw', () async {
      final gate = NotificationPermissionGate();

      await expectLater(
        gate.guard(() => Future<void>.error(StateError('boom'))),
        throwsA(isA<StateError>()),
      );

      // A later, unrelated caller (the other permission source, on a
      // later cold start / a retry) must not be left permanently queued
      // behind the failed one.
      expect(await gate.guard(() async => 'ok'), 'ok');
    });

    test('every queued caller gets its own result, not another caller\'s',
        () async {
      final gate = NotificationPermissionGate();
      final results = await Future.wait([
        gate.guard(() async => 'a'),
        gate.guard(() async => 'b'),
        gate.guard(() async => 'c'),
      ]);
      expect(results, ['a', 'b', 'c']);
    });

    test('a later guard call queues behind requests already queued before '
        'it existed -- the chain keeps extending, not resetting', () async {
      final gate = NotificationPermissionGate();
      final events = <String>[];
      final first = Completer<void>();

      final firstFuture = gate.guard(() async {
        events.add('first start');
        await first.future;
        events.add('first end');
      });

      // Queued while the first is still running.
      final secondFuture = gate.guard(() async {
        events.add('second');
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, ['first start']);

      first.complete();
      await Future.wait([firstFuture, secondFuture]);
      expect(events, ['first start', 'first end', 'second']);
    });
  });

  test(
      'defaultNotificationPermissionGate itself serializes two requests -- '
      'the top-level singleton every real caller (FirebasePushTokenSource '
      'and FlutterLocalNotificationsScheduler, unless a test overrides it) '
      'defaults to, so they share it and not one each', () async {
    final events = <String>[];
    final gateA = Completer<void>();

    final resultA = defaultNotificationPermissionGate.guard(() async {
      events.add('a start');
      await gateA.future;
      events.add('a end');
    });
    final resultB = defaultNotificationPermissionGate.guard(() async {
      events.add('b');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['a start'],
        reason: 'b must queue behind a on the shared default gate');

    gateA.complete();
    await Future.wait([resultA, resultB]);
    expect(events, ['a start', 'a end', 'b']);
  });
}
