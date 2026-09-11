/// Contract for writing and sharing CSV exports (Issue #469).
/// Pure Dart interface with no Flutter or path_provider dependencies.
library;

abstract interface class CsvExportWriter {
  /// Delivers [cyclesCsv] and [dailyLogCsv] named according to [exportedAt]
  /// to the platform delivery step.
  Future<void> exportAndShare({
    required String cyclesCsv,
    required String dailyLogCsv,
    required DateTime exportedAt,
  });
}
