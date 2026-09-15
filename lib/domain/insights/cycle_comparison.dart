/// Pure data shaping for the side-by-side cycle comparison view (Issue
/// #235): aligns two of a profile's cycles on cycle day (day 1 of cycle A
/// directly above day 1 of cycle B, and so on) and carries each aligned
/// day's flow level and tags, plus a small set of compared statistics.
///
/// Reuses the exact same cycle derivation the rest of the Analysis tab
/// already relies on -- [Episode]/`deriveEpisodes(bleedDatesOf(entries))`
/// (`lib/domain/episodes/episodes.dart`) for cycle boundaries, the same
/// `cycle_overrides`-backed exclusion set `lib/domain/prediction/
/// cycle_history.dart`'s [CycleExclusionList] already exposes for "omit
/// from averages" -- rather than deriving cycles a second way. The
/// per-cycle-day alignment (cycle day = `date.difference(cycleStart) + 1`)
/// mirrors `lib/domain/insights/bbt_chart.dart`'s [BbtPoint.cycleDay]
/// exactly (issue #245), so a reader already familiar with that file's
/// axis will recognise this one.
///
/// Pure Dart, no drift/Flutter/`dart:ui` imports (R14/R16) --
/// `test/architecture/layering_test.dart` enforces that for every file
/// under `lib/domain/`.
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../prediction/prediction.dart' show kMaxCycleDays;

/// Minimum number of a profile's cycles before a comparison is meaningful
/// at all -- the UI's honest empty/not-enough-cycles state (issue #235 AC)
/// gates on this. Distinct from `prediction.dart`'s
/// `kMinCompletedValidCycles`: that floor is about a *reliable estimate*,
/// this one is simply "two cycles exist to compare".
const int kMinCyclesToCompare = 2;

/// One aligned day within a compared cycle.
class CycleComparisonDayRow {
  const CycleComparisonDayRow({
    required this.cycleDay,
    required this.date,
    required this.flow,
    required this.tags,
  });

  /// 1-based day within the cycle this row belongs to (the cycle's own
  /// start date is cycle day 1) -- the axis both sides align on.
  final int cycleDay;

  /// The civil date this row represents, carried for tooltips/tests, not
  /// consulted by the alignment itself.
  final LocalDate date;

  /// Null when [date] has no logged day entry at all -- distinct from an
  /// explicit [FlowLevel.none]/[FlowLevel.notBleeding] assertion, which are
  /// themselves logged facts.
  final FlowLevel? flow;

  /// Tag codes from the domain taxonomy (`lib/domain/tags.dart`); empty
  /// when [flow] is null (nothing logged) or the day simply carries none.
  final List<String> tags;
}

/// One side of a comparison: a single cycle's aligned day rows plus the
/// facts about it the header/stats row needs.
class CycleComparisonSide {
  const CycleComparisonSide({
    required this.cycleStart,
    required this.lengthDays,
    required this.excluded,
    required this.days,
  });

  /// The episode start this cycle begins on.
  final LocalDate cycleStart;

  /// Days from [cycleStart] to (but not past) the next cycle's start;
  /// null for the still-open cycle (mirrors
  /// `cycle_history.dart`'s [CycleHistoryItem.lengthDays]/`isOpen`).
  final int? lengthDays;

  /// Whether [cycleStart] is in the caller's exclusion set (issue #235 AC4:
  /// an excluded/omitted cycle is marked, not silently included) --
  /// sourced the same way `cycle_history.dart`'s [CycleHistoryItem.omitted]
  /// is, via `CycleExclusionList`.
  final bool excluded;

  /// Cycle day 1 through [days.length], oldest first.
  final List<CycleComparisonDayRow> days;

  bool get isOpen => lengthDays == null;

  /// Count of [days] whose logged flow is a real bleed day
  /// ([isBleed]) -- for the still-open cycle this is "so far", the same
  /// partial-count-is-still-meaningful posture [CycleHistoryItem] takes.
  int get bleedDayCount =>
      days.where((day) => day.flow != null && isBleed(day.flow!)).length;
}

/// The compared statistics between [CycleComparisonData.sideA] and
/// [CycleComparisonData.sideB] -- deliberately small (length and bleed-day
/// count) rather than re-deriving `cycle_history.dart`'s full averages,
/// which are already shown elsewhere on this screen; this is a two-cycle
/// delta, not a second averages engine.
class CycleComparisonStats {
  const CycleComparisonStats({
    required this.lengthDeltaDays,
    required this.bleedDayCountDelta,
  });

  /// Side B's [CycleComparisonSide.lengthDays] minus side A's; null
  /// whenever either side is still open, so a comparison never implies an
  /// ongoing cycle finished shorter or longer than a completed one.
  final int? lengthDeltaDays;

  /// Side B's [CycleComparisonSide.bleedDayCount] minus side A's --
  /// always computable, since an open cycle's bleed days so far still
  /// count.
  final int bleedDayCountDelta;
}

