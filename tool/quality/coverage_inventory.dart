/// LLA-106: a complete-source-inventory check that sits in front of both
/// gates (plan U2/U3's `evaluateCoverageGate`/`evaluateCrapGate`).
///
/// Both gates only ever look at files lcov *has* a record for -- a file
/// dropped from `coverage/lcov.info` entirely (never loaded by any test)
/// simply never shows up in the map either gate iterates, so it silently
/// drops out of both the coverage floor's denominator and the CRAP scan.
/// That is indistinguishable from "100% covered, nothing to report" to
/// either gate, which is the defect: absent evidence must never read as
/// passing evidence.
///
/// [missingCoverageEvidence] cross-references the real, non-excluded `lib/`
/// file inventory ([nonExcludedLibDartFiles] -- the same walk
/// `crap_gate.dart`/`mutation_gate.dart` already share, KTD6) against
/// `filtered`'s keys, and reports every file that (a) is absent from
/// `filtered` and (b) has at least one scoreable method
/// ([fileHasScoreableCode]) -- i.e. is not just a pure-interface/re-export
/// file that legitimately has nothing for lcov to record. That second
/// condition is the "distinguish unmeasured from nonexecutable" half of the
/// finding: a file with zero executable code needs no lcov record to begin
/// with, so its absence is not a gap.
///
/// `tool/quality_gate.dart`'s `main()` calls this before either gate runs
/// and hard-fails the whole run when it's non-empty -- an empty or
/// unreadable `lcov.info` (every non-trivial file is then "missing") fails
/// the same way a single removed `SF:` record does, satisfying "reject
/// empty evidence" without a separate special case.
library;

import 'dart:io';

import 'coverage_filter.dart';
import 'crap_gate.dart';
import 'exclusions.dart';

/// Every non-excluded `lib/` file with scoreable code that has no matching
/// entry in [filtered], sorted for stable, readable output. Empty means the
/// coverage evidence is complete relative to the real source inventory.
List<String> missingCoverageEvidence(
  Map<String, FileCoverage> filtered, {
  Directory? libDir,
}) {
  final knownPaths = {
    for (final key in filtered.keys) normalizeSourcePath(key),
  };

  final missing = <String>[];
  for (final libFile in nonExcludedLibDartFiles(libDir)) {
    if (knownPaths.contains(libFile.libRelativePath)) continue;
    if (fileHasScoreableCode(libFile.file)) {
      missing.add(libFile.libRelativePath);
    }
  }
  missing.sort();
  return missing;
}
