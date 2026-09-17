/// Domain model for Issue #170's `day_entry_history`: one machine-written,
/// content-free audit row per day-entry change — WHO changed an entry,
/// WHEN, WHICH column names changed, and the kind of change.
///
/// `changedFields` carries day_entries COLUMN NAMES only (enforced
/// server-side by `day_entry_history_changed_fields_check`): a consumer can
/// show *that* something changed and *who* did it without a competing store
/// recording *what* the values were. #124's shared activity feed is the
/// intended consumer; no feed UI ships in #170 itself.
library;

/// The kind of change one history row records (mirrors the server's
/// `change_kind` CHECK's closed set).
enum DayEntryChangeKind {
  /// The entry was created (a live row inserted).
  logged,

  /// Tracked content columns changed on a live row.
  updated,

  /// The entry was deleted (`deleted_at` set, payload cleared).
  tombstoned,

  /// A same-date merge discarded this row's value for one field (the
  /// losing row of the resolver's collision; `day_entry_merge_events`
  /// carries the recoverable text, this row only the field name).
  mergedDiscard;

  /// Parses the server's wire string, degrading an unrecognised value to
  /// [updated] (the generic kind) rather than failing a pull over display
  /// metadata — the same posture `row_codec.dart` takes for other
  /// closed-set display fields.
  static DayEntryChangeKind fromDb(String raw) => switch (raw) {
        'logged' => logged,
        'tombstoned' => tombstoned,
        'merged_discard' => mergedDiscard,
        _ => updated,
      };

  String toDb() => switch (this) {
        logged => 'logged',
        updated => 'updated',
        tombstoned => 'tombstoned',
        mergedDiscard => 'merged_discard',
      };
}

/// One change-history row (Issue #170). Immutable once written: rows are
/// server-trigger-written, pulled read-only, and removed only by the
/// server's 90-day retention purge and profile wipes (mirrored locally by
/// the read window and the wipe paths).
final class DayEntryHistoryChange {
  const DayEntryHistoryChange({
    required this.id,
    required this.entryId,
    required this.profileId,
    required this.changedByUserId,
    required this.changedAt,
    required this.kind,
    required this.changedFields,
  });

  final String id;

  /// The day entry the change happened to. NOT a foreign key locally: the
  /// local store's tombstone sweep may remove an old day-entry row while
  /// its (90-day) history is still inside the feed window, and the
  /// server's purge order guarantees the same rows outlive their entries
  /// only the other way around.
  final String entryId;

  final String profileId;

  /// Display attribution only (never a permission input).
  final String changedByUserId;

  final DateTime changedAt;
  final DayEntryChangeKind kind;

  /// day_entries COLUMN NAMES, never values — the table's whole contract.
  final List<String> changedFields;
}
