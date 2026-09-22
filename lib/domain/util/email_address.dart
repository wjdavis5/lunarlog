/// Minimal "does this look like an email address" guard shared by the
/// surfaces that hand a typed address to the auth or feedback service
/// (issue #1030). Pure Dart, so `lib/domain` stays free of Flutter.
///
/// Deliberately shallow: it catches an empty or obviously malformed entry
/// before a round trip, and leaves the server as the authority on whether
/// an address is deliverable. Callers trim the input first.
library;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Whether [value] plausibly looks like an email address: a non-empty local
/// part, one `@`, and a dotted domain with no whitespace.
bool looksLikeEmail(String value) => _emailPattern.hasMatch(value);
