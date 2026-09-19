/// Repository seam for a profile's per-guardian dated notes (Issue #801):
/// one attributed note per author per calendar day. Every method is scoped
/// to exactly one profile id (R3).
///
/// Distinct from [CareContentRepository] (Issue #128): a care note is
/// standing and non-date-bound; a guardian note is bound to a date AND to
/// its author. The two never merge and are never interchangeable.
library;

import '../models/guardian_note.dart';
import '../models/local_date.dart';

abstract interface class GuardianNotesRepository {
  /// The profile's live guardian notes, oldest write first.
  Future<List<GuardianNote>> listForProfile(String profileId);

  /// Live view of [listForProfile] for reactive UI.
  Stream<List<GuardianNote>> watchForProfile(String profileId);

  /// Live note authored by [authorUserId] for [profileId] on [localDate], or
  /// null when that author has not written one that day. The UI uses this to
  /// edit an existing note rather than mint a second one.
  Future<GuardianNote?> findOwnNoteForDate({
    required String profileId,
    required LocalDate localDate,
    required String? authorUserId,
  });

  /// Creates (no [id]) or revises ([id] set) the caller's own note for a
  /// date. One row per (author, profile, date): callers pass the existing
  /// note's [id] to edit it, or omit [id] to create. [loggedByUserId] is a
  /// local-only hint (the bound account) so an offline-authored note can be
  /// recognised as its author's before the server stamps it; the server
  /// remains authoritative and never accepts it from a payload.
  Future<GuardianNote> save({
    String? id,
    required String profileId,
    required LocalDate localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
  });

  /// Tombstones one of the caller's own notes (never a hard delete — the
  /// deletion syncs).
  Future<void> delete(String id);
}
