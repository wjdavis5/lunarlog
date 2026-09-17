/// Cramp symptom prediction from historical tag entries (Issue #229, A2-10).
///
/// Builds directly on the symptom cycle-day distribution (Issue #135):
/// when the user has logged the `cramps` tag across at least [kMinCrampCycles]
/// (3 cycles) and cramps consistently cluster on specific cycle days,
/// projects anticipated cramp days for the upcoming cycle around
/// [ActivePrediction.estimatedNextStart].
///
/// **Constraints & Framing**:
/// - Conservative thresholding: do not predict from thin or scattered data.
/// - Mandatory non-diagnostic disclaimer: "Cramp estimates are based on your past
///   logged tags, not medical diagnosis. Timing may vary."
/// - Visually and semantically distinct from period and PMS bands.
library;

import '../models/local_date.dart';

/// Minimum distinct cycles with logged cramps required to generate a forecast.
const int kMinCrampCycles = 3;

/// Minimum frequency ratio across cycles with cramps to qualify a cycle day.
const double kCrampDayThresholdRatio = 0.4;

/// A statistical forecast of likely cramp days in the next cycle.
class CrampPrediction {
  const CrampPrediction({
    required this.predictedCycleDays,
    required this.predictedDates,
    required this.observedCycleCount,
    required this.totalCyclesAnalyzed,
    required this.disclaimer,
  });

  /// The cycle days (1-based or relative) when cramps most reliably occur.
  final List<int> predictedCycleDays;

  /// Concrete estimated calendar dates in the upcoming cycle.
  final List<LocalDate> predictedDates;

  /// Number of historical cycles in which cramps were observed.
  final int observedCycleCount;

  /// Total cycles evaluated.
  final int totalCyclesAnalyzed;

  /// Mandatory non-medical disclaimer.
  final String disclaimer;

  /// Standard disclaimer text accompanying every cramp forecast.
  static const String kStandardDisclaimer =
      'Cramp estimates are based on your past logged tags, not medical diagnosis. '
      'Individual cycle timing and physical sensations may naturally vary.';

  /// User-facing summary (e.g. "Likely on Cycle Days 1, 2").
  String get summaryText {
    if (predictedCycleDays.isEmpty) return 'No pattern identified';
    if (predictedCycleDays.length == 1) {
      return 'Likely on Cycle Day ${predictedCycleDays.first}';
    }
    return 'Likely on Cycle Days ${predictedCycleDays.join(', ')}';
  }
}
