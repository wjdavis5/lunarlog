/// Pure data shaping for the BBT chart (Issue #245): turns a profile's
/// logged BBT observations plus its derived cycle episodes into a
/// per-cycle series of (cycle day, temperature) points, so the chart can
/// plot BBT against cycle day with a cycle-day overlay letting several
/// cycles be compared on the same axis rather than sprawled across
/// calendar dates.
///
/// Pure Dart with no drift/Flutter/`dart:ui` imports (R14/R16) —
/// `test/architecture/layering_test.dart` enforces that; the geometry
/// fractions here are plain doubles, and the `Canvas`/`Offset` math that
/// turns them into pixels lives in the painter,
/// `lib/ui/insights/bbt_chart.dart`, mirroring `lib/ui/components/
/// cycle_wheel.dart`'s split between this file's pure fraction functions
/// and its own widget-side `CustomPainter`.
library;

import '../episodes/episodes.dart';
import '../models/local_date.dart';
import '../models/measurement_unit.dart';
import '../models/observation.dart';

/// One logged BBT reading, already resolved to a cycle day within its own
/// cycle and converted to Celsius (the canonical unit this file always
/// computes in — the painter converts to the profile's display unit only
/// at render time, the same read-time-only conversion rule
/// `measurement_unit.dart` documents).
class BbtPoint {
  const BbtPoint({
    required this.cycleDay,
    required this.celsius,
    required this.date,
  });

  /// 1-based day within the cycle this point belongs to (the cycle's own
  /// start date is cycle day 1).
  final int cycleDay;

  final double celsius;

  /// The civil date the reading was logged on — carried for tooltips/tests,
  /// not consulted by the geometry functions below.
  final LocalDate date;
}

/// One cycle's BBT points (Issue #245's overlay unit): [points] is sorted
/// by [BbtPoint.cycleDay] and may be empty (a cycle logged with no BBT
/// readings at all still gets a series here, simply an empty one — callers
/// that want "cycles with data" filter on [points.isNotEmpty]).
class BbtCycleSeries {
  const BbtCycleSeries({required this.cycleStart, required this.points});

  final LocalDate cycleStart;
  final List<BbtPoint> points;
}

/// The whole chart's derived data: one [BbtCycleSeries] per episode-derived
/// cycle (oldest first, matching [Episode]'s own natural sort), plus the
/// widest cycle-day reached by any point (the chart's x-axis extent).
class BbtChartData {
  const BbtChartData({required this.series, required this.maxCycleDay});

  final List<BbtCycleSeries> series;

  /// The largest [BbtPoint.cycleDay] across every series; 0 when
  /// [isEmpty].
  final int maxCycleDay;

  /// True when no cycle carries a single BBT point — the chart's honest
  /// empty state (issue #245 AC3) renders instead of an empty/broken axis.
  bool get isEmpty => series.every((s) => s.points.isEmpty);

  /// Every logged Celsius value across every series, for computing the
  /// chart's y-axis range ([bbtChartValueRange]).
  Iterable<double> get allCelsiusValues => [
        for (final s in series)
          for (final p in s.points) p.celsius,
      ];
}

/// Derives [BbtChartData] from a profile's already-live-filtered
/// [observations] and its cycle [episodes] (the same [Episode] derivation
/// `lib/domain/prediction/cycle_history.dart` and the Analysis tab already
/// use, via `deriveEpisodes(bleedDatesOf(entries))`) — so the chart's
/// cycle-day axis is the exact same cycle boundaries the rest of the app
/// shows.
///
/// Only live (`deletedAt == null`), non-[Observation.excluded]
/// (`excluded` is BBT's own per-point exclusion flag, A1-44 — a reading
/// the operator marked as not representative, e.g. taken after an
/// unusually late wake-up) `category: 'bbt'` rows with a non-null
/// [Observation.valueNum] are plotted. When a date carries more than one
/// live BBT row (a manual entry alongside a wearable/imported one, per the
/// same-date source discipline `20260914020000_numeric_measurement_units
/// .sql` documents), the most recently updated row wins — an arbitrary but
/// deterministic tiebreak, since plotting more than one value for the same
/// calendar date on a line chart would be a broken axis, not a feature.
///
/// A date outside every known cycle (older than the first episode's start
/// — defensively unreachable for a `bbt` row logged through this app,
/// since the day sheet's own day sheet only exists for days a profile
/// already has, but always possible for an imported BBT-only day with no
/// bleed of its own nearby) is silently dropped rather than plotted
/// against a cycle it does not belong to.
BbtChartData deriveBbtChartData({
  required List<Episode> episodes,
  required List<Observation> observations,
}) {
  final starts = ([...episodes]..sort()).map((e) => e.start).toList();
  if (starts.isEmpty) {
    return const BbtChartData(series: [], maxCycleDay: 0);
  }

  // Latest-updatedAt-wins per date (see doc comment): sort ascending so a
  // later map assignment for the same key overwrites an earlier one.
  final sortedRows = [...observations]
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  final celsiusByDate = <String, double>{};
  for (final o in sortedRows) {
    if (o.category != 'bbt' ||
        o.deletedAt != null ||
        o.excluded ||
        o.valueNum == null) {
      continue;
    }
    celsiusByDate[o.localDate.iso] = convertTemperature(
      o.valueNum!,
      from: BbtUnit.fromDb(o.unit),
      to: BbtUnit.celsius,
    );
  }

  final pointsByCycle = List.generate(starts.length, (_) => <BbtPoint>[]);
  var maxCycleDay = 0;
  for (final entry in celsiusByDate.entries) {
    final date = LocalDate.fromIso(entry.key);
    final cycleIndex = _cycleIndexFor(date, starts);
    if (cycleIndex == null) continue;
    final cycleDay = date.difference(starts[cycleIndex]) + 1;
    pointsByCycle[cycleIndex].add(
      BbtPoint(cycleDay: cycleDay, celsius: entry.value, date: date),
    );
    if (cycleDay > maxCycleDay) maxCycleDay = cycleDay;
  }

  final series = [
    for (var i = 0; i < starts.length; i++)
      BbtCycleSeries(
        cycleStart: starts[i],
        points: pointsByCycle[i]
          ..sort((a, b) => a.cycleDay.compareTo(b.cycleDay)),
      ),
  ];
  return BbtChartData(series: series, maxCycleDay: maxCycleDay);
}

