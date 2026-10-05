part of 'supabase_auth_service.dart';

// Identity-link state machine for [SupabaseAuthService] (part of
// `supabase_auth_service.dart`, mixed into the class below): link handling,
// the PKCE exchange it drives, auth-event mapping, the recovery latch, and
// the session-state surface of [AuthService]. Provider sign-in flows live
// in `supabase_auth_providers.dart`.
// Moved verbatim from `supabase_auth_service.dart` (#436); requirement tags
// move with the members they document.

/// Link-state members mixed into [SupabaseAuthService].
mixin SupabaseAuthSessionState {
  AuthGateway get _gateway;
  AuthLinkSource get _links;

  StreamController<AuthSessionState> get _states;
  StreamController<AuthFailure> get _linkFailures;

  AuthSessionState get _state;
  set _state(AuthSessionState value);

  bool get _pendingRecovery;
  set _pendingRecovery(bool value);

  AuthFailure? get _pendingLinkFailure;
  set _pendingLinkFailure(AuthFailure? value);

  bool get _started;
  set _started(bool value);

  String? get _lastHandledLink;
  set _lastHandledLink(String? value);

  StreamSubscription<AuthState>? get _eventSub;
  set _eventSub(StreamSubscription<AuthState>? value);

  StreamSubscription<Uri>? get _linkSub;
  set _linkSub(StreamSubscription<Uri>? value);

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
    if (initial != null) unawaited(handleLink(initial));
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
      // GoTrue emits signedIn before getSessionFromUrl returns. Clear the
      // stale failure first so observers of that event cannot capture it.
      _pendingLinkFailure = null;
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
        // gotrue emits `signedIn` directly when a magic link replaces a
        // live session — no preceding `signedOut` (vendored gotrue-2.27.2's
        // own comments on `getSessionFromUrl`). That silently ends whatever
        // account was signed in before, so this is also a session-ending
        // path (KTD7): without this clear, on a shared device the account
        // signing in here would inherit the outgoing account's breadcrumbs,
        // which then ride into *its own* support ticket `device_info` — the
        // cross-account leak this file already guards against on every
        // other transition.
        defaultBreadcrumbLog.clear();
        _setState(_sessionState);
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
    // Every `signedOut` event ends this device's session with *some*
    // account — a local sign-out, "sign out everywhere" landing here from
    // another device, or gotrue detecting an expired/missing session on its
    // own. `resetDevice` clears the ring for its own path (KTD16); this is
    // the gate for every other one, so breadcrumbs recorded under the
    // account that just left can never ride into a ticket filed by whoever
    // is signed in next on a shared device.
    defaultBreadcrumbLog.clear();
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

  AuthSessionState get state => _state;

  Stream<AuthSessionState> get states => _states.stream;

  bool get pendingRecovery => _pendingRecovery;

  void consumeRecovery() {
    if (!_pendingRecovery) return;
    _pendingRecovery = false;
    _setState(_gateway.currentSession == null
        ? AuthSessionState.signedOut
        : AuthSessionState.signedIn);
  }

  AuthFailure? get pendingLinkFailure => _pendingLinkFailure;

  Stream<AuthFailure> get linkFailures => _linkFailures.stream;

  void consumeLinkFailure() => _pendingLinkFailure = null;

  AuthUser? get currentUser => _toUser(_gateway.currentSession?.user);

  String? get currentUserId => _gateway.currentSession?.user.id;

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _linkSub?.cancel();
    await _states.close();
    await _linkFailures.close();
  }
}
