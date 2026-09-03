/// Sync status UI state (U5, KTD6): a `ChangeNotifier` over the domain
/// [SyncEngine]'s snapshot stream, shaped like `AuthController` over its
/// service. Provided by `LunarLogApp` only when the root built an engine;
/// an unconfigured build provides nothing and shows no sync status.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

class SyncStatusController extends ChangeNotifier {
  SyncStatusController({required SyncEngine engine})
      : _engine = engine,
        _snapshot = engine.snapshot {
    _sub = engine.snapshots.listen(_onSnapshot);
  }

  final SyncEngine _engine;
  SyncSnapshot _snapshot;
  StreamSubscription<SyncSnapshot>? _sub;

  SyncSnapshot get snapshot => _snapshot;

  SyncPhase get phase => _snapshot.phase;

  /// "Sync now": coalesces while a cycle runs.
  void requestSync() => _engine.requestSync();

  /// Answers [SyncPhase.awaitingUploadConsent] (R14); a no-op otherwise.
  Future<void> confirmUpload() => _engine.confirmUpload();

  void _onSnapshot(SyncSnapshot next) {
    if (next == _snapshot) return;
    _snapshot = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
