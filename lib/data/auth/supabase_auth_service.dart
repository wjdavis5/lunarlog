/// [AuthService] over Supabase (U4; KTD7, KTD8, KTD9).
///
/// Constructed by `lib/startup/supabase_bootstrap.dart` *before the first
/// frame*: it subscribes to `onAuthStateChange`, observes incoming links,
/// exchanges PKCE codes itself (`detectSessionInUri` is off so no exchange
/// can happen before this subscription exists), and latches
/// [pendingRecovery] so a cold-start reset link survives until the device
/// gate opens (AE8). It holds no reference to the gate.
///
/// Every provider error is reduced to a typed [AuthFailure]; raw messages,
/// link `error_description`s, and emails never leave this file.
///
/// Native Google Sign-In (#2 U2; KTD1, KTD8) runs through the injected
/// [GoogleSignInClient] with one hashed nonce per process (#2 AS2); log
/// lines carry only a runtime type or an exception-code name (#2 KTD7).
/// Passwordless email (#2 U7; KTD3, KTD4) rides the same PKCE callback;
/// [mapAuthError] stays pure and each operation wraps its own failures.
/// Sign-in methods come from `User.identities` and linking a second one
/// reuses the Google and Apple credential paths against
/// `linkIdentityWithIdToken` (#2 U8; KTD5). Removing one (#31 U2; KTD2,
/// KTD3, KTD4, KTD5) is read (`getUserIdentities`) -> guard (the last
/// identity) -> delete (`unlinkIdentity`) -> refresh (`refreshSession`),
/// with `single_identity_not_deletable` mapped beside the existing codes.
///
/// Split (#436): the members documented above now live in two `part`
/// files, each mixed back into [SupabaseAuthService] —
/// `supabase_auth_session_state.dart` (the identity-link state machine:
/// link handling, auth-event mapping, the recovery latch, and the
/// session-state surface) and `supabase_auth_providers.dart` (the four
/// sign-in providers plus identity linking) — while
/// `supabase_auth_service.dart` stays the single import path. One library,
/// one private namespace: no importer changes, no signature changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
import 'package:http/http.dart' as http;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/auth/auth_gateway.dart';
import 'package:lunarlog/data/auth/auth_link_classifier.dart';
import 'package:lunarlog/data/auth/google_sign_in_client.dart';
import 'package:lunarlog/data/auth/passkey_ceremony_client.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

export 'package:lunarlog/data/auth/auth_link_classifier.dart'
    show
        kAuthCallbackHost,
        kAuthCallbackScheme,
        kAuthCallbackUrl,
        kWebAuthCallbackPath;

part 'supabase_auth_providers.dart';
part 'supabase_auth_session_state.dart';
part 'supabase_auth_mfa.dart';

class SupabaseAuthService
    with SupabaseAuthSessionState, SupabaseAuthProviders, SupabaseAuthMfa
    implements AuthService {
  SupabaseAuthService({
    required this._gateway,
    required this._links,
    String? redirectTo,
    Uri? webInitialUri,
    bool? appleAvailable,
    this._requestAppleCredential = defaultAppleCredentialRequest,
    bool? googleAvailable,
    GoogleSignInClient? googleClient,
    this._generateNonce = generateRawNonce,
    bool? passkeysAvailable,
    PasskeyCeremonyClient? passkeyClient,
  })  : _redirectTo =
            redirectTo ?? resolveAuthRedirectUrl(isWeb: kIsWeb, base: Uri.base),
        _webInitialUri = webInitialUri ?? (kIsWeb ? Uri.base : null),
        _appleAvailable = appleAvailable ??
            computeAppleSignInAvailable(
              isWeb: kIsWeb,
              isIos: defaultTargetPlatform == TargetPlatform.iOS,
            ),
        _googleAvailable = googleAvailable ?? (!kIsWeb && AppConfig.hasGoogle),
        _googleClient = googleClient ?? PluginGoogleSignInClient(),
        _passkeysAvailable = passkeysAvailable ?? AppConfig.hasPasskeys,
        _passkeyClient = passkeyClient ?? const UnsupportedPasskeyCeremonyClient();

  @override
  final AuthGateway _gateway;
  @override
  final AuthLinkSource _links;
  @override
  final String _redirectTo;

  /// The browser's launch URL on web (epic #831 slice 2): a confirmation,
  /// passwordless, or reset email lands on `<origin>/auth/callback?code=…`,
  /// and this service — not the browser — exchanges that code over the same
  /// PKCE path native links use. Null on native (where app_links supplies
  /// [AuthLinkSource.initialLink] instead); injectable so tests can drive a
  /// web callback without a browser.
  @override
  final Uri? _webInitialUri;

  @override
  final bool _appleAvailable;
  @override
  final AppleCredentialRequest _requestAppleCredential;
  @override
  final bool _googleAvailable;
  @override
  final GoogleSignInClient _googleClient;
  @override
  final String Function() _generateNonce;
  @override
  final bool _passkeysAvailable;
  @override
  final PasskeyCeremonyClient _passkeyClient;

  /// The per-process Google nonce pair (#2 AS2): minted on the first
  /// Google call, the hash given to the client once, the raw value sent to
  /// Supabase with every Google ID token. In memory only, never logged.
  @override
  ({String raw, String hashed})? _googleNonce;
  @override
  bool _googleInitialized = false;

  // Issue #548: close_sinks only looks within the declaring class/mixin
  // body, not across `part` files — these are closed in `dispose()` in
  // `supabase_auth_session_state.dart` (part of this same library).
  @override
  // ignore: close_sinks
  final StreamController<AuthSessionState> _states =
      StreamController<AuthSessionState>.broadcast();
  @override
  // ignore: close_sinks
  final StreamController<AuthFailure> _linkFailures =
      StreamController<AuthFailure>.broadcast();

  @override
  AuthSessionState _state = AuthSessionState.signedOut;
  @override
  bool _pendingRecovery = false;
  @override
  AuthFailure? _pendingLinkFailure;
  @override
  bool _started = false;
  @override
  String? _lastHandledLink;
  // Issue #548: cancel_subscriptions has the same cross-part blind spot as
  // close_sinks above — both are cancelled in dispose() in
  // supabase_auth_session_state.dart.
  @override
  // ignore: cancel_subscriptions
  StreamSubscription<AuthState>? _eventSub;
  @override
  // ignore: cancel_subscriptions
  StreamSubscription<Uri>? _linkSub;
}