/// The whole comparison: two aligned sides, the widest cycle-day either
/// reaches (the shared axis length), and the compared statistics.
class CycleComparisonData {
  const CycleComparisonData({
    required this.sideA,
    required this.sideB,
    required this.maxCycleDay,
    required this.stats,
  });

  final CycleComparisonSide sideA;
  final CycleComparisonSide sideB;

  /// The larger of the two sides' [CycleComparisonSide.days] lengths --
  /// the shared axis both sides align against, mirroring
  /// [BbtChartData.maxCycleDay]'s role.
  final int maxCycleDay;

  final CycleComparisonStats stats;
}

/// Derives [CycleComparisonData] for [cycleAStart]/[cycleBStart] out of a
/// profile's [episodes] and [entries]. Null when either start is not one
/// of [episodes]' own starts (defensive -- every real caller selects a
/// start straight from the same cycle-history list this file's
/// derivation agrees with, so this is a floor against a stale selection,
/// e.g. a cycle merged or re-derived out from under an already-open
/// comparison screen, not an expected path).
CycleComparisonData? deriveCycleComparison({
  required List<Episode> episodes,
  required Iterable<DayEntry> entries,
  required LocalDate today,
  required LocalDate cycleAStart,
  required LocalDate cycleBStart,
  Set<LocalDate> excludedCycleStarts = const {},
}) {
  final starts = ([...episodes]..sort()).map((e) => e.start).toList();
  final indexA = starts.indexOf(cycleAStart);
  final indexB = starts.indexOf(cycleBStart);
  if (indexA == -1 || indexB == -1) return null;

  final entriesByDate = <String, DayEntry>{
    for (final entry in entries)
      if (entry.deletedAt == null) entry.localDate.iso: entry,
  };

  final sideA =
      _sideFor(indexA, starts, entriesByDate, today, excludedCycleStarts);
  final sideB =
      _sideFor(indexB, starts, entriesByDate, today, excludedCycleStarts);

  return CycleComparisonData(
    sideA: sideA,
    sideB: sideB,
    maxCycleDay:
        sideA.days.length > sideB.days.length ? sideA.days.length : sideB.days.length,
    stats: CycleComparisonStats(
      lengthDeltaDays: sideA.lengthDays == null || sideB.lengthDays == null
          ? null
          : sideB.lengthDays! - sideA.lengthDays!,
      bleedDayCountDelta: sideB.bleedDayCount - sideA.bleedDayCount,
    ),
  );
}

/// Convenience mirroring [deriveCycleComparison] over raw [entries]
/// (mirrors `cycle_history.dart`'s `deriveCycleHistoryFromEntries` and
/// `bbt_chart.dart`'s own episode-from-entries derivation).
CycleComparisonData? deriveCycleComparisonFromEntries({
  required Iterable<DayEntry> entries,
  required LocalDate today,
  required LocalDate cycleAStart,
  required LocalDate cycleBStart,
  Set<LocalDate> excludedCycleStarts = const {},
}) =>
    deriveCycleComparison(
      episodes: deriveEpisodes(bleedDatesOf(entries)),
      entries: entries,
      today: today,
      cycleAStart: cycleAStart,
      cycleBStart: cycleBStart,
      excludedCycleStarts: excludedCycleStarts,
    );

/// Builds one side's aligned day rows. A completed cycle's rows run
/// [start] through the day before the next cycle's start; the still-open
/// cycle (the newest start) runs through [today] instead. Both cases are
/// capped at [kMaxCycleDays] days out from [start] -- the same window
/// `cycle_history.dart` already treats as the outer bound of a *valid*
/// cycle length -- so neither a historical data-entry error spanning
/// years nor a very overdue open cycle grows this list without bound.
CycleComparisonSide _sideFor(
  int index,
  List<LocalDate> starts,
  Map<String, DayEntry> entriesByDate,
  LocalDate today,
  Set<LocalDate> excludedCycleStarts,
) {
  final start = starts[index];
  final isOpen = index == starts.length - 1;
  final naturalEnd = isOpen ? today : starts[index + 1].addDays(-1);
  final cappedEnd = start.addDays(kMaxCycleDays - 1);
  final end = naturalEnd.isAfter(cappedEnd) ? cappedEnd : naturalEnd;
  final lengthDays = isOpen ? null : end.difference(start) + 1;

  final days = <CycleComparisonDayRow>[
    for (var day = start; !day.isAfter(end); day = day.addDays(1))
      CycleComparisonDayRow(
        cycleDay: day.difference(start) + 1,
        date: day,
        flow: entriesByDate[day.iso]?.flow,
        tags: entriesByDate[day.iso]?.tags ?? const [],
      ),
  ];

  return CycleComparisonSide(
    cycleStart: start,
    lengthDays: lengthDays,
    excluded: excludedCycleStarts.contains(start),
    days: days,
  );
}
