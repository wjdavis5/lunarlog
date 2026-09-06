/// Account UI state (U4, KTD6): a `ChangeNotifier` over the domain
/// [AuthService], shaped like `ProfileController` over its repository.
/// Provided once by `LunarLogApp`, above any screen that navigates —
/// including the pushed `SettingsScreen`/`AccountSection` (#31 finding 2) —
/// only when the build has an auth service; an unconfigured build provides
/// nothing and shows no account section. Delegates native Google Sign-In
/// like Apple (#2 U2), the passwordless send and verify pair (#2 U7),
/// identity linking (#2 U8), and removing a linked identity (#31 U3).
///
/// [currentUser] adopts the [AuthUser] a successful [linkGoogle],
/// [linkApple], or [unlinkProvider] call returns and prefers it over
/// re-reading the service (#31 KTD6): a removal's post-delete session
/// refresh can fail without being surfaced (KTD4), so the service's own
/// `currentUser` can lag the value the call just returned. Living here
/// rather than on a pushed screen's `State` means that override survives a
/// Settings round trip instead of resetting to the stale value on
/// `dispose`/re-`initState` (#31 finding 2).
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

  /// The user adopted from the most recent successful [linkGoogle],
  /// [linkApple], or [unlinkProvider] call (#31 KTD6), preferred over
  /// [AuthService.currentUser] below. Cleared whenever the signed-in
  /// user's id changes so a sign-out/sign-in cannot show a previous
  /// account's methods.
  AuthUser? _freshUser;
  String? _freshUserOwnerId;

  AuthSessionState get state => _state;

  /// A usable session exists and no recovery is pending.
  bool get signedIn => _state == AuthSessionState.signedIn;

  AuthUser? get currentUser {
    final live = _service.currentUser;
    _syncFreshUser(live);
    return _freshUser ?? live;
  }

  String? get currentUserId => _service.currentUserId;

  /// Drops the adopted [_freshUser] once the signed-in user's id no
  /// longer matches the one it was adopted for (#31 KTD6).
  void _syncFreshUser(AuthUser? live) {
    if (live?.id == _freshUserOwnerId) return;
    _freshUser = null;
    _freshUserOwnerId = live?.id;
  }

  void _adoptFreshUser(AuthUser user) {
    _freshUser = user;
    _freshUserOwnerId = user.id;
  }

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

  Future<GoogleSignInResult> signInWithGoogleNative() =>
      _service.signInWithGoogleNative();

  Future<void> sendMagicLink({
    required String email,
    required bool createAccount,
  }) =>
      _service.sendMagicLink(email: email, createAccount: createAccount);

  Future<AuthUser> verifyEmailCode({
    required String email,
    required String code,
  }) =>
      _service.verifyEmailCode(email: email, code: code);

  /// Adds a sign-in method to the current account (#2 U8; KTD5). The
  /// caller runs the device-credential check first. A same-state
  /// `userUpdated` does not arrive over [states], so the returned user is
  /// adopted into [currentUser] directly and listeners are notified here
  /// (#31 finding 2).
  Future<AuthUser> linkGoogle() => _adopting(_service.linkGoogle());

  Future<AuthUser> linkApple() => _adopting(_service.linkApple());

  /// Removes a sign-in method from the current account (#31 U3). Like
  /// [linkGoogle] / [linkApple], the caller runs the device-credential
  /// check first, and the returned user is adopted the same way.
  Future<AuthUser> unlinkProvider(String provider) =>
      _adopting(_service.unlinkProvider(provider));

  /// Awaits [call], adopts its result into [currentUser], and notifies
  /// listeners — shared by [linkGoogle], [linkApple], and
  /// [unlinkProvider] so every caller (not just the one that made the
  /// call) sees the fresh user (#31 finding 2). A failed [call] propagates
  /// unchanged; nothing is adopted and no notification fires.
  Future<AuthUser> _adopting(Future<AuthUser> call) async {
    final user = await call;
    _adoptFreshUser(user);
    notifyListeners();
    return user;
  }

  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local}) =>
      _service.signOut(scope: scope);

  void _onState(AuthSessionState next) {
    if (next == _state) {
      // A same-state signal (e.g. Supabase's `userUpdated` event, or a
      // token refresh) can still carry a genuinely newer user under the
      // same id — e.g. a real unlink elsewhere. When a [_freshUser] is
      // cached, drop it so [currentUser] re-reads the service's fresh
      // value instead of serving a stale cached one for the rest of the
      // app session (#31 finding 2 round 2); with nothing cached, a
      // repeated identical state (a plain token refresh) still notifies
      // no one, unchanged from before.
      if (_freshUser != null) {
        _freshUser = null;
        notifyListeners();
      }
      return;
    }
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
