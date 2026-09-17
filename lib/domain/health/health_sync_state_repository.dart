/// Device-local health-store sync anchors (Issue #186, sync mechanics) —
/// the domain contract behind the `health_sync_state` Drift table.
///
/// One row per OS health platform (`healthkit` / `health_connect`), holding
/// the platform's opaque change anchor (Health Connect's `getChangesToken`
/// token, or HealthKit's anchor UUID / last-read instant as a string) and
/// the instant it was last persisted. **Deliberately never synced to the
/// server** — anchors are device-specific and the platform stores are local
/// (never server state), exactly the rationale `sync_state`'s cursor columns
/// document for lunarlog's own sync. The whole local database belongs to at
/// most one account, so the anchor is a device-level fact, not a per-profile
/// one.
///
/// Pure Dart (R14/R16): the drift-backed implementation lives in
/// `lib/data/repositories/`, wired through `app_dependencies.dart`.
library;

/// One persisted anchor for one health platform.
class HealthSyncAnchor {
  const HealthSyncAnchor({
    required this.platform,
    this.anchor,
    this.lastSyncedAt,
  });

  /// `healthkit` | `health_connect`.
  final String platform;

  /// The platform's opaque change anchor. Null before the first successful
  /// read; clearing it signals "no anchor — do a full time-range read" (the
  /// `ChangesTokenExpiredException` fallback of issue #186).
  final String? anchor;

  /// The UTC instant this anchor was last persisted at.
  final DateTime? lastSyncedAt;
}

/// The read/write port for device-local health-store anchors.
abstract interface class HealthSyncStateRepository {
  /// The stored anchor for [platform], or null when never read/written.
  Future<HealthSyncAnchor?> readAnchor(String platform);

  /// Upserts the anchor row for [platform] (created lazily on first write).
  Future<void> writeAnchor(HealthSyncAnchor anchor);
}
