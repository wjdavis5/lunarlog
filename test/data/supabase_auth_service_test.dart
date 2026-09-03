/// U4 (KTD8, KTD9, R1–R3): [SupabaseAuthService] over a fake gateway and a
/// fake link source — link classification, the PKCE exchange it drives
/// itself, the recovery latch set before any widget exists, typed failure
/// mapping with no provider text, and the native Apple flow.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/auth_gateway.dart';
import 'package:lunarlog/data/auth/auth_link_classifier.dart';
import 'package:lunarlog/data/auth/supabase_auth_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User makeUser(String id, {String? email}) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-09-02T00:00:00Z',
      email: email,
    );

Session makeSession(String id, {String? email}) => Session(
      accessToken: 'access-$id',
      tokenType: 'bearer',
      refreshToken: 'refresh-$id',
      user: makeUser(id, email: email),
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

  final getSessionFromUrlCalls = <Uri>[];
  final signUpCalls = <({String email, String password, String? redirect})>[];
  final signInCalls = <({String email, String password})>[];
  final resetCalls = <({String email, String? redirect})>[];
  final updateUserCalls = <UserAttributes>[];
  final idTokenCalls =
      <({OAuthProvider provider, String idToken, String? nonce})>[];
  final signOutCalls = <SignOutScope>[];

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
    session = makeSession('pw', email: email);
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
    String? nonce,
  }) async {
    idTokenCalls.add((provider: provider, idToken: idToken, nonce: nonce));
    _maybeThrow();
    session = makeSession('apple');
    emit(AuthChangeEvent.signedIn);
    return AuthResponse(session: session);
  }

  @override
  Future<void> signOut({required SignOutScope scope}) async {
    signOutCalls.add(scope);
    _maybeThrow();
    session = null;
    emit(AuthChangeEvent.signedOut, reason: SignOutReason.userInitiated);
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
      expect(classifyAuthLink(Uri.parse('$callback#access_token=x&type=recovery')),
          const AuthLinkCallback(recovery: true));
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

    test('a link with no matching verifier yields no session, stays '
        'signedOut, and surfaces a typed failure', () async {
      final service = await started();
      final failures = <AuthFailure>[];
      service.linkFailures.listen(failures.add);
      await service.handleLink(Uri.parse('$callback?code=abc'));
      await settle();
      expect(gateway.getSessionFromUrlCalls, hasLength(1));
      expect(service.state, AuthSessionState.signedOut);
      expect(service.currentUserId, isNull);
      expect(service.pendingRecovery, isFalse);
      expect(service.pendingLinkFailure, isA<AuthUnknownFailure>());
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
      expect(failure, isA<AuthUnknownFailure>());
      expect(failure.toString(), isNot(contains('expired')));
      expect(failure.toString(), isNot(contains('otp')));
      expect(failure.toString(), isNot(contains('access_denied')));
      expect(failures.single, same(failure));
      service.consumeLinkFailure();
      expect(service.pendingLinkFailure, isNull);
    });

    test('links without auth parameters are ignored', () async {
      final service = await started();
      await service.handleLink(Uri.parse(callback));
      await service.handleLink(Uri.parse('https://example.com/?x=1'));
      expect(gateway.getSessionFromUrlCalls, isEmpty);
      expect(service.pendingLinkFailure, isNull);
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
}
