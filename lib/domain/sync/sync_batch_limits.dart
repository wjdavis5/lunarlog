/// The per-table row cap the sync `push` RPC accepts, exposed so `lib/ui`
/// can display it without depending on `PushBatch` (R5).
///
/// The value mirrors `PushBatch.maxRows` in `lib/data/sync/sync_transport.dart`
/// (the RPC raises `22023` beyond it); it is a literal here so `lib/domain`
/// does not import `lib/data`.
library;

abstract final class SyncBatchLimits {
  /// The maximum number of rows one table may contribute to a single push
  /// batch.
  static const int maxRowsPerTable = 500;
}
