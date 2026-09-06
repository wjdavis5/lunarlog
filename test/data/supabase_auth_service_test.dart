/// U4 (KTD8, KTD9, R1–R3): [SupabaseAuthService] over a fake gateway and a
/// fake link source — link classification, the PKCE exchange it drives
/// itself, the recovery latch set before any widget exists, typed failure
/// mapping with no provider text, and the native Apple flow. The native
/// Google flow (#2 U2; KTD1, KTD8; AE1, AE2) runs over a fake
/// [GoogleSignInClient] so no test touches the plugin. Passwordless email
/// (#2 U7; KTD3, KTD4; AE3) covers the uniform unknown-email response and
/// the by-operation mapping of link and code failures. Sign-in methods and
/// identity linking (#2 U8; KTD5; AE6, R15) run the same credential paths
/// against `linkIdentityWithIdToken` on the fake gateway.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lunarlog/data/auth/auth_gateway.dart';
import 'package:lunarlog/data/auth/auth_link_classifier.dart';
import 'package:lunarlog/data/auth/google_sign_in_client.dart';
import 'package:lunarlog/data/auth/supabase_auth_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

User makeUser(
  String id, {
  String? email,
  List<String>? identities,
  Map<String, dynamic> appMetadata = const {},
}) =>
    User(
      id: id,
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-09-02T00:00:00Z',
      email: email,
      identities: identities
          ?.map((provider) => UserIdentity(
                id: '$provider-$id',
                userId: id,
                identityData: const {},
                identityId: '$provider-$id',
                provider: provider,
                createdAt: '2026-09-02T00:00:00Z',
                lastSignInAt: '2026-09-02T00:00:00Z',
              ))
          .toList(),
    );

Session makeSession(
  String id, {
  String? email,
  List<String>? identities,
  Map<String, dynamic> appMetadata = const {},
}) =>
    Session(
      accessToken: 'access-$id',
      tokenType: 'bearer',
      refreshToken: 'refresh-$id',
      user: makeUser(
        id,
        email: email,
        identities: identities,
        appMetadata: appMetadata,
      ),
    );

/// Mimics the slice of `GoTrueClient` the service relies on, including
/// gotrue's own PKCE behaviour: the exchange fails without a stored
/// verifier, and a verifier stored by `resetPasswordForEmail` carries the
/// `passwordRecovery` event name.
class FakeAuthGateway implements AuthGateway {
  final StreamController<AuthState> events =
      StreamController<AuthState>.broadcast();

  Session? session;

  /// Stored PKCE verifier (`verifier` or `verifier/passwordRecovery`).
  String? codeVerifier;

  Object? nextError;

  AuthResponse? signUpResponse;

  /// When set, every sign-in path (password, ID token, code) yields a
  /// session for this user id, so R15 can compare `currentUserId` across
  /// paths.
  String? fixedUserId;

  Completer<void>? getSessionFromUrlGate;
  bool deliverAuthEventBeforeReturn = false;

  final getSessionFromUrlCalls = <Uri>[];
  final signUpCalls = <({String email, String password, String? redirect})>[];
  final signInCalls = <({String email, String password})>[];
  final resetCalls = <({String email, String? redirect})>[];
  final updateUserCalls = <UserAttributes>[];
  final idTokenCalls = <({
    OAuthProvider provider,
    String idToken,
    String? accessToken,
    String? nonce,
  })>[];
  final signOutCalls = <SignOutScope>[];
  final otpCalls =
      <({String email, String? redirect, bool shouldCreateUser})>[];
  final verifyOtpCalls = <({String email, String token, OtpType type})>[];
  final linkIdentityCalls = <({
    OAuthProvider provider,
    String idToken,
    String? accessToken,
    String? nonce,
  })>[];
  final unlinkIdentityCalls = <UserIdentity>[];
  final getUserIdentitiesCalls = <void>[];
  int refreshSessionCalls = 0;

  /// When true, [refreshSession] throws instead of applying a pending
  /// [unlinkIdentity] delete to [session] (#31 U2; KTD4).
  bool refreshSessionShouldFail = false;

  /// Identity ids deleted by [unlinkIdentity] but not yet applied to
  /// [session] — mirrors gotrue: the delete stores nothing locally until
  /// [refreshSession] pulls a fresh session (#31 KTD3, KTD4).
  final _pendingUnlinkedIdentityIds = <String>[];

  /// When set, [getUserIdentities] returns this list verbatim instead of
  /// deriving it from [session] — independent of the local pre-call
  /// snapshot, so a test can model the server's fresh read disagreeing
  /// with the stale local `session` a caller took before the call (#31
  /// P1: a real fresh-server-read-after-removal test needs this
  /// divergence, which deriving from `session` alone cannot express).
  List<UserIdentity>? getUserIdentitiesOverride;

  void _maybeThrow() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  void emit(AuthChangeEvent event, {SignOutReason? reason}) {
    events.add(AuthState(event, session, signOutReason: reason));
  }

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Session? get currentSession => session;

