/// Splits a [SeedPayload] into `sync_push`-sized calls (issue #710).
///
/// `sync_push` caps each payload array at 500 rows and the combined total
/// at 3500 (`20260915200001_sync_push_tombstone_resurrection_guard.sql`).
/// This chunker walks the tables in dependency order — profiles, then day
/// entries, then observations, then the profile-scoped tables — one table
/// chunk per call, so a parent row is always stored before any of its
/// children reference it (observations validate `day_entry_id` against the
/// stored table; a call whose day entries ride an earlier call is safe, a
/// call pairing an observation with an unsent day entry is not).
library;

import 'payload_generator.dart';

/// The per-array cap mirrored from `sync_push`'s `c_max_rows`.
const int kSyncPushMaxRowsPerArray = 500;

/// The combined cap mirrored from `sync_push`'s `c_max_total_rows`.
const int kSyncPushMaxTotalRows = 3500;

/// One ready-to-send `sync_push` call: only non-empty arrays are carried
/// (the server defaults every omitted array to `'[]'::jsonb`).
class SyncPushBatch {
  const SyncPushBatch(this.tableName, this.params);

  /// Debug label for the carried table ('profiles', 'day_entries', ...).
  final String tableName;

  /// JSON body for `POST /rest/v1/rpc/sync_push`: a subset of the seven
  /// parameter keys, each mapped to its (<= 500 row) array.
  final Map<String, List<Map<String, Object?>>> params;

  /// Total rows across the carried arrays (always <= 500 by construction,
  /// far below the 3500 combined cap).
  int get totalRows =>
      params.values.map((a) => a.length).reduce((a, b) => a + b);
}

List<SyncPushBatch> _chunkTable(
  String paramName,
  List<Map<String, Object?>> rows,
) {
  final batches = <SyncPushBatch>[];
  for (var i = 0; i < rows.length; i += kSyncPushMaxRowsPerArray) {
    final end = (i + kSyncPushMaxRowsPerArray).clamp(0, rows.length);
    batches.add(SyncPushBatch(
      paramName,
      {paramName: rows.sublist(i, end)},
    ));
  }
  return batches;
}

/// Chunks [payload] in dependency order. Every batch respects both caps;
/// an assertion pins that at generation time (a violation is a tool bug,
/// never a server-side retry loop).
List<SyncPushBatch> chunkForSyncPush(SeedPayload payload) {
  final batches = <SyncPushBatch>[
    ..._chunkTable('p_profiles', payload.profiles),
    ..._chunkTable('p_day_entries', payload.dayEntries),
    ..._chunkTable('p_observations', payload.observations),
    ..._chunkTable('p_profile_modes', payload.profileModes),
    ..._chunkTable('p_cycle_overrides', payload.cycleOverrides),
    ..._chunkTable('p_care_notes', payload.careNotes),
    ..._chunkTable('p_visit_prep_items', payload.visitPrepItems),
  ];
  assert(
    batches.every((b) =>
        b.totalRows <= kSyncPushMaxTotalRows &&
        b.params.values.every((a) => a.length <= kSyncPushMaxRowsPerArray)),
    'chunker produced an oversized sync_push batch',
  );
  return batches;
}
