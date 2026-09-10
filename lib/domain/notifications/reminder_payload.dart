/// The notification payload codec (Issue #136): what a scheduled reminder
/// carries, and how a tap or an action-button tap decodes back into an
/// intent.
///
/// Two payload shapes decode here:
///
/// * **Current (Issue #136):** a compact JSON object
///   `{"v":1,"p":"<profileId>","k":"<kind>","a":"<actionId>"}` — the kind
///   and the action id are optional. Actions always ride the same payload;
///   a plain notification tap decodes with `actionId == null`.
/// * **Legacy (pre-#136, still pending on a device when the app
///   updates):** the bare profile id string. Decodes with a null kind and
///   null action — exactly the old "route to the profile's overview"
///   behavior, so an upgrade never strands an already-scheduled reminder.
///
/// The payload carries only the profile id, the reminder kind, and the
/// action id — never a profile name, date, or any health detail (KTD7):
/// on Android the payload is not rendered, and on iOS the generic
/// `kReminderTitle`/`kReminderBody` are the only rendered strings.
library;

import 'dart:convert';

import 'package:lunarlog/domain/notifications/reminder_config.dart'
    show ReminderKind;

/// The notification action ids (Issue #136). These strings are the
/// `AndroidNotificationAction` ids and `DarwinNotificationAction`
/// identifiers the scheduler attaches, and come back verbatim in the
/// `NotificationResponse.actionId` of an action tap.
const String kReminderActionStarted = 'started';
const String kReminderActionSpotting = 'spotting';
const String kReminderActionNotYet = 'not_yet';

/// The button labels the actions render — generic words only (KTD7):
/// nothing here names a profile, a date, or any health detail. The exact
/// strings must match `kReminderActionIds`' order so the scheduler and
/// the executor agree on what a returned action id means.
const String kReminderActionStartedLabel = 'Started';
const String kReminderActionSpottingLabel = 'Spotting';
const String kReminderActionNotYetLabel = 'Not yet';

/// Every action id the app attaches, for the scheduler and tests.
const List<String> kReminderActionIds = [
  kReminderActionStarted,
  kReminderActionSpotting,
  kReminderActionNotYet,
];

/// A decoded notification tap: which profile it was for, which kind of
/// reminder fired (null for a legacy plain-payload tap), and which action
/// button was pressed (null for a plain tap on the notification body).
class ReminderLaunch {
  const ReminderLaunch({
    required this.profileId,
    this.kind,
    this.actionId,
  });

  final String profileId;
  final ReminderKind? kind;
  final String? actionId;

  /// Whether this tap pressed an action button (rather than the
  /// notification body itself).
  bool get isAction => actionId != null;

  @override
  bool operator ==(Object other) =>
      other is ReminderLaunch &&
      other.profileId == profileId &&
      other.kind == kind &&
      other.actionId == actionId;

  @override
  int get hashCode => Object.hash(profileId, kind, actionId);

  @override
  String toString() =>
      'ReminderLaunch($profileId, kind: $kind, actionId: $actionId)';
}

/// Encodes the payload a scheduled reminder carries. [kind] is always
/// known for a newly-scheduled reminder; the encoder never emits an empty
/// profile id.
String encodeReminderPayload({
  required String profileId,
  ReminderKind? kind,
}) {
  if (kind == null) return profileId;
  return jsonEncode({'v': 1, 'p': profileId, 'k': kind.name});
}

/// Decodes a tap's payload. Returns null when the payload is empty or a
/// JSON object without a usable profile id — a payload the app can't act
/// on is dropped, never guessed at. An unrecognised kind or action id
/// degrades to null (a plain tap) rather than throwing: a payload from a
/// newer app version must not crash an older one.
ReminderLaunch? decodeReminderLaunch(String? payload, {String? actionId}) {
  if (payload == null || payload.isEmpty) return null;
  if (!payload.startsWith('{')) {
    // A legacy (pre-#136) payload is exactly the profile id.
    return ReminderLaunch(profileId: payload);
  }
  final profileId = _jsonPayloadProfileId(payload);
  if (profileId == null) return null;
  return ReminderLaunch(
    profileId: profileId,
    kind: _jsonPayloadKind(payload),
    actionId: kReminderActionIds.contains(actionId) ? actionId : null,
  );
}

/// The `"p"` field of a JSON payload, or null when it is missing, empty,
/// or not a string.
String? _jsonPayloadProfileId(String payload) {
  final decoded = _decodePayloadJson(payload);
  if (decoded == null) return null;
  final p = decoded['p'];
  if (p is! String || p.isEmpty) return null;
  return p;
}

/// The `"k"` field as a [ReminderKind], or null when absent or
/// unrecognised (a kind from a newer app version).
ReminderKind? _jsonPayloadKind(String payload) {
  final decoded = _decodePayloadJson(payload);
  if (decoded == null) return null;
  final k = decoded['k'];
  if (k is! String) return null;
  for (final candidate in ReminderKind.values) {
    if (candidate.name == k) return candidate;
  }
  return null;
}

/// Parses a JSON payload object; null when it does not parse into a map.
Map<String, Object?>? _decodePayloadJson(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  return decoded;
}
