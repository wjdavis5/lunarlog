/// Parses `flutter test --coverage`'s `coverage/lcov.info` and applies
/// [excludedLibFilePaths] (plan U1).
///
/// `flutter test --coverage`'s lcov output carries only `SF`/`DA`/`LF`/`LH`
/// records — no `FN`/`FNDA` function records (verified empirically; see the
/// plan's KTD2). [FileCoverage.daHits] is exactly those `DA` records, which
/// `crap_gate.dart` intersects with `package:analyzer`'s method line ranges
/// to get per-method coverage.
///
/// The original design (KTD1) called for shelling out to the
/// `remove_from_coverage` pub package, but its pubspec caps the Dart SDK at
/// `<3.0.0`, which this project's Dart 3.13.2 doesn't satisfy — so the
/// (small) filtering logic it would have provided is implemented directly
/// here instead. Same result — a file matching [excludedLibFilePaths] is
/// dropped from the denominator — no subprocess, no incompatible
/// dependency.
library;

import 'dart:io';

import 'exclusions.dart';

/// One file's coverage from `lcov.info`: [daHits] maps each executable line
/// number to its hit count (0 = uncovered). [lf]/[lh] are lcov's own
/// "lines found"/"lines hit" totals for the file, kept alongside [daHits]
/// so callers don't have to recompute them.
class FileCoverage {
  FileCoverage(this.path, this.daHits, this.lf, this.lh);

  final String path;
  final Map<int, int> daHits;
  final int lf;
  final int lh;

  double get percent => lf == 0 ? 100.0 : lh / lf * 100.0;
}

/// Parses raw lcov content into per-file records, keyed by the file's
/// lcov `SF:` path exactly as written (OS-native separators).
Map<String, FileCoverage> parseLcov(String content) {
  final files = <String, FileCoverage>{};
  String? currentPath;
  Map<int, int>? currentHits;
  int currentLf = 0;
  int currentLh = 0;

  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      currentPath = line.substring(3);
      currentHits = {};
      currentLf = 0;
      currentLh = 0;
    } else if (line.startsWith('DA:') && currentHits != null) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        final lineNo = int.tryParse(parts[0]);
        final hitCount = int.tryParse(parts[1]);
        if (lineNo != null && hitCount != null) {
          currentHits[lineNo] = hitCount;
        }
      }
    } else if (line.startsWith('LF:')) {
      currentLf = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      currentLh = int.tryParse(line.substring(3)) ?? 0;
    } else if (line == 'end_of_record' && currentPath != null) {
      files[currentPath] = FileCoverage(
        currentPath,
        currentHits ?? const {},
        currentLf,
        currentLh,
      );
      currentPath = null;
      currentHits = null;
    }
  }
  return files;
}

/// Drops every file matching [excludedLibFilePaths] (KTD4/KTD6 — the single
/// exclusion list both gates share).
Map<String, FileCoverage> applyExclusions(Map<String, FileCoverage> files) {
  final filtered = <String, FileCoverage>{};
  for (final entry in files.entries) {
    if (!isExcluded(entry.key)) {
      filtered[entry.key] = entry.value;
    }
  }
  return filtered;
}

/// Reads [lcovFile], parses it, and applies [excludedLibFilePaths] — the one
/// entrypoint `coverage_gate.dart` and `crap_gate.dart` both call so a file
/// excluded from the coverage floor is excluded from CRAP too (KTD6).
Map<String, FileCoverage> filteredCoverageFromFile(File lcovFile) {
  final content = lcovFile.readAsStringSync();
  return applyExclusions(parseLcov(content));
}
