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

  /// Passkey relying-party id: a bare HTTPS domain (e.g. `example.com`, no
  /// scheme), supplied by `PASSKEY_RP_ID`.
  ///
  /// This value is **immutable once the first passkey is enrolled** for that
  /// domain - changing it later orphans every credential enrolled against
  /// the old id. It is chosen by a human release operator, never inferred or
  /// defaulted (#30 U1; KTD3). See `docs/ops/supabase-go-live.md`'s Passkeys
  /// section for the full activation checklist.
  ///
  /// No workflow (`ci.yml`, `ios-release.yml`, `play-store-release.yml`)
  /// passes this define today, so [hasPasskeys] resolves to `false` in every
  /// build that exists - CI, forks, PR builds, TestFlight, and Play
  /// internal. Do **not** "fix" that omission by adding the define to a
  /// workflow; turning the feature on is a deliberate, separate release
  /// action gated on the human prerequisites in `docs/ops/supabase-go-live.md`.
  ///
  /// The client never sends this value to the server - Supabase's
  /// `gotrue` returns the relying-party id inside the WebAuthn options it
  /// issues (#30 KTD1). It is held here because the iOS Associated Domains
  /// entitlement and the Android manifest need the same literal at
  /// activation, and because it is the honest name for "which relying party
  /// is this build for".
  static const String passkeyRelyingPartyId =
      String.fromEnvironment('PASSKEY_RP_ID');

  /// True when passkey support is available for this build and platform:
  /// Supabase configured, not web, and a relying-party id supplied (#30 U1;
  /// KTD3). Web passkeys are out of scope (Non-goals) so web is excluded
  /// outright, on the same terms as [hasGoogle].
  ///
  /// Kept as a `const` expression (Dart forbids function calls in constant
  /// initializers) so unconfigured code paths tree-shake; [computeHasPasskeys]
  /// is the same rule as a testable function, and `test/config_test.dart`
  /// asserts the two agree.
  static const bool hasPasskeys =
      hasSupabase && !kIsWeb && passkeyRelyingPartyId != '';
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

/// Pure decision behind [AppConfig.hasPasskeys] (#30 U1; KTD3).
///
/// Requires [hasSupabase], a non-web platform, and a non-empty relying-party
/// id. Exposed as a function so the rule is unit-testable even though the
/// production inputs are compile-time constants.
bool computeHasPasskeys({
  required bool hasSupabase,
  required bool isWeb,
  required String relyingPartyId,
}) {
  if (!hasSupabase || isWeb) return false;
  if (relyingPartyId.isEmpty) return false;
  return true;
}
