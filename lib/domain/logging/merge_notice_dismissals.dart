/// Device-local dismissal of same-date merge notices (Issue #130, AC:
/// "The notice is dismissible and does not reappear once dismissed on that
/// device").
///
/// Dismissal is deliberately LOCAL, never synced: one guardian dismissing a
/// notice must not erase the other guardian's (or even the same guardian's
/// other device's) notice — the server row stays until the 30-day
/// retention purge, and only this device stops showing it. Stored under an
/// `app_settings` key, exactly like #124's device-local activity-feed
/// markers, with the same bounded-list shape.
///
/// Pure Dart (R14/R16): `dart:convert` is the only import.
library;

import 'dart:convert';

/// The `app_settings` key holding [profileId]'s dismissed merge-event ids.
String mergeNoticeDismissalsKey(String profileId) =>
    'merge_notice_dismissed_$profileId';

/// Cap on stored dismissal ids per profile; the oldest are evicted on
/// append. The events themselves age out of the 30-day display window, so
/// a bounded list of ids can never resurrect a notice by eviction (an id
/// evicted from the list belongs to an event that has long stopped
/// rendering anyway).
const int kMergeNoticeDismissalCap = 200;

/// Decodes a stored settings value into dismissed event ids. Tolerant by
/// design: a null, empty, or corrupt value decodes to an empty list, and
/// non-string elements are skipped — a bad row can never wedge the day
/// sheet (the `merge_events.dart` decode precedent).
List<String> decodeMergeNoticeDismissals(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  final dynamic decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return [for (final element in decoded) if (element is String) element];
}

/// Encodes [ids] for storage.
String encodeMergeNoticeDismissals(List<String> ids) =>
    jsonEncode(List<String>.of(ids));

/// Appends [id]: a duplicate is a no-op (idempotent), and the list is
/// capped at [cap] with the oldest evicted. Returns a new list; the input
/// is untouched.
List<String> appendMergeNoticeDismissal(
  List<String> ids,
  String id, {
  int cap = kMergeNoticeDismissalCap,
}) {
  if (ids.contains(id)) return ids;
  final next = [...ids, id];
  return next.length > cap ? next.sublist(next.length - cap) : next;
}
