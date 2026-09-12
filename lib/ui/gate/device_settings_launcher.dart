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

/// The Android intent URI for the Security settings screen
/// (`android.provider.Settings.ACTION_SECURITY_SETTINGS`), where the
/// screen-lock/passcode setup lives on stock Android.
const String kAndroidSecuritySettingsIntent =
    'intent://#Intent;action=android.settings.SECURITY_SETTINGS;end';

/// Real implementation, wired as [LockScreen]'s default.
///
/// iOS: `app-settings:` is Apple's documented
/// `UIApplicationOpenSettingsURLString` — it opens this app's own page in
/// the Settings app and needs no extra entitlement or Info.plist
/// declaration (it is a system scheme, not a third-party app's).
///
/// Android: there is no single plain-URL scheme for "Security > screen
/// lock" the way there is for notification settings, but
/// `url_launcher_android` can launch an `intent://` URI directly. This
/// tries [kAndroidSecuritySettingsIntent] first; some OEM skins don't
/// expose that screen under this exact action, so a failed launch falls
/// back to this app's own "App info" page
/// (`ACTION_APPLICATION_DETAILS_SETTINGS`), which always exists and gets
/// the operator one tap from Security settings regardless of skin. The
/// package name comes from `package_info_plus` (already a dependency)
/// rather than a hardcoded `applicationId`.
///
/// Never throws: every platform call is best-effort, matching
/// `applyPlatformPrivacyProtections`'s posture in `gate_controller.dart` —
/// a failed settings launch must never crash the lock screen the operator
/// is trying to get past.
Future<void> defaultOpenDeviceSettings({
  BreadcrumbLog? breadcrumbLog,
}) async {
  final log = breadcrumbLog ?? defaultBreadcrumbLog;
  if (kIsWeb) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await launchUrl(Uri.parse('app-settings:'));
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _openAndroidSecuritySettings(log);
  } catch (error, stackTrace) {
    log.record('gate', error.runtimeType.toString());
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}

Future<void> _openAndroidSecuritySettings(BreadcrumbLog log) async {
  try {
    await launchUrl(
      Uri.parse(kAndroidSecuritySettingsIntent),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // Some OEM skins don't expose SECURITY_SETTINGS under this exact
    // action — fall back to this app's own settings page, which always
    // exists and is one tap from Security settings on every skin.
    log.record('gate', 'AndroidSecuritySettingsUnavailable');
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    await launchUrl(
      Uri.parse(
        'intent://#Intent;'
        'action=android.settings.APPLICATION_DETAILS_SETTINGS;'
        'package=$packageName;end',
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}
