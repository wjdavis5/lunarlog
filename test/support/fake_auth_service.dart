/// Hand-written [AuthService] fake (KTD6, the `FakeGate` convention): a
/// controllable state stream plus call recorders, so widget and controller
/// tests never touch a Supabase client.
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

  @override
  bool pendingRecovery;

  @override
  AuthFailure? pendingLinkFailure;

  /// What [signUp] returns; defaults to "awaiting confirmation" for the
  /// email passed in (hosted email confirmation on, AS10).
  SignUpResult? signUpResult;

  /// What [signInWithAppleNative] returns.
  AppleSignInResult appleResult = const AppleSignInCancelled();

  /// When set, every mutating call throws it once.
  AuthFailure? nextFailure;

  /// Throw [UnsupportedError] from [signInWithAppleNative] (non-iOS).
  bool appleUnsupported = false;

  /// When set, every mutating call waits for it before completing, so a
  /// widget test can observe the pending state (U6). Complete it to let
  /// the call through.
  Completer<void>? hold;

  final signUpCalls = <({String email, String password})>[];
  final signInCalls = <({String email, String password})>[];
  final passwordResetCalls = <String>[];
  final updatePasswordCalls = <String>[];
  final signOutCalls = <AuthSignOutScope>[];
  int appleCalls = 0;
  int recoveryConsumed = 0;
  int linkFailureConsumed = 0;

  /// Pushes a new state to subscribers and updates [state].
  void emit(AuthSessionState next, {AuthUser? user}) {
    if (user != null) _user = user;
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
  AuthUser? get currentUser => _user;

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
    final user = AuthUser(id: 'user-$email', email: email);
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
