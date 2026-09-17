/// Symptom trends and recurring cycle-day patterns (Issue #135, A2-10).
///
/// Computes descriptive statistical distributions over historical [DayEntry]
/// tags and flow levels across completed cycles:
/// - Where in the cycle each frequently-logged tag typically occurs (cycle-day frequency).
/// - Trend direction across recent cycles (increasing, decreasing, stable).
/// - Bleed flow distributions across period days.
/// - Explicit minimum-observation thresholds ([kMinObservationCycles] = 3) to
///   loudly suppress noisy findings when data is thin.
///
/// **Constraints & Framing**:
/// - Descriptive statistics only: no causal inference, no medical diagnosis,
///   no individualized predictions beyond the standard cycle estimator.
/// - Every analytical rendering carries [kEstimateDisclaimer].
library;

import '../models/flow_level.dart';
import 'cramp_prediction.dart';

/// Minimum distinct cycles an observation must appear in before being reported
/// as a recurring pattern (honest thresholding).
const int kMinObservationCycles = 3;

/// Trend direction comparing the most recent cycles vs previous cycles.
enum TrendDirection {
  increasing,
  decreasing,
  stable,
  insufficientData;

  String get displayName => switch (this) {
        TrendDirection.increasing => 'Rising recently',
        TrendDirection.decreasing => 'Decreasing recently',
        TrendDirection.stable => 'Consistent',
        TrendDirection.insufficientData => 'Gathering data',
      };
}

/// A recurring pattern for a specific tracked tag.
class SymptomPattern {
  const SymptomPattern({
    required this.tag,
    required this.totalOccurrences,
    required this.cycleCount,
    required this.frequencyByCycleDay,
    required this.peakCycleDays,
    required this.trend,
    required this.meetsThreshold,
  });

  /// The tracked tag name (e.g. `cramps`, `headache`, `bloating`).
  final String tag;

  /// Total recorded occurrences across all analyzed cycles.
  final int totalOccurrences;

  /// Distinct cycles in which this tag was logged at least once.
  final int cycleCount;

  /// Distribution of occurrences indexed by cycle day (1-based).
  final Map<int, int> frequencyByCycleDay;

  /// Peak cycle days with the highest frequency of this symptom.
  final List<int> peakCycleDays;

  /// Direction of trend over recent cycles.
  final TrendDirection trend;

  /// Whether this pattern satisfies [kMinObservationCycles].
  final bool meetsThreshold;

  /// Short user-facing summary of peak timing (e.g. "Most common on Days 1–2").
  String get timingSummary {
    if (peakCycleDays.isEmpty) return 'Variable timing';
    if (peakCycleDays.length == 1) {
      return 'Most common on Cycle Day ${peakCycleDays.first}';
    }
    return 'Most common on Cycle Days ${peakCycleDays.join(', ')}';
  }
}

/// Observed distribution of flow intensity across period days.
class FlowPattern {
  const FlowPattern({
    required this.flowByCycleDay,
    required this.typicalPeakFlow,
    required this.typicalPeakDay,
  });

  /// Breakdown of flow level counts per bleed cycle day.
  final Map<int, Map<FlowLevel, int>> flowByCycleDay;

  /// The most common peak flow level recorded (e.g. [FlowLevel.heavy]).
  final FlowLevel typicalPeakFlow;

  /// The cycle day where peak flow most frequently occurs (e.g. Day 2).
  final int typicalPeakDay;
}

/// Comprehensive cycle insights report aggregating symptoms, flow, and cramp forecasts.
class CycleInsightsReport {
  const CycleInsightsReport({
    required this.symptomPatterns,
    required this.flowPattern,
    required this.crampPrediction,
    required this.analyzedCycleCount,
    required this.hasEnoughData,
  });

  /// Recurring symptom patterns meeting the observation threshold.
  final List<SymptomPattern> symptomPatterns;

  /// Flow distribution pattern across periods.
  final FlowPattern? flowPattern;

  /// Predicted cramp days for upcoming cycles (Issue #229).
  final CrampPrediction? crampPrediction;

  /// Total cycles included in the statistical analysis.
  final int analyzedCycleCount;

  /// Whether at least [kMinObservationCycles] were available for analysis.
  final bool hasEnoughData;

  /// Empty report returned when history is below threshold.
  static const CycleInsightsReport empty = CycleInsightsReport(
    symptomPatterns: [],
    flowPattern: null,
    crampPrediction: null,
    analyzedCycleCount: 0,
    hasEnoughData: false,
  );
}
