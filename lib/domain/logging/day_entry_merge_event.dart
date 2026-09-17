/// Domain model for a same-date merge disclosure (Issue #130): the record
/// that tells both guardians a merge on this date discarded a `flow` or
/// `note` value, and retains the losing value's text so its author can
/// recover it.
///
/// Rows are machine-written by whichever resolver witnessed the merge (the
/// server's, inside `sync_push`, or a client's, pushed back through
/// `p_merge_events`) — never user-composed content. The losing value text
/// is health content: it rides the device-credential gate with the rest of
/// the store, is length-bounded, never enters a notification payload, and
/// is deny-listed out of crash reports (`sentryDenyListedKeys`).
///
/// Pure Dart (R14/R16): no imports.
library;

/// Which value kind a discard lost. The closed set IS the feature: `tags`
/// merges are a set union and never discard anything, so no event may
/// claim them (AC).
enum DayEntryMergeEventField {
  flow,
  note;

  /// The server/wire string (`day_entry_merge_events.field`'s CHECK set).
  String toDb() => name;

  /// Parses the wire string; an unrecognised value (only possible from a
  /// broken writer — the server CHECKs the set) degrades to [note] rather
  /// than throwing, mirroring `row_codec.dart`'s decode-side normalisation.
  static DayEntryMergeEventField fromDb(String raw) =>
      raw == 'flow' ? DayEntryMergeEventField.flow : DayEntryMergeEventField.note;
}

/// One recorded same-date merge discard.
class DayEntryMergeEvent {
  const DayEntryMergeEvent({
    required this.id,
    required this.profileId,
    required this.localDateIso,
    required this.winningRowId,
    required this.losingRowId,
    required this.field,
    required this.losingValueText,
    this.losingAuthorUserId,
    this.winningAuthorUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Dedupe identity: the row's id. Dismissal is keyed on this, per device.
  final String id;

  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` the colliding entries were both for.
  final String localDateIso;

  final String winningRowId;
  final String losingRowId;
  final DayEntryMergeEventField field;

  /// The discarded value itself: the losing note's text, or the losing
  /// flow level's wire string (`heavy` etc.).
  final String losingValueText;

  /// Display attribution only (resolved to a name at render time, like
  /// `CaregiverAttributionBadge` resolves `logged_by_user_id`): whose
  /// value was discarded, and whose survived. Null for a legacy or
  /// unattributed row.
  final String? losingAuthorUserId;
  final String? winningAuthorUserId;

  /// The UTC instant the merge was recorded. Drives the 30-day recovery
  /// window (the client mirror of the server's retention purge).
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Record equality over every field (kept complexity-flat on purpose:
  /// a hand-written `&&` chain over eleven fields sits at the quality
  /// gate's complexity ceiling; a record compare is one decision).
  @override
  bool operator ==(Object other) =>
      other is DayEntryMergeEvent &&
      (id, profileId, localDateIso, winningRowId, losingRowId, field,
           losingValueText, losingAuthorUserId, winningAuthorUserId,
           createdAt, updatedAt) ==
      (other.id, other.profileId, other.localDateIso, other.winningRowId,
           other.losingRowId, other.field, other.losingValueText,
           other.losingAuthorUserId, other.winningAuthorUserId,
           other.createdAt, other.updatedAt);

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        localDateIso,
        winningRowId,
        losingRowId,
        field,
        losingValueText,
        losingAuthorUserId,
        winningAuthorUserId,
        createdAt,
        updatedAt,
      );
}
