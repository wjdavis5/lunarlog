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
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';

void main() {
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
