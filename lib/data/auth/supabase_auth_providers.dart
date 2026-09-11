part of 'supabase_auth_service.dart';

// Sign-in providers for [SupabaseAuthService] (part of
// `supabase_auth_service.dart`, mixed into the class below): email/password,
// native Apple, native Google, passwordless email, passkeys, and the
// identity-link/unlink state machine over `linkIdentityWithIdToken`.
// The link-exchange and session-state machine live in
// `supabase_auth_session_state.dart`.
// Moved verbatim from `supabase_auth_service.dart` (#436); requirement tags
// move with the members they document.

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
    case 'single_identity_not_deletable':
      return const AuthFailure.lastSignInMethod();
  }
  final bucketed = _mapThrottlingOrMisconfigured(error);
  if (bucketed != null) return bucketed;
  // Older GoTrue servers send no code for a bad login, only the message.
  if (error.statusCode == '400' &&
      error.message.toLowerCase().contains('invalid login credentials')) {
    return const AuthFailure.wrongPassword();
  }
  return const AuthFailure.unknown();
}

/// Issue #32's soft-bucket codes (AC2, AC4), split out of
/// [_mapGoTrueAuthException] purely to keep that method's cyclomatic
/// complexity under the CRAP gate's threshold — same mapping, no behavior
/// change. Null when neither applies.
///
/// * `over_request_rate_limit` (or a code-less 429) is throttled, not
///   rejected — kept distinct from invalidCode so a 429 on verifyOTP never
///   reads as a bad code.
/// * `manual_linking_disabled` / `email_provider_disabled` mean the
///   dashboard is not set up for this operation — kept distinct from
///   unknown so a misconfigured project does not read as a bug in-app.
AuthFailure? _mapThrottlingOrMisconfigured(AuthException error) {
  switch (error.code) {
    case 'over_request_rate_limit':
      return const AuthFailure.rateLimited();
    case 'manual_linking_disabled':
    case 'email_provider_disabled':
      return const AuthFailure.misconfigured();
  }
  // Some GoTrue rate-limit responses carry no code, only the 429 status.
  if (error.statusCode == '429') return const AuthFailure.rateLimited();
  return null;
}

bool _isNetworkShapedError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException;

AuthUser? _toUser(User? user) => user == null
      ? null
      : AuthUser(id: user.id, email: user.email, providers: _providersOf(user));

