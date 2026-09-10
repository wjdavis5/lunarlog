/// The debounced health-store write coordinator contract (Issue #193): the
/// seam the composition root holds and disposes, expressed in domain models
/// only.
///
/// The concrete implementation lives in
/// `lib/data/health/health_flow_write_coordinator.dart`; the root only ever
/// calls [start] and [dispose].
library;

abstract interface class HealthFlowWriteCoordinator {
  /// Subscribes to the health-store binding and the bound profile's entries.
  void start();

  /// Cancels every subscription and timer.
  Future<void> dispose();
}
