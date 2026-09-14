/// Per-profile "recently used tags" (Issue #234): a bounded,
/// most-recent-first list of taxonomy codes per profile, backing
/// [CategoryPicker]'s "Recent" row (`lib/ui/components/category_picker.dart`).
///
/// Persistence posture, same call as `reminder_config.dart`'s (device-local
/// scheduling preferences) and `merge_events.dart`'s (device-local activity
/// bookkeeping): recents are **device-local by design**, stored through the
/// device-local [SettingsStore] and never synced. They are a per-device
/// logging-UI convenience (what this operator, on this device, tends to
/// pick), not health data, and a co-guardian on another device does not
/// need to see the same shortlist.
///
/// Pure Dart (R14/R16): only `dart:convert`.
library;

import 'dart:convert';

/// How many recent codes are kept per profile; the oldest beyond this cap
/// is evicted on every append. Small by design — this is a shortlist, not
/// a history.
const int kTagRecentsCap = 8;

/// Returns [current] with [code] moved to the front (most-recent-first),
/// de-duplicated, and capped at [cap]. Pure: callers persist the result
/// themselves via [encodeTagRecents]/[TagRecentsStore].
List<String> withRecordedTagUse(
  List<String> current,
  String code, {
  int cap = kTagRecentsCap,
}) {
  final next = [code, for (final existing in current) if (existing != code) existing];
  return next.length > cap ? next.sublist(0, cap) : next;
}

/// Encodes the per-profile recents map (`profileId -> most-recent-first
/// codes`) as the JSON string the settings store keeps — the same
/// `{'v': 1, 'profiles': {...}}` shape `reminder_config.dart`'s
/// `encodeReminderConfigs` uses.
String encodeTagRecents(Map<String, List<String>> recents) => jsonEncode({
      'v': 1,
      'profiles': {
        for (final entry in recents.entries) entry.key: entry.value,
      },
    });

/// Decodes a stored `tag_recents` value. Anything malformed — not a map, an
/// unparseable string, a profile entry that isn't a list of strings —
/// degrades to an empty list for that profile (or an empty map for the
/// whole document) rather than throwing: a bad store value must never take
/// the day sheet down, only silently lose the "Recent" row's convenience.
Map<String, List<String>> decodeTagRecents(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  final profiles = decoded['profiles'];
  if (profiles is! Map<String, Object?>) return const {};
  return {
    for (final entry in profiles.entries)
      if (entry.value is List)
        entry.key: [
          for (final code in entry.value as List)
            if (code is String) code,
        ],
  };
}
