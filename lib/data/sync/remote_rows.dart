/// Value types the storage sync API consumes: a remote (server) copy of a
/// profile or day entry, the table selector for per-table cursors, and the
/// retryable apply error.
///
/// U10's row codec maps Supabase JSON into these; U5's engine hands them to
/// `LunarLogStorage.applyRemote*`. They are deliberately plain: no JSON, no
/// drift, and every timestamp is already a parsed `DateTime` (KTD5 compares
/// instants, never strings). Tombstones are recognised by `deletedAt`; the
/// storage layer clears their payload on write regardless of what the
/// codec put in `note`, `tags` or `displayName`.
library;

import '../db/tables.dart';

/// The synced tables (per-table pull cursors, KTD2, Issue #8, Issue #240,
/// Issue #188, Issue #128).
enum SyncTable {
  profiles,
  dayEntries,
  profileGuardians,
  observations,
  profileModes,
  cycleOverrides,
  careNotes,
  visitPrepItems,
}

/// A server copy of a synced row.
sealed class RemoteRow {
  const RemoteRow();

  String get id;
  DateTime get updatedAt;
  DateTime? get deletedAt;
  SyncTable get table;

  /// The server-assigned `server_version` (KTD2): the pull cursor the
  /// engine advances to the page's maximum. `0` when unknown — a row built
  /// locally (tests) or decoded from a payload without the column.
  int get serverVersion;

  bool get isTombstone => deletedAt != null;
}

final class RemoteProfileRow extends RemoteRow {
  const RemoteProfileRow({
    required this.id,
    required this.displayName,
    required this.isMinor,
    required this.sortOrder,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.mode = 'standard',
    this.birthYear,
    this.relationship,
    this.transferredAt,
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
    this.trackingPreferences,
  });

  @override
  final String id;
  final String displayName;
  final bool isMinor;
  final int sortOrder;
  final DateTime? archivedAt;
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  /// Issue #131. The raw `toDb()` string. `row_codec.dart`'s `decodeProfile`
  /// already normalises an unrecognised or absent value to `standard`
  /// against the closed set before constructing this row (mode is
  /// presentation-only, non-null by default); `mappers.dart`'s
  /// `ProfileMode.fromDb` normalises again on the way to the domain model,
  /// so a row built directly (tests) with a raw, unvalidated string still
  /// degrades safely.
  final String mode;

  /// Issue #4 R1. Raw, undecoded: only `row_codec.dart`'s decode reads it
  /// off the wire; converting to a domain type happens in `mappers.dart`.
  final int? birthYear;

  /// Issue #4 R3. The raw `toDb()` string. `row_codec.dart`'s `decodeProfile`
  /// already normalises an unrecognised value to null against the closed
  /// set before constructing this row; `mappers.dart`'s
  /// `ProfileRelationship.fromDb` normalises again on the way to the
  /// domain model, so a row built directly (tests) with a raw, unvalidated
  /// string still degrades safely.
  final String? relationship;

  /// Issue #4 R5. Server-owned; pulled here but never pushed by
  /// `encodeProfile`.
  final DateTime? transferredAt;

  /// Issue #218: the onboarding cycle facts, raw and undecoded. The date
  /// is the `yyyy-MM-dd` wire string (same shape as
  /// `RemoteProfileModeRow.modeStartedOn`); `mappers.dart` parses it into
  /// a `LocalDate` on the way to the domain model. Pushed and pulled like
  /// any other profile column.
  final String? lastPeriodStart;
  final int? typicalCycleLengthDays;
  final int? typicalPeriodLengthDays;

  /// Issue #259: the profile's tracking-preferences document, raw and
  /// undecoded — the JSON text of the `{category: {enabled, sort_order}}`
  /// object (the wire carries a JSON object; `row_codec.dart` re-encodes
  /// it to text exactly like `observations.raw`). Null when the profile
  /// was never customized. Pulled and pushed (only when locally non-null)
  /// like any other profile column; parsing into the domain model happens
  /// in `mappers.dart`.
  final String? trackingPreferences;

