/// Pure classification of an incoming link (U4, KTD8). Looks only at
/// parameter *names* (query and fragment) so nothing here ever holds an
/// `error_description` value; the result types are fieldless except for
/// the recovery flag.
///
/// The app is PKCE-only: a link is exchanged only when it carries a `code`.
/// Implicit-flow tokens (`access_token` / `refresh_token`) in a link would
/// install whatever session the link's author minted, so they classify as
/// an error and are never handed to the provider.
library;

/// Custom-scheme callback for confirmation and reset emails on native
/// (KTD8). Registered in `AndroidManifest.xml` and `Info.plist`. A link on
/// this scheme is honoured only on [kAuthCallbackHost].
const String kAuthCallbackScheme = 'lunarlog';
const String kAuthCallbackHost = 'auth-callback';
const String kAuthCallbackUrl = '$kAuthCallbackScheme://$kAuthCallbackHost';

sealed class AuthLink {
  const AuthLink();
}

/// Not an auth callback at all.
final class AuthLinkIgnored extends AuthLink {
  const AuthLinkIgnored();

  @override
  bool operator ==(Object other) => other is AuthLinkIgnored;

  @override
  int get hashCode => (AuthLinkIgnored).hashCode;

  @override
  String toString() => 'AuthLink.ignored';
}

/// The provider redirected with `error` / `error_code` /
/// `error_description` (expired or reused link), or the link carried
/// implicit-flow tokens (`access_token` / `refresh_token`), which a
/// PKCE-only client never installs. Never exchanged.
final class AuthLinkError extends AuthLink {
  const AuthLinkError();

  @override
  bool operator ==(Object other) => other is AuthLinkError;

  @override
  int get hashCode => (AuthLinkError).hashCode;

  @override
  String toString() => 'AuthLink.error';
}

/// Carries a PKCE `code` to exchange — PKCE code only; a link with implicit
/// tokens is an [AuthLinkError].
final class AuthLinkCallback extends AuthLink {
  const AuthLinkCallback({required this.recovery});

  /// `type=recovery` was present: a password-reset link.
  final bool recovery;

  @override
  bool operator ==(Object other) =>
      other is AuthLinkCallback && other.recovery == recovery;

  @override
  int get hashCode => Object.hash(AuthLinkCallback, recovery);

  @override
  String toString() => 'AuthLink.callback(recovery: $recovery)';
}

AuthLink classifyAuthLink(Uri uri) {
  // On the custom scheme only the registered host is this app's callback;
  // any other host is not ours. (Web callbacks arrive on the page origin,
  // so an https link is classified on its parameters alone.)
  if (uri.scheme == kAuthCallbackScheme && uri.host != kAuthCallbackHost) {
    return const AuthLinkIgnored();
  }
  final params = <String, String>{
    ..._safeSplit(uri.fragment),
    ...uri.queryParameters,
  };
  if (params.containsKey('error') ||
      params.containsKey('error_code') ||
      params.containsKey('error_description')) {
    return const AuthLinkError();
  }
  if (params.containsKey('access_token') ||
      params.containsKey('refresh_token')) {
    return const AuthLinkError();
  }
  if (params.containsKey('code')) {
    return AuthLinkCallback(recovery: params['type'] == 'recovery');
  }
  return const AuthLinkIgnored();
}

Map<String, String> _safeSplit(String fragment) {
  if (fragment.isEmpty) return const {};
  try {
    return Uri.splitQueryString(fragment);
  } on FormatException {
    return const {};
  }
}
