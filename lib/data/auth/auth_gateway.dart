/// Seams between [SupabaseAuthService] and the platform (U4, KTD6/KTD8):
/// the slice of `GoTrueClient` it calls and the deep-link source. Both are
/// interfaces so the service's link handling and event mapping are
/// unit-testable with fakes; `SupabaseClient` itself is not fakeable.
/// `signInWithIdToken` carries the optional Google access token
/// (#2 U2; KTD1).
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
