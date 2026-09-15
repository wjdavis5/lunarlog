/// FCM foreground/background presentation (Issue #174): the client half of
/// caregiver-alert delivery the server has always sent but nothing handled
/// — a foreground `onMessage` subscription presenting through
/// `flutter_local_notifications`, a top-level background handler registered
/// before `runApp()`, and the pure decision function both share.
///
/// Like everything FCM in this app, the plugin-bound paths are reachable
/// only behind `AppConfig.hasPush` (the composition root and `main.dart`
/// gate on it; the FCM `dart-define`s are empty in CI and on forks), so an
/// unconfigured build never touches firebase_messaging. The one decision
/// worth testing — *whether* an incoming push must be presented, and with
/// exactly what content — is [pushNotificationPresentation], a pure
/// function whose discretion rule (fixed generic copy only, never anything
/// read from the payload) is pinned by `test/data/notifications/
/// push_presentation_test.dart` the same way `notification_copy.ts` is
/// pinned server-side: the push payload is content-free by server design
/// (see `notification_outbox`), and this code must never become the thing
/// that surfaces payload fields even if one ever appears.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';

/// What an incoming push presents when this app itself must present it.
@immutable
class PushNotificationPresentation {
  const PushNotificationPresentation({
    required this.id,
    required this.title,
    required this.body,
    required this.channelId,
  });

  /// The notification id. Derived deterministically from the FCM message id
  /// via [stableReminderId] (the same 31-bit hash reminders use), so a
  /// redelivered message replaces its own earlier presentation rather than
  /// stacking a duplicate.
  final int id;

  /// Always [kReminderTitle] — never anything read from [pushNotificationPresentation]'s
  /// `data` argument.
  final String title;

  /// Always [kReminderBody].
  final String body;

  /// Always [kReminderChannelId] — the same "Reminders" channel locally
  /// scheduled notifications are posted on.
  final String channelId;
}

/// Decides whether this app itself must present a local notification for an
/// incoming FCM message, and with exactly what content (Issue #174).
///
/// The `data` map is **accepted and deliberately never read** — that is the
/// discretion rule made structural: whatever a payload carries (or a future
/// server bug makes it carry), the presented copy stays the fixed generic
/// [kReminderTitle]/[kReminderBody], character-for-character the strings the
/// server's own `notification_copy.ts` sends and locally scheduled
/// reminders show. The tests pin this by feeding a payload full of
/// health-looking fields and asserting the exact fixed strings back.
///
/// Who presents what:
///
/// * A message carrying FCM's own `notification` payload while the app is
///   backgrounded or terminated is presented by the OS itself (Android's
///   tray presentation via the manifest meta-data; iOS's notification
///   center) — presenting again here would double every alert, so the
///   answer is null. (On Android the handler usually is not even invoked
///   for such messages; the guard is defence in depth for the paths where
///   it is, e.g. iOS's background callback.)
/// * A notification-carrying message while the app is foregrounded on iOS
///   is presented by the system too, because startup calls
///   `setForegroundNotificationPresentationOptions(alert: true, badge:
///   true, sound: true)` (`firebase_push_token_source.dart`). Null again.
/// * A notification-carrying message while the app is foregrounded on
///   Android is presented by nobody — FCM never auto-presents in the
///   foreground — so this app must, through `flutter_local_notifications`.
/// * A data-only message is presented by nobody on either platform, in
///   either lifecycle state, so this app must.
PushNotificationPresentation? pushNotificationPresentation({
  required Map<String, dynamic> data,
  required String? messageId,
  required bool hasNotificationPayload,
  required bool isIOS,
  required bool isBackground,
}) {
  if (hasNotificationPayload && (isBackground || isIOS)) return null;
  return PushNotificationPresentation(
    id: stableReminderId('fcm_push|$messageId'),
    title: kReminderTitle,
    body: kReminderBody,
    channelId: kReminderChannelId,
  );
}

/// Presents a foreground (`onMessage`) push through
/// `flutter_local_notifications`. Started next to the push-registration
/// coordinator (same `AppConfig.hasPush` gate, `lib/app_root.dart`) and
/// disposed with it; construction lives in `lib/composition/`.
///
/// The presentation decision runs per message through
/// [pushNotificationPresentation], so an iOS foreground notification
/// payload — which the system presents via the startup presentation
/// options — is *not* shown a second time here, while an Android foreground
/// message (any shape) and a data-only message (any platform) are, always
/// with the fixed generic copy on the "Reminders" channel.
class PushForegroundPresenter {
  PushForegroundPresenter({
    Stream<RemoteMessage>? messages,
    FlutterLocalNotificationsPlugin? plugin,
    bool? isIOS,
    BreadcrumbLog? breadcrumbLog,
  })  : _messages = messages ?? FirebaseMessaging.onMessage,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _isIOS = isIOS ?? (defaultTargetPlatform == TargetPlatform.iOS),
        _breadcrumbLog = breadcrumbLog ?? defaultBreadcrumbLog;

