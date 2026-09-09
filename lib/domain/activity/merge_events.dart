/// Device-local record of same-date merge outcomes (issue #124, AC4).
///
/// A [MergeEvent] is written by `LunarLogStorage` at the exact moment one of
/// its apply paths resolves a same-date (or push-resolution) collision by
/// discarding one guardian's `flow` or `note` value in favour of another's.
/// The window in which a discard is knowable is that moment only — the
/// schema keeps no revision history — so it is captured then and there and
/// stored under an `app_settings` key, never synced.
///
/// Content discretion (issue #124): an event carries actor *ids*, the date,
/// and booleans saying which value *kinds* were discarded. It never carries
/// note text, tag codes, or flow levels — the feed row says "a note was
/// discarded", never what the note said.
///
/// Pure Dart (R14/R16): `dart:convert` is the only import.
library;

import 'dart:convert';

/// The `app_settings` key holding [profileId]'s bounded merge-event list.
String activityMergeEventsKey(String profileId) =>
    'activity_merge_events_$profileId';

/// The `app_settings` key holding the ISO instant this device last opened
/// [profileId]'s activity feed (issue #124 unread marker; device-local).
String activityLastSeenKey(String profileId) =>
    'activity_last_seen_$profileId';

/// Cap on stored events per profile; the oldest are evicted on append. The
/// value is a compromise between "the feed reaches back forever" and "one
/// settings row grows without bound" — a settings row is not a table.
const int kMergeEventCap = 200;

/// One recorded merge outcome.
class MergeEvent {
  const MergeEvent({
    required this.id,
    required this.profileId,
    required this.localDateIso,
    required this.occurredAt,
    this.winnerActorId,
    this.loserActorId,
    required this.discardedNote,
    required this.discardedFlow,
  });

  /// Dedupe identity: `<loser entry id>@<resolution stamp ISO>`. A replayed
  /// apply (the per-id rule lets a tied remote copy re-apply) recomputes the
  /// same id and [appendMergeEvent] skips it, so a resolution is recorded
  /// exactly once no matter how often it is re-delivered.
  final String id;

  /// The profile whose entry collided (also selects the settings key).
  final String profileId;

  /// ISO `yyyy-MM-dd` the colliding entries were both for.
  final String localDateIso;

  /// The winner's `updated_at` — when the resolution settled.
  final DateTime occurredAt;

  /// The user id whose values survived, or null when the winning copy is a
  /// legacy/unattributed row. Resolved to a display name at render time;
  /// never a name itself (guardian display names change).
  final String? winnerActorId;

  /// The user id whose `flow`/`note` was discarded, or null likewise.
  final String? loserActorId;

  /// Whether a note value was discarded (the loser's note differed from the
  /// winner's). Never the note's content.
  final bool discardedNote;

  /// Whether a flow level was discarded.
  final bool discardedFlow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MergeEvent &&
          other.id == id &&
          other.profileId == profileId &&
          other.localDateIso == localDateIso &&
          other.occurredAt == occurredAt &&
          other.winnerActorId == winnerActorId &&
          other.loserActorId == loserActorId &&
          other.discardedNote == discardedNote &&
          other.discardedFlow == discardedFlow;

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        localDateIso,
        occurredAt,
        winnerActorId,
        loserActorId,
        discardedNote,
        discardedFlow,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'profileId': profileId,
        'localDate': localDateIso,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'winner': winnerActorId,
        'loser': loserActorId,
        'note': discardedNote,
        'flow': discardedFlow,
      };

  /// Decodes one map, or null when it is malformed in any way — a corrupt
  /// element is dropped, never thrown, so a bad row can never wedge the
  /// sync apply or the feed.
  static MergeEvent? fromMap(Object? map) {
    if (map is! Map) return null;
    final id = _stringField(map['id']);
    final profileId = _stringField(map['profileId']);
    final localDate = _stringField(map['localDate']);
    final occurredRaw = _stringField(map['occurredAt']);
    final at = occurredRaw == null ? null : DateTime.tryParse(occurredRaw);
    if (id == null || profileId == null || localDate == null || at == null) {
      return null;
    }
    return MergeEvent(
      id: id,
      profileId: profileId,
      localDateIso: localDate,
      occurredAt: at,
      winnerActorId: _stringField(map['winner']),
      loserActorId: _stringField(map['loser']),
      discardedNote: map['note'] is bool && map['note'] as bool,
      discardedFlow: map['flow'] is bool && map['flow'] as bool,
    );
  }

  /// A String-typed field, or null for anything else.
  static String? _stringField(Object? value) => value is String ? value : null;
}

/// Decodes a stored settings value into events. Tolerant by design: a null,
/// empty, or corrupt value decodes to an empty list — the device-local
/// record degrades to "absent", it never breaks the feed or the apply that
/// reads it. Elements that fail [MergeEvent.fromMap] are skipped.
List<MergeEvent> decodeMergeEvents(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  final dynamic decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return [
    // Null-aware element: malformed entries decode to null and drop out.
    for (final element in decoded) ?MergeEvent.fromMap(element),
  ];
}

/// Encodes [events] for storage. Compact keys keep the bounded list small
/// (200 events × ~150 bytes ≈ 30 KB worst case for one settings row).
String encodeMergeEvents(List<MergeEvent> events) =>
    jsonEncode([for (final event in events) event.toMap()]);

/// Appends [event] to [events]: newest-first order, a duplicate [MergeEvent.id]
/// is a no-op (idempotent under replay), and the list is capped at [cap]
/// with the oldest evicted. Returns a new list; the input is untouched.
List<MergeEvent> appendMergeEvent(
  List<MergeEvent> events,
  MergeEvent event, {
  int cap = kMergeEventCap,
}) {
  if (events.any((existing) => existing.id == event.id)) return events;
  final next = [...events, event]
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return next.length > cap ? next.sublist(0, cap) : next;
}
