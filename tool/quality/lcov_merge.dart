/// Merges the `lcov.info` files produced by sharded `flutter test --coverage`
/// runs (`--total-shards N --shard-index i`) into one record set the
/// coverage and CRAP gates can read as if a single run had produced it.
///
/// Each shard covers a disjoint subset of test *files*, so the same `lib/`
/// source appears in several shards' output with different per-line hit
/// counts. Merging is per (file, line): hit counts are summed, `LF` is the
/// number of instrumented lines, and `LH` the number with a non-zero sum —
/// the same two totals `flutter test --coverage` writes itself, so
/// `parseLcov` (see coverage_filter.dart) needs no knowledge of sharding.
///
/// Only the record kinds the gate's parser reads (`SF`, `DA`, `LF`, `LH`,
/// `end_of_record`) are emitted; `flutter test --coverage` writes no
/// function or branch records for this project, and the gate never reads
/// them.
library;

import 'coverage_filter.dart';

/// Merges several lcov documents into one. Files are emitted in sorted path
/// order and lines in ascending order, so the output is deterministic
/// regardless of shard order.
String mergeLcovContents(Iterable<String> contents) {
  final hitsByFile = <String, Map<int, int>>{};
  for (final content in contents) {
    for (final file in parseLcov(content).values) {
      final hits = hitsByFile.putIfAbsent(file.path, () => <int, int>{});
      for (final entry in file.daHits.entries) {
        hits.update(
          entry.key,
          (v) => v + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
  }

  final buffer = StringBuffer();
  final paths = hitsByFile.keys.toList()..sort();
  for (final path in paths) {
    final hits = hitsByFile[path]!;
    final lines = hits.keys.toList()..sort();
    buffer.writeln('SF:$path');
    var covered = 0;
    for (final line in lines) {
      final count = hits[line]!;
      if (count > 0) covered++;
      buffer.writeln('DA:$line,$count');
    }
    buffer.writeln('LF:${lines.length}');
    buffer.writeln('LH:$covered');
    buffer.writeln('end_of_record');
  }
  return buffer.toString();
}
