/// A ring visualization of the current cycle (issue #209; B-29, A2-39):
/// an elapsed-days progress arc, the predicted-bleed band at the top of
/// the ring (the days a period is typically expected to run), today's
/// marker at the current day's angle, and a centre label ("Cycle day N"
/// or "Period · day N").
///
/// Pure geometry ([cycleWheelFraction]) and the screen-reader label
/// ([cycleWheelSemanticsLabel]) are top-level functions, unit-testable
/// without pumping a widget; [_CycleWheelPainter] itself stays a thin
/// [CustomPainter] whose `paint` only dispatches to per-layer helper
/// methods (CRAP gate: keeps `paint`'s own branching at zero).
///
/// Colours come from the theme rather than literals: the base ring and
/// elapsed arc use plain [ColorScheme] roles, and the predicted band uses
/// [LunarLogColors.predictedBand]/[predictedBorder] -- the same tokens the
/// calendar's own predicted-period cells are conceptually built from
/// (issue #176). A theme with no [LunarLogColors] extension (a bare
/// `ThemeData()` in an older test harness) falls back to plain
/// [ColorScheme] roles instead of throwing.
///
/// Vocabulary is date-based only (R13): no "fertile"/"ovulation" wording
/// anywhere in this file.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

import '../theme/lunarlog_colors.dart';

/// Fraction of a full lap around the wheel that [days] occupies within a
/// [cycleLengthDays]-day cycle. [cycleLengthDays] is floored at 1 day so a
/// (defensively unreachable, since a real prediction's mean cycle length
/// is always within the 15-60 valid window) zero or negative length never
/// divides by zero. The result is not itself clamped to one lap -- a day
/// count past the cycle length (an open, overdue cycle) yields a fraction
/// over 1; callers that need "how far around the ring" (never past one
/// full lap) clamp the day count themselves before calling this.
double cycleWheelFraction(int days, int cycleLengthDays) =>
    days / (cycleLengthDays > 0 ? cycleLengthDays : 1);

/// Whether the predicted-bleed band should render at all (issue #316
/// review item 8). When the caller's `meanPeriodLengthDays` rounds to 0
/// (an as-yet-unknown or degenerate bleed length) there is no defensible
/// band to draw -- a zero-sweep arc would be an invisible sliver, not an
/// honest "we don't know" signal -- so the ring simply omits the band
/// rather than drawing a meaningless one. Public and pure so the rule is
/// directly unit-testable without a `Canvas`.
bool cycleWheelShowsPredictedBand(int periodLengthDays) => periodLengthDays > 0;

/// Dash boundaries for the predicted band's border (issue #316 review item
/// 2): [LunarLogColors.predictedBand]'s own contract says it must stay
/// distinguishable without colour, paired with a dashed/hatched border --
/// a solid 2px ring in the same hue family fails that for a colour-blind or
/// grayscale view. Returns the sweep angle (radians) of each successive
/// dash covering `[0, sweep)`; the gap after each dash is left unpainted by
/// the caller rather than returned here. The final dash is shortened
/// (never omitted) when [sweep] does not divide evenly into whole dashes.
/// Pure geometry, no [Canvas] -- directly unit-testable.
List<double> predictedBandDashes(double sweep, double dashLen, double gapLen) {
  if (sweep <= 0 || dashLen <= 0) return const [];
  final dashes = <double>[];
  var covered = 0.0;
  while (covered < sweep) {
    final remaining = sweep - covered;
    dashes.add(remaining < dashLen ? remaining : dashLen);
    covered += dashLen + gapLen;
  }
  return dashes;
}

/// Screen-reader label for the whole wheel (R13: date-based vocabulary
/// only). Public so it is directly unit-testable without a `Semantics`
/// pump. #138: the phrases come from [AppLocalizations] (#340's rule),
/// same strings the centre label renders for `en`.
String cycleWheelSemanticsLabel({
  required int cycleDay,
  required bool duringEpisode,
  required int cycleLengthDays,
  required int periodLengthDays,
  required AppLocalizations l10n,
}) {
  final phase = duringEpisode
      ? l10n.cycleWheelPhasePeriodDay(cycleDay)
      : l10n.cycleWheelCenterCycleDay(cycleDay);
  return l10n.cycleWheelSemanticsBody(phase, cycleLengthDays, periodLengthDays);
}

class CycleWheel extends StatelessWidget {
  const CycleWheel({
    super.key,
    required this.cycleDay,
    required this.duringEpisode,
    required this.cycleLengthDays,
    required this.periodLengthDays,
    this.diameter = 200,
  });

  /// 1-based day of the current cycle (matches
  /// `ActivePrediction.cycleDay`).
  final int cycleDay;

  /// Whether today falls inside a logged bleed episode.
  final bool duringEpisode;

  /// The cycle's typical length in days -- the ring's full lap.
  final int cycleLengthDays;

  /// The typical bleed length in days -- the predicted band drawn from the
  /// top of the ring.
  final int periodLengthDays;

  final double diameter;

