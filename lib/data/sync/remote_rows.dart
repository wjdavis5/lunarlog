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

/// The synced tables (per-table pull cursors, KTD2, Issue #8).
enum SyncTable { profiles, dayEntries, profileGuardians }

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
    required this.updatedAt,
    required this.deletedAt,
    this.serverVersion = 0,
    this.loggedByUserId,
    this.lastModifiedByUserId,
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
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final int serverVersion;

  final String? loggedByUserId;
  final String? lastModifiedByUserId;

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
