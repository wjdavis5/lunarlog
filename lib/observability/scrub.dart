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
/// `contexts.runtime`, `contexts.app.version`, the request URL up to `?`
/// with any UUID-shaped path segment redacted (issue #640/LLA-082 —
/// [scrubUrl]; keeps a Storage object path from carrying an account or
/// ticket identifier) and its method, exception type names with their stack
/// frames, and breadcrumbs that pass [scrubBreadcrumb]. `user`, `extra`,
/// `server_name`, every other context, request headers, bodies, query
/// strings, and message params never do.
library;

import 'package:lunarlog/observability/route_names.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Keys whose presence anywhere in a breadcrumb's `data` (any depth) drops
/// the breadcrumb, and whose presence in `event.tags`, `event.logger`, or the
/// message text scrubs that field. Listed in snake_case; [isDenyListedKey]
/// also matches the camelCase spelling of each (`display_name` and
/// `displayName` are the same key), ignores case, and (issue #520) matches
/// [sentryDenyListedKeyStems] as a substring of the normalised key — so a
/// prefixed or suffixed variant that is not spelled out verbatim below
/// (`p_token_hash`, `reply_email`, `p_child_display_name`, `value_text`) is
/// still caught. See [isDenyListedKey] for exactly how the two checks
/// combine.
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
/// Shared care content (Issue #128): `body` (the free-text column on both
/// `care_notes` and `visit_prep_items`), the table names in either spelling
/// (`care_note(s)`, `visit_prep(_item(s))`, `prep_item(s)`), and the
/// `sync_push` payload names that wrap whole rows (`p_care_notes`,
/// `p_visit_prep_items`).
///
/// Issue #497/#520: the three `sync_push` payload names (and bare table
/// names) added by the observations/profile-modes/cycle-overrides features
/// (`p_observations`, `p_profile_modes`, `p_cycle_overrides`) went
/// unlisted, along with the health content and state columns those and
/// earlier features added — `flow`, `pms`, `mode`, `birth_control_method`
/// and its start/stop dates, `health_sync_consent`, the mode-change and
/// cycle-fact dates, and the shared-prediction `projection` payload.
/// `value_text`/`value_num` and `raw` (Observations' free-text and raw-JSON
/// escape-hatch columns) are caught via the `value`/`raw` stems rather than
/// listed verbatim — see [sentryDenyListedKeyStems].
///
/// Issue #520 also closes three drift gaps the same audit found outside the
/// schema itself: `is_minor`/`birth_year` (profile demographic facts,
/// exact-match only — neither matches a stem); the bulk importer's
/// `p_rows` (a batch of whole imported day-entry-shaped rows, the same
/// shape of gap `p_day_entries` already covered, just on a different RPC —
/// see `lib/data/import/supabase_bulk_importer.dart`) and its
/// `p_estimated_next_start` sibling in the reminder-window RPC (a predicted
/// cycle-start date); and `recipient_label`/`p_recipient_label` (a
/// user-typed label for a sharing/transfer recipient — the same kind of
/// content as `display_name`, just not sharing its stem).
///
/// Deliberately NOT listed, even though issue #520 also flagged them as
/// missing from `lib/data/db/tables.dart`: `category`/`code`/`unit`/
/// `intensity`/`excluded` (Observations). These are short, mostly
/// closed-vocabulary labels (`pain`, `bbt`, `migraine`) rather than open
/// free text, and — unlike every other key here — they collide with
/// harmless bare words already exercised as breadcrumb data elsewhere
/// (`{'code': 'canceled'}` in a Google sign-in breadcrumb): deny-listing
/// them as bare words would drop breadcrumbs that carry no health content
/// at all. The guard test in `test/observability/deny_list_coverage_test.dart`
/// waives them with this same reasoning, alongside every other column that
/// is bookkeeping/opaque-id shaped rather than content shaped.
///
/// Bare words such as `name`, `token`, `user`, `sub`, and `session` are
/// deliberately absent: [mentionsDenyListedKey] drops any message that
/// mentions a listed key, and those words appear in ordinary Drift, gotrue,
/// and HTTP messages. A `session` breadcrumb is already covered by the token
/// keys nested inside it. `token` is also why [sentryDenyListedKeyStems]
/// treats it as a whole-key exemption (see [isDenyListedKey]): a substring
/// stem with no such exemption would silently resurrect this exact
/// false-positive.
const List<String> sentryDenyListedKeys = [
  'note',
  'tags',
  'body',
  'care_note',
  'care_notes',
  'visit_prep',
  'visit_prep_item',
  'visit_prep_items',
  'prep_item',
  'prep_items',
  'display_name',
  'local_date',
  'email',
  'record',
  'old_record',
  'p_day_entries',
  'p_profiles',
  'p_care_notes',
  'p_visit_prep_items',
  // Issue #257: the custom-tag registry push param — carries the
  // user's own health vocabulary (display_name et al), exactly the
  // content class p_day_entries/p_care_notes protect.
  'p_tag_registry',
  // Issue #130: the same-date merge disclosure's retained losing value
  // (a discarded note's text, or a flow level string) is health content
  // exactly like `note` — it must never reach a crash report or breadcrumb.
  'losing_value_text',
  'merge_event',
  'merge_events',
  'p_merge_events',
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
  // Issue #497/#520: observations, profile_modes, and cycle_overrides
  // sync_push parameters and table names, plus the health content/state
  // columns those and earlier features added.
  'observations',
  'p_observations',
  'profile_modes',
  'p_profile_modes',
  'cycle_overrides',
  'p_cycle_overrides',
  'projection',
  'p_projection',
  'flow',
  'pms',
  'mode',
  'is_minor',
  'birth_year',
  'birth_control_method',
  'birth_control_started_on',
  'birth_control_stopped_on',
  'health_sync_consent',
  'mode_started_on',
  // Issue #192: a pregnancy due date is health content of the most
  // sensitive kind the app carries (it dates a pregnancy) — scrubbed
  // like its `mode_started_on` sibling.
  'estimated_due_date',
  'cycle_start_date',
  'last_period_start',
  'typical_cycle_length_days',
  'typical_period_length_days',
  // Issue #259: the curated-categories document reveals which (potentially
  // intimate) areas a profile tracks at all — content-adjacent, scrubbed
  // like 'tags'.
  'tracking_preferences',
  // Issue #520: the bulk importer's per-chunk payload (a batch of whole
  // imported day-entry-shaped rows) and its reminder-window sibling (a
  // predicted cycle-start date), plus a user-typed recipient label
  // (display_name-shaped free text that does not share its stem).
  'p_rows',
  'p_estimated_next_start',
  'recipient_label',
  'p_recipient_label',
];