/// The index of the last cycle-start in [sortedStarts] that is not after
/// [date] — i.e. the cycle [date] falls inside, given cycles run from one
/// start up to (but not including) the next. Null when [date] precedes
/// every known start.
int? _cycleIndexFor(LocalDate date, List<LocalDate> sortedStarts) {
  int? found;
  for (var i = 0; i < sortedStarts.length; i++) {
    if (!sortedStarts[i].isAfter(date)) {
      found = i;
    } else {
      break;
    }
  }
  return found;
}

/// Issue #245: the most recent [maxCycles] cycles carrying at least one
/// BBT point, most-recent-last (so a caller drawing oldest-to-newest paints
/// the current cycle's line on top). Caps the overlay's visual clutter the
/// same way `cycle_history.dart`'s `kAverageWindowCycles` caps the
/// statistics window, rather than overlaying a profile's entire logging
/// history on one axis.
List<BbtCycleSeries> bbtChartRecentSeries(
  BbtChartData data, {
  int maxCycles = 6,
}) {
  final withData = [
    for (final s in data.series)
      if (s.points.isNotEmpty) s,
  ];
  if (withData.length <= maxCycles) return withData;
  return withData.sublist(withData.length - maxCycles);
}

/// Vertical padding (Celsius) added above/below the plotted values' own
/// min/max so a point never sits flush against the chart's top/bottom edge
/// and a single value (a zero-width data range) still gets a sensible span
/// to plot inside.
const double kBbtChartPaddingCelsius = 0.3;

/// The y-axis range (Celsius) for [values] — the smallest span that fits
/// every value plus [kBbtChartPaddingCelsius] on each side. A fixed
/// mid-range default (with padding on each side) when [values] is empty,
/// so a caller can compute a range before checking emptiness without
/// dividing by zero.
(double min, double max) bbtChartValueRange(Iterable<double> values) {
  if (values.isEmpty) {
    return (36.0 - kBbtChartPaddingCelsius, 36.0 + kBbtChartPaddingCelsius);
  }
  var minV = double.infinity;
  var maxV = double.negativeInfinity;
  for (final v in values) {
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }
  return (minV - kBbtChartPaddingCelsius, maxV + kBbtChartPaddingCelsius);
}

/// Horizontal fraction (0-1) of the chart's plot width [cycleDay] falls at,
/// given the axis runs from cycle day 1 to [maxCycleDay]. [maxCycleDay] of
/// 1 or less places every point at the left edge (0.0) rather than
/// dividing by zero.
double bbtChartXFraction(int cycleDay, int maxCycleDay) {
  if (maxCycleDay <= 1) return 0.0;
  return (cycleDay - 1) / (maxCycleDay - 1);
}

/// Vertical fraction (0-1) of the chart's plot height [celsius] falls at,
/// given the axis runs from [minCelsius] to [maxCelsius] — 0.0 at the
/// range's low end, 1.0 at its high end (the painter, working in `Canvas`
/// coordinates where y grows downward, is what inverts this for drawing).
/// A degenerate (non-positive) range places every value at the midpoint
/// rather than dividing by zero.
double bbtChartYFraction(double celsius, double minCelsius, double maxCelsius) {
  final span = maxCelsius - minCelsius;
  if (span <= 0) return 0.5;
  return (celsius - minCelsius) / span;
}

/// Opacity for the cycle at [indexFromNewest] (0 = the most recent cycle
/// shown) among [totalShown] overlaid cycles (Issue #245's overlay) — full
/// opacity for the current cycle, fading toward 0.35 for the oldest shown,
/// so more recent cycles read as more prominent without any one older
/// cycle becoming invisible. [totalShown] of 1 always returns full opacity
/// (nothing to fade relative to).
double bbtChartCycleOpacity(int indexFromNewest, int totalShown) {
  if (totalShown <= 1) return 1.0;
  final fadeRange = 0.65;
  final step = fadeRange / (totalShown - 1);
  final opacity = 1.0 - (indexFromNewest * step);
  return opacity.clamp(1.0 - fadeRange, 1.0);
}
