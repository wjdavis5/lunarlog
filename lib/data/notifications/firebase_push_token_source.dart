/// [PushTokenSource] adapter over `firebase_messaging` (Issue #5, U7; KTD6).
///
/// `FirebaseOptions` are built entirely from [AppConfig] - deliberately no
/// `google-services.json`, no `GoogleService-Info.plist`, and no Google
/// Services Gradle plugin, so `AppConfig.hasPush` gates this file's every
/// code path and an unconfigured build never links Firebase at runtime
/// (R17, R18, R22). Excluded from the coverage/CRAP gate
/// (`tool/quality/exclusions.dart`): a pure plugin adapter with no
/// branching logic worth testing in isolation, the same treatment as
/// `google_sign_in_client.dart`.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/notifications/push_registration.dart';

class FirebasePushTokenSource implements PushTokenSource {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: isIOS ? AppConfig.fcmIosApiKey : AppConfig.fcmAndroidApiKey,
        appId: isIOS ? AppConfig.fcmIosAppId : AppConfig.fcmAndroidAppId,
        messagingSenderId: AppConfig.fcmSenderId,
        projectId: AppConfig.fcmProjectId,
      ),
    );
    _initialized = true;
  }

  @override
  Future<String?> currentToken() async {
    await _ensureInitialized();
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<String> tokenRefreshes() => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<String?> taps() {
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
    return controller.stream;
  }
}
