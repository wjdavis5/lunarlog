/// Bounded in-memory breadcrumb ring for feedback diagnostics (Issue #6,
/// U4; KTD9, R7, R8). Reduces every entry to a category and a name before
/// keeping it — never a `data` map — and applies the same
/// [isDenyListedKey] deny-list `scrub.dart` uses for Sentry, so this file
/// can never become a second, unscrubbed leak of the same content Sentry's
/// allowlist already keeps out.
///
/// Entries are kept as already-formatted `"<category>: <name>"` strings
/// rather than a dedicated record type: `sentry_flutter` exports its own
/// `Breadcrumb` class, and a second same-named type in this library would
/// collide in any file importing both (as `sentry_bootstrap.dart` does).
library;

import 'package:lunarlog/observability/scrub.dart';

/// Default capacity: at most this many recent breadcrumbs are kept, per R8.
const int kBreadcrumbLogCapacity = 25;

/// A fixed-capacity ring of recent breadcrumbs (R8). `record` drops an entry
/// whose category or name matches [isDenyListedKey] (the same allowlist
/// `scrub.dart` enforces for Sentry) and evicts the oldest entry once the
/// ring is full.
class BreadcrumbLog {
  BreadcrumbLog({this.capacity = kBreadcrumbLogCapacity}) : assert(capacity > 0);

  final int capacity;
  final List<String> _entries = [];

  void record(String category, String name) {
    if (isDenyListedKey(category) || isDenyListedKey(name)) return;
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
