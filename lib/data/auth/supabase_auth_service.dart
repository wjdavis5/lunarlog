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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lunarlog/data/auth/auth_gateway.dart';
import 'package:lunarlog/data/auth/auth_link_classifier.dart';
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
AuthFailure mapAuthError(Object error) {
  if (error is AuthFailure) return error;
  if (error is AuthWeakPasswordException) return const AuthFailure.weakPassword();
  if (error is AuthRetryableFetchException) return const AuthFailure.network();
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return const AuthFailure.wrongPassword();
      case 'weak_password':
        return const AuthFailure.weakPassword();
    }
    // Older GoTrue servers send no code for a bad login, only the message.
    if (error.statusCode == '400' &&
        error.message.toLowerCase().contains('invalid login credentials')) {
      return const AuthFailure.wrongPassword();
    }
    return const AuthFailure.unknown();
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return const AuthFailure.network();
  }
  return const AuthFailure.unknown();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({
    required this._gateway,
    required this._links,
    String? redirectTo,
    bool? appleAvailable,
    this._requestAppleCredential = defaultAppleCredentialRequest,
    this._generateNonce = generateRawNonce,
  })  : _redirectTo =
            redirectTo ?? resolveAuthRedirectUrl(isWeb: kIsWeb, base: Uri.base),
        _appleAvailable = appleAvailable ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final AuthGateway _gateway;
  final AuthLinkSource _links;
  final String _redirectTo;
  final bool _appleAvailable;
  final AppleCredentialRequest _requestAppleCredential;
  final String Function() _generateNonce;

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
        _surfaceLinkFailure(const AuthFailure.unknown());
      case AuthLinkCallback(:final recovery):
        // Latched before the exchange so the stream replay of the launch
        // link cannot start a second exchange while this one is in flight.
        _lastHandledLink = key;
        try {
          final response = await _gateway.getSessionFromUrl(uri);
          if (recovery || _isRecoveryType(response.redirectType)) {
            _latchRecovery();
          }
        } catch (error) {
          final failure = mapAuthError(error);
          // A transient failure un-latches the link so the same link can
          // be exchanged again; a definitive one (expired code, missing
          // verifier) stays latched so the replay does not surface it twice.
          if (failure is AuthNetworkFailure && _lastHandledLink == key) {
            _lastHandledLink = null;
          }
          _surfaceLinkFailure(failure);
        }
    }
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
        // A session that vanished cannot complete a recovery.
        _pendingRecovery = false;
        final involuntary = change.signOutReason == SignOutReason.sessionExpired ||
            change.signOutReason == SignOutReason.sessionMissing;
        _setState(involuntary
            ? AuthSessionState.expired
            : AuthSessionState.signedOut);
      default:
        break;
    }
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
    if (!_appleAvailable) {
      throw UnsupportedError('Apple Sign-In is available natively on iOS only');
    }
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await _requestAppleCredential(hashedNonce: hashedNonce);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return const AppleSignInCancelled();
      }
      throw const AuthFailure.unknown();
    } catch (_) {
      throw const AuthFailure.unknown();
    }
    final idToken = credential.identityToken;
    if (idToken == null) throw const AuthFailure.unknown();
    final session = await _guard(() async {
      final response = await _gateway.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      final session = response.session;
      if (session == null) throw const AuthFailure.unknown();
      return session;
    });
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

  static AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}
