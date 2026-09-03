/// Account UI state (U4, KTD6): a `ChangeNotifier` over the domain
/// [AuthService], shaped like `ProfileController` over its repository.
/// Provided by `LunarLogApp` only when the build has an auth service; an
/// unconfigured build provides nothing and shows no account section.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({required AuthService authService})
      : _service = authService,
        _state = authService.state {
    _stateSub = authService.states.listen(_onState);
    _failureSub = authService.linkFailures.listen((_) => notifyListeners());
  }

  final AuthService _service;
  AuthSessionState _state;
  StreamSubscription<AuthSessionState>? _stateSub;
  StreamSubscription<AuthFailure>? _failureSub;

  AuthSessionState get state => _state;

  /// A usable session exists and no recovery is pending.
  bool get signedIn => _state == AuthSessionState.signedIn;

  AuthUser? get currentUser => _service.currentUser;

  String? get currentUserId => _service.currentUserId;

  /// Read straight from the service so a recovery latched before this
  /// controller existed (cold-start link, KTD8) is visible on first read.
  /// The home gate consumes it only when the device gate is unlocked
  /// (AE8).
  bool get pendingRecovery => _service.pendingRecovery;

  void consumeRecovery() {
    if (!_service.pendingRecovery) return;
    _service.consumeRecovery();
    notifyListeners();
  }

  AuthFailure? get pendingLinkFailure => _service.pendingLinkFailure;

  void consumeLinkFailure() {
    if (_service.pendingLinkFailure == null) return;
    _service.consumeLinkFailure();
    notifyListeners();
  }

  // ------------------------------------------------------------ actions
  // Thin delegations so screens depend on this notifier only (KTD6). Each
  // throws the service's typed [AuthFailure]; state changes arrive through
  // [states] and notify listeners.

  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _service.signInWithPassword(email: email, password: password);

  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) =>
      _service.signUp(email: email, password: password);

  Future<void> sendPasswordReset(String email) =>
      _service.sendPasswordReset(email);

  Future<void> updatePassword(String newPassword) =>
      _service.updatePassword(newPassword);

  Future<AppleSignInResult> signInWithAppleNative() =>
      _service.signInWithAppleNative();

  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local}) =>
      _service.signOut(scope: scope);

  void _onState(AuthSessionState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_failureSub?.cancel());
    _stateSub = null;
    _failureSub = null;
    super.dispose();
  }
}
