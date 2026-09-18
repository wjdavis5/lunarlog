/// FCM foreground/background presentation (Issue #174).
///
/// Three layers, mirroring how `firebase_push_token_source.dart` and
/// `notification_scheduler.dart` are tested:
///
/// * [pushNotificationPresentation] — the pure who-presents-what decision,
///   including the discretion pin: a payload carrying health-looking fields
///   still yields exactly `kReminderTitle`/`kReminderBody`, never anything
///   read from the payload.
/// * [PushForegroundPresenter] — the `onMessage` subscription, driven
///   through an injected stand-in stream against the real
///   `flutter_local_notifications` singleton over a mocked platform channel
///   (the same `dexterous.com/flutter/local_notifications` harness
///   `notification_scheduler_test.dart` uses).
/// * [presentPushInBackground] — the background handler's testable core,
///   same mocked channel.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/push_presentation.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pushNotificationPresentation (Issue #174 decision matrix)', () {
    const healthLookingData = <String, dynamic>{
      'profile_id': 'profile-7',
      'profile_name': 'Daughter (14)',
      'note': 'heavy bleeding today',
      'flow': 'heavy',
      'local_date': '2026-09-14',
      'kind': 'high_severity',
    };

    PushNotificationPresentation? decide({
      Map<String, dynamic> data = const {},
      String? messageId = 'msg-1',
      bool hasNotificationPayload = true,
      bool isIOS = false,
      bool isBackground = false,
    }) =>
        pushNotificationPresentation(
          data: data,
          messageId: messageId,
          hasNotificationPayload: hasNotificationPayload,
          isIOS: isIOS,
          isBackground: isBackground,
        );

    test(
        'foreground, Android, notification payload: the app presents, with '
        'exactly the fixed generic copy on the Reminders channel',
        () {
      final presentation = decide(
        data: healthLookingData,
        isIOS: false,
        isBackground: false,
        hasNotificationPayload: true,
      )!;

      expect(presentation.title, kReminderTitle);
      expect(presentation.body, kReminderBody);
      expect(presentation.channelId, kReminderChannelId);
      expect(presentation.channelId, 'lunarlog_reminders');
    });

    test(
        'DISCRETION PIN (foreground, Android): a payload full of '
        'health-looking fields still presents only the fixed strings — no '
        'profile name, date, flow, note, or kind value ever reaches the '
        'banner',
        () {
      final presentation = decide(
        data: healthLookingData,
        isIOS: false,
        isBackground: false,
        hasNotificationPayload: true,
      )!;

      final presented = '${presentation.title}\n${presentation.body}';
      for (final forbidden in [
        'Daughter (14)',
        'heavy bleeding today',
        'heavy',
        '2026-09-14',
        'high_severity',
        'profile-7',
      ]) {
        expect(presented, isNot(contains(forbidden)),
            reason: 'payload value "$forbidden" leaked into presented copy');
      }
      expect(presented, '$kReminderTitle\n$kReminderBody');
    });

    test(
        'DISCRETION PIN (background, data-only): same fixed strings even '
        'when the payload mimics the fields the server never sends',
        () {
      final presentation = decide(
        data: healthLookingData,
        isIOS: false,
        isBackground: true,
        hasNotificationPayload: false,
      )!;

      expect(presentation.title, 'A reminder from lunarlog');
      expect(presentation.body, 'Open lunarlog to see what it is about.');
    });

    test(
        'foreground, Android, data-only payload: the app presents (FCM '
        'never auto-presents in the foreground)',
        () {
      expect(
        decide(hasNotificationPayload: false, isIOS: false),
        isA<PushNotificationPresentation>(),
      );
    });

    test(
        'foreground, iOS, notification payload: nobody presents locally — '
        'the system does, via setForegroundNotificationPresentationOptions',
        () {
      expect(
        decide(hasNotificationPayload: true, isIOS: true),
        isNull,
        reason: 'presenting locally as well would double every iOS banner',
      );
    });

    test('foreground, iOS, data-only payload: the app presents', () {
      final presentation =
          decide(hasNotificationPayload: false, isIOS: true)!;
      expect(presentation.title, kReminderTitle);
    });

    test(
        'background, notification payload: nobody presents locally on '
        'either platform — the OS tray/notification center already did',
        () {
      expect(
        decide(hasNotificationPayload: true, isIOS: false, isBackground: true),
        isNull,
      );
      expect(
        decide(hasNotificationPayload: true, isIOS: true, isBackground: true),
        isNull,
      );
    });

    test(
        'background, data-only payload: the app presents on both platforms '
        '(this is exactly what the background handler exists for)',
        () {
      expect(
        decide(hasNotificationPayload: false, isIOS: false, isBackground: true),
        isA<PushNotificationPresentation>(),
      );
      expect(
        decide(hasNotificationPayload: false, isIOS: true, isBackground: true),
        isA<PushNotificationPresentation>(),
      );
    });

    test(
        'the notification id is deterministic per message id (a redelivery '
        'replaces its own presentation) and distinct across messages',
        () {
      final first = decide(messageId: 'msg-1')!;
      final firstAgain = decide(messageId: 'msg-1')!;
      final second = decide(messageId: 'msg-2')!;

      expect(first.id, firstAgain.id);
      expect(first.id, isNot(second.id));
    });
  });

  group('PushForegroundPresenter / presentPushInBackground (plugin side)',
      () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    Object? failOnShow;

    setUp(() {
      calls.clear();
      failOnShow = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'show' && failOnShow != null) throw failOnShow!;
        if (call.method == 'initialize') return true;
        return null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      // Restore whichever platform implementation the surrounding suite
      // expects, the same way notification_scheduler_test.dart does.
      IOSFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void usePlatform(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      switch (platform) {
        case TargetPlatform.android:
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        case TargetPlatform.iOS:
          IOSFlutterLocalNotificationsPlugin.registerWith();
        case TargetPlatform.macOS:
          MacOSFlutterLocalNotificationsPlugin.registerWith();
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          break;
      }
    }

    MethodCall? shownCall() {
      for (final call in calls.reversed) {
        if (call.method == 'show') return call;
      }
      return null;
    }

    Map<Object?, Object?> argsOf(MethodCall call) =>
        Map<Object?, Object?>.from(call.arguments as Map<Object?, Object?>);

    test(
        'foreground Android: a notification-carrying message is shown with '
        'exactly the fixed copy on the Reminders channel',
        () async {
      usePlatform(TargetPlatform.android);
      final messages = _FakeMessageStream();
      final presenter = PushForegroundPresenter(
        messages: messages,
        isIOS: false,
      )..start();
      await pumpEventQueue();

      messages.emit(const RemoteMessage(
        messageId: 'msg-fg-1',
        notification: RemoteNotification(
            title: 'A reminder from lunarlog',
            body: 'Open lunarlog to see what it is about.'),
        data: {'profile_id': 'profile-7'},
      ));
      await pumpEventQueue();

      final show = shownCall();
      expect(show, isNotNull,
          reason: 'an Android foreground push must be presented by the app');
      expect(argsOf(show!)['title'], kReminderTitle);
      expect(argsOf(show)['body'], kReminderBody);
      final specifics = argsOf(show)['platformSpecifics']
          as Map<Object?, Object?>?;
      expect(specifics!['channelId'], kReminderChannelId);
      expect(specifics['visibility'], NotificationVisibility.secret.index,
          reason: 'push banners keep the reminders\' lock-screen privacy');

      await presenter.dispose();
    });

    test(
        'foreground Android: a data-only message carrying health-looking '
        'fields is shown with only the fixed copy (discretion pin on the '
        'plugin path)',
        () async {
      usePlatform(TargetPlatform.android);
      final messages = _FakeMessageStream();
      final presenter = PushForegroundPresenter(
        messages: messages,
        isIOS: false,
      )..start();
      await pumpEventQueue();

      messages.emit(const RemoteMessage(
        messageId: 'msg-fg-2',
        data: {
          'profile_id': 'profile-7',
          'note': 'heavy bleeding today',
          'flow': 'heavy',
          'local_date': '2026-09-14',
        },
      ));
      await pumpEventQueue();

      final show = shownCall()!;
      expect(argsOf(show)['title'], kReminderTitle);
      expect(argsOf(show)['body'], kReminderBody);
      expect('${argsOf(show)['title']}${argsOf(show)['body']}',
          isNot(contains('heavy')));

      await presenter.dispose();
    });

    test(
        'foreground iOS: a notification-carrying message is NOT shown '
        'locally (the system presents it via the startup presentation '
        'options — showing again would double the banner)',
        () async {
      usePlatform(TargetPlatform.iOS);
      final messages = _FakeMessageStream();
      final presenter = PushForegroundPresenter(
        messages: messages,
        isIOS: true,
      )..start();
      await pumpEventQueue();

      messages.emit(const RemoteMessage(
        messageId: 'msg-fg-3',
        notification: RemoteNotification(
            title: 'A reminder from lunarlog',
            body: 'Open lunarlog to see what it is about.'),
      ));
      await pumpEventQueue();

      expect(shownCall(), isNull);

      await presenter.dispose();
    });

    test(
        'dispose() detaches: a message emitted after disposal presents '
        'nothing and throws no unhandled error',
        () async {
      usePlatform(TargetPlatform.android);
      final messages = _FakeMessageStream();
      final presenter = PushForegroundPresenter(
        messages: messages,
        isIOS: false,
      )..start();
      await pumpEventQueue();
      await presenter.dispose();

      messages.emit(const RemoteMessage(messageId: 'msg-after-dispose'));
      await pumpEventQueue();

      expect(shownCall(), isNull);
    });

    test(
        'a platform failure inside show is swallowed into a breadcrumb, '
        'never thrown into the stream subscription',
        () async {
      usePlatform(TargetPlatform.android);
      failOnShow = PlatformException(code: 'plugin_not_initialized');
      final log = BreadcrumbLog();
      final messages = _FakeMessageStream();
      final presenter = PushForegroundPresenter(
        messages: messages,
        isIOS: false,
        breadcrumbLog: log,
      )..start();
      await pumpEventQueue();

      messages.emit(const RemoteMessage(messageId: 'msg-fg-4'));
      await pumpEventQueue();

      expect(
          log.snapshot(), contains('push_present: PlatformException'));
      // The subscription must still be alive: a later message retries.
      failOnShow = null;
      messages.emit(const RemoteMessage(messageId: 'msg-fg-5'));
      await pumpEventQueue();
      expect(shownCall(), isNotNull);

      await presenter.dispose();
    });

    test(
        'background Android, data-only: initializes a fresh plugin, '
        '(re)creates the Reminders channel, and shows the fixed copy',
        () async {
      usePlatform(TargetPlatform.android);

      await presentPushInBackground(
        message: const RemoteMessage(
          messageId: 'msg-bg-1',
          data: {'profile_id': 'profile-7'},
        ),
        plugin: FlutterLocalNotificationsPlugin(),
        platform: TargetPlatform.android,
      );

      expect(calls.any((c) => c.method == 'initialize'), isTrue,
          reason: 'the background engine has no initialized plugin');
      final channelCall = calls.firstWhere(
        (c) => c.method == 'createNotificationChannel',
        orElse: () => throw StateError('channel not created'),
      );
      expect(argsOf(channelCall)['id'], kReminderChannelId);
      final show = shownCall()!;
      expect(argsOf(show)['title'], kReminderTitle);
      expect(argsOf(show)['body'], kReminderBody);
    });

    test(
        'background Android, notification payload: nothing at all — the OS '
        'tray already presented it',
        () async {
      usePlatform(TargetPlatform.android);

      await presentPushInBackground(
        message: const RemoteMessage(
          messageId: 'msg-bg-2',
          notification: RemoteNotification(
              title: 'A reminder from lunarlog',
              body: 'Open lunarlog to see what it is about.'),
        ),
        plugin: FlutterLocalNotificationsPlugin(),
        platform: TargetPlatform.android,
      );

      expect(calls, isEmpty);
    });

    test(
        'background iOS, data-only: shows WITHOUT re-initializing the '
        'plugin — initialize() here would replace the scheduler\'s '
        'registered response callback (the reminder action buttons)',
        () async {
      usePlatform(TargetPlatform.iOS);

      await presentPushInBackground(
        message: const RemoteMessage(
          messageId: 'msg-bg-3',
          data: {'profile_id': 'profile-7'},
        ),
        plugin: FlutterLocalNotificationsPlugin(),
        platform: TargetPlatform.iOS,
      );

      expect(calls.any((c) => c.method == 'initialize'), isFalse);
      final show = shownCall()!;
      expect(argsOf(show)['title'], kReminderTitle);
      expect(argsOf(show)['body'], kReminderBody);
    });

    test(
        'background iOS, notification payload: nothing — iOS already '
        'displayed it',
        () async {
      usePlatform(TargetPlatform.iOS);

      await presentPushInBackground(
        message: const RemoteMessage(
          messageId: 'msg-bg-4',
          notification: RemoteNotification(
              title: 'A reminder from lunarlog',
              body: 'Open lunarlog to see what it is about.'),
        ),
        plugin: FlutterLocalNotificationsPlugin(),
        platform: TargetPlatform.iOS,
      );

      expect(calls, isEmpty);
    });

    test(
        'a platform failure in the background path is swallowed (never '
        'crash the background isolate)',
        () async {
      usePlatform(TargetPlatform.android);
      failOnShow = PlatformException(code: 'cannot_post');

      await presentPushInBackground(
        message: const RemoteMessage(messageId: 'msg-bg-5'),
        plugin: FlutterLocalNotificationsPlugin(),
        platform: TargetPlatform.android,
      );
      // Reaching here without throwing is the assertion.
    });
  });
}

/// Stand-in for `FirebaseMessaging.onMessage` (a broadcast stream), the
/// same shape as `firebase_push_token_source_test.dart`'s opened-app fake.
class _FakeMessageStream extends Stream<RemoteMessage> {
  final StreamController<RemoteMessage> _controller =
      StreamController<RemoteMessage>.broadcast();

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
