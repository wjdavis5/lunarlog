/// Hand-written [SyncEngine] fake (KTD6, the `FakeGate` convention) for
/// U6's account UI and `SyncStatusController` tests: a controllable
/// snapshot stream plus recorders for every call, so widget tests never
/// touch a transport or a database.
library;

import 'dart:async';

import 'package:lunarlog/domain/sync/sync_engine.dart';

class FakeSyncEngine implements SyncEngine {
  FakeSyncEngine({SyncSnapshot initial = SyncSnapshot.initial})
      : _snapshot = initial;

  final StreamController<SyncSnapshot> _snapshots =
      StreamController<SyncSnapshot>.broadcast();

  SyncSnapshot _snapshot;

  int startCalls = 0;
  int requestSyncCalls = 0;
  int confirmUploadCalls = 0;
  int disposeCalls = 0;

  /// When set, [confirmUpload] throws it once.
  Object? nextConfirmUploadError;

  /// Pushes [next] to subscribers and makes it the current [snapshot].
  void emit(SyncSnapshot next) {
    _snapshot = next;
    _snapshots.add(next);
  }

  /// Convenience: emits a copy of the current snapshot with [phase] (and
  /// optional fields) changed.
  void emitPhase(
    SyncPhase phase, {
    SyncErrorKind? lastError,
    int? dirtyCount,
    int? rejectedCount,
    DateTime? lastSyncAt,
    String? boundUserId,
  }) =>
      emit(_snapshot.copyWith(
        phase: phase,
        lastError: lastError,
        dirtyCount: dirtyCount,
        rejectedCount: rejectedCount,
        lastSyncAt: lastSyncAt,
        boundUserId: boundUserId,
      ));

  @override
  SyncSnapshot get snapshot => _snapshot;

  @override
  Stream<SyncSnapshot> get snapshots => _snapshots.stream;

  @override
  void start() {
    startCalls++;
  }

  int triggerFullReconcileCalls = 0;

  @override
  void triggerFullReconcile() {
    triggerFullReconcileCalls++;
    requestSync();
  }

  @override
  void requestSync() {
    requestSyncCalls++;
  }

  @override
  Future<void> confirmUpload() async {
    confirmUploadCalls++;
    final error = nextConfirmUploadError;
    if (error != null) {
      nextConfirmUploadError = null;
      throw error;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}
