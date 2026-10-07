/// Direct unit coverage for [buildFirebaseOptions] (Issue #5; round-2
/// review #3): the one piece of pure branching logic pulled out of the
/// otherwise plugin-excluded `firebase_push_token_source.dart` (see that
/// file's own doc comment and `tool/quality/exclusions.dart`'s entry for
/// it). Round-1 #10 flagged the coverage exclusion for claiming "no
/// branching worth testing" while hiding the sequencing bugs that shipped
/// in #4/#5; round-2 #3 found that the rewritten rationale went on to claim
/// this exact test existed when it did not. This file makes that claim
/// true.
///
/// Issue #206 (C-26) adds the `taps()` lifecycle coverage through the
/// class's testing seams: before the fix every `taps()` call leaked a
/// permanent `onMessageOpenedApp` listener and a never-closed controller,
/// so each device reset attached another generation that a single
/// notification tap would reach.
///
/// Issue #1425 adds [pushPermissionStateOf] and the permission ask,
/// `askPermission`, run through the real class with fakes for its two
/// plugin calls: it still queues on the shared permission gate, opens the
/// system-UI window only for its own request, and counts its Android
/// refusals where the real scheduler's "Turn on reminders" path reads
/// them. Issue #1444 moves the ask in context (no launch-time request);
/// the wiring these tests pin is unchanged, only the caller is.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';
import 'package:lunarlog/data/notifications/notification_permission_gate.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/domain/notifications/push_permission_plan.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildFirebaseOptions', () {
    test('isIOS: true selects the iOS apiKey/appId, not the Android pair',
        () {
      final options = buildFirebaseOptions(
        isIOS: true,
        iosApiKey: 'ios-api-key',
        iosAppId: 'ios-app-id',
        androidApiKey: 'android-api-key',
        androidAppId: 'android-app-id',
        senderId: 'sender-1',
        projectId: 'project-1',
      );

      expect(
        options,
        const FirebaseOptions(
          apiKey: 'ios-api-key',
          appId: 'ios-app-id',
          messagingSenderId: 'sender-1',
          projectId: 'project-1',
        ),
      );
    });

    test('isIOS: false selects the Android apiKey/appId, not the iOS pair',
        () {
      final options = buildFirebaseOptions(
        isIOS: false,
        iosApiKey: 'ios-api-key',
        iosAppId: 'ios-app-id',
        androidApiKey: 'android-api-key',
        androidAppId: 'android-app-id',
        senderId: 'sender-1',
        projectId: 'project-1',
      );

      expect(
        options,
        const FirebaseOptions(
          apiKey: 'android-api-key',
          appId: 'android-app-id',
          messagingSenderId: 'sender-1',
          projectId: 'project-1',
        ),
      );
    });

    test('senderId and projectId pass through unchanged on both platforms',
        () {
      final ios = buildFirebaseOptions(
        isIOS: true,
        iosApiKey: 'a',
        iosAppId: 'b',
        androidApiKey: 'c',
        androidAppId: 'd',
        senderId: 'shared-sender',
        projectId: 'shared-project',
      );
      final android = buildFirebaseOptions(
        isIOS: false,
        iosApiKey: 'a',
        iosAppId: 'b',
        androidApiKey: 'c',
        androidAppId: 'd',
        senderId: 'shared-sender',
        projectId: 'shared-project',
      );

      expect(ios.messagingSenderId, 'shared-sender');
      expect(ios.projectId, 'shared-project');
      expect(android.messagingSenderId, 'shared-sender');
      expect(android.projectId, 'shared-project');
    });
  });

  group('taps() subscription lifecycle (#206 C-26)', () {
    test('cancelling the returned stream detaches its onMessageOpenedApp '
        'listener and closes the bridge', () async {
      final openedApp = _FakeOpenedAppStream();
      final source = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final sub = source.taps().listen((_) {});
      await pumpEventQueue();
      expect(openedApp.hasListener, isTrue);

      await sub.cancel();
      await pumpEventQueue();

      expect(openedApp.hasListener, isFalse,
          reason: 'the inner onMessageOpenedApp subscription must be '
              'cancelled when the consumer cancels, not leaked forever');
    });

    test('two consecutive taps() lifecycles (two device-reset cycles): only '
        'the current generation stays attached, and after it too is '
        'cancelled nothing is left listening', () async {
      final openedApp = _FakeOpenedAppStream();

      // Generation one: a coordinator's taps() subscription, then the
      // device reset disposes that coordinator.
      final first = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final firstSub = first.taps().listen((_) {});
      await pumpEventQueue();
      expect(openedApp.hasListener, isTrue);
      await firstSub.cancel();
      await pumpEventQueue();
      expect(openedApp.hasListener, isFalse);

      // Generation two: the post-reset coordinator binds a fresh source to
      // the same (process-wide) plugin stream.
      final second = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final secondSub = second.taps().listen((_) {});
      await pumpEventQueue();
      expect(openedApp.hasListener, isTrue);

      await secondSub.cancel();
      await pumpEventQueue();
      expect(openedApp.hasListener, isFalse,
          reason: 'before #206 the first generation listener was never '
              'detached, so it stayed attached for the rest of the process');
    });

    test('overlapping generations: after the first generation cancels, a '
        'notification tap is delivered only to the current generation',
        () async {
      final openedApp = _FakeOpenedAppStream();
      final firstGeneration = <String?>[];
      final secondGeneration = <String?>[];

      final first = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final firstSub = first.taps().listen(firstGeneration.add);
      await pumpEventQueue();

      final second = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final secondSub = second.taps().listen(secondGeneration.add);
      await pumpEventQueue();

      await firstSub.cancel();
      await pumpEventQueue();
      openedApp.emit(const RemoteMessage(data: {'profile_id': 'gen-2-only'}));
      await pumpEventQueue();

      expect(secondGeneration, contains('gen-2-only'));
      expect(firstGeneration, isNot(contains('gen-2-only')),
          reason: 'a cancelled generation stays deaf: its bridge is closed '
              'and its listener detached, so no later tap can reach it');

      await secondSub.cancel();
    });

    test('forwards the tapped payload profile_id, or null when the payload '
        'carried none', () async {
      final openedApp = _FakeOpenedAppStream();
      final source = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: Future<RemoteMessage?>.value(null),
      );
      final received = <String?>[];
      final sub = source.taps().listen(received.add);
      await pumpEventQueue();

      openedApp
        ..emit(const RemoteMessage(data: {'profile_id': 'profile-7'}))
        ..emit(const RemoteMessage());
      await pumpEventQueue();

      expect(received, ['profile-7', null]);

      await sub.cancel();
    });

    test('a cold-start getInitialMessage payload is merged in, and cannot '
        'reach the closed bridge after the consumer cancels', () async {
      final openedApp = _FakeOpenedAppStream();
      final initialMessage = Completer<RemoteMessage?>();
      final source = FirebasePushTokenSource.forTesting(
        openedAppMessages: openedApp,
        initialMessage: initialMessage.future,
      );
      final received = <String?>[];
      final sub = source.taps().listen(received.add);
      await pumpEventQueue();

      await sub.cancel();
      // Resolves after cancellation, like a cold-start payload landing while
      // the reset tears the coordinator down.
      initialMessage.complete(
          const RemoteMessage(data: {'profile_id': 'cold-start'}));
      await pumpEventQueue();

      expect(received, isEmpty,
          reason: 'the payload raced past its only consumer; it must be '
              'dropped, not thrown into a closed controller');
    });
  });

  group('pushPermissionStateOf (issue #1425)', () {
    test('authorized and provisional both count as granted', () {
      expect(pushPermissionStateOf(AuthorizationStatus.authorized),
          PushPermissionState.granted);
      expect(pushPermissionStateOf(AuthorizationStatus.provisional),
          PushPermissionState.granted);
    });

    test('notDetermined is undetermined: the dialog has not been shown', () {
      expect(pushPermissionStateOf(AuthorizationStatus.notDetermined),
          PushPermissionState.undetermined);
    });

    test('denied and deniedPermanently are both refused -- whether Android '
        'has stopped showing its dialog is the refusal count\'s call, not '
        'the plugin\'s inference', () {
      expect(pushPermissionStateOf(AuthorizationStatus.denied),
          PushPermissionState.refused);
      expect(pushPermissionStateOf(AuthorizationStatus.deniedPermanently),
          PushPermissionState.refused);
    });

    test('every status the plugin can report has a mapping', () {
      for (final status in AuthorizationStatus.values) {
        expect(PushPermissionState.values,
            contains(pushPermissionStateOf(status)),
            reason: '$status');
      }
    });
  });

  group('askPermission -- the in-context ask (issues #1425, #1444)', () {
    // The real FirebasePushTokenSource, with fakes in place of the two
    // plugin calls only: the queueing on the shared permission gate, the
    // window and the refusal count are this class's own wiring.
    const localNotifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    final schedulerCalls = <String>[];

    setUp(() {
      schedulerCalls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      // Notifications are off and Android no longer answers a request with
      // a dialog: a `requestNotificationsPermission` here is a dead tap.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localNotifications,
              (MethodCall call) async {
        schedulerCalls.add(call.method);
        return switch (call.method) {
          'initialize' || 'openAppNotificationSettings' => true,
          'areNotificationsEnabled' ||
          'requestNotificationsPermission' =>
            false,
          _ => null,
        };
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localNotifications, null);
    });

    /// One in-context ask: a fresh source over [store] (as after a process
    /// restart) making its ask, with the platform at [state] beforehand
    /// and the operator's answer leaving it at [answer]. Returns how many
    /// requests were made.
    Future<int> ask(
      FakeSettingsStore store, {
      required PushPermissionState state,
      required PushPermissionState answer,
    }) async {
      var requests = 0;
      final source = FirebasePushTokenSource(
        permissionGate: NotificationPermissionGate(),
        settingsStore: store,
      );
      await source.askPermission(
        isAndroid: true,
        currentState: () async => state,
        request: () async {
          requests++;
          return answer;
        },
      );
      return requests;
    }

    /// The "Turn on reminders" tap, through the real scheduler over the
    /// same [store].
    Future<void> tapTurnOnReminders(FakeSettingsStore store) async {
      final scheduler = FlutterLocalNotificationsScheduler(
        settingsStore: store,
        localTimeZoneProvider: () async => 'UTC',
        permissionGate: NotificationPermissionGate(),
      );
      await scheduler.initialize();
      schedulerCalls.clear();
      await scheduler.requestPermission();
    }

    test('the ask waits its turn on the shared permission gate, and its '
        'window opens only once that turn comes', () async {
      final gate = NotificationPermissionGate();
      final events = <String>[];
      final window = _RecordingWindow(events);
      final earlier = Completer<void>();
      // Another permission request already in flight -- a "Turn on
      // reminders" tap, say.
      final earlierDone = gate.guard(() async {
        events.add('earlier request starts');
        await earlier.future;
        events.add('earlier request ends');
      });
      final source = FirebasePushTokenSource(
        permissionGate: gate,
        duringSystemUi: window.call,
        settingsStore: FakeSettingsStore(),
      );

      final ask = source.askPermission(
        isAndroid: true,
        currentState: () async {
          events.add('probe');
          return PushPermissionState.undetermined;
        },
        request: () async {
          events.add('request');
          return PushPermissionState.granted;
        },
      );
      await pumpEventQueue();

      expect(events, ['earlier request starts'],
          reason: 'issue #287: still serialized behind the earlier request');
      expect(window.opened, 0,
          reason: 'the window must not sit open (covering the app) while '
              'the ask is only waiting in the queue');

      earlier.complete();
      await earlierDone;
      await ask;

      expect(events, [
        'earlier request starts',
        'earlier request ends',
        'probe',
        'window opens',
        'request',
        'window closes',
      ]);
    });

    test('an ask whose permission is already settled makes no request '
        'and opens no window', () async {
      final events = <String>[];
      final window = _RecordingWindow(events);
      final source = FirebasePushTokenSource(
        permissionGate: NotificationPermissionGate(),
        duringSystemUi: window.call,
        settingsStore: FakeSettingsStore(),
      );

      await source.askPermission(
        isAndroid: true,
        currentState: () async => PushPermissionState.granted,
        request: () async {
          events.add('request');
          return PushPermissionState.granted;
        },
      );

      expect(window.opened, 0);
      expect(events, isEmpty);
    });

    test('a refused push ask increments the count the scheduler reads, and '
        'a granted one resets it', () async {
      final store = FakeSettingsStore();
      const key = SettingsKeys.androidNotificationDeniedAttempts;

      await ask(
        store,
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
      );
      expect(await store.get(key), '1');

      await ask(
        store,
        state: PushPermissionState.refused,
        answer: PushPermissionState.granted,
      );
      expect(await store.get(key), '0');
    });

    test('after two refused push asks, the first "Turn on reminders" tap '
        'opens settings instead of making a dead request', () async {
      final store = FakeSettingsStore();

      // Ask 1: the first dialog, refused. Ask 2: the second, refused
      // -- Android will show no third.
      expect(
        await ask(
          store,
          state: PushPermissionState.undetermined,
          answer: PushPermissionState.refused,
        ),
        1,
      );
      expect(
        await ask(
          store,
          state: PushPermissionState.refused,
          answer: PushPermissionState.refused,
        ),
        1,
      );
      // Ask 3: nothing left to ask.
      expect(
        await ask(
          store,
          state: PushPermissionState.refused,
          answer: PushPermissionState.refused,
        ),
        0,
        reason: 'a request now would be silently dropped',
      );

      await tapTurnOnReminders(store);

      expect(schedulerCalls, contains('openAppNotificationSettings'),
          reason: 'the dialogs were spent in context; settings is the only '
              'path back to "on"');
      expect(schedulerCalls, isNot(contains('requestNotificationsPermission')),
          reason: 'the pre-fix bug: push registration\'s refusals went '
              'uncounted, so this tap -- and the next -- asked into '
              'silence');
    });

    test('after one refused push ask the tap still asks -- Android has a '
        'dialog left -- and a refusal there is the last', () async {
      final store = FakeSettingsStore();
      await ask(
        store,
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
      );

      await tapTurnOnReminders(store);
      expect(schedulerCalls, contains('requestNotificationsPermission'));
      expect(schedulerCalls, isNot(contains('openAppNotificationSettings')));

      // The tap's own refusal took the shared count to the line: push
      // registration's next in-context ask asks nothing, and the next tap
      // opens settings.
      expect(
        await ask(
          store,
          state: PushPermissionState.refused,
          answer: PushPermissionState.refused,
        ),
        0,
        reason: 'the count is one count: the tap\'s refusal stops the '
            'in-context ask too',
      );
      await tapTurnOnReminders(store);
      expect(schedulerCalls, contains('openAppNotificationSettings'));
      expect(schedulerCalls, isNot(contains('requestNotificationsPermission')));
    });

    test('an older build\'s uncounted dialog is caught up at the next '
        'ask, so the first tap still opens settings', () async {
      // A pre-#1425 build spent both dialogs in a single launch (push
      // registration's ask, then the scheduler's own) and counted only the
      // scheduler's. This build's first in-context ask asks once more --
      // the OS drops the request and reports it refused -- and that brings
      // the count to the line before the hint is ever tapped.
      final store = FakeSettingsStore(
          {SettingsKeys.androidNotificationDeniedAttempts: '1'});

      await ask(
        store,
        state: PushPermissionState.refused,
        answer: PushPermissionState.refused,
      );
      await tapTurnOnReminders(store);

      expect(schedulerCalls, contains('openAppNotificationSettings'));
      expect(schedulerCalls, isNot(contains('requestNotificationsPermission')));
    });
  });
}

/// Stands in for `GateController.duringSystemUi`, logging into the same
/// event list as the fake plugin calls.
class _RecordingWindow {
  _RecordingWindow(this.events);

  final List<String> events;
  int opened = 0;

  Future<T> call<T>(Future<T> Function() action) async {
    opened++;
    events.add('window opens');
    try {
      return await action();
    } finally {
      events.add('window closes');
    }
  }
}

/// Stand-in for `FirebaseMessaging.onMessageOpenedApp` that tracks whether
/// anything is currently attached — the observable the issue's leak is
/// stated in.
class _FakeOpenedAppStream extends Stream<RemoteMessage> {
  final StreamController<RemoteMessage> _controller =
      StreamController<RemoteMessage>.broadcast();

  bool get hasListener => _controller.hasListener;

  void emit(RemoteMessage message) => _controller.add(message);

  @override
  StreamSubscription<RemoteMessage> listen(
    void Function(RemoteMessage)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