/// Sensitive stems (issue #520): a key whose *normalised* form contains one
/// of these as a substring is deny-listed even when it is not spelled out
/// verbatim in [sentryDenyListedKeys] — catching a prefixed or suffixed
/// variant like `p_token_hash` (contains `token` and `hash`), `reply_email`
/// (contains `email`), `p_child_display_name`/`p_guardian_display_name`/
/// `p_parent_display_name` (contain `displayname`), and Observations'
/// `value_num`/`value_text` (contain `value`). Exact-match alone missed
/// exactly these in #520's audit.
///
/// A short, deliberately narrow list — not every deny-listed word — keeps
/// the false-positive surface small: see [isDenyListedKey] for the one
/// exemption ([_wholeKeyExemptStems]) this still needs.
const List<String> sentryDenyListedKeyStems = [
  'token',
  'hash',
  'email',
  'displayname',
  'note',
  'value',
  'raw',
];

/// Stems from [sentryDenyListedKeyStems] matched only as a genuine
/// compound, never as the whole normalised key. `token` is one of the "bare
/// words... deliberately absent" from [sentryDenyListedKeys] (see its doc
/// comment) precisely because it appears in ordinary Drift/gotrue/HTTP
/// messages ("session token expired"); matching it as an unqualified
/// substring would resurrect that exact false-positive for every message
/// mentioning the bare word. `p_token`, `token_hash`, `p_token_hash`, and
/// `access_token` are all still caught: each is strictly longer than the
/// bare word `token`.
const Set<String> _wholeKeyExemptStems = {'token'};

/// Exception type-name fragments that mark an exception whose message
/// embeds storage material — SQL, rows, PostgREST details, auth responses,
/// or a filesystem path — as coming from the data layer. Matched
/// case-insensitively against [SentryException.type]. An exception is also
/// treated as data-layer when any stack frame points into `lib/data` or
/// `lib/startup` ([_dataLayerPathMarkers]), whatever its type name.
/// `googlesignin` (#2 U6; KTD7) reduces a `GoogleSignInException` that escapes
/// the KTD8 mapping to its type: its message can carry the account or a token
/// fragment.
///
/// The `filesystem`/`path*`/`platformdirectory` fragments (issue #97 U1)
/// cover what the device-reset delete step can throw out of
/// `lib/startup/startup_native.dart`: a `FileSystemException` (or one of
/// `dart:io`'s path subclasses, or path_provider's
/// `MissingPlatformDirectoryException`) interpolates the database file's
/// absolute path into its message.
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
  // Issue #97 U1: the reset path's filesystem failures (see above).
  'filesystem',
  'pathnotfound',
  'pathaccess',
  'pathexists',
  'platformdirectory',
];

