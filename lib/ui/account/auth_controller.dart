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
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

export 'package:lunarlog/domain/auth/auth_service.dart' show AuthSignOutScope;

class AuthController extends ChangeNotifier {
  AuthController({required AuthService authService, bool? mfaEnabled})
      : _service = authService,
        _state = authService.state,
        mfaEnabled = mfaEnabled ?? AppConfig.mfaEnabled {
    _stateSub = authService.states.listen(_onState);
    _failureSub = authService.linkFailures.listen((_) => notifyListeners());
  }

  final AuthService _service;
  AuthSessionState _state;
  StreamSubscription<AuthSessionState>? _stateSub;
  StreamSubscription<AuthFailure>? _failureSub;

  /// Whether the TOTP MFA client surface is available in this build
  /// (issue #738): the compile-time `LUNARLOG_ENABLE_MFA=true` define,
  /// resolved once here — the only place outside `AppConfig` itself that
  /// reads the flag (pinned by `test/architecture/mfa_flag_seam_test.dart`).
  ///
  /// The `showGoogle`/`showApple` null-means-AppConfig injection precedent:
  /// production (`LunarLogApp`) constructs this controller without the
  /// parameter, so the const applies; widget tests pass `true` to exercise
  /// #714's MFA-on behavior in a single default-off test run. While false
  /// (the default in every CI/workflow build): [requiresMfaStepUp] is
  /// always false, `ensureAal2` auto-passes, and the Account section's
  /// "Two-factor authentication" tile group renders nothing. A future
  /// build flag (issue #739's QA-build step-up bypass) composes by OR-ing
  /// into exactly one of those gates rather than re-reading the define.
  final bool mfaEnabled;

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

  Future<NativeSignInResult> signInWithAppleNative() =>
      _service.signInWithAppleNative();

  Future<NativeSignInResult> signInWithGoogleNative() =>
      _service.signInWithGoogleNative();

  /// Passkey sign-in (#30 U4; KTD5), mirroring
  /// [signInWithGoogleNative]/[signInWithAppleNative] exactly: no adoption
  /// step, since the resulting session's `signedIn` state arrives through
  /// [states] like every other sign-in path.
  Future<NativeSignInResult> signInWithPasskey() =>
      _service.signInWithPasskey();

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

  /// Adds a passkey to the current account (#30 U4; KTD5). Unlike
  /// [linkGoogle]/[linkApple], a passkey is never an identity provider
  /// (R10), so [NativeSignInResult] — not a bare [AuthUser] — is the
  /// return type; only a non-cancelled [NativeSignInSession] adopts
  /// its user and notifies listeners, the same adoption [_adopting] gives
  /// every other add-a-method call.
  Future<NativeSignInResult> registerPasskey() async {
    final result = await _service.registerPasskey();
    if (result is NativeSignInSession) {
      _adoptFreshUser(result.user);
      notifyListeners();
    }
    return result;
  }

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

  // -------------------------------------------------------------- MFA
  // Thin delegations (#268): no adoption step needed — the settings
  // screen re-reads [listMfaFactors] itself after each mutation, and a
  // step-up's session promotion arrives through [AuthService.states] like
  // every other session change.

  Future<TotpEnrollmentOffer> enrollTotp() => _service.enrollTotp();

  Future<void> verifyTotpCode({required String factorId, required String code}) =>
      _service.verifyTotpCode(factorId: factorId, code: code);

  Future<List<MfaFactor>> listMfaFactors() => _service.listMfaFactors();

  Future<void> unenrollMfaFactor(String factorId) =>
      _service.unenrollMfaFactor(factorId);

  AuthAssuranceLevel? get assuranceLevel => _service.assuranceLevel;

  /// Issue #738: with [mfaEnabled] false (the default build) this is
  /// always false — no account can demand an AAL2 step-up, because no
  /// client can enrol a factor in the first place. The service is never
  /// consulted, so the flag-off posture is structural rather than a
  /// filtered-away answer.
  Future<bool> requiresMfaStepUp() async {
    if (!mfaEnabled) return false;
    return _service.requiresMfaStepUp();
  }

  void _onState(AuthSessionState next) {
    // Any incoming state notification — a same-state signal (e.g.
    // Supabase's `userUpdated` event, or a token refresh) *or* a real
    // transition — can carry a genuinely newer user under the same id:
    // a real unlink elsewhere, or a round trip like
    // signedIn -> passwordRecovery -> signedIn or
    // signedIn -> signedOut -> signedIn that settles back under the same
    // user. This clear must run unconditionally, above the dedupe
    // early-return below, so it fires on transitions too — not just
    // same-state echoes — and [currentUser] re-reads the service's fresh
    // value instead of serving a stale cached one for the rest of the app
    // session (#31 finding 2 round 3).
    final hadFreshUser = _freshUser != null;
    _freshUser = null;

    if (next == _state) {
      // With nothing cached, a repeated identical state (a plain token
      // refresh) still notifies no one, unchanged from before. When a
      // [_freshUser] was just cleared above, that alone is a visible
      // change, so notify for it even though the state itself didn't move.
      if (hadFreshUser) {
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
