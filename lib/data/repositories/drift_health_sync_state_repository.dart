/// Drift-backed [HealthSyncStateRepository] (Issue #186) over the
/// device-local `health_sync_state` table — the concrete half of the
/// per-device/per-platform anchor contract. Deliberately never part of any
/// server sync path (`health_sync_state` is not in the `SyncTable` remote
/// set, so `sync_push`/`remote_rows.dart`/`row_codec.dart` cannot see it);
/// wired through `app_dependencies.dart`.
library;

import 'package:lunarlog/domain/health/health_sync_state_repository.dart';

import '../db/db.dart';
import '../db/storage.dart';

class DriftHealthSyncStateRepository implements HealthSyncStateRepository {
  DriftHealthSyncStateRepository(this.storage);

  final LunarLogStorage storage;

  @override
  Future<HealthSyncAnchor?> readAnchor(String platform) async {
    final row = await storage.readHealthSyncAnchor(platform);
    if (row == null) return null;
    return HealthSyncAnchor(
      platform: row.platform,
      anchor: row.anchor,
      lastSyncedAt: row.lastSyncedAt?.toUtc(),
    );
  }

  @override
  Future<void> writeAnchor(HealthSyncAnchor anchor) => storage
      .writeHealthSyncAnchor(HealthSyncStateRow(
        platform: anchor.platform,
        anchor: anchor.anchor,
        lastSyncedAt: anchor.lastSyncedAt?.toUtc(),
      ));
}