/// Path fragments marking an exception as raised from storage code —
/// `lib/data` (the repositories and the Drift store) and, since issue #97
/// U1, `lib/startup` (the reset/startup primitives that touch the database
/// file directly).
///
/// Since issue #516, this predicate is no longer what decides whether
/// [_scrubException] reduces a value — the default is now reduced
/// regardless (see [_sentrySafeExceptionTypes]) because
/// `--obfuscate --split-debug-info` can destroy both of this predicate's
/// discriminators at once. It still runs as defense-in-depth: an
/// allowlisted-safe type raised from `lib/data`/`lib/startup` is reduced
/// anyway, on the chance the allowlist is ever wrong for a given call site.
const List<String> _dataLayerPathMarkers = [
  'lib/data/',
  'lunarlog/data/',
  'lib/startup/',
  'lunarlog/startup/',
];

final Set<String> _normalizedDenyList =
    sentryDenyListedKeys.map(_normalizeKey).toSet();

final List<String> _normalizedDenyListedKeyStems =
    sentryDenyListedKeyStems.map(_normalizeKey).toList(growable: false);

/// Lower-cases and strips underscores so `display_name`, `displayName`, and
/// `DISPLAY_NAME` compare equal.
String _normalizeKey(String key) => key.toLowerCase().replaceAll('_', '');

/// True when [key] is one of [sentryDenyListedKeys] in any spelling, or its
/// normalised form contains one of [sentryDenyListedKeyStems] as a genuine
/// substring (issue #520) — except a stem in [_wholeKeyExemptStems] matching
/// the *entire* normalised key, which is deliberately not enough on its own
/// (see that constant's doc comment).
bool isDenyListedKey(String key) {
  final normalized = _normalizeKey(key);
  if (_normalizedDenyList.contains(normalized)) return true;
  for (final stem in _normalizedDenyListedKeyStems) {
    if (normalized == stem && _wholeKeyExemptStems.contains(stem)) continue;
    if (normalized.contains(stem)) return true;
  }
  return false;
}

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

/// True when [value] (a map, list, or scalar) contains a string that
/// mentions a deny-listed key via [mentionsDenyListedKey], at any depth.
/// Unlike [containsDenyListedKey] (which inspects only map keys, never
/// values), this inspects string leaves — closing the gap issue #520
/// identifies: an ordinary (non-navigation) breadcrumb's `data` can carry
/// deny-listed content under a key that is not itself deny-listed, e.g.
/// `{'error': 'UNIQUE constraint failed: day_entries.note'}`.
bool _dataValuesMentionDenyListedKey(Object? value) {
  if (value is String) return mentionsDenyListedKey(value);
  if (value is Map) return value.values.any(_dataValuesMentionDenyListedKey);
  if (value is Iterable) return value.any(_dataValuesMentionDenyListedKey);
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

/// A UUID (any RFC 4122 version — hex digits in the canonical 8-4-4-4-12
/// dashed grouping), matched case-insensitively.
final RegExp _uuidPattern = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);

/// Replaces every UUID-shaped run in [url] with `<id>` (issue #640/LLA-082).
///
/// A general rule rather than a single hard-coded bucket: it catches the
/// account uuid, ticket uuid, and generated object-name uuid alike in a
/// Storage path like `.../storage/v1/object/feedback-attachments/UID/
/// TICKET_ID/OBJECT_UUID.png` (see
/// `SupabaseFeedbackService._attachAndUpdate`), and any other UUID-shaped
/// path segment a future endpoint introduces — without needing to know the
/// bucket name or path shape. Matches wherever a UUID appears in the
/// string, not just as a whole path segment, since the object name embeds
/// a file extension right after it (`OBJECT_UUID.png`).
String _redactUuidSegments(String url) =>
    url.replaceAll(_uuidPattern, '<id>');

