/// Bounded in-memory breadcrumb ring for feedback diagnostics (Issue #6,
/// U4; KTD9, R7, R8). Reduces every entry to a category and a name before
/// keeping it — never a `data` map — and applies the same token-wise
/// [mentionsDenyListedKey] deny-list check `scrub.dart` uses for Sentry
/// message text, so this file can never become a second, unscrubbed leak of
/// the same content Sentry's allowlist already keeps out. A whole-string
/// match alone would miss it: `sentry_flutter`'s `DebugPrintIntegration`
/// turns every `debugPrint()` call into a `console` breadcrumb carrying the
/// full printed string (which can embed a raw DB error or SQL with bound
/// arguments), and that string is never itself exactly one deny-listed key.
///
/// Entries are kept as already-formatted `"<category>: <name>"` strings
/// rather than a dedicated record type: `sentry_flutter` exports its own
/// `Breadcrumb` class, and a second same-named type in this library would
/// collide in any file importing both (as `sentry_bootstrap.dart` does).
library;

import 'package:lunarlog/observability/scrub.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Breadcrumb;

/// The label to feed [BreadcrumbLog.record] for [breadcrumb] (U1; KTD5).
///
/// `SentryNavigatorObserver` produces data-only breadcrumbs with a null
/// `message` — feeding `breadcrumb.message ?? ''` to the log would record
/// `navigation: ` with nothing after the colon. This derives a readable
/// label instead: the message when present, else the already-scrubbed `to`
/// route for a `navigation` breadcrumb (by the time this runs, [breadcrumb]
/// has already passed [scrubBreadcrumb], so `to` is a screen name or
/// `unknown`, never raw route data), else the empty string.
///
/// This is the only file under `lib/observability/` that imports
/// `sentry_flutter`'s [Breadcrumb] type — needed for exactly this parameter.
String breadcrumbLabel(Breadcrumb breadcrumb) {
  final message = breadcrumb.message;
  if (message != null && message.isNotEmpty) return message;
  if (breadcrumb.category == 'navigation') {
    final to = breadcrumb.data?['to'];
    if (to is String) return to;
  }
  return '';
}

/// Default capacity: at most this many recent breadcrumbs are kept, per R8.
const int kBreadcrumbLogCapacity = 25;

/// A fixed-capacity ring of recent breadcrumbs (R8). `record` drops an entry
/// whose category or name mentions a deny-listed key anywhere in its text
/// ([mentionsDenyListedKey], the same token-wise check `scrub.dart` enforces
/// on Sentry message text — not just an entry that *is* one) and evicts the
/// oldest entry once the ring is full.
class BreadcrumbLog {
  BreadcrumbLog({this.capacity = kBreadcrumbLogCapacity}) : assert(capacity > 0);

  final int capacity;
  final List<String> _entries = [];

  void record(String category, String name) {
    if (mentionsDenyListedKey(category) || mentionsDenyListedKey(name)) return;
    if (_entries.length >= capacity) {
      _entries.removeAt(0);
    }
    _entries.add('$category: $name');
  }

  /// Formatted lines, oldest first, as an unmodifiable snapshot: mutating
  /// the log afterward never changes an already-taken snapshot.
  List<String> snapshot() => List.unmodifiable(_entries);

  void clear() => _entries.clear();
}

/// The app-wide breadcrumb log. [configureSentryOptions] tees into this
/// instance by default when Sentry is configured; an unconfigured build
/// (or any other call site) records into it directly via [BreadcrumbLog.record].
final BreadcrumbLog defaultBreadcrumbLog = BreadcrumbLog();
