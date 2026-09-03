import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration read from `--dart-define` values.
///
/// Every value is a compile-time constant. Release and CI workflows pass the
/// defines from repository secrets; local development uses
/// `flutter run --dart-define-from-file=dart_defines.json` (gitignored; see
/// `dart_defines.example.json`). An empty string means "unconfigured", and the
/// app must behave as a purely local build in that case.
///
/// Only client-safe values belong here: the Supabase publishable key and a
/// Sentry DSN are designed to ship inside the app binary. Server-side secrets
/// (database password, CLI tokens) live in `.env`, which the app never reads.
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
