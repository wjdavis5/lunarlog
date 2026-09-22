/// Browser-URL cleanup after a web PKCE exchange (epic #831 slice 4).
///
/// A web auth email lands on `<origin>/auth/callback?code=…`; the app
/// exchanges that code itself (slice 2). The code stays in the address bar
/// afterwards, so a manual reload re-attempts the exchange — the PKCE
/// verifier is gone — and surfaces a bogus expired-link failure even though
/// the session was restored from browser storage. [cleanAuthUrl] strips the
/// spent parameters and the service hands the result to a [WebUrlCleaner],
/// whose production implementation rewrites the current history entry via
/// `window.history.replaceState` on web ([replaceBrowserUrl]) and does
/// nothing on native.
library;

import 'web_url_cleaner_stub.dart'
    if (dart.library.js_interop) 'web_url_cleaner_web.dart' as platform;

/// A function the auth service calls with the browser URL once it has
/// handled a web auth callback, so the address bar no longer advertises a
/// spent code or a provider error. Injectable: tests record the cleaned
/// [Uri] instead of touching `window.history`; native never calls it.
typedef WebUrlCleaner = void Function(Uri cleanedUri);

/// The production [WebUrlCleaner]: `window.history.replaceState` on web, a
/// deliberate no-op on every native platform. The service only invokes it
/// when it holds a web initial URI (i.e. on web), so a native build neither
/// reaches this nor has a browser URL to rewrite.
void replaceBrowserUrl(Uri uri) => platform.replaceBrowserUrl(uri);

/// The parameters a PKCE auth callback can carry. After the exchange — or
/// after the provider rejects the link — these are removed from the browser
/// URL so a reload cannot replay a spent code or re-surface a bogus
/// expired-link failure. `type` is included because it only ever marks a
/// recovery callback.
const Set<String> kAuthUrlParamNames = {
  'code',
  'error',
  'error_code',
  'error_description',
  'access_token',
  'refresh_token',
  'type',
};

/// [uri] with every [kAuthUrlParamNames] parameter removed — from the query
/// and the fragment — while preserving the scheme, authority, path, the
/// parameter order, duplicate keys, and every other parameter. Returns
/// [uri] unchanged when it carries no auth parameter, so a caller can treat
/// identity as "nothing to clean". Pure; unit-tested directly.
Uri cleanAuthUrl(Uri uri) {
  final cleanedQuery = _stripAuthParams(uri.query);
  final cleanedFragment = _stripAuthParams(uri.fragment);
  if (cleanedQuery == uri.query && cleanedFragment == uri.fragment) {
    return uri;
  }
  // Rebuilt with the Uri constructor rather than `Uri.replace`: replacing
  // `query`/`fragment` with `''` leaves a trailing `?`/`#`, whereas a null
  // query/fragment here omits both.
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    query: cleanedQuery.isEmpty ? null : cleanedQuery,
    fragment: cleanedFragment.isEmpty ? null : cleanedFragment,
  );
}

String _stripAuthParams(String component) {
  if (component.isEmpty) return component;
  final kept = <String>[];
  for (final pair in component.split('&')) {
    if (pair.isEmpty) continue;
    final separator = pair.indexOf('=');
    final rawKey = separator < 0 ? pair : pair.substring(0, separator);
    if (kAuthUrlParamNames.contains(_decodeQueryKey(rawKey))) continue;
    kept.add(pair);
  }
  return kept.join('&');
}

String _decodeQueryKey(String rawKey) {
  try {
    return Uri.decodeQueryComponent(rawKey);
  } on ArgumentError {
    return rawKey;
  }
}
