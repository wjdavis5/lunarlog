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
/// environment, level, transaction (scrubbed through [scrubRouteName] —
/// U1/KTD4; this is the field `SentryNavigatorObserver`'s
/// `setRouteNameAsTransaction` feeds, and it appears on every event, not
/// just navigation breadcrumbs), culprit, fingerprint, sdk, debug images,
/// modules, threads (frames only; Dart never fills locals), `contexts.os`,
/// `contexts.runtime`, `contexts.app.version`, the request URL up to `?` and
/// its method, exception type names with their stack frames, and breadcrumbs
/// that pass [scrubBreadcrumb]. `user`, `extra`, `server_name`, every other
/// context, request headers, bodies, query strings, and message params never
/// do.
library;

import 'package:lunarlog/observability/route_names.dart';
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

/// KTD2's shape fallback for a route name that is not in [kSentryRouteNames]:
/// a bare identifier starting with an uppercase letter, matching the
/// class-name convention `route_names.dart` uses. Rejects anything
/// containing `/`, `_`, or a lowercase leading character, so a path
/// (`/profiles/8f2c-…`) or a snake_case data key can never pass through as
/// if it were a screen name.
final RegExp kSentryRouteNamePattern = RegExp(r'^[A-Z][A-Za-z0-9]{0,63}$');

/// KTD2: the two-stage route-name check every `navigation` breadcrumb's
/// `from`/`to` and every `event.transaction` (KTD4) pass through. A `null`
/// name, or one that fails both stages, becomes `'unknown'` rather than
/// being passed through or silently dropped — the navigation shape survives
/// even when the name cannot be trusted.
///
/// 1. Registry membership ([kSentryRouteNames]) is the real gate: a
///    registered name is always kept, whatever its shape.
/// 2. Otherwise the name must match [kSentryRouteNamePattern] **and** not
///    itself be a deny-listed key (`DisplayName` is shape-legal but still
///    normalizes to the deny-listed `display_name`) to survive — this lets
///    a third-party route (a plugin's dialog) through as a name without
///    admitting a path, an id, or a health-adjacent key.
String scrubRouteName(String? name) {
  if (name == null) return 'unknown';
  if (kSentryRouteNames.contains(name)) return name;
  if (kSentryRouteNamePattern.hasMatch(name) && !isDenyListedKey(name)) {
    return name;
  }
  return 'unknown';
}

/// KTD1: `state` is one of the three navigation-type strings
/// `RouteObserverBreadcrumb` produces (`didPush`, `didPop`, `didReplace`),
/// or `'unknown'` — never passed through unchecked.
String scrubNavigationState(Object? state) {
  const known = {'didPush', 'didPop', 'didReplace'};
  return state is String && known.contains(state) ? state : 'unknown';
}

/// KTD1: rebuilds a navigation breadcrumb's `data` map key by key — `state`,
/// `from`, `to` only, each of `from`/`to` passed through [scrubRouteName].
/// `from_arguments`, `to_arguments`, and any `data` sub-map are dropped
/// unconditionally, never inspected for deny-listed content: this is the
/// hole [containsDenyListedKey] cannot see. `RouteObserverBreadcrumb`
/// stringifies a non-map route argument (`RouteSettings(arguments: profile)`)
/// into a single scalar string via `toString()`, and a scalar has no keys
/// for a deny-list check to find (KTD1). Dropping the whole field, rather
/// than scanning its value, is what actually protects it.
///
/// Extracted from [scrubBreadcrumb] (rather than inlined) to keep that
/// function's McCabe complexity under `tool/quality/crap_gate.dart`'s
/// threshold — see U1's Approach note; this is a quality-gate requirement,
/// not a style preference.
Map<String, dynamic>? scrubNavigationData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final from = data['from'];
  final to = data['to'];
  return {
    'state': scrubNavigationState(data['state']),
    if (from != null) 'from': scrubRouteName(from is String ? from : null),
    if (to != null) 'to': scrubRouteName(to is String ? to : null),
  };
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

