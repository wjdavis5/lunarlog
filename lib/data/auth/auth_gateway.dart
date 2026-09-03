/// Seams between [SupabaseAuthService] and the platform (U4, KTD6/KTD8):
/// the slice of `GoTrueClient` it calls and the deep-link source. Both are
/// interfaces so the service's link handling and event mapping are
/// unit-testable with fakes; `SupabaseClient` itself is not fakeable.
/// `signInWithIdToken` carries the optional Google access token
/// (#2 U2; KTD1); `signInWithOtp` and `verifyOTP` are the passwordless
/// pair (#2 U7; KTD3); `linkIdentityWithIdToken` attaches a second
/// identity to the current session's user (#2 U8; KTD5).
library;

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The auth client as the service sees it.
abstract interface class AuthGateway {
  Stream<AuthState> get onAuthStateChange;

  Session? get currentSession;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  });

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> resetPasswordForEmail(String email, {String? redirectTo});

  Future<UserResponse> updateUser(UserAttributes attributes);

  /// [accessToken] is required by the provider only when the ID token
  /// carries `at_hash` (Google on iOS, #2 AS3).
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  });

  /// Sends the sign-in email and stores a PKCE verifier for its link
  /// (#2 KTD3). [shouldCreateUser] false makes the server reject an
  /// unknown email with `otp_disabled` instead of creating an account.
  Future<void> signInWithOtp({
    required String email,
    String? emailRedirectTo,
    required bool shouldCreateUser,
  });

  /// Verifies the emailed code; [type] is `OtpType.email` for the
  /// passwordless flow.
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    required OtpType type,
  });

  /// Links the identity in [idToken] to the current session's user
  /// (#2 KTD5; the dashboard's "manual linking" must be on). gotrue saves
  /// the returned session and emits `userUpdated`; the server rejects an
  /// identity another account holds with `identity_already_exists`.
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  });

  Future<void> signOut({required SignOutScope scope});

  /// Exchanges the PKCE code (or implicit tokens) carried by [uri] and
  /// stores the session (KTD8: the service calls this itself because
  /// `detectSessionInUri` is off).
  Future<AuthSessionUrlResponse> getSessionFromUrl(Uri uri);
}

/// Production gateway over `Supabase.instance.client.auth`.
class GoTrueAuthGateway implements AuthGateway {
  GoTrueAuthGateway(this._auth);

  final GoTrueClient _auth;

  @override
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  }) =>
      _auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectTo,
      );

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> resetPasswordForEmail(String email, {String? redirectTo}) =>
      _auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) =>
      _auth.updateUser(attributes);

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) =>
      _auth.signInWithIdToken(
        provider: provider,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );

  @override
  Future<void> signInWithOtp({
    required String email,
    String? emailRedirectTo,
    required bool shouldCreateUser,
  }) =>
      _auth.signInWithOtp(
        email: email,
        emailRedirectTo: emailRedirectTo,
        shouldCreateUser: shouldCreateUser,
      );

  @override
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    required OtpType type,
  }) =>
      _auth.verifyOTP(email: email, token: token, type: type);

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) =>
      _auth.linkIdentityWithIdToken(
        provider: provider,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );

  @override
  Future<void> signOut({required SignOutScope scope}) =>
      _auth.signOut(scope: scope);

  @override
  Future<AuthSessionUrlResponse> getSessionFromUrl(Uri uri) =>
      _auth.getSessionFromUrl(uri);
}

/// Where incoming links come from.
abstract interface class AuthLinkSource {
  /// The link the app was launched with, if any. Read once.
  Future<Uri?> initialLink();

  /// Links delivered while the app is running (on mobile, app_links also
  /// replays the initial link here; the service de-duplicates).
  Stream<Uri> get links;
}

/// Production source over `app_links` (bundled by supabase_flutter).
class AppLinksSource implements AuthLinkSource {
  AppLinksSource({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}