  @override
  SyncTable get table => SyncTable.profiles;
}

final class RemoteDayEntryRow extends RemoteRow {
  const RemoteDayEntryRow({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.tz,
    required this.flow,
    required this.tags,
    required this.note,
    this.pms = false,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.loggedByUserId,
    this.lastModifiedByUserId,
    this.source = 'manual',
    this.sourceId,
    this.importId,
  });

  @override
  final String id;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd`.
  final String localDate;
  final String tz;
  final FlowLevel flow;
  final List<String> tags;
  final String? note;

  /// Issue #220: the first-class PMS marker, decoded to `false` when the
  /// key is absent (an old client's payload, or a pre-#220 server row).
  final bool pms;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  final String? loggedByUserId;
  final String? lastModifiedByUserId;

  /// Raw `source` string (Issue #159). Presentation/provenance only, never
  /// a security field — `mappers.dart`'s equivalent normalisation degrades
  /// an unrecognised value to `manual` on the way to any domain type.
  /// Never cleared on the server on a tombstone (see `sync_push`'s doc
  /// comment in `supabase/migrations/20260908170000_import_provenance.sql`).
  final String source;

  /// Import/device provenance key, for idempotent re-import. Never
  /// cleared on a tombstone.
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row. Never cleared on a
  /// tombstone.
  final String? importId;

  @override
  SyncTable get table => SyncTable.dayEntries;
}

final class RemoteProfileGuardianRow extends RemoteRow {
  const RemoteProfileGuardianRow({
    required this.id,
    required this.profileId,
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
    this.serverVersion = 0,
  });

  @override
  final String id;
  final String profileId;
  final String userId;
  final String role;
  final String status;
  final String? displayName;
  final String? invitedBy;
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt = null;
  @override
  final int serverVersion;

  @override
  SyncTable get table => SyncTable.profileGuardians;
}

final class RemoteObservationRow extends RemoteRow {
  const RemoteObservationRow({
    required this.id,
    required this.dayEntryId,
    required this.profileId,
    required this.localDate,
    this.observedAt,
    required this.tz,
    this.category,
    this.code,
    this.valueNum,
    this.valueText,
    this.unit,
    this.intensity,
    this.excluded = false,
    this.source = 'manual',
    this.sourceId,
    this.importId,
    this.raw,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  @override
  final String id;
  final String dayEntryId;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd`.
  final String localDate;
  final DateTime? observedAt;
  final String tz;

  /// Free text — never validated against a closed set (Issue #240 D-10
  /// companion note). Null on a tombstone (review finding: the server
  /// clears it there too, like every other payload column).
  final String? category;
  final String? code;
  final double? valueNum;
  final String? valueText;
  final String? unit;
  final int? intensity;
  final bool excluded;

  /// Raw `source` string. Presentation/provenance only, never a security
  /// field — `mappers.dart`-equivalent normalisation degrades an
  /// unrecognised value to `manual` on the way to any domain type, matching
  /// `mode`'s precedent.
  final String source;
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table). Never cleared
  /// on a tombstone (reverses #240's original source_id-clearing —see
  /// `sync_push`'s doc comment in
  /// `supabase/migrations/20260908170000_import_provenance.sql`).
  final String? importId;

  /// The original datapoint's JSON, undecoded (escape hatch, A1-45).
  final String? raw;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  final String? loggedByUserId;
  final String? lastModifiedByUserId;

  @override
  SyncTable get table => SyncTable.observations;
}

/// A server copy of a `profile_modes` row (Issue #188): the profile's
/// life-stage mode. Exactly one row per profile and no tombstone — the row
/// is created lazily on first write and dies with its profile, so
/// [deletedAt] is always null and [id] is the owning profile's id.
final class RemoteProfileModeRow extends RemoteRow {
  const RemoteProfileModeRow({
    required this.profileId,
    required this.mode,
    this.modeStartedOn,
    this.birthControlMethod,
    this.birthControlStartedOn,
    this.birthControlStoppedOn,
    this.healthSyncConsent = false,
    required this.updatedAt,
    this.serverVersion = 0,
  });

