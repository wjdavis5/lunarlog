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
/// `linkIdentityWithIdToken` (#2 U8; KTD5).
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
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

export 'package:lunarlog/data/auth/auth_link_classifier.dart'
    show kAuthCallbackHost, kAuthCallbackScheme, kAuthCallbackUrl;

/// `emailRedirectTo` / `redirectTo` for the provider's emails: the custom
/// scheme on native, the page origin on web (AS9).
String resolveAuthRedirectUrl({required bool isWeb, required Uri base}) =>
    isWeb ? base.origin : kAuthCallbackUrl;

/// Requests the Apple credential for a *hashed* nonce (KTD9). Injectable so
/// tests never touch the platform channel.
typedef AppleCredentialRequest = Future<AuthorizationCredentialAppleID>
    Function({required String hashedNonce});

Future<AuthorizationCredentialAppleID> defaultAppleCredentialRequest({
  required String hashedNonce,
}) =>
    SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

/// A cryptographically random, URL-safe nonce (32 bytes, base64url).
String generateRawNonce([int bytes = 32]) {
  final random = Random.secure();
  final data = Uint8List.fromList(
      List<int>.generate(bytes, (_) => random.nextInt(256)));
  return base64UrlEncode(data).replaceAll('=', '');
}

/// Reduces any error thrown by the provider to a typed, fieldless
/// [AuthFailure]. Pure; exported for tests.
///
/// Split into this dispatcher plus [_mapGoTrueAuthException] and
/// [_isNetworkShapedError] — same checks, same order, no behavior change.
AuthFailure mapAuthError(Object error) {
  if (error is AuthFailure) return error;
  if (error is AuthWeakPasswordException) return const AuthFailure.weakPassword();
  if (error is AuthRetryableFetchException) return const AuthFailure.network();
  if (error is AuthException) return _mapGoTrueAuthException(error);
  if (_isNetworkShapedError(error)) return const AuthFailure.network();
  return const AuthFailure.unknown();
}

AuthFailure _mapGoTrueAuthException(AuthException error) {
  switch (error.code) {
    case 'invalid_credentials':
      return const AuthFailure.wrongPassword();
    case 'weak_password':
      return const AuthFailure.weakPassword();
    case 'signup_disabled':
      // Sign-ups closed: a first Google, Apple, or passwordless sign-in
      // for an unknown person (#2 KTD3).
      return const AuthFailure.signUpClosed();
    case 'identity_already_exists':
      return const AuthFailure.identityTaken();
  }
  // Older GoTrue servers send no code for a bad login, only the message.
  if (error.statusCode == '400' &&
      error.message.toLowerCase().contains('invalid login credentials')) {
    return const AuthFailure.wrongPassword();
  }
  return const AuthFailure.unknown();
}