  String _centerLabel(AppLocalizations l10n) => duringEpisode
      ? l10n.cycleWheelCenterPeriodDay(cycleDay)
      : l10n.cycleWheelCenterCycleDay(cycleDay);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<LunarLogColors>();
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: cycleWheelSemanticsLabel(
        cycleDay: cycleDay,
        duringEpisode: duringEpisode,
        cycleLengthDays: cycleLengthDays,
        periodLengthDays: periodLengthDays,
        l10n: l10n,
      ),
      // The centre label `Text` below is purely visual duplication of this
      // node's own label -- without this, a screen reader would announce
      // the cycle day twice (once from this label, once from the child
      // Text's own auto-generated semantics).
      excludeSemantics: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _CycleWheelPainter(
            cycleDay: cycleDay,
            cycleLengthDays: cycleLengthDays,
            periodLengthDays: periodLengthDays,
            trackColor: theme.colorScheme.surfaceContainerHighest,
            progressColor: theme.colorScheme.primary,
            predictedBandColor:
                colors?.predictedBand ?? theme.colorScheme.primaryContainer,
            predictedBorderColor:
                colors?.predictedBorder ?? theme.colorScheme.primary,
            todayMarkerColor: theme.colorScheme.onSurface,
          ),
          child: Center(
            child: Text(
              _centerLabel(l10n),
              key: const ValueKey('cycle-wheel-center-label'),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CycleWheelPainter extends CustomPainter {
  const _CycleWheelPainter({
    required this.cycleDay,
    required this.cycleLengthDays,
    required this.periodLengthDays,
    required this.trackColor,
    required this.progressColor,
    required this.predictedBandColor,
    required this.predictedBorderColor,
    required this.todayMarkerColor,
  });

  final int cycleDay;
  final int cycleLengthDays;
  final int periodLengthDays;
  final Color trackColor;
  final Color progressColor;
  final Color predictedBandColor;
  final Color predictedBorderColor;
  final Color todayMarkerColor;

  static const double _strokeWidth = 16;
  static const double _startAngle = -math.pi / 2;

  double _sweepFor(int days) =>
      2 * math.pi * cycleWheelFraction(days, cycleLengthDays);

  /// [cycleDay] clamped to at most one full lap -- used by both the
  /// elapsed arc and today's marker so an overdue/open cycle (cycleDay
  /// past cycleLengthDays) still draws today's position at the top of the
  /// ring rather than wrapping past it.
  int get _elapsedDays =>
      cycleDay > cycleLengthDays ? cycleLengthDays : cycleDay;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    _paintTrack(canvas, center, radius);
    _paintPredictedBand(canvas, center, radius);
    _paintElapsedArc(canvas, center, radius);
    _paintTodayMarker(canvas, center, radius);
  }

  void _paintTrack(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
  }

  /// Issue #316 review item 8: `periodLengthDays` of 0 (a rounded-down
  /// `meanPeriodLengthDays`) skips the band entirely rather than drawing a
  /// zero-sweep arc nobody could see anyway -- see
  /// [cycleWheelShowsPredictedBand]'s own doc comment for why.
  void _paintPredictedBand(Canvas canvas, Offset center, double radius) {
    if (!cycleWheelShowsPredictedBand(periodLengthDays)) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = _sweepFor(periodLengthDays);
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..color = predictedBandColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
    _paintPredictedBandBorder(canvas, rect, sweep);
  }

  static const double _dashRadians = 0.12;
  static const double _gapRadians = 0.08;

  /// Issue #316 review item 2: the border is a dashed/segmented arc (see
  /// [predictedBandDashes]) rather than one solid stroke, so the predicted
  /// band stays distinguishable without colour -- the same requirement
  /// [LunarLogColors.predictedBand]'s own doc comment already states.
  void _paintPredictedBandBorder(Canvas canvas, Rect rect, double sweep) {
    final paint = Paint()
      ..color = predictedBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    var start = _startAngle;
    for (final dash
        in predictedBandDashes(sweep, _dashRadians, _gapRadians)) {
      canvas.drawArc(rect, start, dash, false, paint);
      start += dash + _gapRadians;
    }
  }

  void _paintElapsedArc(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepFor(_elapsedDays),
      false,
      Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth / 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintTodayMarker(Canvas canvas, Offset center, double radius) {
    final angle = _startAngle + _sweepFor(_elapsedDays);
    final markerCenter =
        center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(markerCenter, 6, Paint()..color = todayMarkerColor);
  }

  bool _sameGeometry(_CycleWheelPainter other) =>
      other.cycleDay == cycleDay &&
      other.cycleLengthDays == cycleLengthDays &&
      other.periodLengthDays == periodLengthDays;

  bool _sameColors(_CycleWheelPainter other) =>
      other.trackColor == trackColor &&
      other.progressColor == progressColor &&
      other.predictedBandColor == predictedBandColor &&
      other.predictedBorderColor == predictedBorderColor &&
      other.todayMarkerColor == todayMarkerColor;

  @override
  bool shouldRepaint(covariant _CycleWheelPainter oldDelegate) =>
      !_sameGeometry(oldDelegate) || !_sameColors(oldDelegate);
}
