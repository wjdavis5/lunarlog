/// The debounced health-store write coordinator contract (Issue #193): the
/// seam the composition root holds and disposes, expressed in domain models
/// only.
///
/// The concrete implementation lives in
/// `lib/data/health/health_flow_write_coordinator.dart`; the root only ever
/// calls [start], [onAppResumed], and [dispose].
library;

abstract interface class HealthFlowWriteCoordinator {
  /// Subscribes to the health-store binding and the bound profile's entries.
  void start();

  /// The app came back to the foreground (Issue #1478): schedules one
  /// debounced pass when a profile is bound, and does nothing otherwise.
  ///
  /// The OS health permission can change while the app is behind another
  /// screen — the person answers the health store's own permission sheet,
  /// or changes access in its settings — and a pass is otherwise triggered
  /// only by a change to the bound profile's days. Without this, a grant
  /// made that way is first noticed by the pass that the *next logged day*
  /// starts, which stamps the forward-only cursor after that day was saved
  /// and so never writes it.
  void onAppResumed();

  /// Cancels every subscription and timer.
  Future<void> dispose();
}