/// Provider names from `identities`, falling back to
/// `app_metadata.providers` when the user carries no identity list
/// (#2 KTD5). Never `user_metadata`, which the user can write. Order is
/// preserved, duplicates dropped.
List<String> _providersOf(User user) {
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

/// Provider sign-in and identity-linking members mixed into
/// [SupabaseAuthService].
mixin SupabaseAuthProviders on SupabaseAuthSessionState {
  String get _redirectTo;
  bool get _appleAvailable;
  AppleCredentialRequest get _requestAppleCredential;
  bool get _googleAvailable;
  GoogleSignInClient get _googleClient;
  String Function() get _generateNonce;
  bool get _passkeysAvailable;
  PasskeyCeremonyClient get _passkeyClient;

  ({String raw, String hashed})? get _googleNonce;
  set _googleNonce(({String raw, String hashed})? value);

  bool get _googleInitialized;
  set _googleInitialized(bool value);

  // --- AuthService (providers) ---

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

  Future<void> sendPasswordReset(String email) => _guard(
      () => _gateway.resetPasswordForEmail(email, redirectTo: _redirectTo));

  Future<void> updatePassword(String newPassword) =>
      _guard(() => _gateway.updateUser(UserAttributes(password: newPassword)));

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

  /// Passkey sign-in (#30 U3; KTD1, KTD2, KTD4). No session required: start
  /// -> hand the options to the ceremony client -> null means cancelled ->
  /// verify. Every gateway and ceremony error is reduced to a typed
  /// [AuthFailure] through [_guard]; a verify response with no session is
  /// [AuthUnknownFailure], as every sibling sign-in method treats it.
  Future<PasskeySignInResult> signInWithPasskey() async {
    _requirePasskeys();
    final started = await _guard(() => _gateway.startPasskeyAuthentication());
    final assertion = await _guard(() => _passkeyClient.get(started.options));
    if (assertion == null) return const PasskeySignInCancelled();
    final response = await _guard(() => _gateway.verifyPasskeyAuthentication(
          challengeId: started.challengeId,
          credential: assertion,
        ));
    final user = response.session?.user;
    if (user == null) throw const AuthFailure.unknown();
    return PasskeySignInSession(_toUser(user)!);
  }

  /// Adds a passkey for the current account (#30 U3; KTD1, KTD2, KTD4). The
  /// signed-in check runs before any gateway or ceremony call, as
  /// [linkGoogle]'s does. Passkeys are not identity providers (R10): unlike
  /// [_link], this never touches `AuthUser.providers` — the returned user
  /// is read fresh from [currentUser] after the verify call rather than a
  /// value captured beforehand, so a caller never sees a stale snapshot.
  Future<PasskeyRegistrationResult> registerPasskey() async {
    _requirePasskeys();
    _requireSignedInUser();
    final started = await _guard(() => _gateway.startPasskeyRegistration());
    final credential = await _guard(() => _passkeyClient.create(started.options));
    if (credential == null) return const PasskeyRegistrationCancelled();
    await _guard(() => _gateway.verifyPasskeyRegistration(
          challengeId: started.challengeId,
          credential: credential,
        ));
    final user = currentUser;
    if (user == null) throw const AuthFailure.unknown();
    return PasskeyRegistrationSuccess(user);
  }

  void _requirePasskeys() {
    if (!_passkeysAvailable) {
      throw UnsupportedError('Passkeys are not available in this build');
    }
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

  /// Removes [provider] as a sign-in method (#31 U2; KTD1, KTD2, KTD3,
  /// KTD4, KTD5). `email` is rejected before the signed-in check so the
  /// UI's mistake never reaches the network (R11); every other branch runs
  /// inside [_guard] so `single_identity_not_deletable` mapping stays in
  /// one place.
  Future<AuthUser> unlinkProvider(String provider) async {
    if (provider == AuthProviders.email) throw const AuthFailure.unknown();
    final current = _requireSignedInUser();
    return _guard(() => _removeIdentity(provider, current));
  }

  /// Read -> guard -> delete -> refresh (KTD3). [current] is only used for
  /// `id`/`email`; when the account no longer holds [provider] (R10,
  /// idempotent removal) the returned providers still come from the fresh
  /// read above, not from [current], so this branch cannot disagree with
  /// what the server actually has.
  Future<AuthUser> _removeIdentity(String provider, AuthUser current) async {
    final identities = await _gateway.getUserIdentities();
    UserIdentity? target;
    for (final identity in identities) {
      if (identity.provider == provider) {
        target = identity;
        break;
      }
    }
    if (target == null) {
      // `identities` is already the fresh read above; build the returned
      // user from it rather than the caller's stale pre-call snapshot, so
      // this idempotent branch cannot disagree with what the server
      // actually has (consistent with the success path below). But an
      // empty read here is itself degraded (or identity-less), not proof
      // the account has no providers — fall back to the pre-call snapshot
      // rather than returning an empty provider list.
      if (identities.isEmpty) return current;
      return AuthUser(
        id: current.id,
        email: current.email,
        providers: identities.map((identity) => identity.provider).toSet().toList(),
      );
    }
    if (identities.length < 2) throw const AuthFailure.lastSignInMethod();
    await _gateway.unlinkIdentity(target);
    // A refresh failure here does not undo the delete; the identity is
    // already gone server-side, so reporting an error for a completed
    // action is worse than a brief stale `currentSession` (KTD4). Track
    // success explicitly: `currentSession` is non-null either way while
    // signed in, so its nullity cannot distinguish the two cases.
    var refreshSucceeded = true;
    try {
      await _gateway.refreshSession();
    } catch (error) {
      refreshSucceeded = false;
      debugPrint(
          'lunarlog auth: post-unlink refresh failed (${error.runtimeType})');
    }
    if (refreshSucceeded) {
      final refreshedUser = _gateway.currentSession?.user;
      if (refreshedUser != null) return _toUser(refreshedUser)!;
    }
    final removedId = target.identityId;
    final remaining = identities
        .where((identity) => identity.identityId != removedId)
        .map((identity) => identity.provider)
        .toSet()
        .toList();
    return AuthUser(
        id: current.id, email: current.email, providers: remaining);
  }

  /// Sends the sign-in email (#2 U7; KTD3). In sign-in mode the server's
  /// `otp_disabled` rejection of an unknown email is treated as success so
  /// a known and an unknown email get one response (R6, AE3); in create
  /// mode `signup_disabled` maps to [AuthSignUpClosedFailure] through
  /// [mapAuthError].
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
  /// network failure, a closed sign-up, a throttled request (issue #32
  /// AC2: `over_request_rate_limit`/429 keeps its own kind so it never
  /// reads as a bad code), a misconfigured dashboard (issue #32 AC4), and
  /// a server error keep their own kinds. The `signedIn` state arrives
  /// through `onAuthStateChange`, as for a password sign-in.
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
    if (mapped is AuthNetworkFailure ||
        mapped is AuthSignUpClosedFailure ||
        mapped is AuthRateLimitedFailure ||
        mapped is AuthMisconfiguredFailure) {
      return false;
    }
    if (error.code == 'otp_expired' || error.code == 'otp_disabled') {
      return true;
    }
    return error.statusCode?.startsWith('4') ?? false;
  }

  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local}) =>
      _guard(() => _gateway.signOut(
            scope: switch (scope) {
              AuthSignOutScope.local => SignOutScope.local,
              AuthSignOutScope.global => SignOutScope.global,
            },
          ));

  /// Runs [body], rethrowing anything as a typed [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(mapAuthError(error), stackTrace);
    }
  }
}
