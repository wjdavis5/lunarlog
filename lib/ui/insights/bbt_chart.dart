/// The BBT chart (Issue #245): plots the BBT curve against cycle day, with
/// every recent cycle overlaid on the same axis so they can be visually
/// compared, instead of sprawled across calendar dates the way a plain
/// time-series chart would show them.
///
/// Data shaping ([BbtChartData], the per-cycle-day points, the value
/// range, and every pixel-fraction/opacity computation) is pure Dart in
/// `lib/domain/insights/bbt_chart.dart` (R14/R16) — this file only turns
/// those fractions into `Canvas` drawing, mirroring
/// `lib/ui/components/cycle_wheel.dart`'s split between its own pure
/// geometry functions and its widget-side [CustomPainter]. Per #135's own
/// design constraint (this chart's own issue #245 AC4): a simple drawn
/// [CustomPainter], no charting package added — `pubspec.yaml` has none,
/// and this issue does not introduce one either.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

import '../../domain/insights/bbt_chart.dart';
import '../../domain/models/measurement_unit.dart';
import '../components/empty_state.dart';
import '../theme/tokens.dart';

/// Renders [data] against cycle day; [displayUnit] governs only the
/// caption's temperature range text (every logged value is already
/// resolved to Celsius by [deriveBbtChartData] — converting for display
/// here keeps that read-time-only conversion rule consistent with
/// `measurement_unit.dart`'s own contract).
class BbtChart extends StatelessWidget {
  const BbtChart({
    super.key,
    required this.data,
    this.displayUnit = BbtUnit.celsius,
    this.maxCyclesShown = 6,
    this.height = 200,
  });

  final BbtChartData data;
  final BbtUnit displayUnit;

  /// Caps the cycle-overlay's visual clutter (issue #245's overlay) —
  /// forwarded to [bbtChartRecentSeries].
  final int maxCyclesShown;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (data.isEmpty) {
      return EmptyState(
        key: const ValueKey('bbt-chart-empty'),
        title: l10n.bbtChartEmptyTitle,
        body: l10n.bbtChartEmptyBody,
        crossAxisAlignment: CrossAxisAlignment.start,
      );
    }
    final theme = Theme.of(context);
    final recent = bbtChartRecentSeries(data, maxCycles: maxCyclesShown);
    final (minCelsius, maxCelsius) = bbtChartValueRange(data.allCelsiusValues);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey('bbt-chart'),
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _BbtChartPainter(
              series: recent,
              maxCycleDay: data.maxCycleDay,
              minCelsius: minCelsius,
              maxCelsius: maxCelsius,
              lineColor: theme.colorScheme.primary,
              gridColor: theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: LLSpace.space1),
        Text(
          _captionFor(l10n, recent.length, minCelsius, maxCelsius),
          key: const ValueKey('bbt-chart-caption'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _captionFor(
    AppLocalizations l10n,
    int cycleCount,
    double minCelsius,
    double maxCelsius,
  ) {
    final minDisplay = convertTemperature(
      minCelsius,
      from: BbtUnit.celsius,
      to: displayUnit,
    );
    final maxDisplay = convertTemperature(
      maxCelsius,
      from: BbtUnit.celsius,
      to: displayUnit,
    );
    final unit = displayUnit == BbtUnit.celsius ? '°C' : '°F';
    final range =
        '${minDisplay.toStringAsFixed(1)}$unit–${maxDisplay.toStringAsFixed(1)}$unit';
    return l10n.bbtChartCaption(cycleCount, range);
  }
}

/// Thin `Canvas`-drawing layer over the domain's pure fraction functions
/// (`bbtChartXFraction`/`bbtChartYFraction`/`bbtChartCycleOpacity`): `paint`
/// only dispatches to per-layer helper methods (mirrors
/// `_CycleWheelPainter`'s own CRAP-gate discipline — keeps `paint`'s own
/// branching at zero).
class _BbtChartPainter extends CustomPainter {
  const _BbtChartPainter({
    required this.series,
    required this.maxCycleDay,
    required this.minCelsius,
    required this.maxCelsius,
    required this.lineColor,
    required this.gridColor,
  });

  /// Oldest-first (matches [BbtChartData.series]'s own order) — painted in
  /// that order so the most recent (highest-opacity, thickest) cycle's
  /// line is drawn last and sits on top of any older, fainter one it
  /// crosses.
  final List<BbtCycleSeries> series;
  final int maxCycleDay;
  final double minCelsius;
  final double maxCelsius;
  final Color lineColor;
  final Color gridColor;

  static const int _gridLines = 4;
  static const double _currentCycleStrokeWidth = 2.5;
  static const double _olderCycleStrokeWidth = 1.5;
  static const double _currentCycleDotRadius = 3;
  static const double _olderCycleDotRadius = 2;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintSeries(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= _gridLines; i++) {
      final y = size.height * i / _gridLines;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintSeries(Canvas canvas, Size size) {
    final total = series.length;
    for (var i = 0; i < total; i++) {
      // series[i] is the i-th oldest of the ones shown; the newest is the
      // last element, so its distance from newest is (total - 1 - i).
      final indexFromNewest = total - 1 - i;
      _paintOneCycle(canvas, size, series[i], indexFromNewest, total);
    }
  }

  void _paintOneCycle(
    Canvas canvas,
    Size size,
    BbtCycleSeries cycle,
    int indexFromNewest,
    int totalShown,
  ) {
    final points = cycle.points;
    if (points.isEmpty) return;
    final opacity = bbtChartCycleOpacity(indexFromNewest, totalShown);
    final isCurrent = indexFromNewest == 0;
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCurrent ? _currentCycleStrokeWidth : _olderCycleStrokeWidth
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = _offsetFor(points[i], size);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(path, linePaint);
    final dotPaint = Paint()..color = lineColor.withValues(alpha: opacity);
    final dotRadius = isCurrent ? _currentCycleDotRadius : _olderCycleDotRadius;
    for (final point in points) {
      canvas.drawCircle(_offsetFor(point, size), dotRadius, dotPaint);
    }
  }

  /// Canvas y grows downward, so the fraction (0 at the range's low end, 1
  /// at its high end) is inverted here — the only place this painter
  /// converts the domain's axis-agnostic fraction into a screen position.
  Offset _offsetFor(BbtPoint point, Size size) {
    final xFraction = bbtChartXFraction(point.cycleDay, maxCycleDay);
    final yFraction = bbtChartYFraction(point.celsius, minCelsius, maxCelsius);
    return Offset(size.width * xFraction, size.height * (1 - yFraction));
  }

  @override
  bool shouldRepaint(covariant _BbtChartPainter oldDelegate) => true;
}
