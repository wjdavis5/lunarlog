/// Opens the platform's device settings from the lock screen's
/// [GateDenialReason.noCredentialEnrolled] state (issue #534): the device
/// has no screen lock at all, so `local_auth` can never present a prompt,
/// and the operator otherwise has no way to know where to go fix that.
///
/// Neither `app_settings` nor `url_launcher` was a dependency of this repo
/// before this issue. `app_settings` was checked first and is not present,
/// so this uses `url_launcher` instead — a very common, well-maintained
/// package already pulled in transitively by nothing else here (see the
/// `pubspec.yaml` comment next to it).
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Injectable seam for [LockScreen]'s `openDeviceSettings` field, so tests
/// substitute a fake and never touch `url_launcher`'s platform channel —
/// same pattern as `AccountSection`'s `appleAuthorizationCodeRequest`.
typedef DeviceSettingsLauncher = Future<void> Function();

/// The `url_launcher` call shape [openDeviceSettingsWith] depends on,
/// narrowed to the two arguments it actually uses so a test can substitute
/// a recording fake without depending on the package's own surface.
typedef LaunchUrlFn = Future<bool> Function(Uri url, {LaunchMode mode});

/// Resolves this app's Android package name for the App-info fallback
/// intent. Real implementation reads `package_info_plus`.
typedef PackageNameProvider = Future<String> Function();

/// The Android intent URI for the Security settings screen
/// (`android.provider.Settings.ACTION_SECURITY_SETTINGS`), where the
/// screen-lock/passcode setup lives on stock Android.
const String kAndroidSecuritySettingsIntent =
    'intent://#Intent;action=android.settings.SECURITY_SETTINGS;end';

/// The iOS `UIApplicationOpenSettingsURLString` scheme — opens this app's
/// own page in the Settings app with no extra entitlement or Info.plist
/// declaration (a system scheme, not a third-party app's).
const String kIosAppSettingsUrl = 'app-settings:';

/// The App-info fallback intent for [packageName] — see
/// [openDeviceSettingsWith] for why it exists.
String androidAppDetailsIntent(String packageName) =>
    'intent://#Intent;'
    'action=android.settings.APPLICATION_DETAILS_SETTINGS;'
    'package=$packageName;end';

Future<bool> _launchUrl(
  Uri url, {
  LaunchMode mode = LaunchMode.platformDefault,
}) => launchUrl(url, mode: mode);

Future<String> _packageName() async =>
    (await PackageInfo.fromPlatform()).packageName;

/// Real implementation, wired as [LockScreen]'s default. Only resolves the
/// platform defaults and delegates to [openDeviceSettingsWith], which holds
/// all of the behaviour and is what the unit tests exercise (the CRAP gate
/// scores untested platform-channel code harshly, so the logic and the
/// platform glue are deliberately kept in separate functions).
Future<void> defaultOpenDeviceSettings({BreadcrumbLog? breadcrumbLog}) =>
    openDeviceSettingsWith(
      breadcrumbLog: breadcrumbLog ?? defaultBreadcrumbLog,
      launch: _launchUrl,
      packageName: _packageName,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );

/// The behaviour behind [defaultOpenDeviceSettings], with every platform
/// dependency injected.
///
/// iOS: launches [kIosAppSettingsUrl].
///
/// Android: there is no single plain-URL scheme for "Security > screen
/// lock" the way there is for notification settings, but
/// `url_launcher_android` can launch an `intent://` URI directly. This
/// tries [kAndroidSecuritySettingsIntent] first; some OEM skins don't
/// expose that screen under this exact action, so a failed launch falls
/// back to this app's own "App info" page
/// (`ACTION_APPLICATION_DETAILS_SETTINGS`), which always exists and gets
/// the operator one tap from Security settings regardless of skin. The
/// package name comes from [packageName] (`package_info_plus` in
/// production) rather than a hardcoded `applicationId`.
///
/// Web and every other platform: no-op — there is no gate there.
///
/// Never throws: every platform call is best-effort, matching
/// `applyPlatformPrivacyProtections`'s posture in `gate_controller.dart` —
/// a failed settings launch must never crash the lock screen the operator
/// is trying to get past. A failure is recorded as a breadcrumb and sent
/// to Sentry (type name only).
Future<void> openDeviceSettingsWith({
  required BreadcrumbLog breadcrumbLog,
  required LaunchUrlFn launch,
  required PackageNameProvider packageName,
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
    await _openAndroidSecuritySettings(breadcrumbLog, launch, packageName);
  } catch (error, stackTrace) {
    breadcrumbLog.record('gate', error.runtimeType.toString());
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}

Future<void> _openAndroidSecuritySettings(
  BreadcrumbLog log,
  LaunchUrlFn launch,
  PackageNameProvider packageName,
) async {
  try {
    await launch(
      Uri.parse(kAndroidSecuritySettingsIntent),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // Some OEM skins don't expose SECURITY_SETTINGS under this exact
    // action — fall back to this app's own settings page, which always
    // exists and is one tap from Security settings on every skin.
    log.record('gate', 'AndroidSecuritySettingsUnavailable');
    await launch(
      Uri.parse(androidAppDetailsIntent(await packageName())),
      mode: LaunchMode.externalApplication,
    );
  }
}
