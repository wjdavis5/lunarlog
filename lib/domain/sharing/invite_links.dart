/// Invite, claim, and prediction-connection deep links (issue #129).
///
/// Two forms carry the same query (`code`, optional `profile`, optional
/// `kind`) and route identically downstream:
///
/// * Custom scheme (always available):
///   `lunarlog://invite?code=<rawToken>&profile=<profileId>[&kind=...]`.
/// * HTTPS universal link (only when a hosted domain is configured via
///   `AppConfig.linkDomain`, i.e. `--dart-define=LUNARLOG_LINK_DOMAIN=...`):
///   `https://<domain>/invite?code=<rawToken>&profile=<profileId>[&kind=...]`.
///
/// An empty domain means custom-scheme-only — today's behavior, unchanged.
/// `kind=claim` routes to `ClaimProfileSheet`, `kind=prediction` to
/// `AcceptPredictionConnectionSheet`, and anything else to
/// `AcceptInviteSheet` (the router in `lib/app.dart` owns that decision;
/// this file only builds and recognises the links).
///
/// Privacy: the `code` is a redeemable credential. It travels in the URL
/// only — builders here never log it and parsers here never persist it.
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary.
library;

import 'package:meta/meta.dart';

/// Custom-scheme form's scheme (`lunarlog://invite?...`).
const String kInviteLinkScheme = 'lunarlog';

/// Custom-scheme form's host (`lunarlog://invite?...`).
const String kInviteLinkHost = 'invite';

/// HTTPS form's path (`https://<domain>/invite?...`).
const String kInviteLinkPath = '/invite';

/// `kind` value routing to `ClaimProfileSheet` (ownership transfer).
const String kInviteLinkKindClaim = 'claim';

/// `kind` value routing to `AcceptPredictionConnectionSheet`.
const String kInviteLinkKindPrediction = 'prediction';

/// A recognised invite/claim/prediction link, either form.
@immutable
class InviteLink {
  const InviteLink({required this.code, this.profileId, this.kind});

  /// The redeemable token from the link's `code` query parameter.
  final String code;

  /// The `profile` query parameter, when present and non-empty.
  final String? profileId;

  /// The `kind` query parameter, when present and non-empty.
  final String? kind;

  /// True for an ownership-transfer claim link.
  bool get isClaim => kind == kInviteLinkKindClaim;

  /// True for a prediction-only connection link.
  bool get isPrediction => kind == kInviteLinkKindPrediction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteLink &&
          other.code == code &&
          other.profileId == profileId &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(code, profileId, kind);
}

/// Normalizes a configured link domain to a bare lowercase host.
///
/// Accepts the forms an operator might supply (`example.com`,
/// `https://example.com`, `https://example.com/` with different casing or
/// surrounding whitespace) and reduces them to the host the HTTPS link and
/// the platform associations match against. Empty in, empty out.
String normalizeLinkDomain(String raw) {
  var domain = raw.trim().toLowerCase();
  for (final prefix in const ['https://', 'http://']) {
    if (domain.startsWith(prefix)) {
      domain = domain.substring(prefix.length);
      break;
    }
  }
  final slash = domain.indexOf('/');
  if (slash >= 0) {
    domain = domain.substring(0, slash);
  }
  while (domain.endsWith('.')) {
    domain = domain.substring(0, domain.length - 1);
  }
  return domain.trim();
}

/// Builds an invite/claim/prediction link for [code].
///
/// Emits the HTTPS universal-link form when [linkDomain] is non-empty and
/// the custom-scheme form otherwise. Callers pass `AppConfig.linkDomain`;
/// tests pass explicit values.
Uri buildInviteLink({
  required String code,
  String? profileId,
  String? kind,
  String linkDomain = '',
}) {
  final query = <String, String>{'code': code};
  final profile = profileId;
  if (profile != null && profile.isNotEmpty) {
    query['profile'] = profile;
  }
  final linkKind = kind;
  if (linkKind != null && linkKind.isNotEmpty) {
    query['kind'] = linkKind;
  }
  final domain = normalizeLinkDomain(linkDomain);
  if (domain.isEmpty) {
    return Uri(
      scheme: kInviteLinkScheme,
      host: kInviteLinkHost,
      queryParameters: query,
    );
  }
  return Uri(
    scheme: 'https',
    host: domain,
    path: kInviteLinkPath,
    queryParameters: query,
  );
}

/// Parses [uri] as an invite/claim/prediction link, either form.
///
/// Returns null for anything that is not a link: null, a missing/empty
/// `code`, another host or path, a non-HTTPS scheme on the universal form,
/// or an HTTPS invite URL when no [linkDomain] is configured (an
/// unconfigured build only ever honours the custom scheme).
InviteLink? parseInviteLink(Uri? uri, {String linkDomain = ''}) {
  if (uri == null) {
    return null;
  }
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) {
    return null;
  }
  if (_isCustomSchemeInvite(uri)) {
    return InviteLink(
      code: code,
      profileId: _nonEmpty(uri.queryParameters['profile']),
      kind: _nonEmpty(uri.queryParameters['kind']),
    );
  }
  if (_isUniversalInvite(uri, normalizeLinkDomain(linkDomain))) {
    return InviteLink(
      code: code,
      profileId: _nonEmpty(uri.queryParameters['profile']),
      kind: _nonEmpty(uri.queryParameters['kind']),
    );
  }
  return null;
}

/// Whether [uri] is an invite/claim/prediction link — the filter
/// `lib/main.dart` applies to incoming links, cold start and warm.
bool isInviteLink(Uri? uri, {String linkDomain = ''}) =>
    parseInviteLink(uri, linkDomain: linkDomain) != null;

bool _isCustomSchemeInvite(Uri uri) =>
    uri.scheme == kInviteLinkScheme && uri.host == kInviteLinkHost;

bool _isUniversalInvite(Uri uri, String domain) {
  if (domain.isEmpty) {
    return false;
  }
  if (uri.scheme != 'https' || uri.host.toLowerCase() != domain) {
    return false;
  }
  return uri.path == kInviteLinkPath || uri.path == '$kInviteLinkPath/';
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
