import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration read from `--dart-define` values.
///
/// Every value is a compile-time constant. Release and CI workflows pass the
/// defines from repository secrets; local development uses
/// `flutter run --dart-define-from-file=dart_defines.json` (gitignored; see
/// `dart_defines.example.json`). An empty string means "unconfigured", and the
/// app must behave as a purely local build in that case.
///
/// Only client-safe values belong here: the Supabase publishable key, a
/// Sentry DSN, and Google OAuth client ids are designed to ship inside the
/// app binary. Server-side secrets (database password, CLI tokens) live in
/// `.env`, which the app never reads.
///
/// Google client ids (#2 U1; KTD2): client-safe, but they still come from
/// defines rather than literals so forks and PR builds compile with empty
/// values and simply hide Google Sign-In.
abstract final class AppConfig {
  /// Supabase project URL (`https://<ref>.supabase.co`).
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase publishable (`sb_publishable_...`) key. In CI this comes from
  /// the `SUPABASE_ANON_KEY` repository secret, which already holds the
  /// publishable key.
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Sentry DSN. Empty disables crash reporting entirely.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Raw value of `LUNARLOG_WEB_SYNC`; only the literal `true` opts a web
  /// build into account sign-in and sync. Never set in CI.
  static const String _webSyncRaw = String.fromEnvironment('LUNARLOG_WEB_SYNC');

  /// True only when the build was compiled with `LUNARLOG_WEB_SYNC=true`.
  static const bool webSyncEnabled = _webSyncRaw == 'true';

  /// True when Supabase is configured for this build and platform. On web,
  /// this additionally requires [webSyncEnabled]: a signed-in web session
  /// would hold a bearer token in browser storage, so a default web build
  /// opts out of accounts entirely.
  ///
  /// Kept as a `const` expression (Dart forbids function calls in constant
  /// initializers) so unconfigured code paths tree-shake; [computeHasSupabase]
  /// is the same rule as a testable function, and `test/config_test.dart`
  /// asserts the two agree.
  static const bool hasSupabase = supabaseUrl != '' &&
      supabasePublishableKey != '' &&
      (!kIsWeb || webSyncEnabled);

  /// True when a Sentry DSN was supplied. Mirrors [computeHasSentry].
  static const bool hasSentry = sentryDsn != '';

  /// Google OAuth iOS client id (`GOOGLE_IOS_CLIENT_ID`). Client-safe, but
  /// still a define so forks and CI build with an empty value (#2 U1; KTD2).
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Google OAuth Web client id (`GOOGLE_WEB_CLIENT_ID`), the audience of the
  /// Android ID token. Client-safe, but still a define so forks and CI build
  /// with an empty value (#2 U1; KTD2).
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// True when native Google Sign-In is available for this build and
  /// platform: Supabase configured, not web, and both client ids supplied.
  /// Web builds never show Google regardless of defines (#2 U1; KTD2).
  ///
  /// Kept as a `const` expression (Dart forbids function calls in constant
  /// initializers) so unconfigured code paths tree-shake; [computeHasGoogle]
  /// is the same rule as a testable function, and `test/config_test.dart`
  /// asserts the two agree.
  static const bool hasGoogle = hasSupabase &&
      !kIsWeb &&
      googleIosClientId != '' &&
      googleWebClientId != '';

  /// Firebase project id, shared by both platforms (Issue #5, U7).
  static const String fcmProjectId = String.fromEnvironment('FCM_PROJECT_ID');

  /// Firebase Cloud Messaging sender id (the GCM/FCM project number).
  static const String fcmSenderId = String.fromEnvironment('FCM_SENDER_ID');

  /// Android `google-services.json`'s `current_key` equivalent — client-safe
  /// per Firebase's own model, but still a define so forks/PR builds compile
  /// with an empty value (KTD6, mirroring Google Sign-In's #2 U1 precedent).
  static const String fcmAndroidApiKey =
      String.fromEnvironment('FCM_ANDROID_API_KEY');

  /// Android Firebase app id (`1:...:android:...`).
  static const String fcmAndroidAppId =
      String.fromEnvironment('FCM_ANDROID_APP_ID');

  /// iOS `GoogleService-Info.plist`'s `API_KEY` equivalent.
  static const String fcmIosApiKey = String.fromEnvironment('FCM_IOS_API_KEY');

  /// iOS Firebase app id (`1:...:ios:...`).
  static const String fcmIosAppId = String.fromEnvironment('FCM_IOS_APP_ID');

  /// True when push is configured for this build and platform: Supabase
  /// configured, not web, and every `FCM_*` define supplied (R17, R18).
  /// `Firebase.initializeApp(options:)` is built from these — never from a
  /// checked-in `google-services.json`/`GoogleService-Info.plist` (KTD6) —
  /// so an unconfigured build (empty defines) never touches Firebase at all.
  ///
  /// Kept as a `const` expression (Dart forbids function calls in constant
  /// initializers) so unconfigured code paths tree-shake; [computeHasPush]
  /// is the same rule as a testable function, and `test/config_test.dart`
  /// asserts the two agree.
  static const bool hasPush = hasSupabase &&
      !kIsWeb &&
      fcmProjectId != '' &&
      fcmSenderId != '' &&
      fcmAndroidApiKey != '' &&
      fcmAndroidAppId != '' &&
      fcmIosApiKey != '' &&
      fcmIosAppId != '';
}

/// Pure decision behind [AppConfig.webSyncEnabled]: the literal `true` only.
/// Case variants (`TRUE`), `1`, and padded strings all count as off.
bool parseWebSyncEnabled(String raw) => raw == 'true';

/// Pure decision behind [AppConfig.hasSupabase].
///
/// Requires a non-empty URL and key; on web it further requires
/// [webSyncEnabled]. Exposed as a function so the rule is unit-testable even
/// though the production inputs are compile-time constants.
bool computeHasSupabase({
  required String url,
  required String publishableKey,
  required bool isWeb,
  required bool webSyncEnabled,
}) {
  if (url.isEmpty || publishableKey.isEmpty) return false;
  if (isWeb && !webSyncEnabled) return false;
  return true;
}

/// Pure decision behind [AppConfig.hasSentry]: any non-empty DSN.
bool computeHasSentry(String dsn) => dsn.isNotEmpty;

/// Pure decision behind [AppConfig.hasGoogle] (#2 U1; KTD2).
///
/// Requires [hasSupabase], a non-web platform, and non-empty iOS and Web
/// client ids. Exposed as a function so the rule is unit-testable even
/// though the production inputs are compile-time constants.
bool computeHasGoogle({
  required bool hasSupabase,
  required bool isWeb,
  required String iosClientId,
  required String webClientId,
}) {
  if (!hasSupabase || isWeb) return false;
  if (iosClientId.isEmpty || webClientId.isEmpty) return false;
  return true;
}

/// Pure decision behind [AppConfig.hasPush] (Issue #5, U7).
///
/// Requires [hasSupabase], a non-web platform, and every `FCM_*` value
/// non-empty. Exposed as a function so the rule is unit-testable even
/// though the production inputs are compile-time constants.
bool computeHasPush({
  required bool hasSupabase,
  required bool isWeb,
  required String projectId,
  required String senderId,
  required String androidApiKey,
  required String androidAppId,
  required String iosApiKey,
  required String iosAppId,
}) {
  if (!hasSupabase || isWeb) return false;
  if (projectId.isEmpty || senderId.isEmpty) return false;
  if (androidApiKey.isEmpty || androidAppId.isEmpty) return false;
  if (iosApiKey.isEmpty || iosAppId.isEmpty) return false;
  return true;
}
