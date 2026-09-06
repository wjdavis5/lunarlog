/// Sentry privacy floor (U7; KTD12, R18, AE7): pure functions that reduce a
/// [SentryEvent] or [Breadcrumb] to an allowlist before it leaves the device.
///
/// The posture is allowlist-shaped: [scrubEvent] rebuilds the event from the
/// fields it is allowed to keep rather than deleting the fields it knows
/// about, so an SDK field added later is dropped by default. Nothing here
/// touches the Sentry hub, so both functions are unit-testable on hand-built
/// objects and safe to call when Sentry is not initialized.
///
/// What survives an event: id, timestamp, platform, release, dist,
/// environment, level, transaction, culprit, fingerprint, sdk, debug images,
/// modules, threads (frames only; Dart never fills locals), `contexts.os`,
/// `contexts.runtime`, `contexts.app.version`, the request URL up to `?` and
/// its method, exception type names with their stack frames, and breadcrumbs
/// that pass [scrubBreadcrumb]. `user`, `extra`, `server_name`, every other
/// context, request headers, bodies, query strings, and message params never
/// do.
library;

import 'package:sentry_flutter/sentry_flutter.dart';

/// Keys whose presence anywhere in a breadcrumb's `data` (any depth) drops
/// the breadcrumb, and whose presence in `event.tags`, `event.logger`, or the
/// message text scrubs that field. Listed in snake_case; [isDenyListedKey]
/// also matches the camelCase spelling of each (`display_name` and
/// `displayName` are the same key) and ignores case.
///
/// Sources: local schema columns that carry health content (`note`, `tags`,
/// `local_date`, `display_name`), account identity (`email`), the Supabase
/// realtime/RPC payload names that wrap whole rows (`record`, `old_record`,
/// `p_day_entries`, `p_profiles`), and the two request headers that carry
/// credentials (`authorization`, `apikey`). Identity payloads (#2 U6; KTD7):
/// the gotrue user and session fields, the Google and Apple token, code, and
/// nonce names, and the profile claims (name parts, picture, hosted domain)
/// that a sign-in flow could put in a breadcrumb.
///
/// Bare words such as `name`, `token`, `user`, `sub`, and `session` are
/// deliberately absent: [mentionsDenyListedKey] drops any message that
/// mentions a listed key, and those words appear in ordinary Drift, gotrue,
/// and HTTP messages. A `session` breadcrumb is already covered by the token
/// keys nested inside it.
const List<String> sentryDenyListedKeys = [
  'note',
  'tags',
  'display_name',
  'local_date',
  'email',
  'record',
  'old_record',
  'p_day_entries',
  'p_profiles',
  'authorization',
  'apikey',
  // Identity payloads (#2 U6; KTD7).
  'identities',
  'identity_data',
  'id_token',
  'identity_token',
  'access_token',
  'refresh_token',
  'provider_token',
  'provider_refresh_token',
  'authorization_code',
  'server_auth_code',
  'token_hash',
  'code_verifier',
  'nonce',
  'full_name',
  'given_name',
  'family_name',
  'picture',
  'avatar_url',
  'photo_url',
  'hd',
  'user_metadata',
];

/// Exception type-name fragments that mark an exception as coming from the
/// data layer, whose messages embed SQL, rows, PostgREST details, or auth
/// responses. Matched case-insensitively against [SentryException.type]. An
/// exception is also treated as data-layer when any stack frame points into
/// `lib/data` ([_dataLayerPathMarkers]), whatever its type name.
/// `googlesignin` (#2 U6; KTD7) reduces a `GoogleSignInException` that escapes
/// the KTD8 mapping to its type: its message can carry the account or a token
/// fragment.
const List<String> sentryDataLayerTypeMarkers = [
  'sqlite',
  'drift',
  'postgrest',
  'auth',
  'gotrue',
  'supabase',
  'rowcodec',
  'synctransport',
  'database',
  'encryption',
  'googlesignin',
];

const List<String> _dataLayerPathMarkers = [
  'lib/data/',
  'lunarlog/data/',
];

final Set<String> _normalizedDenyList =
    sentryDenyListedKeys.map(_normalizeKey).toSet();

/// Lower-cases and strips underscores so `display_name`, `displayName`, and
/// `DISPLAY_NAME` compare equal.
String _normalizeKey(String key) => key.toLowerCase().replaceAll('_', '');

/// True when [key] is one of [sentryDenyListedKeys] in any spelling.
bool isDenyListedKey(String key) =>
    _normalizedDenyList.contains(_normalizeKey(key));

/// True when [value] (a map, list, or scalar) contains a deny-listed key at
/// any depth. Scalars never match: this checks key names, not values.
bool containsDenyListedKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && isDenyListedKey(key)) return true;
      if (containsDenyListedKey(entry.value)) return true;
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(containsDenyListedKey);
  }
  return false;
}

/// True when [text] mentions a deny-listed key as a word or path segment
/// (`day_entries.note`, `note:`, `displayName=`), in either spelling.
///
/// Exported (not just used internally for Sentry messages/loggers) so other
/// free-text sinks — `breadcrumbs.dart`'s `BreadcrumbLog.record`, in
/// particular — can apply the same token-wise check to arbitrary printed
/// strings (a raw error message, a SQL string with bound arguments), not
/// just to a value that is itself exactly one deny-listed key.
bool mentionsDenyListedKey(String text) {
  final tokens = text.split(RegExp(r'[^A-Za-z0-9_]+'));
  return tokens.any((token) => token.isNotEmpty && isDenyListedKey(token));
}

/// Cuts a URL at its first `?`, dropping the query string and anything after.
String stripQueryString(String url) {
  final index = url.indexOf('?');
  return index < 0 ? url : url.substring(0, index);
}

