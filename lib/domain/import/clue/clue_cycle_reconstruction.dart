/// Reconstructs period episodes from a Clue datapoint stream (Issue #190).
///
/// Clue's export carries no cycle-boundary field at all (A1-41 — Read
/// Your Body, who ship a production Clue importer, confirm this and
/// reconstruct from bleeding patterns themselves), so episodes here are
/// derived purely from bleed-day runs, the same way this app already
/// derives them for its own manually-logged data
/// (`lib/domain/episodes/episodes.dart`).
///
/// Pure Dart, no drift/Flutter imports (R14/R16).
library;

import 'dart:collection';

import '../../episodes/episodes.dart';
import '../../models/local_date.dart';
import 'clue_datapoint.dart';

/// The bleed dates that count toward a Clue-reconstructed period episode.
/// Only [CluePeriodDatapoint]s at a real bleed level count —
/// [ClueFlowLevel.notBleeding] (the `period/none` assertion) is excluded,
/// and so is every non-period datapoint, spotting included: spotting is
/// never a [CluePeriodDatapoint] here (it lands in
/// `ClueObservationDatapoint(category: 'spotting')` instead — see
/// `clue_option_map.dart`), which alone is what makes a spotting-only run
/// derive zero episodes rather than a spurious period.
Set<LocalDate> cluePeriodBleedDatesOf(Iterable<ClueDatapoint> datapoints) => {
      for (final datapoint in datapoints)
        if (datapoint is CluePeriodDatapoint && datapoint.level.isBleed)
          datapoint.date,
    };

/// Derives period episodes from [datapoints] (Issue #190). Reuses
/// `lib/domain/episodes/episodes.dart`'s [deriveEpisodes] unchanged — its
/// existing "one skipped day tolerated; 3+ days apart splits" rule already
/// matches Clue's own reconstruction rule (one skipped day tolerated,
/// spotting-only runs rejected). The only thing this function adds is
/// excluding spotting from the bleed-date set before handing it off (see
/// [cluePeriodBleedDatesOf]); a run of only spotting days never enters
/// that set, so it never produces an [Episode] at all.
List<Episode> reconstructClueEpisodes(Iterable<ClueDatapoint> datapoints) =>
    deriveEpisodes(cluePeriodBleedDatesOf(datapoints));

/// Groups [datapoints] by [ClueDatapoint.date] (Issue #190 review — the
/// issue's "group by date" acceptance item, met by this module rather
/// than deferred to every caller). Each date's list preserves the input's
/// relative order; the returned map's keys iterate in date order (a
/// [SplayTreeMap], not an insertion-order [Map]) since [LocalDate] is
/// already [Comparable].
Map<LocalDate, List<ClueDatapoint>> groupClueDatapointsByDate(
  Iterable<ClueDatapoint> datapoints,
) {
  final grouped = SplayTreeMap<LocalDate, List<ClueDatapoint>>();
  for (final datapoint in datapoints) {
    grouped.putIfAbsent(datapoint.date, () => []).add(datapoint);
  }
  return grouped;
}

/// The same-day rule for period levels (Issue #190 review): when more
/// than one [CluePeriodDatapoint] lands on the same date (an export
/// artifact — Clue's UI only ever lets a user set one flow level per
/// day, but a merge/edit history in the export can still produce two
/// `period` rows for one date), the **highest bleed level wins**.
/// [ClueFlowLevel.notBleeding] never beats a bleed level, even if it
/// sorts first or last in [datapoints] — a stray `period/none` alongside
/// a real bleed entry for the same day must never erase that bleed.
/// Returns `null` for an empty list.
ClueFlowLevel? highestCluePeriodLevel(Iterable<CluePeriodDatapoint> list) {
  ClueFlowLevel? highest;
  for (final datapoint in list) {
    final level = datapoint.level;
    if (highest == null || level.index > highest.index) {
      highest = level;
    }
  }
  return highest;
}
