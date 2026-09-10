/// [PushTokenSource] adapter over `firebase_messaging` (Issue #5, U7; KTD6).
///
/// `FirebaseOptions` are built entirely from [AppConfig] - deliberately no
/// `google-services.json`, no `GoogleService-Info.plist`, and no Google
/// Services Gradle plugin, so `AppConfig.hasPush` gates this file's every
/// code path and an unconfigured build never links Firebase at runtime
/// (R17, R18, R22).
///
/// Excluded from the coverage/CRAP gate (`tool/quality/exclusions.dart`) --
/// but, per #10 (review fix), *not* because it has no branching worth
/// testing: it previously claimed that while quietly hiding the exact
/// sequencing bugs #4 (missing `requestPermission()`) and #5
/// (`FirebaseMessaging.instance` touched before `Firebase.initializeApp()`
/// completed) shipped in. What is actually excluded is only the
/// plugin-bound calls themselves (`Firebase.initializeApp`,
/// `requestPermission`, `getToken`, the two `FirebaseMessaging` stream
/// getters) -- none of which can run under `flutter test` without a real
/// platform channel. [buildFirebaseOptions] pulls the one piece of pure
/// branching logic (which platform's FCM identifiers to use) out into a
/// directly unit-tested function, and [FirebasePushTokenSource]'s own
/// sequencing (initialize-then-request-permission-then-touch-Firebase-
/// Messaging, exactly once, memoized against concurrent callers) is
/// covered indirectly through `PushRegistrationCoordinator`'s tests against
/// a fake `PushTokenSource` that models the same ordering contract.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/notifications/push_registration.dart';