bool _isDataLayerException(SentryException exception) {
  final type = exception.type?.toLowerCase() ?? '';
  if (sentryDataLayerTypeMarkers.any(type.contains)) return true;
  final module = exception.module?.toLowerCase() ?? '';
  if (_dataLayerPathMarkers.any(module.contains)) return true;
  for (final frame in exception.stackTrace?.frames ?? const <SentryStackFrame>[]) {
    for (final location in [
      frame.absPath,
      frame.fileName,
      frame.module,
      frame.package,
    ]) {
      final normalized = location?.replaceAll('\\', '/').toLowerCase();
      if (normalized != null &&
          _dataLayerPathMarkers.any(normalized.contains)) {
        return true;
      }
    }
  }
  return false;
}

SentryException _scrubException(SentryException exception) {
  final reduce = _isDataLayerException(exception);
  return SentryException(
    type: exception.type,
    // A data-layer message can embed SQL with bound arguments, a PostgREST
    // `details` row, or an auth response with the email: keep only the type.
    value: reduce ? exception.type : exception.value,
    module: exception.module,
    stackTrace: exception.stackTrace,
    mechanism: exception.mechanism,
    threadId: exception.threadId,
    throwable: exception.throwable,
  );
}

Contexts _scrubContexts(Contexts contexts) {
  final app = contexts.app;
  return Contexts(
    operatingSystem: contexts.operatingSystem,
    runtimes: contexts.runtimes,
    app: app == null ? null : SentryApp(version: app.version),
  );
}

SentryRequest? _scrubRequest(SentryRequest? request) {
  if (request == null) return null;
  final url = request.url;
  return SentryRequest(
    url: url == null ? null : stripQueryString(url),
    method: request.method,
  );
}

SentryMessage? _scrubMessage(SentryMessage? message) {
  if (message == null) return null;
  final formatted = message.formatted;
  final template = message.template;
  final tainted = mentionsDenyListedKey(formatted) ||
      (template != null && mentionsDenyListedKey(template));
  // Params are the interpolated values (a note, a date) and are never kept.
  return tainted ? SentryMessage('[scrubbed]') : SentryMessage(formatted);
}

Map<String, String>? _scrubTags(Map<String, String>? tags) {
  if (tags == null) return null;
  final kept = <String, String>{
    for (final entry in tags.entries)
      if (!isDenyListedKey(entry.key)) entry.key: entry.value,
  };
  return kept.isEmpty ? null : kept;
}

/// Reduces [event] to the KTD12 allowlist. Never returns null: dropping an
/// event would hide the crash, and the allowlist already removes everything
/// R18 forbids. Returns a new event; [event] is not mutated.
SentryEvent? scrubEvent(SentryEvent event) {
  final logger = event.logger;
  final breadcrumbs = event.breadcrumbs
      ?.map(scrubBreadcrumb)
      .whereType<Breadcrumb>()
      .toList(growable: false);
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: event.platform,
    logger: logger != null && mentionsDenyListedKey(logger) ? null : logger,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    modules: event.modules,
    message: _scrubMessage(event.message),
    transaction: event.transaction,
    // The decorated throwable keeps the SDK's mechanism bookkeeping; the
    // throwable itself is never serialized.
    throwable: event.throwableMechanism,
    level: event.level,
    culprit: event.culprit,
    tags: _scrubTags(event.tags),
    fingerprint: event.fingerprint,
    contexts: _scrubContexts(event.contexts),
    breadcrumbs: breadcrumbs,
    sdk: event.sdk,
    request: _scrubRequest(event.request),
    debugMeta: event.debugMeta,
    exceptions: event.exceptions?.map(_scrubException).toList(growable: false),
    threads: event.threads,
    type: event.type,
    // Deliberately absent: user, extra, serverName, unknown.
  );
}

/// Scrubs breadcrumb free text the same way [_scrubMessage] scrubs an event
/// message: null passes through, anything mentioning a deny-listed key
/// becomes `[scrubbed]`, everything else passes through unchanged.
String? _scrubBreadcrumbMessage(String? message) =>
    message != null && mentionsDenyListedKey(message) ? '[scrubbed]' : message;

/// Applies the KTD12 breadcrumb rules. Returns null (drop) when the
/// breadcrumb's `data` carries a deny-listed key at any depth; otherwise a
/// new breadcrumb with navigation `data` removed, `http` URLs cut at `?`,
/// and `message` scrubbed via [_scrubBreadcrumbMessage] — raw
/// console/debugPrint text can itself carry health-log content or a DB
/// error with bound arguments, and this breadcrumb goes to the Sentry SDK
/// via `beforeBreadcrumb` regardless of what the local breadcrumb ring
/// keeps.
Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb) {
  if (breadcrumb == null) return null;
  final data = breadcrumb.data;
  if (containsDenyListedKey(data)) return null;

  final category = breadcrumb.category;
  final isHttp = category == 'http' || breadcrumb.type == 'http';
  final Map<String, dynamic>? scrubbedData;
  if (category == 'navigation') {
    // Route names and arguments can carry an entry date or profile id.
    scrubbedData = null;
  } else if (isHttp && data != null) {
    scrubbedData = <String, dynamic>{
      for (final entry in data.entries)
        if (entry.key == 'url' && entry.value is String)
          entry.key: stripQueryString(entry.value as String)
        else if (entry.key != 'http.query' && entry.key != 'http.fragment')
          entry.key: entry.value,
    };
  } else {
    scrubbedData = data;
  }

  return Breadcrumb(
    message: _scrubBreadcrumbMessage(breadcrumb.message),
    timestamp: breadcrumb.timestamp,
    category: category,
    data: scrubbedData,
    level: breadcrumb.level,
    type: breadcrumb.type,
  );
}