  @override
  Future<AuthSessionUrlResponse> getSessionFromUrl(Uri uri) async {
    getSessionFromUrlCalls.add(uri);
    await getSessionFromUrlGate?.future;
    _maybeThrow();
    final params = uri.queryParameters;
    if (params.containsKey('error_description') ||
        params.containsKey('error')) {
      throw AuthException(
        params['error_description'] ?? 'unspecified',
        code: params['error'],
      );
    }
    final verifier = codeVerifier;
    if (verifier == null) {
      throw const AuthException(
          'Code verifier could not be found in local storage.');
    }
    codeVerifier = null;
    final recovery = verifier.endsWith('/passwordRecovery');
    session = makeSession('linked');
    emit(recovery ? AuthChangeEvent.passwordRecovery : AuthChangeEvent.signedIn);
    if (deliverAuthEventBeforeReturn) await Future<void>.delayed(Duration.zero);
    return AuthSessionUrlResponse(
      session: session!,
      redirectType: recovery ? 'passwordRecovery' : null,
    );
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  }) async {
    signUpCalls.add((email: email, password: password, redirect: emailRedirectTo));
    _maybeThrow();
    final response = signUpResponse ?? AuthResponse(user: makeUser('new'));
    if (response.session != null) {
      session = response.session;
      emit(AuthChangeEvent.signedIn);
    }
    return response;
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls.add((email: email, password: password));
    _maybeThrow();
    session = makeSession(fixedUserId ?? 'pw', email: email);
    emit(AuthChangeEvent.signedIn);
    return AuthResponse(session: session);
  }

  @override
  Future<void> resetPasswordForEmail(String email, {String? redirectTo}) async {
    resetCalls.add((email: email, redirect: redirectTo));
    _maybeThrow();
    codeVerifier = 'verifier/passwordRecovery';
  }

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) async {
    updateUserCalls.add(attributes);
    _maybeThrow();
    emit(AuthChangeEvent.userUpdated);
    return UserResponse.fromJson({'user': session?.user.toJson()});
  }

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) async {
    idTokenCalls.add((
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
    ));
    _maybeThrow();
    session = makeSession(fixedUserId ?? provider.name);
    emit(AuthChangeEvent.signedIn);
    return AuthResponse(session: session);
  }

  /// Like gotrue: requires a session, appends the identity to the current
  /// user, saves the session, and emits `userUpdated` (#2 U8; KTD5).
  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) async {
    linkIdentityCalls.add((
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
    ));
    _maybeThrow();
    final current = session;
    if (current == null) throw const AuthException('no session to link');
    final existing =
        current.user.identities?.map((i) => i.provider).toList() ?? const [];
    session = Session(
      accessToken: current.accessToken,
      tokenType: current.tokenType,
      refreshToken: current.refreshToken,
      user: makeUser(
        current.user.id,
        email: current.user.email,
        identities: [...existing, provider.name],
        appMetadata: current.user.appMetadata,
      ),
    );
    emit(AuthChangeEvent.userUpdated);
    return AuthResponse(session: session);
  }

  /// Fresh read, like gotrue's own `getUser()`-backed implementation: it
  /// sees a delete recorded by [unlinkIdentity] even before [refreshSession]
  /// has applied it to [session] (#31 U2; KTD3). When
  /// [getUserIdentitiesOverride] is set it wins outright, independent of
  /// [session] and any pending unlink, so a test can make the server's
  /// answer diverge from the stale local snapshot taken before the call.
  @override
  Future<List<UserIdentity>> getUserIdentities() async {
    getUserIdentitiesCalls.add(null);
    _maybeThrow();
    final override = getUserIdentitiesOverride;
    if (override != null) return override;
    final identities = session?.user.identities ?? const <UserIdentity>[];
    if (_pendingUnlinkedIdentityIds.isEmpty) return identities;
    return identities
        .where((identity) =>
            !_pendingUnlinkedIdentityIds.contains(identity.identityId))
        .toList();
  }

  /// Like gotrue: a bare server-side delete that stores nothing locally
  /// (#31 U2; KTD3, KTD4) — [refreshSession] is what updates [session].
  @override
  Future<void> unlinkIdentity(UserIdentity identity) async {
    unlinkIdentityCalls.add(identity);
    _maybeThrow();
    if (session == null) {
      throw const AuthException('no session to unlink');
    }
    _pendingUnlinkedIdentityIds.add(identity.identityId);
  }

  @override
  Future<void> refreshSession() async {
    refreshSessionCalls++;
    if (refreshSessionShouldFail) {
      throw AuthRetryableFetchException(message: 'offline');
    }
    final current = session;
    if (current == null || _pendingUnlinkedIdentityIds.isEmpty) return;
    final existing = current.user.identities ?? const <UserIdentity>[];
    session = Session(
      accessToken: current.accessToken,
      tokenType: current.tokenType,
      refreshToken: current.refreshToken,
      user: makeUser(
        current.user.id,
        email: current.user.email,
        identities: existing
            .where((identity) =>
                !_pendingUnlinkedIdentityIds.contains(identity.identityId))
            .map((identity) => identity.provider)
            .toList(),
        appMetadata: current.user.appMetadata,
      ),
    );
    _pendingUnlinkedIdentityIds.clear();
  }

  @override
  Future<void> signOut({required SignOutScope scope}) async {
    signOutCalls.add(scope);
    _maybeThrow();
    session = null;
    emit(AuthChangeEvent.signedOut, reason: SignOutReason.userInitiated);
  }

  /// Like gotrue, stores a PKCE verifier so the emailed link can be
  /// exchanged on this device (#2 U7; KTD3).
  @override
  Future<void> signInWithOtp({
    required String email,
    String? emailRedirectTo,
    required bool shouldCreateUser,
  }) async {
    otpCalls.add((
      email: email,
      redirect: emailRedirectTo,
      shouldCreateUser: shouldCreateUser,
    ));
    _maybeThrow();
    codeVerifier = 'verifier';
  }

  @override
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    required OtpType type,
  }) async {
    verifyOtpCalls.add((email: email, token: token, type: type));
    _maybeThrow();
    session = makeSession(fixedUserId ?? 'otp', email: email);
    emit(AuthChangeEvent.signedIn);
    return AuthResponse(session: session);
  }
}

/// Records `initialize` arguments and returns a configured credential or
/// throws a configured error from `authenticate`, standing in for the
/// `google_sign_in` plugin (#2 U2; KTD1).
class FakeGoogleSignInClient implements GoogleSignInClient {
  FakeGoogleSignInClient({
    this.credential = const GoogleCredential(idToken: 'google-id-token'),
    this.authenticateError,
  });

  GoogleCredential? credential;
  Object? authenticateError;

  final initializeCalls = <({
    String? iosClientId,
    String webClientId,
    String hashedNonce,
  })>[];
  int authenticateCalls = 0;

  @override
  Future<void> initialize({
    required String? iosClientId,
    required String webClientId,
    required String hashedNonce,
  }) async {
    initializeCalls.add((
      iosClientId: iosClientId,
      webClientId: webClientId,
      hashedNonce: hashedNonce,
    ));
  }

  @override
  Future<GoogleCredential> authenticate() async {
    authenticateCalls++;
    final error = authenticateError;
    if (error != null) throw error;
    final result = credential;
    if (result == null) throw StateError('no credential configured');
    return result;
  }
}

class FakeLinkSource implements AuthLinkSource {
  FakeLinkSource({this.initial});

  Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();
  int initialLinkCalls = 0;

  @override
  Future<Uri?> initialLink() async {
    initialLinkCalls++;
    return initial;
  }

  @override
  Stream<Uri> get links => controller.stream;
}