bool _isNetworkShapedError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException;

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({
    required this._gateway,
    required this._links,
    String? redirectTo,
    bool? appleAvailable,
    this._requestAppleCredential = defaultAppleCredentialRequest,
    bool? googleAvailable,
    GoogleSignInClient? googleClient,
    this._generateNonce = generateRawNonce,
  })  : _redirectTo =
            redirectTo ?? resolveAuthRedirectUrl(isWeb: kIsWeb, base: Uri.base),
        _appleAvailable = appleAvailable ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
        _googleAvailable = googleAvailable ?? (!kIsWeb && AppConfig.hasGoogle),
        _googleClient = googleClient ?? PluginGoogleSignInClient();

  final AuthGateway _gateway;
  final AuthLinkSource _links;
  final String _redirectTo;
  final bool _appleAvailable;
  final AppleCredentialRequest _requestAppleCredential;
  final bool _googleAvailable;
  final GoogleSignInClient _googleClient;
  final String Function() _generateNonce;

  /// The per-process Google nonce pair (#2 AS2): minted on the first
  /// Google call, the hash given to the client once, the raw value sent to
  /// Supabase with every Google ID token. In memory only, never logged.
  ({String raw, String hashed})? _googleNonce;
  bool _googleInitialized = false;

  final StreamController<AuthSessionState> _states =
      StreamController<AuthSessionState>.broadcast();
  final StreamController<AuthFailure> _linkFailures =
      StreamController<AuthFailure>.broadcast();

  AuthSessionState _state = AuthSessionState.signedOut;
  bool _pendingRecovery = false;
  AuthFailure? _pendingLinkFailure;
  bool _started = false;
  String? _lastHandledLink;
  StreamSubscription<AuthState>? _eventSub;
  StreamSubscription<Uri>? _linkSub;

  /// Subscribes to auth events and links, then handles the launch link.
  /// Idempotent. Awaited by the bootstrap before `runApp` (KTD8).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _state = _gateway.currentSession == null
        ? AuthSessionState.signedOut
        : AuthSessionState.signedIn;
    _eventSub = _gateway.onAuthStateChange.listen(
      _onAuthState,
      onError: _onAuthStreamError,
    );
    _linkSub = _links.links.listen((uri) => unawaited(handleLink(uri)));
    Uri? initial;
    try {
      initial = await _links.initialLink();
    } catch (error) {
      debugPrint('lunarlog auth: initial link unavailable '
          '(${error.runtimeType})');
    }
    if (initial != null) await handleLink(initial);
  }

  /// Classifies and, for a callback, exchanges [uri]. Public so tests (and
  /// the link observer) drive it directly. A link seen twice — app_links
  /// replays the launch link on its stream — is handled once, except that
  /// an exchange which failed transiently (network) leaves the link
  /// retryable.
  ///
  /// Failures are mapped by operation (#2 U7; KTD4): a link the provider
  /// already rejected and every non-network exchange failure — expired
  /// (`otp_expired`), reused or stale (`flow_state_not_found`,
  /// `flow_state_expired`, `bad_code_verifier`), or opened on a device
  /// with no verifier (gotrue's code-less "Code verifier could not be
  /// found") — surface as one generic [AuthExpiredLinkFailure] (R7).
  /// Split into this dispatcher plus [_exchangeAuthLink]/
  /// [_handleAuthLinkExchangeError] — same sequencing, same conditions, no
  /// behavior change.
  Future<void> handleLink(Uri uri) async {
    final link = classifyAuthLink(uri);
    if (link is AuthLinkIgnored) return;
    final key = uri.toString();
    if (key == _lastHandledLink) return;
    switch (link) {
      case AuthLinkIgnored():
        return;
      case AuthLinkError():
        _lastHandledLink = key;
        // Never call getSessionFromUrl: gotrue would throw an AuthException
        // whose message *is* the error_description.
        _surfaceLinkFailure(const AuthFailure.expiredLink());
      case AuthLinkCallback(:final recovery):
        // Latched before the exchange so the stream replay of the launch
        // link cannot start a second exchange while this one is in flight.
        _lastHandledLink = key;
        await _exchangeAuthLink(uri, recovery: recovery, key: key);
    }
  }

  Future<void> _exchangeAuthLink(
    Uri uri, {
    required bool recovery,
    required String key,
  }) async {
    try {
      final response = await _gateway.getSessionFromUrl(uri);
      if (recovery || _isRecoveryType(response.redirectType)) {
        _latchRecovery();
      }
    } catch (error) {
      _handleAuthLinkExchangeError(error, key);
    }
  }

  void _handleAuthLinkExchangeError(Object error, String key) {
    final failure = mapAuthError(error);
    if (failure is AuthNetworkFailure) {
      // A transient failure un-latches the link so the same link can be
      // exchanged again.
      if (_lastHandledLink == key) _lastHandledLink = null;
      _surfaceLinkFailure(failure);
      return;
    }
    // A definitive failure stays latched so the replay does not surface it
    // twice; its kind is not distinguished (KTD4).
    debugPrint('lunarlog auth: link exchange rejected '
        '(${error.runtimeType})');
    _surfaceLinkFailure(const AuthFailure.expiredLink());
  }

  static bool _isRecoveryType(String? redirectType) =>
      redirectType == 'recovery' ||
      redirectType == AuthChangeEvent.passwordRecovery.name;

  void _onAuthState(AuthState change) {
    final hasSession = change.session != null;
    switch (change.event) {
      case AuthChangeEvent.initialSession:
        _setState(hasSession ? _sessionState : AuthSessionState.signedOut);
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.mfaChallengeVerified:
        _setState(_sessionState);
      case AuthChangeEvent.passwordRecovery:
        _latchRecovery();
      case AuthChangeEvent.signedOut:
        _handleSignedOutEvent(change.signOutReason);
      default:
        break;
    }
  }

  /// Split out of [_onAuthState] verbatim — same conditions, no behavior
  /// change.
  void _handleSignedOutEvent(SignOutReason? reason) {
    // A session that vanished cannot complete a recovery.
    _pendingRecovery = false;
    final involuntary = reason == SignOutReason.sessionExpired ||
        reason == SignOutReason.sessionMissing;
    _setState(
        involuntary ? AuthSessionState.expired : AuthSessionState.signedOut);
  }

  /// The state to report while a session exists: recovery wins until it
  /// is consumed, so a token refresh under the lock cannot mask it.
  AuthSessionState get _sessionState => _pendingRecovery
      ? AuthSessionState.passwordRecovery
      : AuthSessionState.signedIn;

  void _onAuthStreamError(Object error, StackTrace stackTrace) {
    // gotrue reports refresh failures here (a retryable fetch while
    // offline keeps the session; an expired token also emits signedOut
    // with a reason, handled above). Nothing to change; never log the
    // message — it can embed a URL.
    debugPrint('lunarlog auth: stream error (${error.runtimeType})');
  }

  void _latchRecovery() {
    _pendingRecovery = true;
    _setState(AuthSessionState.passwordRecovery);
  }

  void _setState(AuthSessionState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _surfaceLinkFailure(AuthFailure failure) {
    _pendingLinkFailure = failure;
    if (!_linkFailures.isClosed) _linkFailures.add(failure);
  }

  // --- AuthService ---

  @override
  AuthSessionState get state => _state;

  @override
  Stream<AuthSessionState> get states => _states.stream;

  @override
  bool get pendingRecovery => _pendingRecovery;

  @override
  void consumeRecovery() {
    if (!_pendingRecovery) return;
    _pendingRecovery = false;
    _setState(_gateway.currentSession == null
        ? AuthSessionState.signedOut
        : AuthSessionState.signedIn);
  }

  @override
  AuthFailure? get pendingLinkFailure => _pendingLinkFailure;

  @override
  Stream<AuthFailure> get linkFailures => _linkFailures.stream;

  @override
  void consumeLinkFailure() => _pendingLinkFailure = null;

  @override
  AuthUser? get currentUser => _toUser(_gateway.currentSession?.user);

  @override
  String? get currentUserId => _gateway.currentSession?.user.id;

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final response = await _gateway.signUp(
          email: email,
          password: password,
          emailRedirectTo: _redirectTo,
        );
        final session = response.session;
        if (session == null) return SignUpAwaitingConfirmation(email);
        return SignUpSession(_toUser(session.user)!);
      });

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final response = await _gateway.signInWithPassword(
          email: email,
          password: password,
        );
        final user = response.session?.user ?? response.user;
        if (user == null) throw const AuthFailure.unknown();
        return _toUser(user)!;
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(
      () => _gateway.resetPasswordForEmail(email, redirectTo: _redirectTo));

  @override
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _gateway.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<AppleSignInResult> signInWithAppleNative() async {
    _requireApple();
    final rawNonce = _generateNonce();
    final credential = await _requestAppleCredentialFor(rawNonce);
    if (credential == null) return const AppleSignInCancelled();
    final idToken = credential.identityToken;
    if (idToken == null) throw const AuthFailure.unknown();
    final session = await _exchangeIdTokenForSession(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    // Apple sends the name only with the *first* credential; keep it.
    final fullName = [credential.givenName, credential.familyName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (fullName.isNotEmpty) {
      try {
        await _gateway.updateUser(UserAttributes(data: {'full_name': fullName}));
      } catch (error) {
        // Best effort: the session is established regardless.
        debugPrint('lunarlog auth: name update failed (${error.runtimeType})');
      }
    }
    return AppleSignInSession(_toUser(session.user)!);
  }

  void _requireApple() {
    if (!_appleAvailable) {
      throw UnsupportedError('Apple Sign-In is available natively on iOS only');
    }
  }

  /// Requests the Apple credential for the SHA-256 of [rawNonce] (KTD9).
  /// Null when the operator dismissed the dialog; [AuthUnknownFailure] for
  /// any other authorization error. Shared by sign-in and linking so both
  /// follow one nonce discipline (#2 AS6).
  Future<AuthorizationCredentialAppleID?> _requestAppleCredentialFor(
      String rawNonce) async {
    final hashedNonce = _hashNonce(rawNonce);
    try {
      return await _requestAppleCredential(hashedNonce: hashedNonce);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw const AuthFailure.unknown();
    } catch (_) {
      throw const AuthFailure.unknown();
    }
  }

  @override
  Future<GoogleSignInResult> signInWithGoogleNative() async {
    _requireGoogle();
    final nonce = _googleNonce ??= _mintGoogleNonce();
    final credential = await _requestGoogleCredential(nonce);
    if (credential == null) return const GoogleSignInCancelled();
    final idToken = credential.idToken;
    if (idToken == null) throw const AuthFailure.unknown();
    final session = await _exchangeIdTokenForSession(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: credential.accessToken,
      nonce: nonce.raw,
    );
    return GoogleSignInSession(_toUser(session.user)!);
  }

  /// Exchanges a provider ID token for a session through [_guard], so every
  /// provider error becomes a typed [AuthFailure]; a response without a
  /// session is [AuthUnknownFailure]. Shared by the Apple and Google flows.
  Future<Session> _exchangeIdTokenForSession({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    required String nonce,
  }) =>
      _guard(() async {
        final response = await _gateway.signInWithIdToken(
          provider: provider,
          idToken: idToken,
          accessToken: accessToken,
          nonce: nonce,
        );
        final session = response.session;
        if (session == null) throw const AuthFailure.unknown();
        return session;
      });

  /// SHA-256 hex of a raw nonce: what the native SDKs receive while Supabase
  /// gets the raw value (KTD9, #2 KTD1).
  static String _hashNonce(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  void _requireGoogle() {
    if (!_googleAvailable) {
      throw UnsupportedError(
          'Google Sign-In needs client ids and a native platform');
    }
  }

  /// Initializes the client once with the hashed nonce and runs the
  /// picker (#2 KTD1). Null when the operator dismissed it;
  /// [AuthProviderUnavailableFailure] for every other plugin code (#2 KTD8);
  /// [AuthUnknownFailure] otherwise. Shared by sign-in and linking.
  Future<GoogleCredential?> _requestGoogleCredential(
      ({String raw, String hashed}) nonce) async {
    try {
      if (!_googleInitialized) {
        await _googleClient.initialize(
          iosClientId: AppConfig.googleIosClientId,
          webClientId: AppConfig.googleWebClientId,
          hashedNonce: nonce.hashed,
        );
        _googleInitialized = true;
      }
      return await _googleClient.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      // Every other code, including "no credentials" reported as
      // unknownError on Android (#2 KTD8). The description is never logged.
      debugPrint('lunarlog auth: google sign-in failed (${error.code.name})');
      throw const AuthFailure.providerUnavailable();
    } catch (error) {
      debugPrint('lunarlog auth: google sign-in failed (${error.runtimeType})');
      throw const AuthFailure.unknown();
    }
  }

  ({String raw, String hashed}) _mintGoogleNonce() {
    final raw = _generateNonce();
    return (raw: raw, hashed: _hashNonce(raw));
  }

  /// Links Google to the current account (#2 U8; KTD5, R10): the same
  /// per-process nonce pair and client as sign-in, then
  /// `linkIdentityWithIdToken` with the raw nonce. The signed-in check runs
  /// before any platform call; a dismissed picker returns the user as is.
  @override
  Future<AuthUser> linkGoogle() async {
    _requireGoogle();
    final current = _requireSignedInUser();
    final nonce = _googleNonce ??= _mintGoogleNonce();
    final credential = await _requestGoogleCredential(nonce);
    if (credential == null) return current;
    final idToken = credential.idToken;
    if (idToken == null) throw const AuthFailure.unknown();
    return _link(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: credential.accessToken,
      nonce: nonce.raw,
    );
  }

  /// Links Apple to the current account (#2 U8; KTD5, AS6) with a fresh
  /// hashed nonce, as sign-in does. The name Apple sends with a first
  /// credential is not written: the account already has its profile.
  @override
  Future<AuthUser> linkApple() async {
    _requireApple();
    final current = _requireSignedInUser();
    final rawNonce = _generateNonce();
    final credential = await _requestAppleCredentialFor(rawNonce);
    if (credential == null) return current;
    final idToken = credential.identityToken;
    if (idToken == null) throw const AuthFailure.unknown();
    return _link(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  /// The current user while [state] is `signedIn`; [AuthUnknownFailure]
  /// otherwise (no session, recovery pending, or expired).
  AuthUser _requireSignedInUser() {
    final user = _state == AuthSessionState.signedIn ? currentUser : null;
    if (user == null) throw const AuthFailure.unknown();
    return user;
  }

  /// Calls `linkIdentityWithIdToken` through [_guard] (so
  /// `identity_already_exists` is [AuthIdentityTakenFailure]) and re-reads
  /// the session's user so [AuthUser.providers] is fresh, falling back to
  /// the response's user.
  Future<AuthUser> _link({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    required String nonce,
  }) async {
    final response = await _guard(() => _gateway.linkIdentityWithIdToken(
          provider: provider,
          idToken: idToken,
          accessToken: accessToken,
          nonce: nonce,
        ));
    final user = _gateway.currentSession?.user ??
        response.session?.user ??
        response.user;
    if (user == null) throw const AuthFailure.unknown();
    return _toUser(user)!;
  }

  /// Sends the sign-in email (#2 U7; KTD3). In sign-in mode the server's
  /// `otp_disabled` rejection of an unknown email is treated as success so
  /// a known and an unknown email get one response (R6, AE3); in create
  /// mode `signup_disabled` maps to [AuthSignUpClosedFailure] through
  /// [mapAuthError].
  @override
  Future<void> sendMagicLink({
    required String email,
    required bool createAccount,
  }) =>
      _guard(() async {
        try {
          await _gateway.signInWithOtp(
            email: email,
            emailRedirectTo: _redirectTo,
            shouldCreateUser: createAccount,
          );
        } on AuthException catch (error) {
          if (!createAccount && error.code == 'otp_disabled') return;
          rethrow;
        }
      });

  /// Verifies the emailed code (#2 U7; KTD3, KTD4). Mapping is by
  /// operation: any client-side rejection of the code (`otp_expired`,
  /// `otp_disabled`, or another 4xx) is [AuthInvalidCodeFailure]; a
  /// network failure, a closed sign-up, and a server error keep their own
  /// kinds. The `signedIn` state arrives through `onAuthStateChange`, as
  /// for a password sign-in.
  @override
  Future<AuthUser> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    final AuthResponse response;
    try {
      response = await _gateway.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
    } catch (error, stackTrace) {
      final failure = mapAuthError(error);
      Error.throwWithStackTrace(
        _isRejectedCode(error, failure)
            ? const AuthFailure.invalidCode()
            : failure,
        stackTrace,
      );
    }
    final user = response.session?.user ?? response.user;
    if (user == null) throw const AuthFailure.unknown();
    return _toUser(user)!;
  }

  static bool _isRejectedCode(Object error, AuthFailure mapped) {
    if (error is! AuthException) return false;
    if (mapped is AuthNetworkFailure || mapped is AuthSignUpClosedFailure) {
      return false;
    }
    if (error.code == 'otp_expired' || error.code == 'otp_disabled') {
      return true;
    }
    return error.statusCode?.startsWith('4') ?? false;
  }

  @override
  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local}) =>
      _guard(() => _gateway.signOut(
            scope: switch (scope) {
              AuthSignOutScope.local => SignOutScope.local,
              AuthSignOutScope.global => SignOutScope.global,
            },
          ));

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _linkSub?.cancel();
    await _states.close();
    await _linkFailures.close();
  }

  /// Runs [body], rethrowing anything as a typed [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(mapAuthError(error), stackTrace);
    }
  }

  static AuthUser? _toUser(User? user) => user == null
      ? null
      : AuthUser(id: user.id, email: user.email, providers: _providersOf(user));

  /// Provider names from `identities`, falling back to
  /// `app_metadata.providers` when the user carries no identity list
  /// (#2 KTD5). Never `user_metadata`, which the user can write. Order is
  /// preserved, duplicates dropped.
  static List<String> _providersOf(User user) {
    final identities = user.identities;
    final Iterable<String> names;
    if (identities != null && identities.isNotEmpty) {
      names = identities.map((identity) => identity.provider);
    } else {
      final raw = user.appMetadata['providers'];
      names = raw is List ? raw.whereType<String>() : const <String>[];
    }
    return List.unmodifiable(names.toSet());
  }
}
