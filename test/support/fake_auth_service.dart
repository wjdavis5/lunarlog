/// Hand-written [AuthService] fake (KTD6, the `FakeGate` convention): a
/// controllable state stream plus call recorders, so widget and controller
/// tests never touch a Supabase client. Google Sign-In mirrors the Apple
/// knobs (#2 U2); the passwordless pair records its calls and signs in on
/// a verified code like a password sign-in (#2 U7). Sign-in methods and
/// linking (#2 U8) are a `providers` list the current user carries plus
/// recorded `linkCalls`. Removing one (#31 U3) is the same list in reverse,
/// via `unlinkCalls`.
library;

import 'dart:async';

import 'package:lunarlog/domain/auth/auth_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({
    AuthSessionState initialState = AuthSessionState.signedOut,
    this.pendingRecovery = false,
    this._user,
  }) : _state = initialState;

  final StreamController<AuthSessionState> _states =
      StreamController<AuthSessionState>.broadcast();
  final StreamController<AuthFailure> _linkFailures =
      StreamController<AuthFailure>.broadcast();

  AuthSessionState _state;
  AuthUser? _user;

  /// The current user's sign-in methods (#2 U8; KTD5). Applied to every
  /// user this fake builds, and taken from an emitted user that carries
  /// its own list.
  List<String> providers = const [];

  @override
  bool pendingRecovery;

  @override
  AuthFailure? pendingLinkFailure;

  /// What [signUp] returns; defaults to "awaiting confirmation" for the
  /// email passed in (hosted email confirmation on, AS10).
  SignUpResult? signUpResult;

  /// What [signInWithAppleNative] returns.
  AppleSignInResult appleResult = const AppleSignInCancelled();

  /// What [signInWithGoogleNative] returns (#2 U2).
  GoogleSignInResult googleResult =
      const GoogleSignInSession(AuthUser(id: 'user-google'));

  /// What [signInWithPasskey] returns (#30 U2).
  PasskeySignInResult passkeySignInResult = const PasskeySignInCancelled();

  /// What [registerPasskey] returns (#30 U2). Never touches [providers] —
  /// passkeys are not identity providers and do not appear in
  /// [AuthUser.providers] (R10).
  PasskeyRegistrationResult passkeyRegistrationResult =
      const PasskeyRegistrationCancelled();

  /// Throw [UnsupportedError] from [signInWithPasskey] / [registerPasskey]
  /// (build has no passkey configuration).
  bool passkeyUnsupported = false;

  /// When set, every mutating call throws it once.
  AuthFailure? nextFailure;

  /// What [linkGoogle] / [linkApple] return when set; otherwise the
  /// provider is appended to [providers] and the current user returned.
  AuthUser? linkResult;

  /// What [unlinkProvider] returns when set (#31 U3); otherwise the
  /// provider is removed from [providers] and the current user returned.
  AuthUser? unlinkResult;

  /// When true, [unlinkProvider] still returns the correctly-computed
  /// fresh user, but leaves this fake's own [providers]/[currentUser]
  /// unchanged — mirroring a server-side post-delete refresh that fails
  /// silently (KTD4), so a test can check that a caller prefers the
  /// returned user over re-reading [currentUser] (#31 finding 2).
  bool unlinkLeavesCurrentUserStale = false;

  /// Simulates a dismissed picker or dialog while linking: the current
  /// user is returned unchanged and nothing is recorded as linked.
  bool linkCancelled = false;

  /// Throw a non-[AuthFailure] error from [unlinkProvider] before recording
  /// a call, mirroring [googleUnsupported] for the link path (#31 U3):
  /// exercises the account section's generic (non-`AuthFailure`) catch
  /// branch for the remove ceremony.
  bool unlinkThrowsGeneric = false;

  /// Throw [UnsupportedError] from [signInWithAppleNative] (non-iOS).
  bool appleUnsupported = false;

  /// Throw [UnsupportedError] from [signInWithGoogleNative] (no client ids,
  /// or web).
  bool googleUnsupported = false;

  /// When set, every mutating call waits for it before completing, so a
  /// widget test can observe the pending state (U6). Complete it to let
  /// the call through.
  Completer<void>? hold;

  final signUpCalls = <({String email, String password})>[];
  final signInCalls = <({String email, String password})>[];
  final passwordResetCalls = <String>[];
  final updatePasswordCalls = <String>[];
  final signOutCalls = <AuthSignOutScope>[];
  final magicLinkCalls = <({String email, bool createAccount})>[];
  final codeCalls = <({String email, String code})>[];
  final linkCalls = <String>[];
  final unlinkCalls = <String>[];
  int appleCalls = 0;
  int googleCalls = 0;
  int passkeySignInCalls = 0;
  int registerPasskeyCalls = 0;
  int recoveryConsumed = 0;
  int linkFailureConsumed = 0;

  /// Pushes a new state to subscribers and updates [state].
  void emit(AuthSessionState next, {AuthUser? user}) {
    if (user != null) {
      if (user.providers.isNotEmpty) providers = user.providers;
      _user = user;
    }
    if (next == AuthSessionState.signedOut ||
        next == AuthSessionState.expired) {
      _user = null;
    }
    _state = next;
    _states.add(next);
  }

  /// Simulates a recovery exchange: latches and emits [AuthSessionState
  /// .passwordRecovery] (a session exists during recovery).
  void latchRecovery({AuthUser? user}) {
    pendingRecovery = true;
    emit(AuthSessionState.passwordRecovery,
        user: user ?? const AuthUser(id: 'user-recovery'));
  }

  void emitLinkFailure(AuthFailure failure) {
    pendingLinkFailure = failure;
    _linkFailures.add(failure);
  }

  @override
  AuthSessionState get state => _state;

  @override
  Stream<AuthSessionState> get states => _states.stream;

  @override
  Stream<AuthFailure> get linkFailures => _linkFailures.stream;

  @override
  AuthUser? get currentUser {
    final user = _user;
    if (user == null) return null;
    return AuthUser(id: user.id, email: user.email, providers: providers);
  }

  @override
  String? get currentUserId => _user?.id;

  @override
  void consumeRecovery() {
    pendingRecovery = false;
    recoveryConsumed++;
  }

  @override
  void consumeLinkFailure() {
    pendingLinkFailure = null;
    linkFailureConsumed++;
  }

  Future<void> _maybeThrow() async {
    final gate = hold;
    if (gate != null) await gate.future;
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    signUpCalls.add((email: email, password: password));
    await _maybeThrow();
    return signUpResult ?? SignUpAwaitingConfirmation(email);
  }

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls.add((email: email, password: password));
    await _maybeThrow();
    final user =
        AuthUser(id: 'user-$email', email: email, providers: providers);
    emit(AuthSessionState.signedIn, user: user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetCalls.add(email);
    await _maybeThrow();
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalls.add(newPassword);
    await _maybeThrow();
  }

  @override
  Future<AppleSignInResult> signInWithAppleNative() async {
    if (appleUnsupported) {
      throw UnsupportedError('Apple Sign-In is available on iOS only');
    }
    appleCalls++;
    await _maybeThrow();
    final result = appleResult;
    if (result is AppleSignInSession) {
      emit(AuthSessionState.signedIn, user: result.user);
    }
    return result;
  }

  @override
  Future<GoogleSignInResult> signInWithGoogleNative() async {
    if (googleUnsupported) {
      throw UnsupportedError('Google Sign-In is not available in this build');
    }
    googleCalls++;
    await _maybeThrow();
    final result = googleResult;
    if (result is GoogleSignInSession) {
      emit(AuthSessionState.signedIn, user: result.user);
    }
    return result;
  }

  @override
  Future<PasskeySignInResult> signInWithPasskey() async {
    if (passkeyUnsupported) {
      throw UnsupportedError('Passkeys are not available in this build');
    }
    passkeySignInCalls++;
    await _maybeThrow();
    final result = passkeySignInResult;
    if (result is PasskeySignInSession) {
      emit(AuthSessionState.signedIn, user: result.user);
    }
    return result;
  }

  @override
  Future<PasskeyRegistrationResult> registerPasskey() async {
    if (passkeyUnsupported) {
      throw UnsupportedError('Passkeys are not available in this build');
    }
    if (_state != AuthSessionState.signedIn) {
      throw const AuthFailure.unknown();
    }
    registerPasskeyCalls++;
    await _maybeThrow();
    return passkeyRegistrationResult;
  }

  @override
  Future<void> sendMagicLink({
    required String email,
    required bool createAccount,
  }) async {
    magicLinkCalls.add((email: email, createAccount: createAccount));
    await _maybeThrow();
  }

  @override
  Future<AuthUser> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    codeCalls.add((email: email, code: code));
    await _maybeThrow();
    final user =
        AuthUser(id: 'user-$email', email: email, providers: providers);
    emit(AuthSessionState.signedIn, user: user);
    return user;
  }

  @override
  Future<AuthUser> linkGoogle() async {
    if (googleUnsupported) {
      throw UnsupportedError('Google Sign-In is not available in this build');
    }
    return _link('google');
  }

  @override
  Future<AuthUser> linkApple() async {
    if (appleUnsupported) {
      throw UnsupportedError('Apple Sign-In is available on iOS only');
    }
    return _link('apple');
  }

  Future<AuthUser> _link(String provider) async {
    if (_state != AuthSessionState.signedIn) {
      throw const AuthFailure.unknown();
    }
    linkCalls.add(provider);
    await _maybeThrow();
    if (linkCancelled) return currentUser!;
    final result = linkResult;
    if (result != null) {
      emit(_state, user: result);
      return result;
    }
    if (!providers.contains(provider)) providers = [...providers, provider];
    return currentUser!;
  }

  /// Mirrors [_link] in reverse (#31 U3): the signed-in check runs before
  /// recording the call, so a not-signed-in caller never touches
  /// [nextFailure] or [hold].
  @override
  Future<AuthUser> unlinkProvider(String provider) async {
    if (provider == AuthProviders.email) throw const AuthFailure.unknown();
    if (_state != AuthSessionState.signedIn) {
      throw const AuthFailure.unknown();
    }
    if (unlinkThrowsGeneric) {
      throw StateError('unlink failed unexpectedly');
    }
    unlinkCalls.add(provider);
    await _maybeThrow();
    final result = unlinkResult;
    if (result != null) {
      if (unlinkLeavesCurrentUserStale) return result;
      emit(_state, user: result);
      return result;
    }
    final remaining =
        providers.where((existing) => existing != provider).toList();
    if (unlinkLeavesCurrentUserStale) {
      final current = _user!;
      return AuthUser(
          id: current.id, email: current.email, providers: remaining);
    }
    providers = remaining;
    return currentUser!;
  }

  @override
  Future<void> signOut({
    AuthSignOutScope scope = AuthSignOutScope.local,
  }) async {
    signOutCalls.add(scope);
    await _maybeThrow();
    emit(AuthSessionState.signedOut);
  }

  Future<void> dispose() async {
    await _states.close();
    await _linkFailures.close();
  }
}