  /// The owning profile (also the server table's primary key).
  final String profileId;

  /// Raw `LifecycleMode` `toDb()` string (Issue #188 — NOT #131's care
  /// mode; the two axes are orthogonal and never merged).
  /// `row_codec.dart`'s `decodeProfileMode` already normalises an absent or
  /// unrecognised value to `tracking` against the closed set before
  /// constructing this row.
  final String mode;

  /// ISO calendar date `yyyy-MM-dd`, or null.
  final String? modeStartedOn;
  final String? birthControlMethod;
  final String? birthControlStartedOn;
  final String? birthControlStoppedOn;

  /// D-29: distinct per-profile health-platform sync consent.
  final bool healthSyncConsent;

  @override
  String get id => profileId;
  @override
  final DateTime updatedAt;
  @override
  DateTime? get deletedAt => null;
  @override
  final int serverVersion;

  @override
  SyncTable get table => SyncTable.profileModes;
}

/// A server copy of a `cycle_overrides` row (Issue #188): one manual
/// cycle-boundary correction. Tombstones (deletedAt set) carry no payload —
/// the server's `cycle_overrides_tombstone_payload_check` clears
/// `excludedFromAverage`/`manualStart`/`noteId`, keeping
/// `cycleStartDate`/`id`/`profileId`.
final class RemoteCycleOverrideRow extends RemoteRow {
  const RemoteCycleOverrideRow({
    required this.id,
    required this.profileId,
    required this.cycleStartDate,
    this.excludedFromAverage = false,
    this.manualStart = false,
    this.noteId,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
  });

  @override
  final String id;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` of the manual boundary.
  final String cycleStartDate;
  final bool excludedFromAverage;
  final bool manualStart;

  /// Placeholder id of a future notes-table row (#132).
  final String? noteId;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  @override
  SyncTable get table => SyncTable.cycleOverrides;
}

/// A server copy of a `care_notes` row (Issue #128): one standing,
/// non-date-bound note on a profile. Tombstones (deletedAt set) carry no
/// payload — the server's `care_notes_tombstone_payload_check` clears
/// `body`, keeping `id`/`profileId`.
final class RemoteCareNoteRow extends RemoteRow {
  const RemoteCareNoteRow({
    required this.id,
    required this.profileId,
    required this.body,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  @override
  final String id;
  final String profileId;

  /// Free-text standing note. Empty on a tombstone.
  final String body;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  final String? loggedByUserId;
  final String? lastModifiedByUserId;

  @override
  SyncTable get table => SyncTable.careNotes;
}

/// A server copy of a `visit_prep_items` row (Issue #128): one checklist
/// item on a profile's visit-prep list. Tombstones (deletedAt set) carry no
/// payload — the server's `visit_prep_items_tombstone_payload_check` clears
/// `body` and resets the check state, keeping `id`/`profileId`.
final class RemoteVisitPrepItemRow extends RemoteRow {
  const RemoteVisitPrepItemRow({
    required this.id,
    required this.profileId,
    required this.body,
    this.isChecked = false,
    this.checkedByUserId,
    this.checkedAt,
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  @override
  final String id;
  final String profileId;

  /// The item/question text. Empty on a tombstone.
  final String body;
  final bool isChecked;
  final String? checkedByUserId;
  final DateTime? checkedAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  final String? loggedByUserId;
  final String? lastModifiedByUserId;

  @override
  SyncTable get table => SyncTable.visitPrepItems;
}

/// Applying a remote row failed for a reason the next cycle can fix — today
/// only a day entry whose profile is not held locally yet (the profile page
/// is still in flight, or was rejected). The engine retries; it never treats
/// this as fatal or drops the row.
class RetryableSyncApplyError implements Exception {
  const RetryableSyncApplyError(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'RetryableSyncApplyError: $message${cause == null ? '' : ' ($cause)'}';
}
