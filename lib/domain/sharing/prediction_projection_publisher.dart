/// Contract for the background publisher that keeps the server's
/// prediction-projection snapshot in step with the profiles an account
/// shares predictions for (Issue #151; R4).
///
/// The UI needs to start, nudge, and dispose the publisher but must not
/// depend on the concrete implementation in `lib/data/sharing/`; the
/// contract speaks only in primitives.
library;

abstract interface class PredictionProjectionPublisher {
  /// How long a prediction change is debounced before publishing.
  Duration get debounce;

  /// How long a failed publish of an otherwise-unchanged prediction waits
  /// before retrying.
  Duration get retryDelay;

  /// Begins observing the active-profiles and prediction streams.
  void start();

  /// Publishes [profileId]'s current prediction right away.
  Future<void> publishNow(String profileId);

  /// Publishes the current prediction for every profile the account shares
  /// out, right away.
  Future<void> republishConnected();

  /// Stops observing and cancels every outstanding timer/subscription.
  Future<void> dispose();
}