/// [_scrubContexts] plus a rebuilt `contexts.trace` (U4; KTD9): trace id,
/// span id, operation, status, and sampled survive; the trace's `data` map
/// is dropped entirely. That `data` map is the second copy of the tracer's
/// raw data — see [scrubTransaction]'s doc comment.
Contexts _scrubTransactionContexts(Contexts contexts) {
  final scrubbed = _scrubContexts(contexts);
  final trace = contexts.trace;
  if (trace != null) {
    scrubbed.trace = SentryTraceContext(
      traceId: trace.traceId,
      spanId: trace.spanId,
      operation: trace.operation,
      status: trace.status,
      sampled: trace.sampled,
    );
  }
  return scrubbed;
}

/// KTD9: rebuilds one span's `data` under an allowlist, using the SDK's
/// real key names — `url` (truncated at `?`), `http.request.method`,
/// `http.response.status_code`, `http.response_content_length`,
/// `db.system`, `db.operation`. `http.query`/`http.fragment` and every
/// other key are dropped. Mutates [span.data] in place: `SentrySpan.data`'s
/// getter returns the live field, and mutating it directly is the only way
/// to change a span's data once the transaction has already finished (its
/// own `setData`/`removeData` methods no-op on a finished span).
void _scrubSpanDataInPlace(SentrySpan span) {
  final data = span.data;
  final url = data['url'];
  final allowed = <String, dynamic>{
    if (url is String) 'url': stripQueryString(url),
    for (final key in const [
      'http.request.method',
      'http.response.status_code',
      'http.response_content_length',
      'db.system',
      'db.operation',
    ])
      if (data.containsKey(key)) key: data[key],
  };
  data
    ..clear()
    ..addAll(allowed);
}

/// Reduces [transaction] to the same KTD12 allowlist [scrubEvent] applies
/// to an event, through mutation rather than reconstruction (U4; KTD9).
///
/// [SentryTransaction] cannot be rebuilt through [SentryEvent]'s
/// constructor without erasing its spans and changing its type. There is
/// no reconstruction path either: its only constructor requires the
/// `@internal` [SentryTracer] (reachable only through an
/// `implementation_imports` violation), and `copyWith` is
/// `@Deprecated('Assign values directly to the instance.')` — the SDK's
/// own guidance. So this is the one function in this library that mutates
/// its argument in place and returns it (or null to drop it), rather than
/// building a new value; every other function here is pure.
///
/// The non-obvious part, verified against `sentry` 9.28.0's
/// `SentryTransaction` constructor: it sets `extra: extra ?? tracer.data`
/// and then `contexts.trace = spanContext.toTraceContext(…, data: data)`
/// with that *same* map — so the tracer's data (which
/// `SentryNavigatorObserver` populates with raw route arguments via
/// `transaction.setData('route_settings_arguments', arguments)`) appears
/// in both places. Dropping `extra` alone would leave the second copy,
/// `contexts.trace.data`, on the wire; [_scrubTransactionContexts] is what
/// closes that.
SentryTransaction? scrubTransaction(SentryTransaction transaction) {
  // ignore: deprecated_member_use
  if (containsDenyListedKey(transaction.extra)) return null;
  for (final span in transaction.spans) {
    if (containsDenyListedKey(span.data)) return null;
  }

  transaction.user = null;
  // ignore: deprecated_member_use
  transaction.extra = null;
  transaction.contexts = _scrubTransactionContexts(transaction.contexts);
  transaction.request = _scrubRequest(transaction.request);
  transaction.transaction = transaction.transaction == null
      ? null
      : scrubRouteName(transaction.transaction);
  transaction.tags = _scrubTags(transaction.tags);
  transaction.breadcrumbs = transaction.breadcrumbs
      ?.map(scrubBreadcrumb)
      .whereType<Breadcrumb>()
      .toList(growable: false);
  for (final span in transaction.spans) {
    _scrubSpanDataInPlace(span);
  }
  return transaction;
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
    // KTD4: `SentryNavigatorObserver`'s `setRouteNameAsTransaction` writes
    // the raw route name here on every event, not just navigation
    // breadcrumbs — this is the one field present everywhere that a
    // dynamically-named or third-party route could otherwise bypass both
    // the registry and the shape check.
    transaction:
        event.transaction == null ? null : scrubRouteName(event.transaction),
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
/// new breadcrumb with navigation `data` rebuilt under an allowlist (U1;
/// KTD1/KTD2 — see [scrubNavigationData]), `http` URLs cut at `?`,
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
    // Route names survive under an allowlist (KTD1/KTD2); arguments never
    // do, whatever shape they take — see scrubNavigationData.
    scrubbedData = scrubNavigationData(data);
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
