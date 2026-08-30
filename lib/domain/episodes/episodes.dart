/// Episode derivation: the pure function turning a profile's bleed dates
/// into maximal bleeding episodes (R8).
///
/// A bleed day is any entry whose flow is above none (spotting counts). An
/// episode is a maximal run of bleed dates where gaps of at most one
/// non-bleed day merge into the same episode; a two-day gap splits.
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';

/// A maximal run of bleed dates; [start] and [end] are inclusive.
class Episode implements Comparable<Episode> {
  Episode(this.start, this.end) {
    if (end.isBefore(start)) {
      throw ArgumentError.value(end, 'end', 'must not precede start');
    }
  }

  final LocalDate start;
  final LocalDate end;

  int get lengthDays => end.difference(start) + 1;

  bool contains(LocalDate date) =>
      !date.isBefore(start) && !date.isAfter(end);

  @override
  int compareTo(Episode other) => start.compareTo(other.start);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Episode && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Episode(${start.iso}..${end.iso}, $lengthDays days)';
}

/// The set of bleed dates among [entries]: non-tombstoned days with flow
/// above none. (Repository reads are already live-only; the deletedAt check
/// is defensive for full-fidelity inputs.)
Set<LocalDate> bleedDatesOf(Iterable<DayEntry> entries) => {
      for (final entry in entries)
        if (entry.deletedAt == null && entry.flow != FlowLevel.none)
          entry.localDate,
    };

/// Derives episodes from arbitrary bleed dates (input order irrelevant,
/// duplicates ignored). Consecutive dates at most 2 days apart (a one-day
/// gap) merge; 3 or more days apart start a new episode.
List<Episode> deriveEpisodes(Iterable<LocalDate> bleedDates) {
  final dates = bleedDates.toSet().toList()..sort();
  final episodes = <Episode>[];
  LocalDate? runStart;
  LocalDate? runEnd;
  for (final date in dates) {
    if (runEnd == null || date.difference(runEnd) > 2) {
      if (runEnd != null) {
        episodes.add(Episode(runStart!, runEnd));
      }
      runStart = date;
    }
    runEnd = date;
  }
  if (runEnd != null) {
    episodes.add(Episode(runStart!, runEnd));
  }
  return episodes;
}
