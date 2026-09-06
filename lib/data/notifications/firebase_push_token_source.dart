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
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/notifications/push_registration.dart';

/// Pure branching, directly unit-testable despite living in this otherwise
/// plugin-excluded file (#10 review fix; same treatment `key_store.dart`
/// gives `isValidDbKeyHex`): which platform's FCM identifiers feed
/// [FirebaseOptions]. [FirebaseOptions] itself is a plain value class from
/// `firebase_core` with no platform-channel dependency, so constructing and
/// comparing it runs fine under `flutter test`.
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

  Future<void> _ensureInitialized() => _initFuture ??= _initialize();

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
    await _ensureInitialized();
    final controller = StreamController<String?>.broadcast();
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      controller.add(message.data['profile_id'] as String?);
    });
    unawaited(
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        final profileId = message?.data['profile_id'] as String?;
        if (profileId != null) controller.add(profileId);
      }),
    );
    yield* controller.stream;
  }
}