const callback = 'lunarlog://auth-callback';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAuthGateway gateway;
  late FakeLinkSource links;

  setUp(() {
    gateway = FakeAuthGateway();
    links = FakeLinkSource();
  });

  tearDown(() async {
    await gateway.events.close();
    await links.controller.close();
  });

  Future<SupabaseAuthService> started({
    bool appleAvailable = false,
    AppleCredentialRequest? requestAppleCredential,
    bool googleAvailable = false,
    GoogleSignInClient? googleClient,
    String Function()? generateNonce,
  }) async {
    final service = SupabaseAuthService(
      gateway: gateway,
      links: links,
      appleAvailable: appleAvailable,
      requestAppleCredential:
          requestAppleCredential ?? (({required hashedNonce}) async {
            throw StateError('not expected');
          }),
      googleAvailable: googleAvailable,
      googleClient: googleClient ??
          FakeGoogleSignInClient(
            authenticateError: StateError('not expected'),
          ),
      generateNonce: generateNonce ?? generateRawNonce,
    );
    addTearDown(service.dispose);
    await service.start();
    return service;
  }

  group('link classification (pure)', () {
    test('a code link is a callback; type=recovery marks recovery', () {
      expect(classifyAuthLink(Uri.parse('$callback?code=abc')),
          const AuthLinkCallback(recovery: false));
      expect(
          classifyAuthLink(Uri.parse('$callback?code=abc&type=recovery')),
          const AuthLinkCallback(recovery: true));
      // Implicit-flow tokens are never a callback, recovery or not.
      expect(classifyAuthLink(Uri.parse('$callback#access_token=x&type=recovery')),
          const AuthLinkError());
    });

    test('implicit access_token / refresh_token fragments are an error, '
        'never a callback (PKCE only)', () {
      expect(
          classifyAuthLink(Uri.parse(
              '$callback#access_token=x&refresh_token=y&type=recovery')),
          const AuthLinkError());
      expect(classifyAuthLink(Uri.parse('$callback?refresh_token=y')),
          const AuthLinkError());
      expect(
          classifyAuthLink(Uri.parse('$callback?code=abc&access_token=x')),
          const AuthLinkError(),
          reason: 'a token alongside a code still poisons the link');
    });

    test('a custom-scheme link on another host is ignored', () {
      expect(classifyAuthLink(Uri.parse('lunarlog://other?code=x')),
          const AuthLinkIgnored());
      expect(classifyAuthLink(Uri.parse('lunarlog://other#access_token=x')),
          const AuthLinkIgnored());
    });

    test('error parameters classify as an error and carry no text', () {
      final link = classifyAuthLink(Uri.parse(
          '$callback?error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired'));
      expect(link, const AuthLinkError());
      expect(link.toString(), isNot(contains('expired')));
      expect(link.toString(), isNot(contains('access_denied')));
    });

    test('links without auth parameters are ignored', () {
      expect(classifyAuthLink(Uri.parse(callback)), const AuthLinkIgnored());
      expect(classifyAuthLink(Uri.parse('https://example.com/?foo=bar')),
          const AuthLinkIgnored());
    });
  });

  group('redirect URL (pure)', () {
    test('native uses the custom scheme; web uses the page origin', () {
      expect(resolveAuthRedirectUrl(isWeb: false, base: Uri.parse('https://x.y/z')),
          callback);
      expect(
          resolveAuthRedirectUrl(
              isWeb: true, base: Uri.parse('https://lunarlog.example/app/?a=1')),
          'https://lunarlog.example');
    });
  });

  group('deep links (KTD8)', () {
    test('start() completes immediately on cold start with initial link without awaiting network exchange', () async {
      final gate = Completer<void>();
      gateway.getSessionFromUrlGate = gate;
      gateway.codeVerifier = 'verifier';
      links.initial = Uri.parse('$callback?code=abc');

      var startedCompleted = false;
      final serviceFuture = started().then((s) {
        startedCompleted = true;
        return s;
      });
      await Future<void>.delayed(Duration.zero);
      expect(startedCompleted, isTrue, reason: 'start() must not await getSessionFromUrl');
      final service = await serviceFuture;
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(service.state, AuthSessionState.signedOut);

      gate.complete();
      await settle();
      expect(service.state, AuthSessionState.signedIn);
    });

    test('a recovery link with a stored verifier is exchanged and latches '
        'recovery before any subscriber exists', () async {
      gateway.codeVerifier = 'verifier/passwordRecovery';
      links.initial = Uri.parse('$callback?code=abc');
      final service = await started();
      await settle();

      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(service.pendingRecovery, isTrue);
      expect(service.state, AuthSessionState.passwordRecovery);
      expect(service.currentUserId, 'linked');

      // A late subscriber (the controller) sees the latch on first read.
      final controller = AuthController(authService: service);
      addTearDown(controller.dispose);
      expect(controller.pendingRecovery, isTrue);
      expect(controller.state, AuthSessionState.passwordRecovery);

      service.consumeRecovery();
      await settle();
      expect(service.pendingRecovery, isFalse);
      expect(service.state, AuthSessionState.signedIn);
      expect(controller.state, AuthSessionState.signedIn);
    });

    test('a link whose query says type=recovery latches even when the '
        'exchange reports a plain sign-in', () async {
      gateway.codeVerifier = 'verifier';
      final service = await started();
      await service.handleLink(Uri.parse('$callback?code=abc&type=recovery'));
      expect(service.pendingRecovery, isTrue);
      expect(service.state, AuthSessionState.passwordRecovery);
    });

    test('a confirmation link with a stored verifier signs in without '
        'latching recovery', () async {
      gateway.codeVerifier = 'verifier';
      final service = await started();
      links.controller.add(Uri.parse('$callback?code=abc'));
      await settle();
      expect(service.state, AuthSessionState.signedIn);
      expect(service.pendingRecovery, isFalse);
      expect(service.currentUserId, 'linked');
    });

    test('a link with no matching verifier (opened on another device) '
        'yields no session, stays signedOut, and surfaces expiredLink '
        '(#2 KTD4)', () async {
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      await service.handleLink(Uri.parse('$callback?code=abc'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(service.state, AuthSessionState.signedOut);
      expect(service.currentUserId, isNull);
      expect(service.pendingRecovery, isFalse);
      expect(service.pendingLinkFailure, isA<AuthExpiredLinkFailure>());
      expect(failures, hasLength(1));
    });

    test('a link carrying error_description is never exchanged and the '
        'failure carries none of the link text', () async {
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      await service.handleLink(Uri.parse(
          '$callback?error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      final failure = service.pendingLinkFailure;
      expect(failure, isA<AuthExpiredLinkFailure>());
      // The fieldless type name and nothing else: none of the link's
      // error_description ("Email link is invalid or has expired") or codes.
      expect(failure.toString(), 'AuthFailure.expiredLink');
      expect(failure.toString(), isNot(contains('Email')));
      expect(failure.toString(), isNot(contains('invalid')));
      expect(failure.toString(), isNot(contains('otp')));
      expect(failure.toString(), isNot(contains('access_denied')));
      expect(failures.single, same(failure));
      service.consumeLinkFailure();
      expect(service.pendingLinkFailure, isNull);
    });

    test('a link carrying implicit tokens never reaches getSessionFromUrl '
        'and surfaces a typed failure', () async {
      gateway.codeVerifier = 'verifier';
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      await service.handleLink(Uri.parse(
          '$callback#access_token=attacker&refresh_token=r&type=recovery'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      expect(service.currentUserId, isNull);
      expect(service.pendingRecovery, isFalse);
      expect(service.pendingLinkFailure, isA<AuthExpiredLinkFailure>());
      expect(failures, hasLength(1));
      expect(failures.single.toString(), isNot(contains('attacker')));
    });

    test('links without auth parameters are ignored', () async {
      final service = await started();
      await service.handleLink(Uri.parse(callback));
      await service.handleLink(Uri.parse('https://example.com/?x=1'));
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(service.pendingLinkFailure, isNull);
    });

    test('a custom-scheme link on another host is ignored, code or not',
        () async {
      gateway.codeVerifier = 'verifier';
      final service = await started();
      await service.handleLink(Uri.parse('lunarlog://other?code=x'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(service.pendingLinkFailure, isNull);
      expect(service.state, AuthSessionState.signedOut);
    });

    test('an exchange that fails on the network leaves the link retryable; '
        'the same link is exchanged again', () async {
      gateway.codeVerifier = 'verifier';
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      final uri = Uri.parse('$callback?code=abc');

      gateway.nextError = AuthRetryableFetchException();
      await service.handleLink(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(failures.single, isA<AuthNetworkFailure>());
      expect(service.state, AuthSessionState.signedOut);

      final failuresAtSignedIn = <AuthFailure?>[];
      service.states.listen((state) {
        if (state == AuthSessionState.signedIn) {
          failuresAtSignedIn.add(service.pendingLinkFailure);
        }
      });
      gateway.deliverAuthEventBeforeReturn = true;
      await service.handleLink(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(2));
      expect(service.state, AuthSessionState.signedIn);
      expect(service.currentUserId, 'linked');
      expect(service.pendingLinkFailure, isNull,
          reason: 'successful exchange resets prior pending link failure (Issue #24)');
      expect(failuresAtSignedIn, [isNull],
          reason: 'signed-in observers never capture the stale failure');
    });

    test('a definitive exchange failure stays latched: the stream replay of '
        'the same link is not exchanged again', () async {
      final uri = Uri.parse('$callback?code=abc');
      links.initial = uri;
      final service = await started(); // no verifier: definitive failure
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      links.controller.add(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(service.pendingLinkFailure, isA<AuthExpiredLinkFailure>());
    });

    test('the initial link replayed on the stream is exchanged only once',
        () async {
      gateway.codeVerifier = 'verifier';
      final uri = Uri.parse('$callback?code=abc');
      links.initial = uri;
      await started();
      await settle();
      links.controller.add(uri);
      await settle();
      expect(links.initialLinkCalls, 1);
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
    });
  });

  group('session state mapping', () {
    test('initial session, refresh, sign-out reasons', () async {
      final service = await started();
      final seen = <AuthSessionState>[];
      service.states.listen(seen.add);

      gateway.session = makeSession('u1');
      gateway.emit(AuthChangeEvent.initialSession);
      await settle();
      expect(service.state, AuthSessionState.signedIn);
      expect(service.currentUserId, 'u1');

      gateway.emit(AuthChangeEvent.tokenRefreshed);
      await settle();
      expect(service.state, AuthSessionState.signedIn);

      gateway.session = null;
      gateway.emit(AuthChangeEvent.signedOut, reason: SignOutReason.sessionExpired);
      await settle();
      expect(service.state, AuthSessionState.expired);
      expect(service.currentUserId, isNull);

      gateway.session = makeSession('u1');
      gateway.emit(AuthChangeEvent.signedIn);
      await settle();
      gateway.session = null;
      gateway.emit(AuthChangeEvent.signedOut, reason: SignOutReason.userInitiated);
      await settle();
      expect(service.state, AuthSessionState.signedOut);

      expect(seen, [
        AuthSessionState.signedIn,
        AuthSessionState.signedIn,
        AuthSessionState.expired,
        AuthSessionState.signedIn,
        AuthSessionState.signedOut,
      ]);
    });

    test('an initial session that is absent is signedOut', () async {
      final service = await started();
      gateway.emit(AuthChangeEvent.initialSession);
      await settle();
      expect(service.state, AuthSessionState.signedOut);
    });

    test('a passwordRecovery event latches recovery', () async {
      final service = await started();
      gateway.session = makeSession('u1');
      gateway.emit(AuthChangeEvent.passwordRecovery);
      await settle();
      expect(service.pendingRecovery, isTrue);
      expect(service.state, AuthSessionState.passwordRecovery);
    });

    test('a stream error (refresh failure while offline) keeps the state',
        () async {
      final service = await started();
      gateway.session = makeSession('u1');
      gateway.emit(AuthChangeEvent.signedIn);
      await settle();
      gateway.events.addError(AuthRetryableFetchException());
      await settle();
      expect(service.state, AuthSessionState.signedIn);
    });
  });

  group('email + password', () {
    test('signUp without a session yields awaitingConfirmation(email) and '
        'no state change', () async {
      final service = await started();
      final seen = <AuthSessionState>[];
      service.states.listen(seen.add);
      final result =
          await service.signUp(email: 'a@b.c', password: 'correct horse');
      await settle();
      expect(result, const SignUpAwaitingConfirmation('a@b.c'));
      expect(seen, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      expect(gateway.signUpCalls.single.redirect, callback);
    });

    test('signUp with a session (confirmation off) yields the session',
        () async {
      gateway.signUpResponse = AuthResponse(session: makeSession('fresh'));
      final service = await started();
      final result =
          await service.signUp(email: 'a@b.c', password: 'correct horse');
      await settle();
      expect(result, isA<SignUpSession>());
      expect((result as SignUpSession).user.id, 'fresh');
      expect(service.state, AuthSessionState.signedIn);
    });

    test('signInWithPassword returns the user and moves to signedIn',
        () async {
      final service = await started();
      final user =
          await service.signInWithPassword(email: 'a@b.c', password: 'pw');
      await settle();
      expect(user.id, 'pw');
      expect(user.email, 'a@b.c');
      expect(service.state, AuthSessionState.signedIn);
    });

    test('sendPasswordReset passes the callback redirect', () async {
      final service = await started();
      await service.sendPasswordReset('a@b.c');
      expect(gateway.resetCalls.single.redirect, callback);
    });

    test('updatePassword goes through updateUser', () async {
      final service = await started();
      gateway.session = makeSession('u1');
      await service.updatePassword('new password');
      expect(gateway.updateUserCalls.single.password, 'new password');
    });

    test('signOut maps scopes', () async {
      final service = await started();
      await service.signOut();
      await service.signOut(scope: AuthSignOutScope.global);
      expect(gateway.signOutCalls, [SignOutScope.local, SignOutScope.global]);
    });
  });

  group('typed failures (no provider text)', () {
    test('wrong password, weak password, and network are distinct types',
        () async {
      final service = await started();

      gateway.nextError = const AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      final wrong = await service
          .signInWithPassword(email: 'a@b.c', password: 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(wrong, isA<AuthWrongPasswordFailure>());

      gateway.nextError = AuthWeakPasswordException(
        message: 'Password should be at least 6 characters.',
        statusCode: '422',
        reasons: const ['length'],
      );
      final weak = await service
          .signUp(email: 'a@b.c', password: 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(weak, isA<AuthWeakPasswordFailure>());

      gateway.nextError = AuthRetryableFetchException();
      final network = await service
          .signInWithPassword(email: 'a@b.c', password: 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(network, isA<AuthNetworkFailure>());

      gateway.nextError = const SocketException('Failed host lookup');
      final socket = await service
          .sendPasswordReset('a@b.c')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(socket, isA<AuthNetworkFailure>());

      gateway.nextError = const AuthApiException('Database error saving new user',
          statusCode: '500', code: 'unexpected_failure');
      final unknown = await service
          .signUp(email: 'a@b.c', password: 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(unknown, isA<AuthUnknownFailure>());

      for (final failure in [wrong, weak, network, socket, unknown]) {
        final text = failure.toString();
        expect(text, isNot(contains('Invalid login')));
        expect(text, isNot(contains('6 characters')));
        expect(text, isNot(contains('host lookup')));
        expect(text, isNot(contains('Database')));
        expect(text, isNot(contains('a@b.c')));
      }
      expect(service.state, AuthSessionState.signedOut);
    });

    test('mapAuthError is a pure mapping', () {
      expect(mapAuthError(const AuthApiException('x', code: 'invalid_credentials')),
          isA<AuthWrongPasswordFailure>());
      expect(mapAuthError(const AuthApiException('x', code: 'weak_password')),
          isA<AuthWeakPasswordFailure>());
      expect(mapAuthError(const AuthApiException('x', code: 'validation_failed')),
          isA<AuthUnknownFailure>());
      expect(mapAuthError(TimeoutException('t')), isA<AuthNetworkFailure>());
      expect(mapAuthError(StateError('s')), isA<AuthUnknownFailure>());
      expect(mapAuthError(const AuthFailure.network()),
          isA<AuthNetworkFailure>());
    });
  });

  group('Apple Sign-In (KTD9)', () {
    AuthorizationCredentialAppleID credential({
      String? identityToken = 'id-token',
      String? givenName,
      String? familyName,
    }) =>
        AuthorizationCredentialAppleID(
          userIdentifier: 'apple-user',
          givenName: givenName,
          familyName: familyName,
          authorizationCode: 'auth-code',
          email: null,
          identityToken: identityToken,
          state: null,
        );

    test('off iOS it throws UnsupportedError and leaves state signedOut',
        () async {
      var requests = 0;
      final service = await started(
        appleAvailable: false,
        requestAppleCredential: ({required hashedNonce}) async {
          requests++;
          return credential();
        },
      );
      await expectLater(
          service.signInWithAppleNative(), throwsUnsupportedError);
      expect(requests, 0);
      expect(service.state, AuthSessionState.signedOut);
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('a cancelled dialog returns cancelled with no state change',
        () async {
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'The user canceled the authorization attempt',
          );
        },
      );
      final seen = <AuthSessionState>[];
      service.states.listen(seen.add);
      final result = await service.signInWithAppleNative();
      await settle();
      expect(result, const AppleSignInCancelled());
      expect(seen, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('success hashes the nonce for Apple, sends the raw nonce to '
        'Supabase, and persists the first credential\'s full name', () async {
      String? receivedNonce;
      final service = await started(
        appleAvailable: true,
        generateNonce: () => 'raw-nonce-123',
        requestAppleCredential: ({required hashedNonce}) async {
          receivedNonce = hashedNonce;
          return credential(givenName: 'Ada', familyName: 'Lovelace');
        },
      );
      final result = await service.signInWithAppleNative();
      await settle();
      expect(result, isA<AppleSignInSession>());
      expect((result as AppleSignInSession).user.id, 'apple');
      expect(receivedNonce,
          sha256.convert(utf8.encode('raw-nonce-123')).toString());
      final call = gateway.idTokenCalls.single;
      expect(call.provider, OAuthProvider.apple);
      expect(call.idToken, 'id-token');
      expect(call.nonce, 'raw-nonce-123');
      expect(gateway.updateUserCalls, hasLength(1));
      expect((gateway.updateUserCalls.single.data as Map)['full_name'],
          'Ada Lovelace');
      expect(service.state, AuthSessionState.signedIn);
    });

    test('a later credential without a name does not touch the profile',
        () async {
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async =>
            credential(),
      );
      await service.signInWithAppleNative();
      expect(gateway.updateUserCalls, isEmpty);
    });

    test('a credential without an identity token is an unknown failure',
        () async {
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async =>
            credential(identityToken: null),
      );
      await expectLater(service.signInWithAppleNative(),
          throwsA(isA<AuthUnknownFailure>()));
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('other Apple authorization errors map to unknown', () async {
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'boom',
          );
        },
      );
      final error = await service
          .signInWithAppleNative()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<AuthUnknownFailure>());
      expect(error.toString(), isNot(contains('boom')));
    });

    test('generateRawNonce is url-safe and unique', () {
      final a = generateRawNonce();
      final b = generateRawNonce();
      expect(a, isNot(b));
      expect(a.length, greaterThanOrEqualTo(32));
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(a), isTrue);
    });
  });

  group('Google Sign-In (#2 U2; KTD1, KTD8)', () {
    String hashed(String raw) => sha256.convert(utf8.encode(raw)).toString();

    test('when unavailable it throws UnsupportedError before touching the '
        'client and leaves state signedOut', () async {
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: false, googleClient: client);
      await expectLater(
          service.signInWithGoogleNative(), throwsUnsupportedError);
      expect(client.initializeCalls, isEmpty);
      expect(client.authenticateCalls, 0);
      expect(service.state, AuthSessionState.signedOut);
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('AE1: the client is initialized with the SHA-256 of the raw nonce '
        'sent to Supabase; a second call reuses the nonce and does not '
        're-initialize', () async {
      final client = FakeGoogleSignInClient();
      final nonces = <String>['raw-nonce-1', 'raw-nonce-2'];
      final service = await started(
        googleAvailable: true,
        googleClient: client,
        generateNonce: () => nonces.removeAt(0),
      );

      final first = await service.signInWithGoogleNative();
      await settle();
      expect(first, isA<GoogleSignInSession>());
      expect((first as GoogleSignInSession).user.id, 'google');
      expect(service.state, AuthSessionState.signedIn);
      expect(client.initializeCalls, hasLength(1));
      expect(client.initializeCalls.single.hashedNonce, hashed('raw-nonce-1'));
      final call = gateway.idTokenCalls.single;
      expect(call.provider, OAuthProvider.google);
      expect(call.idToken, 'google-id-token');
      expect(call.nonce, 'raw-nonce-1');
      expect(hashed(call.nonce!), client.initializeCalls.single.hashedNonce);

      final second = await service.signInWithGoogleNative();
      expect(second, isA<GoogleSignInSession>());
      expect(client.initializeCalls, hasLength(1),
          reason: 'initialize runs once per process');
      expect(client.authenticateCalls, 2);
      expect(gateway.idTokenCalls, hasLength(2));
      expect(gateway.idTokenCalls.last.nonce, 'raw-nonce-1');
      expect(nonces, ['raw-nonce-2'], reason: 'only one nonce is minted');
    });

    test('AE2: a cancelled picker returns cancelled with no state change '
        'and no failure', () async {
      final client = FakeGoogleSignInClient(
        authenticateError: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'user canceled',
        ),
      );
      final service =
          await started(googleAvailable: true, googleClient: client);
      final seen = <AuthSessionState>[];
      service.states.listen(seen.add);
      final result = await service.signInWithGoogleNative();
      await settle();
      expect(result, const GoogleSignInCancelled());
      expect(seen, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      expect(service.pendingLinkFailure, isNull);
      expect(gateway.idTokenCalls, isEmpty);
    });

    for (final code in [
      GoogleSignInExceptionCode.providerConfigurationError,
      GoogleSignInExceptionCode.uiUnavailable,
      GoogleSignInExceptionCode.unknownError,
    ]) {
      test('$code maps to providerUnavailable with no provider text',
          () async {
        final client = FakeGoogleSignInClient(
          authenticateError: GoogleSignInException(
            code: code,
            description: 'secret-description user@example.com',
          ),
        );
        final service =
            await started(googleAvailable: true, googleClient: client);
        final error = await service
            .signInWithGoogleNative()
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<AuthProviderUnavailableFailure>());
        expect(error.toString(), isNot(contains('secret-description')));
        expect(error.toString(), isNot(contains('example.com')));
        expect(service.state, AuthSessionState.signedOut);
        expect(gateway.idTokenCalls, isEmpty);
      });
    }

    test('any other client exception maps to unknown', () async {
      final client =
          FakeGoogleSignInClient(authenticateError: StateError('boom'));
      final service =
          await started(googleAvailable: true, googleClient: client);
      final error = await service
          .signInWithGoogleNative()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<AuthUnknownFailure>());
      expect(error.toString(), isNot(contains('boom')));
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('a credential without an ID token is an unknown failure', () async {
      final client = FakeGoogleSignInClient(
        credential: const GoogleCredential(idToken: null, accessToken: 'at'),
      );
      final service =
          await started(googleAvailable: true, googleClient: client);
      await expectLater(service.signInWithGoogleNative(),
          throwsA(isA<AuthUnknownFailure>()));
      expect(gateway.idTokenCalls, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
    });

    test('the access token is forwarded when present and omitted when null',
        () async {
      final client = FakeGoogleSignInClient(
        credential: const GoogleCredential(
            idToken: 'google-id-token', accessToken: 'google-access-token'),
      );
      final service =
          await started(googleAvailable: true, googleClient: client);
      await service.signInWithGoogleNative();
      expect(gateway.idTokenCalls.single.accessToken, 'google-access-token');

      client.credential = const GoogleCredential(idToken: 'google-id-token');
      await service.signInWithGoogleNative();
      expect(gateway.idTokenCalls.last.accessToken, isNull);
    });

    test('a Supabase signup_disabled rejection is signUpClosed', () async {
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: true, googleClient: client);
      gateway.nextError = const AuthApiException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_disabled');
      final error = await service
          .signInWithGoogleNative()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<AuthSignUpClosedFailure>());
      expect(error.toString(), isNot(contains('Signups')));
      expect(service.state, AuthSessionState.signedOut);
    });

    test('a Supabase rejection of the token is unknown', () async {
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: true, googleClient: client);
      gateway.nextError = const AuthApiException('Bad ID token',
          statusCode: '400', code: 'bad_jwt');
      await expectLater(service.signInWithGoogleNative(),
          throwsA(isA<AuthUnknownFailure>()));
    });
  });

  group('new failure kinds (#2 U2; KTD4, R13, R14)', () {
    test('mapAuthError maps signup_disabled and identity_already_exists',
        () {
      expect(
          mapAuthError(const AuthApiException('Signups not allowed',
              code: 'signup_disabled')),
          isA<AuthSignUpClosedFailure>());
      expect(
          mapAuthError(const AuthApiException('Identity is already linked',
              code: 'identity_already_exists')),
          isA<AuthIdentityTakenFailure>());
    });

    test('every new failure is fieldless, equal by type, and text-free', () {
      const failures = <AuthFailure>[
        AuthFailure.expiredLink(),
        AuthFailure.invalidCode(),
        AuthFailure.providerUnavailable(),
        AuthFailure.identityTaken(),
        AuthFailure.signUpClosed(),
      ];
      expect(failures.map((f) => f.runtimeType).toSet(), hasLength(5));
      expect(const AuthFailure.expiredLink(), const AuthFailure.expiredLink());
      expect(const AuthFailure.expiredLink(),
          isNot(const AuthFailure.invalidCode()));
      for (final failure in failures) {
        final text = failure.toString();
        expect(text, startsWith('AuthFailure.'));
        expect(text, isNot(contains('@')));
        expect(text.toLowerCase(), isNot(contains('token')));
        expect(text, isNot(contains(' ')));
      }
    });
  });

  group('passwordless email (#2 U7; KTD3, KTD4)', () {
    Future<Object?> failureOf(Future<Object?> call) =>
        call.then<Object?>((_) => null, onError: (Object e) => e);

    test('AE3: sign-in mode sends the link with shouldCreateUser false and '
        'the callback redirect; an otp_disabled rejection (unknown email) '
        'completes with no failure and no state change', () async {
      final service = await started();
      final seen = <AuthSessionState>[];
      service.states.listen(seen.add);

      await service.sendMagicLink(email: 'known@b.c', createAccount: false);
      expect(gateway.otpCalls.single.email, 'known@b.c');
      expect(gateway.otpCalls.single.redirect, callback);
      expect(gateway.otpCalls.single.shouldCreateUser, isFalse);

      gateway.nextError = const AuthApiException('Signups not allowed for otp',
          statusCode: '422', code: 'otp_disabled');
      await service.sendMagicLink(email: 'unknown@b.c', createAccount: false);
      await settle();
      expect(gateway.otpCalls, hasLength(2));
      expect(gateway.otpCalls.last.shouldCreateUser, isFalse);
      expect(seen, isEmpty);
      expect(service.state, AuthSessionState.signedOut);
      expect(service.pendingLinkFailure, isNull);
    });

    test('create mode passes shouldCreateUser true', () async {
      final service = await started();
      await service.sendMagicLink(email: 'new@b.c', createAccount: true);
      expect(gateway.otpCalls.single.shouldCreateUser, isTrue);
      expect(gateway.otpCalls.single.redirect, callback);
    });

    test('create mode with sign-ups closed throws signUpClosed', () async {
      final service = await started();
      gateway.nextError = const AuthApiException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_disabled');
      final error = await failureOf(
          service.sendMagicLink(email: 'new@b.c', createAccount: true));
      expect(error, isA<AuthSignUpClosedFailure>());
      expect(error.toString(), isNot(contains('Signups')));
      expect(error.toString(), isNot(contains('b.c')));
    });

    test('an otp_disabled rejection in create mode is not swallowed',
        () async {
      final service = await started();
      gateway.nextError = const AuthApiException('Signups not allowed for otp',
          statusCode: '422', code: 'otp_disabled');
      final error = await failureOf(
          service.sendMagicLink(email: 'new@b.c', createAccount: true));
      expect(error, isA<AuthFailure>());
      expect(error, isNot(isA<AuthSignUpClosedFailure>()));
    });

    test('a network failure while sending is network in either mode',
        () async {
      final service = await started();
      gateway.nextError = AuthRetryableFetchException();
      expect(
          await failureOf(
              service.sendMagicLink(email: 'a@b.c', createAccount: false)),
          isA<AuthNetworkFailure>());
      gateway.nextError = const SocketException('Failed host lookup');
      expect(
          await failureOf(
              service.sendMagicLink(email: 'a@b.c', createAccount: true)),
          isA<AuthNetworkFailure>());
    });

    test('verifyEmailCode verifies with OtpType.email, returns the user, '
        'and yields signedIn', () async {
      final service = await started();
      final user =
          await service.verifyEmailCode(email: 'a@b.c', code: '12345678');
      await settle();
      final call = gateway.verifyOtpCalls.single;
      expect(call.email, 'a@b.c');
      expect(call.token, '12345678');
      expect(call.type, OtpType.email);
      expect(user.id, 'otp');
      expect(user.email, 'a@b.c');
      expect(service.state, AuthSessionState.signedIn);
      expect(service.currentUserId, 'otp');
    });

    for (final (code, status, message) in [
      ('otp_expired', '403', 'Token has expired or is invalid'),
      ('otp_disabled', '422', 'Signups not allowed for otp'),
      ('validation_failed', '400', 'Token has invalid format'),
    ]) {
      test('a rejected code ($code) throws invalidCode with no provider text',
          () async {
        final service = await started();
        gateway.nextError =
            AuthApiException(message, statusCode: status, code: code);
        final error = await failureOf(
            service.verifyEmailCode(email: 'a@b.c', code: '00000000'));
        expect(error, isA<AuthInvalidCodeFailure>());
        expect(error.toString(), isNot(contains('Token')));
        expect(error.toString(), isNot(contains('b.c')));
        expect(service.state, AuthSessionState.signedOut);
      });
    }

    test('a network failure while verifying stays network', () async {
      final service = await started();
      gateway.nextError = AuthRetryableFetchException();
      expect(
          await failureOf(
              service.verifyEmailCode(email: 'a@b.c', code: '00000000')),
          isA<AuthNetworkFailure>());
    });

    test('a server error while verifying stays unknown, not invalidCode',
        () async {
      final service = await started();
      gateway.nextError = const AuthApiException('Database error',
          statusCode: '500', code: 'unexpected_failure');
      expect(
          await failureOf(
              service.verifyEmailCode(email: 'a@b.c', code: '00000000')),
          isA<AuthUnknownFailure>());
    });

    test('a link carrying error_code=otp_expired surfaces expiredLink '
        'without exchanging', () async {
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      await service.handleLink(Uri.parse(
          '$callback?error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(failures.single, isA<AuthExpiredLinkFailure>());
      expect(service.pendingLinkFailure, isA<AuthExpiredLinkFailure>());
      expect(failures.single.toString(), isNot(contains('otp')));
      expect(service.state, AuthSessionState.signedOut);
    });

    for (final code in [
      'flow_state_not_found',
      'flow_state_expired',
      'bad_code_verifier',
      'otp_expired',
    ]) {
      test('an exchange rejected with $code surfaces expiredLink and stays '
          'latched', () async {
        gateway.codeVerifier = 'verifier';
        final service = await started();
        final failures = <AuthFailure>[];
        service.linkFailures.listen(failures.add);
        final uri = Uri.parse('$callback?code=abc');
        gateway.nextError = AuthApiException('PKCE flow state is $code',
            statusCode: '404', code: code);
        await service.handleLink(uri);
        await settle();
        expect(gateway.getSessionFromUrlCalls, hasLength(1));
        expect(failures.single, isA<AuthExpiredLinkFailure>());
        expect(failures.single.toString(), isNot(contains('flow')));
        expect(service.state, AuthSessionState.signedOut);

        await service.handleLink(uri);
        await settle();
        expect(gateway.getSessionFromUrlCalls, hasLength(1),
            reason: 'a definitive failure is not exchanged again');
        expect(failures, hasLength(1));
      });
    }

    test('a code callback with no stored verifier (the gotrue null-code '
        'exception) surfaces expiredLink, stays signedOut, and latches the '
        'link so a replay is not exchanged again', () async {
      final service = await started(); // no verifier stored
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      final uri = Uri.parse('$callback?code=abc');
      await service.handleLink(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(failures.single, isA<AuthExpiredLinkFailure>());
      expect(failures.single.toString(), isNot(contains('verifier')));
      expect(service.state, AuthSessionState.signedOut);
      expect(service.currentUserId, isNull);

      links.controller.add(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(failures, hasLength(1));
      expect(service.pendingLinkFailure, isA<AuthExpiredLinkFailure>());
    });

    test('a transient network failure during the exchange is network and '
        'leaves the link retryable', () async {
      final service = await started();
      await service.sendMagicLink(email: 'a@b.c', createAccount: false);
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      final uri = Uri.parse('$callback?code=abc');
      gateway.nextError = AuthRetryableFetchException();
      await service.handleLink(uri);
      await settle();
      expect(failures.single, isA<AuthNetworkFailure>());
      expect(service.state, AuthSessionState.signedOut);

      await service.handleLink(uri);
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(2));
      expect(service.state, AuthSessionState.signedIn);
    });

    test('mapAuthError stays pure: it knows no operation and maps the '
        'exchange codes to unknown on its own', () {
      for (final code in [
        'otp_expired',
        'otp_disabled',
        'flow_state_not_found',
        'flow_state_expired',
        'bad_code_verifier',
      ]) {
        expect(mapAuthError(AuthApiException('x', code: code)),
            isA<AuthUnknownFailure>(),
            reason: code);
      }
      expect(
          mapAuthError(const AuthException(
              'Code verifier could not be found in local storage.')),
          isA<AuthUnknownFailure>());
    });
  });

  group('sign-in methods and identity linking (#2 U8; KTD5)', () {
    String hashed(String raw) => sha256.convert(utf8.encode(raw)).toString();

    AuthorizationCredentialAppleID appleCredential({
      String? identityToken = 'apple-id-token',
    }) =>
        AuthorizationCredentialAppleID(
          userIdentifier: 'apple-user',
          givenName: null,
          familyName: null,
          authorizationCode: 'auth-code',
          email: null,
          identityToken: identityToken,
          state: null,
        );

    test('currentUser.providers lists the identities in order, '
        'de-duplicated, and stays out of toString', () async {
      gateway.session =
          makeSession('u1', identities: ['email', 'google', 'email']);
      final service = await started();
      expect(service.currentUser?.providers, ['email', 'google']);
      expect(service.currentUser.toString(), 'AuthUser(u1)');
    });

    test('providers falls back to appMetadata[providers] when identities '
        'are null or empty, and is empty without either', () async {
      gateway.session = makeSession('u1', appMetadata: const {
        'providers': ['email', 'apple'],
        'provider': 'email',
      });
      final service = await started();
      expect(service.currentUser?.providers, ['email', 'apple']);

      gateway.session = makeSession('u1',
          identities: const [],
          appMetadata: const {
            'providers': ['google']
          });
      expect(service.currentUser?.providers, ['google']);

      gateway.session = makeSession('u1');
      expect(service.currentUser?.providers, isEmpty);
      expect(service.currentUser, const AuthUser(id: 'u1'));
    });

    test('AE6: linkGoogle while signed in links with the Google token and '
        'the raw nonce whose hash the client was initialized with, then '
        'refreshes providers on the same user', () async {
      gateway.session =
          makeSession('u1', email: 'a@b.c', identities: ['email']);
      final client = FakeGoogleSignInClient(
        credential: const GoogleCredential(
            idToken: 'google-id-token', accessToken: 'google-access-token'),
      );
      final service = await started(
        googleAvailable: true,
        googleClient: client,
        generateNonce: () => 'raw-nonce-link',
      );
      expect(service.state, AuthSessionState.signedIn);
      expect(service.currentUser?.providers, ['email']);

      final user = await service.linkGoogle();
      await settle();
      expect(user.id, 'u1');
      expect(user.providers, ['email', 'google']);
      expect(service.currentUser?.providers, ['email', 'google']);
      expect(service.currentUserId, 'u1');
      expect(service.state, AuthSessionState.signedIn);

      final call = gateway.linkIdentityCalls.single;
      expect(call.provider, OAuthProvider.google);
      expect(call.idToken, 'google-id-token');
      expect(call.accessToken, 'google-access-token');
      expect(call.nonce, 'raw-nonce-link');
      expect(client.initializeCalls.single.hashedNonce, hashed(call.nonce!));
      expect(gateway.idTokenCalls, isEmpty, reason: 'linking never signs in');
    });

    test('a Google sign-in after linking reuses the same nonce pair',
        () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final client = FakeGoogleSignInClient();
      final nonces = <String>['raw-nonce-1', 'raw-nonce-2'];
      final service = await started(
        googleAvailable: true,
        googleClient: client,
        generateNonce: () => nonces.removeAt(0),
      );
      await service.linkGoogle();
      await service.signInWithGoogleNative();
      expect(client.initializeCalls, hasLength(1));
      expect(gateway.linkIdentityCalls.single.nonce, 'raw-nonce-1');
      expect(gateway.idTokenCalls.single.nonce, 'raw-nonce-1');
      expect(nonces, ['raw-nonce-2']);
    });

    test('AE6: identity_already_exists throws identityTaken and leaves the '
        'user unchanged', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: true, googleClient: client);
      gateway.nextError = const AuthApiException(
          'Identity is already linked to another user',
          statusCode: '422',
          code: 'identity_already_exists');
      final error = await service
          .linkGoogle()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, const AuthFailure.identityTaken());
      expect(error.toString(), isNot(contains('linked')));
      expect(
          service.currentUser, const AuthUser(id: 'u1', providers: ['email']));
      expect(service.currentUserId, 'u1');
      expect(service.state, AuthSessionState.signedIn);
    });

    test('AE6: linkGoogle while signed out throws unknown and never '
        'touches the client or the gateway', () async {
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: true, googleClient: client);
      expect(service.state, AuthSessionState.signedOut);
      await expectLater(
          service.linkGoogle(), throwsA(const AuthFailure.unknown()));
      expect(client.initializeCalls, isEmpty);
      expect(client.authenticateCalls, 0);
      expect(gateway.linkIdentityCalls, isEmpty);
      expect(gateway.idTokenCalls, isEmpty);
    });

    test('linkGoogle when Google is unavailable throws UnsupportedError',
        () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final client = FakeGoogleSignInClient();
      final service =
          await started(googleAvailable: false, googleClient: client);
      await expectLater(service.linkGoogle(), throwsUnsupportedError);
      expect(client.authenticateCalls, 0);
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('a cancelled Google picker during linking returns the user '
        'unchanged with no failure', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final client = FakeGoogleSignInClient(
        authenticateError: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'user canceled',
        ),
      );
      final service =
          await started(googleAvailable: true, googleClient: client);
      final user = await service.linkGoogle();
      expect(user.providers, ['email']);
      expect(service.currentUser?.providers, ['email']);
      expect(service.pendingLinkFailure, isNull);
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('a provider failure during Google linking is providerUnavailable',
        () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final client = FakeGoogleSignInClient(
        authenticateError: const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'No credentials available',
        ),
      );
      final service =
          await started(googleAvailable: true, googleClient: client);
      await expectLater(service.linkGoogle(),
          throwsA(const AuthFailure.providerUnavailable()));
      expect(service.currentUser?.providers, ['email']);
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('linkApple on a non-iOS platform throws UnsupportedError without '
        'requesting a credential', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      var requests = 0;
      final service = await started(
        appleAvailable: false,
        requestAppleCredential: ({required hashedNonce}) async {
          requests++;
          return appleCredential();
        },
      );
      await expectLater(service.linkApple(), throwsUnsupportedError);
      expect(requests, 0);
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('linkApple while signed out throws unknown without requesting a '
        'credential', () async {
      var requests = 0;
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async {
          requests++;
          return appleCredential();
        },
      );
      await expectLater(
          service.linkApple(), throwsA(const AuthFailure.unknown()));
      expect(requests, 0);
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('a cancelled Apple dialog during linking leaves providers unchanged '
        'and throws no failure', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'The user canceled the authorization attempt',
          );
        },
      );
      final user = await service.linkApple();
      expect(user, const AuthUser(id: 'u1', providers: ['email']));
      expect(service.currentUser?.providers, ['email']);
      expect(service.pendingLinkFailure, isNull);
      expect(gateway.linkIdentityCalls, isEmpty);
      expect(service.state, AuthSessionState.signedIn);
    });

    test('linkApple hashes the nonce for Apple, sends the raw nonce with '
        'the identity token, and refreshes providers', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      String? receivedNonce;
      final service = await started(
        appleAvailable: true,
        generateNonce: () => 'raw-apple-nonce',
        requestAppleCredential: ({required hashedNonce}) async {
          receivedNonce = hashedNonce;
          return appleCredential();
        },
      );
      final user = await service.linkApple();
      expect(receivedNonce, hashed('raw-apple-nonce'));
      final call = gateway.linkIdentityCalls.single;
      expect(call.provider, OAuthProvider.apple);
      expect(call.idToken, 'apple-id-token');
      expect(call.nonce, 'raw-apple-nonce');
      expect(user.providers, ['email', 'apple']);
      expect(service.currentUser?.providers, ['email', 'apple']);
      expect(service.currentUserId, 'u1');
      expect(gateway.idTokenCalls, isEmpty);
      expect(gateway.updateUserCalls, isEmpty,
          reason: 'linking never rewrites the profile name');
    });

    test('an Apple credential without an identity token during linking is '
        'an unknown failure', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final service = await started(
        appleAvailable: true,
        requestAppleCredential: ({required hashedNonce}) async =>
            appleCredential(identityToken: null),
      );
      await expectLater(
          service.linkApple(), throwsA(const AuthFailure.unknown()));
      expect(gateway.linkIdentityCalls, isEmpty);
    });

    test('R15: the Google, emailed-code, and password paths expose the same '
        'currentUserId for the same account', () async {
      gateway.fixedUserId = 'same-user';
      final service = await started(
        googleAvailable: true,
        googleClient: FakeGoogleSignInClient(),
      );

      await service.signInWithPassword(email: 'a@b.c', password: 'pw');
      final viaPassword = service.currentUserId;
      await service.signOut();

      await service.signInWithGoogleNative();
      final viaGoogle = service.currentUserId;
      await service.signOut();

      await service.verifyEmailCode(email: 'a@b.c', code: '12345678');
      final viaCode = service.currentUserId;

      expect(viaPassword, 'same-user');
      expect(viaGoogle, viaPassword);
      expect(viaCode, viaPassword);
    });
  });

  group('removing a sign-in method (#31 U2; KTD2, KTD3, KTD4, KTD5)', () {
    test('unlinkProvider deletes the identity, refreshes, and returns the '
        'user with the provider removed', () async {
      gateway.session =
          makeSession('u1', email: 'a@b.c', identities: ['email', 'google']);
      final service = await started();

      final user = await service.unlinkProvider('google');

      expect(user.providers, ['email']);
      expect(service.currentUser?.providers, ['email']);
      expect(gateway.unlinkIdentityCalls, hasLength(1));
      expect(gateway.unlinkIdentityCalls.single.provider, 'google');
      expect(gateway.refreshSessionCalls, 1);
    });

    test('unlinkProvider(email) throws unknown before any gateway call', () async {
      gateway.session =
          makeSession('u1', identities: ['email', 'google']);
      final service = await started();

      await expectLater(
          service.unlinkProvider('email'), throwsA(const AuthFailure.unknown()));
      expect(gateway.getUserIdentitiesCalls, isEmpty);
      expect(gateway.unlinkIdentityCalls, isEmpty);
      expect(gateway.refreshSessionCalls, 0);
    });

    test('unlinkProvider while signed out throws unknown before any '
        'gateway call', () async {
      final service = await started();
      expect(service.state, AuthSessionState.signedOut);

      await expectLater(
          service.unlinkProvider('google'), throwsA(const AuthFailure.unknown()));
      expect(gateway.getUserIdentitiesCalls, isEmpty);
      expect(gateway.unlinkIdentityCalls, isEmpty);
    });

    test('R10: unlinkProvider for a provider the account does not hold '
        'returns the current user unchanged and issues no delete', () async {
      gateway.session = makeSession('u1', identities: ['email']);
      final service = await started();

      final user = await service.unlinkProvider('google');

      expect(user, const AuthUser(id: 'u1', providers: ['email']));
      expect(gateway.unlinkIdentityCalls, isEmpty);
      expect(gateway.refreshSessionCalls, 0);
    });

    test('P1/P3: R10\'s not-found branch returns the fresh server read, not '
        'the caller\'s stale pre-call session, when the two disagree',
        () async {
      // The caller's session (and therefore its pre-call `current`
      // snapshot) still shows google present. The server's fresh read
      // disagrees on both counts: google is already gone (so this hits
      // the not-found/idempotent branch) and it reports 'apple', which
      // the stale session never had at all. Only an override independent
      // of `session` can express this divergence (#31 P1) — before that
      // fix, `getUserIdentities` could only ever agree with `session`.
      gateway.session =
          makeSession('u1', email: 'a@b.c', identities: ['email', 'google']);
      final service = await started();
      gateway.getUserIdentitiesOverride =
          makeUser('u1', identities: ['email', 'apple']).identities!;

      final user = await service.unlinkProvider('google');

      expect(user.providers, ['email', 'apple'],
          reason: 'the fresh server read, not the stale pre-call session '
              '(which still showed google and never had apple)');
      expect(gateway.unlinkIdentityCalls, isEmpty,
          reason: 'google is already gone server-side; no delete is issued');
      expect(gateway.refreshSessionCalls, 0);
    });

    test('P2: an empty fresh-identities read on the not-found branch falls '
        'back to the pre-call snapshot rather than an empty provider list',
        () async {
      // A degraded/identity-less fresh read (empty, not just missing the
      // target provider) must not be trusted as "the account has no
      // providers" — fall back to the pre-call `current` snapshot instead
      // of building an empty-providers user from it.
      gateway.session =
          makeSession('u1', email: 'a@b.c', identities: ['email']);
      final service = await started();
      gateway.getUserIdentitiesOverride = const [];

      final user = await service.unlinkProvider('google');

      expect(
          user,
          const AuthUser(
              id: 'u1', email: 'a@b.c', providers: ['email']),
          reason: 'the fresh read came back empty (degraded), so the '
              'pre-call snapshot is preferred over an empty provider list');
      expect(gateway.unlinkIdentityCalls, isEmpty);
      expect(gateway.refreshSessionCalls, 0);
    });

    test('R9: unlinkProvider on the account\'s only identity throws '
        'lastSignInMethod and issues no delete', () async {
      gateway.session = makeSession('u1', identities: ['google']);
      final service = await started();

      await expectLater(service.unlinkProvider('google'),
          throwsA(const AuthFailure.lastSignInMethod()));
      expect(gateway.unlinkIdentityCalls, isEmpty);
    });

    test('a gateway single_identity_not_deletable refusal surfaces as '
        'lastSignInMethod', () async {
      gateway.session =
          makeSession('u1', identities: ['email', 'google']);
      final service = await started();
      gateway.nextError = const AuthApiException(
        'The identity cannot be deleted',
        statusCode: '422',
        code: 'single_identity_not_deletable',
      );

      await expectLater(service.unlinkProvider('google'),
          throwsA(const AuthFailure.lastSignInMethod()));
      expect(gateway.refreshSessionCalls, 0,
          reason: 'the delete itself failed; no refresh is attempted');
    });

    test('a network failure from unlinkIdentity surfaces as network and no '
        'refresh is attempted', () async {
      gateway.session =
          makeSession('u1', identities: ['email', 'google']);
      final service = await started();
      gateway.nextError = AuthRetryableFetchException(message: 'down');

      await expectLater(
          service.unlinkProvider('google'), throwsA(const AuthFailure.network()));
      expect(gateway.refreshSessionCalls, 0);
    });

    test('KTD4: a refreshSession failure after a successful delete does not '
        'throw, and the returned user omits the removed provider', () async {
      gateway.session =
          makeSession('u1', email: 'a@b.c', identities: ['email', 'google']);
      gateway.refreshSessionShouldFail = true;
      final service = await started();

      final user = await service.unlinkProvider('google');

      expect(user.providers, ['email']);
      expect(gateway.unlinkIdentityCalls, hasLength(1));
      expect(gateway.refreshSessionCalls, 1);
    });

    test('mapAuthError: single_identity_not_deletable maps to '
        'lastSignInMethod; an unrecognized unlink code maps to unknown', () {
      expect(
        mapAuthError(const AuthApiException('nope',
            statusCode: '422', code: 'single_identity_not_deletable')),
        const AuthFailure.lastSignInMethod(),
      );
      expect(
        mapAuthError(const AuthApiException('nope',
            statusCode: '400', code: 'some_other_unlink_code')),
        const AuthFailure.unknown(),
      );
    });
  });
}
