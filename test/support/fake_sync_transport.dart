/// Hand-written [SyncTransport] fake (KTD6, the `FakeGate` convention) for
/// U5's engine tests: records every push and pull call, serves scripted
/// pull pages per table, can answer pushes with scripted results, and can
/// throw *after* recording a call (AE6: the server accepted, the client
/// never heard back).
library;

import 'dart:async';

import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';

/// One recorded `pullPage` call.
typedef PullCall = ({SyncTable table, int afterVersion, int limit});

class FakeSyncTransport implements SyncTransport {
  FakeSyncTransport({DateTime Function()? serverClock})
      : serverClock = serverClock ?? (() => DateTime.now().toUtc());

  /// Stamps `serverNow` on default push results.
  DateTime Function() serverClock;

  /// Every [push] in order, recorded before any scripted throw.
  final pushes = <PushBatch>[];

  /// Every [pullPage] in order, recorded before any scripted throw.
  final pulls = <PullCall>[];

  /// Scripted push results consumed in order; when empty a push answers with
  /// no resolved rows, no rejections and `serverNow = serverClock()`.
  final pushResults = <PushResult>[];

  /// Scripted pull pages per table, consumed in order regardless of
  /// `afterVersion`; an exhausted table serves an empty page. Use
  /// [pageResolver] instead when the page must depend on the cursor.
  final pages = <SyncTable, List<List<RemoteRow>>>{
    SyncTable.profiles: [],
    SyncTable.dayEntries: [],
    SyncTable.profileGuardians: [],
    SyncTable.observations: [],
    SyncTable.profileModes: [],
    SyncTable.cycleOverrides: [],
    SyncTable.careNotes: [],
    SyncTable.visitPrepItems: [],
    SyncTable.dayEntryMergeEvents: [],
    SyncTable.deletedProfiles: [],
  };

  /// When set, wins over [pages]: computes each page from the call itself
  /// (out-of-order versions, cursor-dependent reconcile pages).
  List<RemoteRow> Function(SyncTable table, int afterVersion, int limit)?
      pageResolver;

  /// Thrown (once) by the next [push], after the batch is recorded.
  Object? nextPushError;

  /// Thrown (once) by the next [pullPage], after the call is recorded.
  Object? nextPullError;

  /// When set, thrown by every push / pull until cleared (persistent
  /// outage); [nextPushError] / [nextPullError] take precedence.
  Object? persistentError;

  /// Optional gate awaited inside every call *after* recording, so a test
  /// can hold a cycle mid-flight (lock during a pull, dispose mid-batch).
  Completer<void>? gate;

  /// Optional per-call hook, run after recording (e.g. to lock the gate
  /// during a specific page).
  FutureOr<void> Function(PullCall call)? onPull;
  FutureOr<void> Function(PushBatch batch)? onPush;

  /// Scripted answer for [fetchWatermark] (issue #521). Defaults to a very
  /// large sentinel — "every version committed so far is watermark-safe" —
  /// so every pre-existing pull test's exact `cursor = max(page)`
  /// expectations keep holding unless a test deliberately narrows this
  /// (to exercise the clamp) or sets it to `null` (to exercise the
  /// lookback fallback for a server without the RPC yet).
  int? watermark = 1 << 40;

  /// Every [fetchWatermark] call, recorded in order.
  int fetchWatermarkCount = 0;

  int get pushCount => pushes.length;
  int get pullCount => pulls.length;

  /// Queues [rows] as the next page for [table].
  void scriptPage(SyncTable table, List<RemoteRow> rows) =>
      pages[table]!.add(rows);

  /// Queues several pages for [table] in order.
  void scriptPages(SyncTable table, List<List<RemoteRow>> rowsPerPage) =>
      pages[table]!.addAll(rowsPerPage);

  /// Queues a result for the next push.
  void scriptPushResult({
    List<RemoteRow> resolved = const [],
    List<String> rejectedIds = const [],
    DateTime? serverNow,
  }) =>
      pushResults.add(PushResult(
        resolved: resolved,
        rejectedIds: rejectedIds,
        serverNow: serverNow ?? serverClock(),
      ));

  Future<void> _await() async {
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Future<PushResult> push(PushBatch batch) async {
    pushes.add(batch);
    await onPush?.call(batch);
    await _await();
    final once = nextPushError;
    if (once != null) {
      nextPushError = null;
      throw once;
    }
    final always = persistentError;
    if (always != null) throw always;
    if (pushResults.isNotEmpty) return pushResults.removeAt(0);
    return PushResult(
      resolved: const [],
      rejectedIds: const [],
      serverNow: serverClock(),
    );
  }

  @override
  Future<List<RemoteRow>> pullPage({
    required SyncTable table,
    required int afterVersion,
    required int limit,
  }) async {
    final call = (table: table, afterVersion: afterVersion, limit: limit);
    pulls.add(call);
    await onPull?.call(call);
    await _await();
    final once = nextPullError;
    if (once != null) {
      nextPullError = null;
      throw once;
    }
    final always = persistentError;
    if (always != null) throw always;
    final resolver = pageResolver;
    if (resolver != null) return resolver(table, afterVersion, limit);
    final queue = pages[table]!;
    if (queue.isEmpty) return const [];
    return queue.removeAt(0);
  }

  @override
  Future<int?> fetchWatermark() async {
    fetchWatermarkCount++;
    return watermark;
  }

  /// Every [primePullCycle] call, recorded in order (issue #598) so a test
  /// can assert the engine primed a cycle with the expected starting
  /// cursors. This fake never actually caches anything for [pullPage] to
  /// read back — [pages]/[pageResolver] remain the only way to script a
  /// page — so priming here is purely observable, matching how a real
  /// transport's priming is invisible to the engine either way.
  final primePullCycleCalls = <Map<SyncTable, int>>[];

  @override
  Future<void> primePullCycle(Map<SyncTable, int> cursors) async {
    primePullCycleCalls.add(Map.unmodifiable(cursors));
  }
}
