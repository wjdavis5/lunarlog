/// The apply side of Supabase sync, split out of
/// `supabase_sync_engine.dart` (issue #435): the push-answer and
/// reconcile-page application lives here, while the sync loop, trigger
/// gating and transport coordination stay in [SupabaseSyncEngine].
///
/// * Push apply: recording per-row rejections, clearing `dirty` on accepted
///   rows (`markPushed`), storing the server's `resolved` copies, and
///   un-rejecting day entries whose profile was accepted alongside them.
/// * Reconcile apply: the single-page and per-row-fallback application of a
///   full-reconcile page, plus the page-maximum version helper both pull
///   paths advance their cursors with.
///
/// The incremental-pull page loop keeps its single `applyRemotePage` call
/// alongside its transport paging, checkpoint and cursor bookkeeping, and
/// the push path keeps its clock-offset persistence there for the same
/// reason; this class holds the push-result and reconcile-page storage
/// writes that used to sit inline in the loop.
///
/// The engine owns one [SupabaseSyncApply] (injected, defaulting to storage)
/// and delegates to it; the rejected-row map lives here, so the loop only
/// sees [pushable], [clearRejected] and [rejectedCount].
///
/// Nothing logged or emitted here carries health content: ids, counts,
/// phases and error *kinds* only (R18).
library;

import '../db/storage.dart';
import 'row_codec.dart';
import 'sync_transport.dart';

/// One pushable dirty row: its table, id, `local_rev` at read time and the
/// codec's JSON payload.
class SyncPushItem {
  const SyncPushItem(this.table, this.id, this.localRev, this.json,
      {this.profileId});

  final SyncTable table;
  final String id;
  final int localRev;
  final JsonRow json;

  /// The owning profile's id for a day-entry item; `null` for a profile
  /// item. Carried so [SupabaseSyncApply._unrejectEntriesOf] can filter
  /// the in-memory rejected map without a storage read (finding #2).
  final String? profileId;
}

/// Applies push answers and reconcile pages to local storage and tracks
/// server rejections.
///
/// Split out of `SupabaseSyncEngine` verbatim (issue #435) — same
/// sequencing, same conditions, no behavior change. The loop in
/// `supabase_sync_engine.dart` keeps the transport calls, cursors and
/// cycle orchestration; this class keeps the push-result and
/// reconcile-page storage writes the loop used to perform inline.
class SupabaseSyncApply {
  SupabaseSyncApply(this._storage);

  final LunarLogStorage _storage;

  /// Rows the server rejected: id → (`local_rev` at rejection, owning
  /// profile id — `null` for a profile row itself). A row is excluded from
  /// pushes while its `local_rev` still equals the rejected one; a later
  /// local write bumps it and the row is retried. The `profileId` lets
  /// [_unrejectEntriesOf] filter this map in memory when a profile is
  /// accepted, with no storage read (finding #2).
  final Map<String, ({int localRev, String? profileId})> _rejected = {};

  /// How many ids are currently held as rejected.
  int get rejectedCount => _rejected.length;

  /// Drops every held rejection (a fresh bind or a due full reconcile
  /// retries each previously-rejected row once the reconcile re-evaluates
  /// it).
  void clearRejected() => _rejected.clear();

  /// Dirty rows the server has not rejected at their current `local_rev`
  /// (a later local write bumps the rev and makes the row pushable again).
  Iterable<T> pushable<T>(
    List<T> rows,
    String Function(T) id,
    int Function(T) localRev,
  ) =>
      rows.where((row) => _rejected[id(row)]?.localRev != localRev(row));

  /// Records a transport-level rejection ([SyncTransportRejectedError]:
  /// no per-row results, so the named rows are rejected and the rest of
  /// the batch stays dirty for the next cycle).
  void markRejected(List<SyncPushItem> batch, List<String> rejectedIds) {
    final byId = {for (final i in batch) i.id: i};
    for (final id in rejectedIds) {
      final item = byId[id];
      if (item != null) {
        _rejected[id] = (localRev: item.localRev, profileId: item.profileId);
      }
    }
  }

  /// Stores one push batch's answer: rejected ids are held, every other
  /// item is cleared via `markPushed`, newly-accepted profiles un-reject
  /// their entries, and the server's `resolved` copies are applied with
  /// `dirty = false`.
  Future<void> applyPushResult(
      List<SyncPushItem> batch, PushResult result) async {
    final rejected = result.rejectedIds.toSet();
    final acceptedProfileIds = <String>{};
    for (final item in batch) {
      if (rejected.contains(item.id)) {
        _rejected[item.id] =
            (localRev: item.localRev, profileId: item.profileId);
        continue;
      }
      _rejected.remove(item.id);
      if (item.table == SyncTable.profiles) {
        acceptedProfileIds.add(item.id);
      }
      await _storage.markPushed(
          table: item.table, id: item.id, localRevAtPush: item.localRev);
    }
    if (acceptedProfileIds.isNotEmpty) {
      _unrejectEntriesOf(acceptedProfileIds, rejected);
    }
    if (result.resolved.isNotEmpty) {
      await _storage.applyResolved(result.resolved);
    }
  }

  /// A day entry rejected alongside its profile is un-rejected once that
  /// profile is accepted (and the entry itself wasn't [rejectedThisBatch]),
  /// so it is retried on the next push instead of waiting for its own
  /// local edit. Filters the in-memory [_rejected] map by the `profileId`
  /// carried on each rejected entry — no storage read (finding #2), so
  /// this stays bounded regardless of how large the dirty set is.
  void _unrejectEntriesOf(
    Set<String> acceptedProfileIds,
    Set<String> rejectedThisBatch,
  ) {
    final toUnreject = <String>[];
    for (final entry in _rejected.entries) {
      if (rejectedThisBatch.contains(entry.key)) continue;
      final profileId = entry.value.profileId;
      if (profileId != null && acceptedProfileIds.contains(profileId)) {
        toUnreject.add(entry.key);
      }
    }
    for (final id in toUnreject) {
      _rejected.remove(id);
    }
  }

  /// Applies a reconcile page in one transaction; when a row hits a
  /// retryable apply failure the page is re-applied row by row so every
  /// other row still lands (the per-row semantics of the single-row
  /// applies). Returns whether any row was left for the next cycle.
  /// The per-row fallback below is type-agnostic by construction:
  /// [LunarLogStorage.applyRemoteRows] with a single-element list is
  /// exactly each row type's single-row apply (one transaction, that one
  /// row, same LWW/retryable semantics -- see its per-type dispatch), so
  /// no switch is needed here and this method's branch count stays put
  /// as synced tables are added (Issue #188 added two more row types).
  Future<bool> applyReconcilePage(List<RemoteRow> page) async {
    try {
      await _storage.applyRemoteRows(page);
      return false;
    } on RetryableSyncApplyError {
      // Fall through to per-row application.
    }
    var retry = false;
    for (final row in page) {
      try {
        await _storage.applyRemoteRows([row]);
      } on RetryableSyncApplyError {
        retry = true;
      }
    }
    return retry;
  }

  /// The maximum `server_version` on [page], floored at [floor] — the
  /// cursor both pull paths advance to.
  int maxVersion(List<RemoteRow> page, int floor) {
    var v = floor;
    for (final row in page) {
      if (row.serverVersion > v) v = row.serverVersion;
    }
    return v;
  }
}
