/// Opens the platform's device settings from the lock screen's
/// [GateDenialReason.noCredentialEnrolled] state (issue #534): the device
/// has no screen lock at all, so `local_auth` can never present a prompt,
/// and the operator otherwise has no way to know where to go fix that.
///
/// How each platform gets there:
///
/// - **iOS** launches the `app-settings:` system scheme through
///   [safeLaunchUrl] (`url_launcher`) — unchanged; the iOS plugin handles
///   schemes via `canOpenURL` and works.
/// - **Android** cannot use `url_launcher` for this (issue #1939). A
///   settings screen is reached by an *action* intent
///   (`android.settings.SECURITY_SETTINGS`), not a URL, and
///   `url_launcher_android` 6.3.33 (`UrlLauncher.java`) builds
///   `new Intent(ACTION_VIEW).setData(Uri.parse(url))` — the raw
///   `intent://#Intent;…;end` string becomes VIEW *data* (no
///   `Intent.parseUri` anywhere in the plugin), and nothing on stock
///   Android VIEW-handles `intent:`-scheme data. Verified on-device on a
///   Pixel 8 Pro / Android 17 during the #600 device-test pass
///   (2026-11-20): the plugin's exact intent shape answered "unable to
///   resolve" while the bare action resolves fine — so the launch
///   mechanism was the broken half. The Android branch therefore calls
///   the first-party `lunarlog/device_settings` platform channel (the
///   `lunarlog/health`/`lunarlog/privacy` precedent), whose Kotlin half
///   (`DeviceSettingsAdapter.kt`, registered from `MainActivity`)
///   `startActivity()`s the real action intent and falls back — only on
///   `ActivityNotFoundException` — to this app's own App-info page
///   (`APPLICATION_DETAILS_SETTINGS` + `context.packageName`), which
///   always exists and is one tap from Security settings on every skin.
///
/// The pre-#1939 code also never noticed failure: a failed launch is a
/// `false` *return* from the launch path, not a throw, and only throws
/// reached the fallback — so the broken intent launch fell through
/// silently, with no fallback, breadcrumb, or Sentry event. Both now do:
/// a `false` from the channel (both native attempts found no handler) and
/// a channel throw reach the same breadcrumb + Sentry path.
///
/// Never throws: every platform call is best-effort, matching
/// `applyPlatformPrivacyProtections`'s posture in `gate_controller.dart` —
/// a failed settings launch must never crash the lock screen the operator
/// is trying to get past. A failure is recorded as a breadcrumb and sent
/// to Sentry (type name / message only).
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/components/safe_launch_url.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// Injectable seam for [LockScreen]'s `openDeviceSettings` field, so tests
/// substitute a fake and never touch a platform channel — same pattern as
/// `AccountSection`'s `appleAuthorizationCodeRequest`.
typedef DeviceSettingsLauncher = Future<void> Function();

/// The first-party channel the Android branch opens device settings
/// through, answered by `DeviceSettingsAdapter.kt` and registered from
/// `MainActivity.configureFlutterEngine` beside the health channel (the
/// `lunarlog/health`/`lunarlog/privacy` naming precedent).
const String kDeviceSettingsChannelName = 'lunarlog/device_settings';

/// The one method on [kDeviceSettingsChannelName]: open Security settings,
/// natively falling back to this app's App-info page when the action has
/// no handler on this skin. Answers whether anything opened.
const String _kOpenSecuritySettingsMethod = 'openSecuritySettings';

/// Injectable seam for that channel call — the same shape as the health
/// adapters' injected platform seams, so [openDeviceSettingsWith] stays
/// fully unit-testable and never touches a real [MethodChannel] under
/// `flutter test`.
typedef AndroidSecuritySettingsOpener = Future<bool> Function();

/// The platform-settings scheme this file opens. Deliberately *not*
/// [kDefaultLaunchSchemes] (http/https/mailto/tel): the only url_launcher
/// launch left here is the iOS `app-settings:` system scheme — Android
/// goes through [kDeviceSettingsChannelName] instead — and the allowlist
/// stays narrowed to exactly what this feature needs.
const Set<String> _deviceSettingsLaunchSchemes = <String>{
  'app-settings',
};