/// The combined URL scrub every recorded URL (request, breadcrumb, span
/// data) goes through: [stripQueryString] cuts the query string, then
/// [_redactUuidSegments] normalises any UUID-shaped path segment that
/// survives — so an account or ticket identifier embedded in a Storage
/// object path never reaches Sentry, not just a query-string value.
String scrubUrl(String url) => _redactUuidSegments(stripQueryString(url));

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

/// Exception types short-listed as safe to keep their `value` verbatim
/// (issue #516): each is a well-known framework type whose message is
/// Flutter's own static diagnostic text, never interpolated app content.
///
/// Deliberately short. Anything not on this list defaults to reduced —
/// the inversion #516 asks for: `--obfuscate --split-debug-info`
/// (`play-store-release.yml`, enabled by #211) destroys both of
/// [_isDataLayerException]'s discriminators (the `type` name and every
/// stack frame's path), so a real `SqliteException` can reach here with a
/// mangled `type` like `'a1b'` and pathless frames. The old "reduce only
/// when recognized as data-layer" default silently stopped reducing that
/// case, because nothing about it looked recognizable. Inverting the
/// default means an unrecognized (or mangled) type is reduced, not kept.
const Set<String> _sentrySafeExceptionTypes = {
  'FlutterError',
};

/// KTD12/#516/#520: reduces [exception] to its type name unless it is on
/// the short [_sentrySafeExceptionTypes] allowlist — and even then, only
/// when it is neither raised from the data layer ([_isDataLayerException],
/// kept as defense-in-depth against the allowlist being wrong for a given
/// call site) nor mentions a deny-listed key itself ([mentionsDenyListedKey]
/// — issue #520: `SentryException.value` was never deny-list-checked, so a
/// "safe" type's message could still happen to name one).
SentryException _scrubException(SentryException exception) {
  final type = exception.type;
  final value = exception.value;
  final isSafeType = type != null && _sentrySafeExceptionTypes.contains(type);
  final keepVerbatim = isSafeType &&
      !_isDataLayerException(exception) &&
      !(value != null && mentionsDenyListedKey(value));
  return SentryException(
    type: type,
    // A data-layer message can embed SQL with bound arguments, a PostgREST
    // `details` row, or an auth response with the email; an obfuscated
    // build can also make any exception's type/frames unrecognizable
    // (#516). So the default is reduced, not kept — only a short, explicit
    // allowlist of known-safe types (further gated by
    // mentionsDenyListedKey) survives verbatim.
    value: keepVerbatim ? value : type,
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

/// The two suffixes `sentry_flutter` 9.28.0's `time_to_initial_display_
/// tracker.dart` / `time_to_full_display_tracker.dart` append to a TTID/TTFD
/// span's `description`: `'${transaction.name} initial display'` /
/// `'... full display'`. `transaction.name` there is the *raw*
/// `RouteSettings.name` the navigator observer saw, not the value
/// [scrubRouteName] has already reduced — so the description carries an
/// unscrubbed route name verbatim unless [_scrubSpanDescription] recognizes
/// this exact shape and scrubs the prefix.
const List<String> _spanDescriptionSuffixes = [
  ' initial display',
  ' full display',
];

/// Reduces a span's `description` the same way [scrubEvent] reduces
/// `event.transaction`: a TTID/TTFD description has its raw route-name
/// prefix passed through [scrubRouteName] (see [_spanDescriptionSuffixes]);
/// anything else is treated like a free-text message — kept unless it
/// mentions a deny-listed key, in which case it becomes `'[scrubbed]'`
/// (mirrors [_scrubMessage]). `null` passes through.
String? _scrubSpanDescription(String? description) {
  if (description == null) return null;
  for (final suffix in _spanDescriptionSuffixes) {
    if (description.endsWith(suffix)) {
      final rawRouteName =
          description.substring(0, description.length - suffix.length);
      return '${scrubRouteName(rawRouteName)}$suffix';
    }
  }
  return mentionsDenyListedKey(description) ? '[scrubbed]' : description;
}

/// KTD9: rebuilds one span's `data` under an allowlist, using the SDK's
/// real key names — `url` (truncated at `?`, then UUID-redacted via
/// [scrubUrl] — issue #640/LLA-082), `http.request.method`,
/// `http.response.status_code`, `http.response_content_length`,
/// `db.system`, `db.operation`. `http.query`/`http.fragment` and every
/// other key are dropped. Mutates [span.data] in place: `SentrySpan.data`'s
/// getter returns the live field, and mutating it directly is the only way
/// to change a span's data once the transaction has already finished (its
/// own `setData`/`removeData` methods no-op on a finished span).
///
/// Also scrubs `span.context.description` (through [_scrubSpanDescription])
/// and `span.tags` — both reach the wire alongside `data` and neither was
/// covered by the allowlist above: a span's `description` carries the raw
/// route name from the TTID/TTFD spans `SentryNavigatorObserver` produces,
/// and `tags` is a second free-form key/value map distinct from `data`,
/// subject to the same deny-list [_scrubTags] applies to an event's tags.
/// `span.tags`'s getter, like `span.data`'s, returns the live map, so it is
/// scrubbed the same way: in place.
void _scrubSpanDataInPlace(SentrySpan span) {
  final data = span.data;
  final url = data['url'];
  final allowed = <String, dynamic>{
    if (url is String) 'url': scrubUrl(url),
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

  span.context.description = _scrubSpanDescription(span.context.description);

  final tags = span.tags;
  final deniedTagKeys =
      tags.keys.where(isDenyListedKey).toList(growable: false);
  for (final key in deniedTagKeys) {
    tags.remove(key);
  }
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
  // One pass: a deny-listed hit drops the whole transaction regardless of
  // scan order, and nothing reads a span mutated before the drop is
  // detected — scrubTransaction returns null and the mutated object is
  // never read again — so checking and scrubbing each span together is
  // exactly as safe as two separate passes, and does half the iteration.
  for (final span in transaction.spans) {
    if (containsDenyListedKey(span.data)) return null;
    _scrubSpanDataInPlace(span);
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
  return transaction;
}

SentryRequest? _scrubRequest(SentryRequest? request) {
  if (request == null) return null;
  final url = request.url;
  return SentryRequest(
    url: url == null ? null : scrubUrl(url),
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

/// The drop decision for [scrubBreadcrumb], split out so that function
/// stays under the CRAP gate's complexity budget. True when the
/// breadcrumb's `data` carries a deny-listed *key* at any depth, or — issue
/// #520, since [containsDenyListedKey] inspects only keys — when a
/// non-navigation breadcrumb's data carries deny-listed content under an
/// innocuous key. Navigation data is exempt from the value scan:
/// [scrubNavigationData] rebuilds it entirely under a route-name allowlist,
/// so there is no free-text value left for this to find.
bool _breadcrumbDataMustDrop(String? category, Map<String, dynamic>? data) {
  if (containsDenyListedKey(data)) return true;
  return category != 'navigation' && _dataValuesMentionDenyListedKey(data);
}

/// Rebuilds an `http` breadcrumb's `data` with the URL cut at `?`, any
/// UUID-shaped path segment redacted ([scrubUrl] — issue #640/LLA-082), and
/// the query/fragment entries dropped, leaving every other entry as-is.
Map<String, dynamic> _scrubHttpBreadcrumbData(Map<String, dynamic> data) =>
    <String, dynamic>{
      for (final entry in data.entries)
        if (entry.key == 'url' && entry.value is String)
          entry.key: scrubUrl(entry.value as String)
        else if (entry.key != 'http.query' && entry.key != 'http.fragment')
          entry.key: entry.value,
    };

/// Applies the KTD12 breadcrumb rules. Returns null (drop) when the
/// breadcrumb's `data` carries a deny-listed key at any depth; otherwise a
/// new breadcrumb with navigation `data` rebuilt under an allowlist (U1;
/// KTD1/KTD2 — see [scrubNavigationData]), `http` URLs scrubbed via
/// [scrubUrl] (cut at `?`, UUID-shaped path segments redacted),
/// and `message` scrubbed via [_scrubBreadcrumbMessage] — raw
/// console/debugPrint text can itself carry health-log content or a DB
/// error with bound arguments, and this breadcrumb goes to the Sentry SDK
/// via `beforeBreadcrumb` regardless of what the local breadcrumb ring
/// keeps.
Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb) {
  if (breadcrumb == null) return null;
  final data = breadcrumb.data;
  final category = breadcrumb.category;
  if (_breadcrumbDataMustDrop(category, data)) return null;

  final Map<String, dynamic>? scrubbedData;
  if (category == 'navigation') {
    // Route names survive under an allowlist (KTD1/KTD2); arguments never
    // do, whatever shape they take — see scrubNavigationData.
    scrubbedData = scrubNavigationData(data);
  } else if ((category == 'http' || breadcrumb.type == 'http') &&
      data != null) {
    scrubbedData = _scrubHttpBreadcrumbData(data);
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
