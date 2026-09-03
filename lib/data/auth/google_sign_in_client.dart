/// Seam between [SupabaseAuthService] and the `google_sign_in` plugin
/// (#2 U2; KTD1, KTD8): a platform concern like `AuthLinkSource`, not a
/// GoTrue one. The service never touches `GoogleSignIn.instance`, so tests
/// inject an ID token without the plugin and the default adapter is the
/// only place that knows the plugin's API.
///
/// Privacy (R13, KTD7): only the two tokens cross this boundary. The
/// account's email, display name, and photo URL stay inside the adapter and
/// are never logged, returned, or stringified; a [GoogleCredential] prints
/// no field.
library;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The tokens a native Google authentication produced.
@immutable
class GoogleCredential {
  const GoogleCredential({required this.idToken, this.accessToken});

  /// The OpenID Connect ID token bound to the hashed nonce the client was
  /// initialized with; null when the platform issued none.
  final String? idToken;

  /// An access token read without a prompt (AS3); null when none could be
  /// read silently. Supabase needs it only when the ID token carries
  /// `at_hash`.
  final String? accessToken;

  @override
  String toString() => 'GoogleCredential';
}

/// What the service needs from the plugin.
abstract interface class GoogleSignInClient {
  /// Configures the platform SDK. [iosClientId] is passed only on iOS (the
  /// Android SDK reads its configuration from the Web client id alone);
  /// [webClientId] is the `serverClientId`, the audience of the ID token on
  /// Android; [hashedNonce] is the SHA-256 hex of the raw nonce the service
  /// later sends to Supabase. Implementations run the underlying
  /// initialization at most once per process.
  Future<void> initialize({
    required String? iosClientId,
    required String webClientId,
    required String hashedNonce,
  });

  /// Shows the platform picker and returns the tokens. Throws
  /// [GoogleSignInException] (with [GoogleSignInExceptionCode.canceled] for
  /// a dismissed picker); the service maps every code.
  Future<GoogleCredential> authenticate();
}

/// Production adapter over [GoogleSignIn.instance].
class PluginGoogleSignInClient implements GoogleSignInClient {
  PluginGoogleSignInClient({GoogleSignIn? plugin, TargetPlatform? platform})
      : _plugin = plugin ?? GoogleSignIn.instance,
        _platform = platform ?? defaultTargetPlatform;

  /// Scopes whose silent authorization yields an access token; both are
  /// granted implicitly by authentication, so no consent UI is involved.
  static const List<String> _accessTokenScopes = ['email', 'profile'];

  final GoogleSignIn _plugin;
  final TargetPlatform _platform;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required String? iosClientId,
    required String webClientId,
    required String hashedNonce,
  }) async {
    if (_initialized) return;
    await _plugin.initialize(
      clientId: _platform == TargetPlatform.iOS ? iosClientId : null,
      serverClientId: webClientId,
      nonce: hashedNonce,
    );
    _initialized = true;
  }

  @override
  Future<GoogleCredential> authenticate() async {
    final account = await _plugin.authenticate();
    final idToken = account.authentication.idToken;
    String? accessToken;
    try {
      // Silent read only (AS3): `authorizeScopes` would prompt and is never
      // called. A null result simply means Supabase gets no access token.
      final authorization = await account.authorizationClient
          .authorizationForScopes(_accessTokenScopes);
      accessToken = authorization?.accessToken;
    } catch (error) {
      debugPrint('lunarlog auth: google access token unavailable '
          '(${error.runtimeType})');
    }
    return GoogleCredential(idToken: idToken, accessToken: accessToken);
  }
}