/// The iOS `UIApplicationOpenSettingsURLString` scheme — opens this app's
/// own page in the Settings app with no extra entitlement or Info.plist
/// declaration (a system scheme, not a third-party app's).
const String kIosAppSettingsUrl = 'app-settings:';

Future<bool> _launchUrl(
  Uri url, {
  LaunchMode mode = LaunchMode.platformDefault,
}) => safeLaunchUrl(
  url,
  mode: mode,
  allowedSchemes: _deviceSettingsLaunchSchemes,
);

/// The production [AndroidSecuritySettingsOpener]: one
/// `openSecuritySettings` invocation on [kDeviceSettingsChannelName]. A
/// `null` answer reads as `false` — nothing opened.
Future<bool> _openSecuritySettingsViaChannel() async =>
    await const MethodChannel(kDeviceSettingsChannelName)
        .invokeMethod<bool>(_kOpenSecuritySettingsMethod) ??
    false;

/// Real implementation, wired as [LockScreen]'s default. Only resolves the
/// platform defaults and delegates to [openDeviceSettingsWith], which holds
/// all of the behaviour and is what the unit tests exercise (the CRAP gate
/// scores untested platform-channel code harshly, so the logic and the
/// platform glue are deliberately kept in separate functions).
Future<void> defaultOpenDeviceSettings({BreadcrumbLog? breadcrumbLog}) =>
    openDeviceSettingsWith(
      breadcrumbLog: breadcrumbLog ?? defaultBreadcrumbLog,
      launch: _launchUrl,
      openSecuritySettings: _openSecuritySettingsViaChannel,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );

/// The behaviour behind [defaultOpenDeviceSettings], with every platform
/// dependency injected.
///
/// iOS: launches [kIosAppSettingsUrl] through [launch].
///
/// Android: calls [openSecuritySettings] — the `lunarlog/device_settings`
/// channel in production, which `startActivity()`s the SECURITY_SETTINGS
/// action and falls back natively (only on `ActivityNotFoundException`) to
/// this app's own App-info page. A `false` return means even the fallback
/// found no handler; a throw means the channel itself failed. **Both**
/// reach the breadcrumb + Sentry path in [_openAndroidSecuritySettings]
/// (issue #1939: a failed launch used to be a silent `false`).
///
/// Web and every other platform: no-op — there is no gate there.
Future<void> openDeviceSettingsWith({
  required BreadcrumbLog breadcrumbLog,
  required LaunchUrlFn launch,
  required AndroidSecuritySettingsOpener openSecuritySettings,
  required TargetPlatform platform,
  required bool isWeb,
}) async {
  if (isWeb) return;
  try {
    if (platform == TargetPlatform.iOS) {
      await launch(Uri.parse(kIosAppSettingsUrl));
      return;
    }
    if (platform != TargetPlatform.android) return;
    await _openAndroidSecuritySettings(breadcrumbLog, openSecuritySettings);
  } catch (error, stackTrace) {
    breadcrumbLog.record('gate', error.runtimeType.toString());
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}

Future<void> _openAndroidSecuritySettings(
  BreadcrumbLog log,
  AndroidSecuritySettingsOpener openSecuritySettings,
) async {
  final bool opened;
  try {
    opened = await openSecuritySettings();
  } catch (error, stackTrace) {
    // The channel itself failed (not merely answered `false`). Issue
    // #1939's rule: a throw and a `false` get the same treatment — plus
    // the exception details for Sentry.
    log.record('gate', 'AndroidSecuritySettingsUnavailable');
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    return;
  }
  if (!opened) {
    // The native half tried SECURITY_SETTINGS and its App-info fallback
    // and neither resolved — there is nothing left to attempt, so record
    // it and tell Sentry. Issue #1939: this used to flow through
    // silently, because a failed launch was a `false` return, not a
    // throw, and only throws reached the failure path.
    log.record('gate', 'AndroidSecuritySettingsUnavailable');
    unawaited(
      Sentry.captureMessage('gate: AndroidSecuritySettingsUnavailable'),
    );
  }
}