  /// Testing seam, standing in for `FirebaseMessaging.onMessage` (a static
  /// broadcast stream — subscribing before `Firebase.initializeApp()` is
  /// harmless; events only flow once the native side is attached).
  final Stream<RemoteMessage> _messages;

  /// The process-wide `flutter_local_notifications` singleton (the factory
  /// constructor returns one shared instance) — the same native plugin the
  /// reminder scheduler initialized, so `show` lands on the already-created
  /// "Reminders" channel and response callback.
  final FlutterLocalNotificationsPlugin _plugin;

  /// `defaultTargetPlatform == TargetPlatform.iOS`, injectable for tests.
  final bool _isIOS;

  final BreadcrumbLog _breadcrumbLog;

  StreamSubscription<RemoteMessage>? _subscription;
  bool _disposed = false;

  void start() {
    if (_disposed || _subscription != null) return;
    _subscription = _messages.listen(
      (message) => unawaited(_present(message)),
      onError: (Object error) {
        _breadcrumbLog.record('push_present', error.runtimeType.toString());
      },
    );
  }

  Future<void> _present(RemoteMessage message) async {
    final presentation = pushNotificationPresentation(
      data: message.data,
      messageId: message.messageId,
      hasNotificationPayload: message.notification != null,
      isIOS: _isIOS,
      isBackground: false,
    );
    if (presentation == null) return;
    try {
      await _plugin.show(
        id: presentation.id,
        title: presentation.title,
        body: presentation.body,
        notificationDetails:
            NotificationDetails(android: reminderNotificationDetails()),
      );
    } catch (error) {
      // Best-effort, like every notification path in this app: a platform
      // failure (e.g. `show` racing the scheduler's own `initialize` at
      // first launch) must never escape into the widget tree.
      _breadcrumbLog.record('push_present', error.runtimeType.toString());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// The FCM background handler (Issue #174). Top-level and
/// `@pragma('vm:entry-point')`-annotated because firebase_messaging's own
/// dispatcher runs it in a background Flutter engine on Android (the app's
/// `main()` is *not* re-executed there — the plugin looks the callback up
/// by handle) and on the app isolate on iOS. Registered before `runApp()`
/// in `lib/main.dart`, gated on `AppConfig.hasPush`; this declaration is
/// what backs the `remote-notification` `UIBackgroundModes` entry in
/// `ios/Runner/Info.plist`.
///
/// The handler never touches the database, the gate, or Supabase — a
/// background context has none of them, and a caregiver alert needs nothing
/// beyond the same fixed generic presentation a locally scheduled reminder
/// gets. All real logic lives in [presentPushInBackground], which is
/// directly testable against the mocked platform channel.
@pragma('vm:entry-point')
Future<void> pushBackgroundMessageHandler(RemoteMessage message) =>
    presentPushInBackground(
      message: message,
      plugin: FlutterLocalNotificationsPlugin(),
      platform: defaultTargetPlatform,
    );

/// The background handler's testable core (Issue #174): present [message]
/// if — and only if — [pushNotificationPresentation] says this app must.
@visibleForTesting
Future<void> presentPushInBackground({
  required RemoteMessage message,
  required FlutterLocalNotificationsPlugin plugin,
  required TargetPlatform platform,
}) async {
  final presentation = pushNotificationPresentation(
    data: message.data,
    messageId: message.messageId,
    hasNotificationPayload: message.notification != null,
    isIOS: platform == TargetPlatform.iOS,
    isBackground: true,
  );
  if (presentation == null) return;
  try {
    if (platform == TargetPlatform.android) {
      // The Android background engine has never run the scheduler's
      // `initialize()`: initialize a minimal, callback-less plugin here
      // (re-)creating the "Reminders" channel — channel creation is
      // idempotent, and channels persist OS-wide once created. No response
      // callback is registered because action handling belongs to the
      // running, gate-aware app, exactly like the LLA-028 posture in
      // `notification_scheduler.dart`.
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(kReminderNotificationChannel);
    }
    // On iOS the handler runs on the app isolate, where the scheduler has
    // already initialized the plugin — calling initialize() again here
    // would replace its registered response callback (the reminder action
    // buttons), so only Android initializes.
    await plugin.show(
      id: presentation.id,
      title: presentation.title,
      body: presentation.body,
      notificationDetails:
          NotificationDetails(android: reminderNotificationDetails()),
    );
  } catch (error) {
    // Never let a platform failure crash the background isolate.
    debugPrint(
        'lunarlog push: background presentation failed (${error.runtimeType})');
  }
}
