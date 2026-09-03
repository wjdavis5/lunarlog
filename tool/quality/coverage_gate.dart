/// The 90% total-line-coverage floor (plan U2, R1/R4).
///
/// Pure function over [FileCoverage] — no `exit()` here, `quality_gate.dart`
/// owns the process exit code (plan U2 Approach #3), so this stays testable.
library;

import 'coverage_filter.dart';

const double coverageFloorPercent = 90.0;

class UncoveredFile {
  const UncoveredFile(this.path, this.percent, this.linesHit, this.linesFound);

  final String path;
  final double percent;
  final int linesHit;
  final int linesFound;
}

class CoverageGateResult {
  const CoverageGateResult({
    required this.passed,
    required this.totalPercent,
    required this.totalLinesHit,
    required this.totalLinesFound,
    required this.topUncovered,
  });

  final bool passed;
  final double totalPercent;
  final int totalLinesHit;
  final int totalLinesFound;

  /// Files below 100%, ascending by coverage percent, capped at
  /// [maxTopUncoveredReported].
  final List<UncoveredFile> topUncovered;
}

const int maxTopUncoveredReported = 10;

/// Evaluates the coverage floor over an already-[filteredCoverageFromFile]
/// map (KTD6 — both gates share one filtered pass).
CoverageGateResult evaluateCoverageGate(Map<String, FileCoverage> filtered) {
  var totalLf = 0;
  var totalLh = 0;
  final uncovered = <UncoveredFile>[];

  for (final file in filtered.values) {
    totalLf += file.lf;
    totalLh += file.lh;
    if (file.lf > 0 && file.lh < file.lf) {
      uncovered.add(UncoveredFile(file.path, file.percent, file.lh, file.lf));
    }
  }

  uncovered.sort((a, b) => a.percent.compareTo(b.percent));
  final topUncovered = uncovered.take(maxTopUncoveredReported).toList();

  final totalPercent = totalLf == 0 ? 100.0 : totalLh / totalLf * 100.0;

  return CoverageGateResult(
    passed: totalPercent >= coverageFloorPercent,
    totalPercent: totalPercent,
    totalLinesHit: totalLh,
    totalLinesFound: totalLf,
    topUncovered: topUncovered,
  );
}

/// Prints the report the gate always shows (R4: "print the measured
/// percentage and the top uncovered files" — printed unconditionally, not
/// only on failure, so a passing CI run still shows the number).
void printCoverageReport(CoverageGateResult result) {
  final status = result.passed ? 'PASS' : 'FAIL';
  // ignore: avoid_print
  print(
    '[coverage] $status: ${result.totalPercent.toStringAsFixed(2)}% '
    '(${result.totalLinesHit}/${result.totalLinesFound} lines) '
    '— floor is ${coverageFloorPercent.toStringAsFixed(0)}%',
  );
  if (result.topUncovered.isNotEmpty) {
    // ignore: avoid_print
    print('[coverage] top uncovered files:');
    for (final f in result.topUncovered) {
      // ignore: avoid_print
      print(
        '[coverage]   ${f.percent.toStringAsFixed(1)}%  '
        '(${f.linesHit}/${f.linesFound})  ${f.path}',
      );
    }
  }
}
