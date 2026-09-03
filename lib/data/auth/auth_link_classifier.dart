/// Pure classification of an incoming link (U4, KTD8). Looks only at
/// parameter *names* (query and fragment) so nothing here ever holds an
/// `error_description` value; the result types are fieldless except for
/// the recovery flag.
library;

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
/// `error_description` (expired or reused link). Never exchanged.
final class AuthLinkError extends AuthLink {
  const AuthLinkError();

  @override
  bool operator ==(Object other) => other is AuthLinkError;

  @override
  int get hashCode => (AuthLinkError).hashCode;

  @override
  String toString() => 'AuthLink.error';
}

/// Carries a PKCE `code` (or implicit `access_token`) to exchange.
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
  final params = <String, String>{
    ..._safeSplit(uri.fragment),
    ...uri.queryParameters,
  };
  if (params.containsKey('error') ||
      params.containsKey('error_code') ||
      params.containsKey('error_description')) {
    return const AuthLinkError();
  }
  if (params.containsKey('code') || params.containsKey('access_token')) {
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
