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

  /// Raw value of `SENTRY_TRACES_SAMPLE_RATE` (issue #7 U4); mirrors the
  /// `_webSyncRaw` idiom (private: nothing but [sentryTracesSampleRate]
  /// needs the unvalidated string). Empty in `dart_defines.example.json`
  /// and in every workflow — an operator opts a build into performance
  /// tracing locally or by adding the flag deliberately, only after issue
  /// #19 exists.
  static const String _sentryTracesSampleRateRaw =
      String.fromEnvironment('SENTRY_TRACES_SAMPLE_RATE');

  /// The tracing sample rate to configure, or null when tracing stays off
  /// (empty or unparseable define). [computeTracesSampleRate] does the
  /// actual parsing/clamping — Dart forbids a function call in a `const`
  /// initializer, so unlike [hasSupabase]/[hasSentry] this cannot itself be
  /// `const`; `static final` still computes it exactly once.
  static final double? sentryTracesSampleRate =
      computeTracesSampleRate(_sentryTracesSampleRateRaw);

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

  /// HTTPS universal-link host for invite/claim links (issue #129): a bare
  /// domain (e.g. `links.example.com`, no scheme), supplied by
  /// `LUNARLOG_LINK_DOMAIN`.
  ///
  /// Client-safe (it is already public the moment the first link is
  /// shared), but still a define so unconfigured builds — CI, forks, PR
  /// builds, and every build today — compile with an empty value and stay
  /// custom-scheme-only. The hosted domain, DNS, and hosting themselves are
  /// human work tracked in issue #384; this value only decides which form
  /// the app's own link builders emit and which form its link filter
  /// honours. Do **not** "fix" the empty default by adding the define to a
  /// workflow; turning the feature on is a deliberate, separate release
  /// action gated on those human prerequisites.
  ///
  /// The client never sends this value to the server.
  static const String linkDomain =
      String.fromEnvironment('LUNARLOG_LINK_DOMAIN');

  /// True when this build emits and honours the HTTPS universal-link form
  /// alongside the custom scheme: any non-empty [linkDomain].
  ///
  /// Kept as a `const` expression (Dart forbids function calls in constant
  /// initializers) so unconfigured code paths tree-shake;
  /// [computeHasUniversalLinks] is the same rule as a testable function,
  /// and `test/config_test.dart` asserts the two agree.
  static const bool hasUniversalLinks = linkDomain != '';

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

  /// True now that a user-visible write flow runs through the #173
  /// adapter: issue #193 wired the one-way, opt-in, forward-only
  /// menstrual-flow write path (`lib/data/health/health_flow_write_service.dart`
  /// + `health_flow_write_coordinator.dart`) over the first-party
  /// `lunarlog/health` channel's Swift `HKHealthStore` half. Reachable on
  /// iOS only — the Settings tile and the app.dart coordinator both gate
  /// on `defaultTargetPlatform == TargetPlatform.iOS` until #202 wires the
  /// Health Connect half's device checklist. Still off on web and inert in
  /// every unconfigured build (no storage/profiles wiring, no tile).
  /// Deliberately a hardcoded constant, not a `--dart-define`: there is no
  /// build-time toggle, only a code change per epic issue.
  static const bool hasHealthSync = true;

  /// Master switch (Issue #153 P0 review) for whether a minor profile may
  /// ever be bound as this device's health-store profile, even after
  /// ownership has transferred to the minor's own account (issue #4) and
  /// the signed-in account is that owner —
  /// `HealthSyncBinding.canBind`/`canWrite` deny every minor profile
  /// outright while this is `false`, regardless of transfer state.
  /// Deliberately a single hardcoded constant here, not a parameter either
  /// of those methods accepts: `lib/domain/health/health_sync_policy.dart`
  /// documents that its call sites must source this value from here and
  /// nowhere else, so a future platform adapter cannot invent its own
  /// per-call bypass the way the pre-review write guard let both of its
  /// call sites neutralise the device-binding check by supplying their
  /// own value. Still `false` under #193: the flow write path only ever
  /// writes for profiles whose guard allows them already, so nothing
  /// exercises the transferred-minor path; flip only alongside a write
  /// flow that needs it, never before. The server-side half of this
  /// consent (a `profiles` column gating writes at the database layer) is
  /// deferred to issue #188 — this flag is client-side only.
  static const bool healthSyncMinorBindingAllowed = false;
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

/// Pure decision behind [AppConfig.sentryTracesSampleRate] (issue #7 U4;
/// KTD8). Empty, unparseable, or non-finite input means tracing stays off
/// (`null`); a finite parseable value is clamped to `[0, 1]`, matching
/// Sentry's own contract for `tracesSampleRate`.
///
/// `double.tryParse` accepts the literal tokens `"NaN"` and `"Infinity"` as
/// successfully parsed (not `null`), and `num.clamp` maps `NaN` to the
/// *upper* bound (`1.0`) rather than rejecting it — so without the explicit
/// `isFinite` check, a stray `SENTRY_TRACES_SAMPLE_RATE=NaN` would silently
/// enable 100% tracing instead of leaving it off.
double? computeTracesSampleRate(String raw) {
  if (raw.isEmpty) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed.clamp(0.0, 1.0).toDouble();
}

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

/// Pure decision behind [AppConfig.hasUniversalLinks] (issue #129).
///
/// Any non-empty link domain opts the build into the HTTPS universal-link
/// form; empty keeps the custom scheme only. Exposed as a function so the
/// rule is unit-testable even though the production input is a
/// compile-time constant.
bool computeHasUniversalLinks(String linkDomain) => linkDomain.isNotEmpty;

/// Pure decision behind [AppConfig.hasPush] (Issue #5, U7).///
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