/// Pure branching, directly unit-testable despite living in this otherwise
/// plugin-excluded file (#10 review fix): which platform's FCM identifiers
/// feed [FirebaseOptions]. [FirebaseOptions] itself is a plain value class
/// from `firebase_core` with no platform-channel dependency, so
/// constructing and comparing it runs fine under `flutter test`.
FirebaseOptions buildFirebaseOptions({
  required bool isIOS,
  required String iosApiKey,
  required String iosAppId,
  required String androidApiKey,
  required String androidAppId,
  required String senderId,
  required String projectId,
}) {
  return FirebaseOptions(
    apiKey: isIOS ? iosApiKey : androidApiKey,
    appId: isIOS ? iosAppId : androidAppId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}

class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource()
      : openedAppMessages = null,
        initialMessage = null;

  /// Testing seams (#206 C-26): when both are supplied they stand in for
  /// the plugin-bound `FirebaseMessaging.onMessageOpenedApp` stream and
  /// `FirebaseMessaging.instance.getInitialMessage()` future on the
  /// [taps] path, and that path skips Firebase initialization entirely
  /// (nothing plugin-bound is touched). Every real caller constructs this
  /// class with the default constructor and behaves exactly as before.
  @visibleForTesting
  FirebasePushTokenSource.forTesting({
    required this.openedAppMessages,
    required this.initialMessage,
  });

  /// The [taps]-path stand-in for `FirebaseMessaging.onMessageOpenedApp`;
  /// null in production builds.
  @visibleForTesting
  final Stream<RemoteMessage>? openedAppMessages;

  /// The [taps]-path stand-in for
  /// `FirebaseMessaging.instance.getInitialMessage()`; null in production
  /// builds.
  @visibleForTesting
  final Future<RemoteMessage?>? initialMessage;

  // #5/#4 (review): a single memoized in-flight Future rather than a bare
  // `bool _initialized` -- every public method below (currentToken,
  // tokenRefreshes, taps) must run this exact same initialization before
  // touching FirebaseMessaging.instance for the first time, including when
  // PushRegistrationCoordinator.start() calls more than one of them back to
  // back with no await in between (it does: tokenRefreshes().listen(...)
  // and taps().listen(...) are both called synchronously before
  // _registerCurrentToken()'s first await). A bare bool flag would let two
  // concurrent callers both see it false and both call
  // Firebase.initializeApp(), the second of which throws
  // "[core/duplicate-app]". Caching the Future itself makes every caller
  // await the same one initialization.
  Future<void>? _initFuture;

  // Round-2 review #4: a bare `_initFuture ??= _initialize()` memoizes the
  // *rejected* Future forever once Firebase.initializeApp() or
  // requestPermission() throws (a transient network blip is enough) --
  // every later currentToken()/tokenRefreshes()/taps() call re-awaits that
  // same failure, silently disabling push for the rest of the process. The
  // catchError here clears _initFuture back to null before rethrowing, so
  // the *next* call starts a fresh attempt instead of replaying the same
  // dead one, restoring the "a later refresh or app restart retries"
  // contract PushRegistrationCoordinator's own comment already promises.
  Future<void> _ensureInitialized() {
    return _initFuture ??= _initialize().catchError((Object error, StackTrace stackTrace) {
      _initFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _initialize() async {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    await Firebase.initializeApp(
      options: buildFirebaseOptions(
        isIOS: isIOS,
        iosApiKey: AppConfig.fcmIosApiKey,
        iosAppId: AppConfig.fcmIosAppId,
        androidApiKey: AppConfig.fcmAndroidApiKey,
        androidAppId: AppConfig.fcmAndroidAppId,
        senderId: AppConfig.fcmSenderId,
        projectId: AppConfig.fcmProjectId,
      ),
    );
    // #4 (review): without this, iOS never asks the user for notification
    // permission, so APNs never issues a token and getToken() below stays
    // null forever on that platform. Android's runtime notification
    // permission (API 33+) is folded into the same call by the plugin.
    await FirebaseMessaging.instance.requestPermission();
  }

  @override
  Future<String?> currentToken() async {
    await _ensureInitialized();
    return FirebaseMessaging.instance.getToken();
  }

  // #5 (review): async* generator bodies do not run until the returned
  // Stream is listened to, but once listened they run to the first
  // yield/yield* before emitting anything -- so the await below always
  // completes before this touches FirebaseMessaging.instance, for every
  // caller, including the disused-token-refresh path (a subscription that
  // starts, then is cancelled before it ever fires) that a bare getter
  // couldn't guard at all.
  @override
  Stream<String> tokenRefreshes() async* {
    await _ensureInitialized();
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }

  @override
  Stream<String?> taps() async* {
    // #206 (C-26): with the testing seams in place nothing plugin-bound is
    // reachable, so skip the (real) initialization they would otherwise
    // require.
    if (openedAppMessages == null && initialMessage == null) {
      await _ensureInitialized();
    }
    yield* bridgeTaps(
      openedApp: openedAppMessages ?? FirebaseMessaging.onMessageOpenedApp,
      initialMessage:
          initialMessage ?? FirebaseMessaging.instance.getInitialMessage(),
    );
  }

  /// The [taps] stream's bridge from the Firebase sources to the
  /// `profile_id` payload contract (#206 C-26). Static and
  /// [visibleForTesting] so the subscription lifecycle — the exact thing
  /// this issue fixes — is directly assertable under `flutter test`:
  /// previously taps() listened to the opened-app stream without ever
  /// holding the subscription and never closed the broadcast controller,
  /// so every device-reset generation of `taps()` permanently attached
  /// another listener and a single notification tap was delivered to every
  /// coordinator ever created in the session. Now cancelling the returned
  /// stream cancels the inner [openedApp] subscription and closes the
  /// controller; the [initialMessage] callback is additionally guarded so
  /// a cold-start payload resolving after that cancellation cannot touch a
  /// closed controller.
  @visibleForTesting
  static Stream<String?> bridgeTaps({
    required Stream<RemoteMessage> openedApp,
    required Future<RemoteMessage?> initialMessage,
  }) async* {
    final controller = StreamController<String?>.broadcast();
    late final StreamSubscription<RemoteMessage> openedAppSub;
    controller.onCancel = () {
      final cancelled = openedAppSub.cancel();
      // Not awaited: `close()` completes through the controller's `done`
      // future, which itself waits on this very onCancel callback --
      // awaiting it here would deadlock the cancellation.
      unawaited(controller.close());
      return cancelled;
    };
    openedAppSub = openedApp.listen((message) {
      controller.add(message.data['profile_id'] as String?);
    });
    unawaited(initialMessage.then((message) {
      final profileId = message?.data['profile_id'] as String?;
      if (profileId != null && !controller.isClosed) controller.add(profileId);
    }));
    yield* controller.stream;
  }
}
