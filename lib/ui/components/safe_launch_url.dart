/// Scheme-allowlisted external URL launching (epic #831, slice 5).
///
/// `url_launcher` hands a [Uri] straight to the OS or the browser. With the
/// web build a first-class client, a `javascript:`/`data:`/arbitrary scheme
/// reaching the platform launcher is the same class of bug an unescaped
/// `href` is on a page — so every launch goes through [safeLaunchUrl], which
/// refuses any scheme outside an explicit allowlist before touching the
/// platform. The XSS surface review that motivates this seam is
/// `docs/web/xss-surface-review.md`.
///
/// Today the only caller is `lib/ui/gate/device_settings_launcher.dart`,
/// which opens fixed *platform* settings schemes (`app-settings:`/`intent:`)
/// and therefore passes its own allowlist. The default allowlist is the
/// web/mail/phone set a deliberate "open this" affordance could legitimately
/// carry; a caller that needs another scheme must widen it explicitly here,
/// in review, rather than silently.
library;

import 'package:url_launcher/url_launcher.dart';

/// The schemes [safeLaunchUrl] permits by default: the web, email, and
/// telephone schemes a user-facing "open this link" affordance can carry.
/// Deliberately excludes `javascript:`, `data:`, `file:`, `intent:`, and
/// every custom scheme — those are never a URL a user typed.
const Set<String> kDefaultLaunchSchemes = <String>{
  'http',
  'https',
  'mailto',
  'tel',
};

/// The `url_launcher` call shape [safeLaunchUrl] depends on, narrowed to the
/// two arguments it uses so a test can substitute a recording fake without
/// depending on the package's own surface.
typedef LaunchUrlFn = Future<bool> Function(Uri url, {LaunchMode mode});

/// Whether [scheme] (case-insensitive) is in [allowedSchemes]. An empty
/// scheme is never allowed: a relative URI has no business being launched.
bool isLaunchSchemeAllowed(String scheme, Set<String> allowedSchemes) =>
    scheme.isNotEmpty && allowedSchemes.contains(scheme.toLowerCase());

/// Launches [url] only when its scheme is allowlisted.
///
/// Returns `false` and never touches the platform for a disallowed or empty
/// scheme — the fail-closed guard. [launch] exists so a test can record the
/// call; production passes nothing and the real `launchUrl` runs.
///
/// The `allowedSchemes` default is [kDefaultLaunchSchemes]; a caller opening
/// an app-specific scheme (see `device_settings_launcher.dart`) passes its
/// own set explicitly instead of widening the default for everyone.
Future<bool> safeLaunchUrl(
  Uri url, {
  Set<String> allowedSchemes = kDefaultLaunchSchemes,
  LaunchMode mode = LaunchMode.platformDefault,
  LaunchUrlFn? launch,
}) {
  if (!isLaunchSchemeAllowed(url.scheme, allowedSchemes)) {
    return Future<bool>.value(false);
  }
  return launch != null ? launch(url, mode: mode) : launchUrl(url, mode: mode);
}
