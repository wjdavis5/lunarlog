/// Month calendar for one profile's day entries (U5, R8/R10; issue #133
/// R1/R2/R3): month navigation with today's month as default, bleed-day
/// markers (flow above none), a small secondary dot for symptom-only days
/// (tags/note without a bleed), and — new in #133 — twelve months of
/// forward navigation with predicted bleed bands (hatched, never filled),
/// cycle-day numerals on the first predicted cycle only, PMS/cramps badges
/// at fixed offsets off the active estimate, up to three symptom layers
/// (defaulting to the profile's most-used tags), a read-only explainer for
/// future cells, and a keep-logging strip when no estimate is active.
///
/// The future-logging lock is deliberate and stays (KTD8): future cells
/// never open the log sheet — tapping one opens the explainer. Predicted
/// and logged days are distinguishable semantically (Semantics labels),
/// not just visually, in both themes (#133 brief / #138 groundwork).
///
/// Active-profile scoping (R3): the calendar operates on exactly one
/// profile id and one repository stream; no drift types cross here.
///
/// Issue #191 (B-2, B-11): a logged bleed day's fill is now graded by
/// [FlowLevel] with the #176 `flow*` ramp tokens (light/medium/heavy
/// climbing the ramp's saturation; issue #247's `superHeavy` reuses
/// `heavy`'s tone), plus a non-colour dot-count channel so the same
/// distinction survives without colour. Issue #247: spotting is no
/// longer a flow level (it is an `observations` category row, and a
/// stored legacy `flow = 'spotting'` row reads back as the explicit
/// `notBleeding` assertion) — it no longer renders here at all, so the
/// ring-plus-centre-dot spotting treatment this comment used to describe
/// is gone along with it. A legend strip keys every mark the grid can
/// show; the month
/// grid is a swipeable [PageView] (the chevrons drive the same
/// controller); a "Today" header action jumps to and highlights the
/// current month; and tapping the month label opens a month/year picker
/// sheet bounded by the same forward limit the chevron already enforced.
///
/// Issue #143: a dashed (never hatched) fertile-window ring renders ahead
/// of each forecasted period band, keyed by the legend's "Estimated
/// fertile days" entry — gated, like every other prediction number, by
/// [CareModeCopy.showsFertileWindow] (`_MonthCalendarState._cellForMode`).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/symptoms/symptom_layers.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart'
    show kEstimateDisclaimer, kFertileWindowDisclaimer;
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

/// The weekday the month grid's weeks start on, as a `DateTime` weekday
/// constant (`DateTime.monday` .. `DateTime.sunday`). Explicit seam
/// (issue #160): the grid previously baked Sunday-start into
/// `DateTime.weekday % 7` arithmetic. The value stays Sunday to preserve
/// today's layout; deriving a default from the active locale and persisting
/// a user override in Settings are tracked follow-on work — both consumers
/// of this seam ([leadingBlanksFor] and [weekdayHeaderLabels]) already
/// honour it.
const int kFirstDayOfWeek = DateTime.sunday;

/// Leading blank cells before day 1 of [year]/[month] in a grid whose weeks
/// start on [firstDayOfWeek] (a `DateTime` weekday constant).
/// `DateTime.weekday` is 1=Monday..7=Sunday; Dart's `%` keeps the result
/// non-negative for a positive divisor, so `(weekday - firstDay) % 7` is
/// correct for every seam value. Public and pure for direct testing, the
/// same discipline as [dayCellSemanticLabel] below.
int leadingBlanksFor(
  int year,
  int month, {
  int firstDayOfWeek = kFirstDayOfWeek,
}) => (DateTime(year, month, 1).weekday - firstDayOfWeek) % 7;

/// The weekday header's single-letter initials, ordered for a grid whose
/// weeks start on [firstDayOfWeek] — the first initial is that day's.
/// [dates.narrowWeekdayInitials] is locale-derived and Sunday-first, so a
/// Sunday start is the identity ordering (the old `kWeekdayLabels` list).
/// Public and pure for direct testing.
List<String> weekdayHeaderLabels({
  String locale = dates.kFallbackLocale,
  int firstDayOfWeek = kFirstDayOfWeek,
}) {
  final narrow = dates.narrowWeekdayInitials(locale: locale);
  return [for (var i = 0; i < 7; i++) narrow[(firstDayOfWeek + i) % 7]];
}

/// Forward navigation may move at most this many months past the current
/// one (R1); [kForecastHorizonMonths] in the forecast module covers it.
const int kForwardMonthLimit = kForecastHorizonMonths;

/// The entries stream's subscription window (issue #197, performance): the
/// displayed month plus this many days behind and ahead, instead of the
/// profile's full history. 45 days each way was chosen over a plain
/// calendar-month margin because it comfortably covers episode-continuity
/// rendering across a month boundary (the longest realistic cycle length
/// plus a multi-day bleed can straddle two months) and the forecast bands'
/// fixed PMS/cramps badge offsets near the edges of the displayed month —
/// see [_MonthCalendarState._maybeRewatchEntriesFor] for when the
/// subscription actually moves. Public so a widget test can assert against
/// the exact bound this file computes ([calendarEntriesWindowFor]).
const int kCalendarWindowLookbehindDays = 45;
const int kCalendarWindowLookaheadDays = 45;

/// The first civil date of [year]/[month].
LocalDate _firstOfMonth(int year, int month) => LocalDate(year, month, 1);

/// The last civil date of [year]/[month].
LocalDate _lastOfMonth(int year, int month) {
  final firstOfNext =
      month == 12 ? LocalDate(year + 1, 1, 1) : LocalDate(year, month + 1, 1);
  return firstOfNext.addDays(-1);
}

/// The entries-subscription window for the displayed month [year]/[month]
/// (issue #197): [kCalendarWindowLookbehindDays] before its first day
/// through [kCalendarWindowLookaheadDays] after its last, inclusive. Public
/// and pure for direct testing, mirroring [dayCellSemanticLabel] and
/// [canDrivePageController] elsewhere in this file.
(LocalDate, LocalDate) calendarEntriesWindowFor(int year, int month) => (
      _firstOfMonth(year, month).addDays(-kCalendarWindowLookbehindDays),
      _lastOfMonth(year, month).addDays(kCalendarWindowLookaheadDays),
    );

/// The [MediaQuery.textScalerOf] scale at and above which the legend strip
/// starts collapsed by default (issue #312, large-text-budget item): past
/// this scale the header/legend/layers stack above the single `Expanded`
/// [PageView] otherwise squeezes the grid too far. Matched in
/// [_MonthCalendarState._legendStrip]; the operator's own toggle always
/// overrides this default once touched.
const double kLegendCollapseTextScale = 1.6;

/// Confidence-appropriate band weight (KTD4): a hatched band's opacity by
/// its cycle's tier. `high` reads strongest, `irregular` faintest — and
/// every cycle past the first has already stepped down one tier, so bands
/// fade with distance too.
double forecastBandOpacity(CycleConfidence tier) => switch (tier) {
  CycleConfidence.high => 0.9,
  CycleConfidence.learning => 0.6,
  CycleConfidence.irregular => 0.35,
  // Issue #218: an onboarding-seeded forecast reads weaker than `learning`
  // (which at least has real cycles behind it) but stronger than the
  // deliberately faint `irregular`.
  CycleConfidence.provisional => 0.5,
};

/// Floor under [forecastBandOpacity] for a predicted band's *border* stroke
/// only (issue #312, review of #191 B-2/KTD4, tightened further in #312's
/// own follow-up review): the hatch fill lines still carry the full
/// per-tier weighting, but `predictedBorder` is solved for only ~3.06:1
/// against `surface` at full alpha, so any alpha under ~0.98 already drops
/// the ring below WCAG's 3:1 non-text floor once blended — a 0.6 floor
/// (the tier weighting's own top value) was still short of that. The
/// border now always draws at full opacity, for every tier.
const double kPredictedBorderMinAlpha = 1.0;

double forecastBorderOpacity(CycleConfidence tier) {
  final base = forecastBandOpacity(tier);
  return base < kPredictedBorderMinAlpha ? kPredictedBorderMinAlpha : base;
}

/// Per-layer dot colors, one per active layer (max
/// [kMaxSymptomLayers]); brightness-aware so both themes keep the dots
/// glanceable.
List<Color> symptomLayerPalette(Brightness brightness) =>
    brightness == Brightness.light
    ? const [Color(0xFF7B1FA2), Color(0xFF00695C), Color(0xFFC2185B)]
    : const [Color(0xFFE1BEE7), Color(0xFF80CBC4), Color(0xFFF8BBD0)];

/// Plain future days stay dimmed like the old lock visual; a day with
/// predicted content renders at full weight so the band carries the
/// distinction instead (KTD3).
double futureCellOpacity(bool isFuture, bool hasForecastContent) =>
    isFuture && !hasForecastContent ? 0.35 : 1;

/// The plain-future-day dim weight [#138, B-23]: below the value a day
/// cell's number text is rendered with `onSurface` at this alpha rather
/// than under an [Opacity] layer — an [Opacity] dims *every* child
/// including the today ring and any markers, and 0.35 over the whole cell
/// lands under usable contrast. Applied to the day-number text only.
const double kFutureDayTextAlpha = 0.38;

/// [#138, B-23] The day-cell geometry for one grid width and text scale:
/// the number circle grows from the scaled 20px baseline (never below its
/// historic 34px), the markers row grows from a scaled 12px baseline
/// (never below its historic 14px), and the cell's row height keeps at
/// least a 48dp touch target. Pure — computed once per month page from the
/// page's own [LayoutBuilder] constraints, directly unit-testable.
class DayCellMetrics {
  const DayCellMetrics({
    required this.circleSize,
    required this.markersHeight,
    required this.aspectRatio,
  });

  /// The day-number circle's outer diameter in logical pixels.
  final double circleSize;

  /// The markers row's fixed height under a day's number.
  final double markersHeight;

  /// `GridView.count`'s `childAspectRatio` (`width / height`) that yields
  /// the intended row height for a 7-column grid over [gridWidth].
  final double aspectRatio;
}

/// Computes [DayCellMetrics] for a 7-column month grid whose content width
/// is [gridWidth] (the page width; the grid's own horizontal padding of 4
/// each side is subtracted here). The 48dp minimum matches Material's
/// [kMinInteractiveDimension]; the `max(cellWidth, ...)` half keeps the
/// historic square cells at the default text scale, so 1.0x rendering is
/// pixel-identical to before this pass and only grows from there.
DayCellMetrics dayCellMetricsFor(double gridWidth, TextScaler textScaler) {
  final cellWidth = (gridWidth - 8) / 7;
  final circleSize = math.min(
    math.max(34.0, textScaler.scale(20)),
    cellWidth,
  );
  final markersHeight = math.max(14.0, textScaler.scale(12));
  final contentHeight = circleSize + 2 + markersHeight;
  final cellHeight = math.max(math.max(cellWidth, 48), contentHeight);
  return DayCellMetrics(
    circleSize: circleSize,
    markersHeight: markersHeight,
    aspectRatio: cellWidth / cellHeight,
  );
}

/// A logged bleed [level]'s fill/on-fill pair from the #176 `flow*` ramp
/// (issue #191 B-2). `spotting`'s `fill` doubles as its ring/centre-dot
/// colour in [_MonthCalendarState._flowCircle] — it never fills the whole
/// circle. [_MonthCalendarState._dayCircle] only ever calls this with a
/// bleed level (`isBleed(level)`, which excludes `none`, the deprecated
/// `spotting` alias, and `notBleeding` — Issue #247); those three share
/// spotting's case rather than adding branches no caller can reach.
/// Issue #247: [FlowLevel.superHeavy] has no dedicated ramp slot — it
/// reuses [LunarLogColors.flowHeavy]/`onFlowHeavy`, distinguished from
/// plain `heavy` only by [_flowLevelMarkCount]'s extra mark (the design
/// decision's documented fallback over adding a fifth ramp step).
({Color fill, Color onFill}) _flowTone(FlowLevel level, LunarLogColors colors) =>
    switch (level) {
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.none || FlowLevel.spotting || FlowLevel.notBleeding => (
        fill: colors.flowSpotting,
        onFill: colors.onFlowSpotting,
      ),
      FlowLevel.light => (fill: colors.flowLight, onFill: colors.onFlowLight),
      FlowLevel.medium => (fill: colors.flowMedium, onFill: colors.onFlowMedium),
      FlowLevel.heavy || FlowLevel.superHeavy => (
        fill: colors.flowHeavy,
        onFill: colors.onFlowHeavy,
      ),
    };

/// The non-colour intensity channel (issue #191 B-2): a small dot count
/// climbing from 1 (spotting) to 5 (super heavy, issue #247), independent
/// of the `flow*` ramp's hue/saturation — asserted directly in widget
/// tests via the `flow-mark-<i>-<iso>` keys [_MonthCalendarState._flowCircle]
/// renders. See [_flowTone] on why `none`/`notBleeding` share spotting's
/// case, and on `superHeavy` reusing `heavy`'s colour.
int _flowLevelMarkCount(FlowLevel level) => switch (level) {
  // ignore: deprecated_member_use_from_same_package
  FlowLevel.none || FlowLevel.spotting || FlowLevel.notBleeding => 1,
  FlowLevel.light => 2,
  FlowLevel.medium => 3,
  FlowLevel.heavy => 4,
  FlowLevel.superHeavy => 5,
};

/// The spotting-day numeral drawn with a thin [haloColor] outline behind
/// its fill (issue #312, contrast review of #191 B-2): `onSurface` [text]
/// sits directly atop the flow-spotting centre dot in
/// [_MonthCalendarState._flowCircle], and in dark mode the two colours can
/// land close enough in luminance that the digit is unreadable where its
/// glyph crosses the dot. A `surface`-coloured stroke keeps the numeral
/// legible regardless of what colour happens to sit underneath it, the
/// same "outlined text" technique as a map label over varying terrain.
Widget _haloedDayNumber(
  String text,
  TextStyle? baseStyle,
  Color textColor,
  Color haloColor,
) {
  final base = baseStyle ?? const TextStyle();
  return Stack(
    alignment: Alignment.center,
    children: [
      Text(
        text,
        style: base.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = haloColor,
        ),
      ),
      Text(text, style: base.copyWith(color: textColor)),
    ],
  );
}

Color pmsBadgeColor(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFF5E35B1)
    : const Color(0xFFB39DDB);

Color crampsBadgeColor(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFF9A6A00)
    : const Color(0xFFFFCC80);

/// The semantic (screen-reader) label for one day cell (#133 seeded the
/// predicted/logged distinction; #138 is the full pass — date with
/// weekday, flow state, symptom presence, and loggability, per the issue's
/// own cell-label spec). Public for direct testing; the calendar wraps
/// every cell's contents with it.
///
/// Issue #160: [monthNames]/[weekdayNames] are the locale-derived name
/// lists the widget passes in (`dates.monthNames`/`dates.fullWeekdayNames`
/// over `dates.calendarLocale(...)`); both default to the `en` lists so
/// this pure, context-free helper (and its direct tests) keep working
/// without a widget tree. Issue #138: the fragments themselves come from
/// [AppLocalizations] (#340's rule — no new hardcoded literals), so the
/// same helper stays localizable.
///
/// [readOnly] appends the read-only fragment to past cells when the
/// caller's effective role makes the day sheet view-only (a future cell
/// already carries the not-loggable fragment, so the two never stack).
/// [fertileWindowLabel] is the care mode's own phrase
/// ([CareModeCopy.fertileWindowLabel]) — the care-mode gate
/// ([_MonthCalendarState._cellForMode]) has already stripped
/// [ForecastDayCell.fertileWindow] entirely when the mode hides it, so a
/// null here only silences an already-unreachable fragment.
String dayCellSemanticLabel({
  required LocalDate date,
  required DayEntry? entry,
  required LocalDate today,
  required ForecastDayCell? cell,
  required AppLocalizations l10n,
  List<String>? monthNames,
  List<String>? weekdayNames,
  bool readOnly = false,
  String? fertileWindowLabel,
}) {
  final months = monthNames ?? dates.monthNames();
  final weekdays = weekdayNames ?? dates.fullWeekdayNames();
  // `DateTime.weekday` is Monday=1..Sunday=7; the name lists are
  // Sunday-first (see [dates.fullWeekdayNames]), so `% 7` indexes them.
  final weekdayIndex = DateTime(date.year, date.month, date.day).weekday % 7;
  final parts = <String>[
    l10n.calendarCellDateLabel(
      weekdays[weekdayIndex],
      months[date.month - 1],
      date.day,
    ),
  ];
  if (date.isAfter(today)) {
    final safeCell = cell;
    if (safeCell != null) {
      parts.addAll(_predictedDayParts(safeCell, l10n, fertileWindowLabel));
    }
    parts.add(l10n.calendarCellFuture);
    return parts.join(', ');
  }
  parts.addAll(_loggedDayParts(entry, l10n));
  if (date == today) parts.add(l10n.calendarCellToday);
  if (readOnly) parts.add(l10n.calendarCellReadOnly);
  return parts.join(', ');
}

/// The logged-day fragments of [dayCellSemanticLabel] (#138): a bleed day
/// names its level plus symptom presence; a symptom-only day says so; a
/// bare logged day still answers "was anything logged?" and names the
/// absence of symptoms, so symptom presence is announced for every logged
/// cell, not only the ones with tags.
List<String> _loggedDayParts(DayEntry? entry, AppLocalizations l10n) {
  if (entry == null) return [l10n.calendarCellNotLogged];
  // Issue #249: pain_free is a positive "none today" assertion, never a
  // symptom — a day carrying only it is announced as symptom-free.
  final hasSymptoms = hasSymptomTags(entry.tags) || entry.note != null;
  if (isBleed(entry.flow)) {
    return [
      l10n.calendarCellFlowState(localizedFlowLabel(entry.flow, l10n)),
      hasSymptoms ? l10n.calendarCellSymptomsLogged : l10n.calendarCellNoSymptoms,
    ];
  }
  if (hasSymptoms) return [l10n.calendarCellLoggedSymptoms];
  return [l10n.calendarCellLogged, l10n.calendarCellNoSymptoms];
}

/// The predicted-day fragments of [dayCellSemanticLabel] — every phrase
/// deliberately contains "predicted"/"estimated" so no forecast state can
/// ever sound like a logged one to a screen reader (#133's seam, #138's
/// verification).
List<String> _predictedDayParts(
  ForecastDayCell cell,
  AppLocalizations l10n,
  String? fertileWindowLabel,
) {
  final parts = <String>[
    if (cell.predictedBleed) l10n.calendarCellPredictedPeriod,
    if (cell.predictedBleed && cell.cycleDayNumber != null)
      l10n.calendarCellCycleDay(cell.cycleDayNumber!),
    if (!cell.predictedBleed && cell.cycleDayNumber != null)
      l10n.calendarCellCycleDayFirstCycle(cell.cycleDayNumber!),
    if (cell.pmsBadge) l10n.calendarCellPmsWindow,
    if (cell.crampsBadge) l10n.calendarCellCrampsWindow,
    if (cell.fertileWindow && fertileWindowLabel != null)
      fertileWindowLabel.toLowerCase(),
  ];
  if (parts.isEmpty) parts.add(l10n.calendarCellNoPrediction);
  return parts;
}

/// Whether [cell] still carries something worth rendering as a forecast
/// cell (issue #143 review, used by [_MonthCalendarState._cellForMode]
/// once a care mode has already stripped [ForecastDayCell.fertileWindow]):
/// a cell whose only content was the fertile window must not survive as a
/// non-null, all-false cell — see [_MonthCalendarState._cellForMode]'s own
/// doc comment for why. Deliberately excludes [ForecastDayCell.tier]/
/// [ForecastDayCell.cycleIndex], which are always present and carry no
/// visible meaning on their own.
bool _hasAnyMarker(ForecastDayCell cell) =>
    cell.predictedBleed ||
    cell.cycleDayNumber != null ||
    cell.pmsBadge ||
    cell.crampsBadge;

int _monthIndex(int year, int month) => year * 12 + (month - 1);

/// Whether a programmatic month navigation
/// ([_MonthCalendarState._goToMonth]) should touch its [PageController] at
/// all: both the animate and jump paths need the same `hasClients` guard
/// (issue #312, symmetry review of #191 — the animate path previously
/// lacked it while the jump path already had it). Public and pure so the
/// `!hasClients` case is directly unit-testable: by the time any widget
/// test can reach a navigation control, the `PageView`'s `Scrollable` has
/// always already attached, so faking that state through the widget tree
/// isn't possible — this predicate is the seam. Public for direct testing,
/// mirroring [dayCellSemanticLabel] elsewhere in this file.
bool canDrivePageController({required bool hasClients}) => hasClients;

/// How [_MonthCalendarState._legendSwatch] draws one legend entry's swatch
/// — mirrors the shapes the grid itself uses so the legend key actually
/// matches what a cell renders (a plain fill, spotting/today's ring,
/// #133's hatched predicted band, or #143's dashed fertile-window ring).
enum _LegendSwatchStyle { fill, ring, hatched, dashed, icon }

/// One row of the legend strip (issue #191; B-2, B-11; issue #312 review:
/// `icon` added for the PMS/cramps badges): a swatch plus its label, keyed
/// by [code] (`legend-<code>`) for direct widget-test lookup.
class _LegendEntry {
  const _LegendEntry(
    this.code,
    this.color,
    this.label, {
    this.style = _LegendSwatchStyle.fill,
    this.icon,
  });

  final String code;
  final Color color;
  final String label;
  final _LegendSwatchStyle style;

  /// Set only when [style] is [_LegendSwatchStyle.icon].
  final IconData? icon;
}

class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.profileId,
    this.readOnly = false,
    this.mode = ProfileMode.standard,
    this.trackingPreferences,
    this.isMinor = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.guardiansRepository,
  });

  final String profileId;
  final bool readOnly;

  /// The profile's care mode (Issue #131): forwarded to [DaySheet] for its
  /// category headings and surfacing order. Presentation only.
  final ProfileMode mode;

  /// The profile's curated tracking categories (Issue #259), forwarded to
  /// [DaySheet]; null means never customized. Presentation only.
  final TrackingPreferences? trackingPreferences;

  /// Whether the profile subject is a minor (Issue #259): gates the
  /// minor-visibility defaults in [DaySheet]. Presentation only.
  final bool isMinor;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Provider for the resolved IANA time zone identifier (paired with #38).
  /// Passed to [DaySheet].
  final String Function()? timezoneProvider;

  /// Source of this profile's guardians for attribution (R12); null in
  /// local-only use (no storage wired up), matching the previous
  /// ambient-provider lookup's own null fallback.
  final ProfileGuardiansRepository? guardiansRepository;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DayEntriesRepository _repository;
  int _displayedYear = 1970;
  int _displayedMonth = 1;

  /// The currently-subscribed window's day entries (review follow-up on
  /// issue #197): kept in state via an explicit subscription rather than
  /// read off a `StreamBuilder` snapshot, so a window crossing
  /// (`_maybeRewatchEntriesFor` swapping in a new stream that has not
  /// emitted yet) keeps rendering the *previous* window's entries — and so
  /// the grid/`PageView` beneath them — instead of falling back to a
  /// full-bleed spinner that would otherwise unmount the `PageView`
  /// mid-swipe-animation. Null only before the very first emission ever,
  /// and right after a profile switch (a genuinely different data set,
  /// reset immediately like [_guardians] below rather than left showing
  /// the old profile's days).
  List<DayEntry>? _entries;
  StreamSubscription<List<DayEntry>>? _entriesSub;

  /// The inclusive range [_entries] is currently subscribed to (issue
  /// #197) — null until the first [_maybeRewatchEntriesFor] call. Tracked
  /// separately from `_displayed*` because the window only moves when the
  /// displayed month falls outside it, not on every page change; see
  /// [_maybeRewatchEntriesFor].
  LocalDate? _entriesWindowFrom;
  LocalDate? _entriesWindowTo;

  /// Attribution context (R12): the signed-in user and this profile's
  /// guardians, so the day sheet's badge can render "Logged by Dad" and
  /// "Logged by you" at the real call site. Null/empty in local-only use.
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];
  StreamSubscription<List<ProfileGuardian>>? _guardiansSub;
  AuthController? _auth;

  /// Forecast seams (KTD9): the prediction and history services when the
  /// ambient provider tree has them (omission-aware, matching the
  /// overview's numbers); null in local-only use, where the calendar
  /// derives from its own entry stream instead.
  ///
  /// Review follow-up on issue #197: that local derivation
  /// (`build()`'s `_predictionStream == null` / `_historyStream == null`
  /// branches, and `defaultLayerTags(entries)` below for the symptom-layer
  /// default) now runs over [_entries] — the calendar's *windowed* list,
  /// not full history — where it used to see the whole profile. In
  /// production both services are always provided (`lib/app.dart` wires
  /// both unconditionally), so this fallback is reachable only from a test
  /// that mounts [MonthCalendar] without them (e.g.
  /// `test/ui/calendar_navigation_test.dart`'s harness); see
  /// `lib/ui/README.md`'s "Calendar windowed entries subscription" section
  /// for the full note, including the `defaultLayerTags` behaviour change.
  CyclePredictionService? _predictionService;
  CycleHistoryService? _historyService;
  Stream<CyclePrediction>? _predictionStream;
  Stream<CycleHistoryView>? _historyStream;

  /// Symptom layers (R2): the active selection lives in widget state only
  /// (never persisted). Until the operator first toggles a layer, the
  /// active set is re-derived per emission from the profile's most-used
  /// tags.
  bool _layersUserSet = false;
  Set<String> _activeLayers = const {};
  bool _layersExpanded = false;

  /// The legend strip's expand/collapse state (issue #312): `null` until
  /// the operator first touches the toggle, meaning
  /// [_legendStrip] falls back to [kLegendCollapseTextScale]'s
  /// scale-based default; once touched, the explicit choice always wins.
  bool? _legendExpanded;

  /// Issue #220: whether the current prediction carries a PMS band at all
  /// (at least `kMinPmsIntervalsForPrediction` logged PMS intervals). Set
  /// during [_calendar]'s build pass, read by [_legendEntries] further
  /// down the same pass — the "PMS window" legend entry only renders while
  /// the band it keys can actually appear on the grid.
  bool _pmsBandActive = false;

  /// Swipe navigation (issue #191): one page per month, indexed by
  /// [_pageIndexFor]/[_monthForPageIndex] against a fixed epoch offset so
  /// page indices never go negative for any real calendar year.
  late final PageController _pageController;

  /// True from the moment a programmatic [_goToMonth] animation starts
  /// until it settles (issue #312, `_goToMonth` asymmetry review):
  /// [_onPageChanged] ignores every intermediate settle event while this
  /// is true, so a (currently unreachable — only [_shiftMonth] animates,
  /// and only ever one page) multi-page animate call could never
  /// transiently rewind `_displayed*` to a page it is only passing
  /// through on the way to the real target.
  bool _isAnimatingToMonth = false;

  /// Generation counter guarding [_isAnimatingToMonth]'s reset (issue #312
  /// follow-up review): a second [_goToMonth] `animate: true` call fired
  /// while the first is still in flight (e.g. two rapid chevron taps)
  /// starts a new [PageController.animateToPage] on the same controller,
  /// which resolves the *first* call's still-pending `.animateToPage`
  /// future early (superseded, not actually settled). Without this token
  /// that early resolution would clear [_isAnimatingToMonth] while the
  /// second animation is still running, letting its own intermediate
  /// [_onPageChanged] settle events rewind `_displayed*`. Each animate
  /// call claims the latest token; only the callback still holding it may
  /// clear the guard.
  int _animateToken = 0;

  /// Issue #143: the fertile-window band, its legend entry, and its
  /// explainer text all gate on [CareModeCopy.showsFertileWindow] through
  /// this one lookup — presentation only, same posture as every other
  /// `CareModeCopy` consumer.
  CareModeCopy get _copy => careModeCopyFor(widget.mode);

  /// Care-mode gate for a forecast cell's fertile-window flag (issue #143):
  /// when the mode hides the estimate, this strips [ForecastDayCell
  /// .fertileWindow] before the cell reaches [_dayCircle], [_futureMarkers],
  /// the semantic label, or the future-day explainer — one gate covers
  /// every rendering rather than repeating the check at each call site.
  ///
  /// Issue #143 review: when the fertile window was the cell's *only*
  /// content, stripping it left a non-null, all-false [ForecastDayCell] —
  /// which [futureCellOpacity] reads as "has forecast content" (full
  /// opacity, not the dimmed plain-future-day weight) and which skipped
  /// [_FutureDayExplainer]'s honest "no prediction for this date" copy in
  /// favour of a bare confidence line. Returning `null` instead (via
  /// [_hasAnyMarker]) makes a hidden fertile-only day render and explain
  /// exactly like any other plain future day.
  ForecastDayCell? _cellForMode(ForecastDayCell? cell) {
    if (cell == null || _copy.showsFertileWindow || !cell.fertileWindow) {
      return cell;
    }
    final stripped = ForecastDayCell(
      predictedBleed: cell.predictedBleed,
      cycleDayNumber: cell.cycleDayNumber,
      pmsBadge: cell.pmsBadge,
      crampsBadge: cell.crampsBadge,
      fertileWindow: false,
      tier: cell.tier,
      cycleIndex: cell.cycleIndex,
    );
    return _hasAnyMarker(stripped) ? stripped : null;
  }

  @override
  void initState() {
    super.initState();
    _repository = context.read<DayEntriesRepository>();
    _predictionService = context.read<CyclePredictionService?>();
    _historyService = context.read<CycleHistoryService?>();
    _rewatchPrediction();
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    _watchGuardians();
    _resetToTodaysMonth();
    // Issue #197: the first window is always a fresh subscription (no prior
    // `_entriesWindowFrom`/`_entriesWindowTo` to already cover it).
    _maybeRewatchEntriesFor(_displayedYear, _displayedMonth);
    _pageController = PageController(
      initialPage: _pageIndexFor(_displayedYear, _displayedMonth),
    );
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

  void _watchGuardians() {
    _guardiansSub?.cancel();
    // Reset immediately (not just on the new stream's first tick) so a
    // profile switch never keeps rendering the previous profile's
    // guardians in the meantime (residual note on #11).
    _guardians = const [];
    final repository = widget.guardiansRepository;
    if (repository == null) return;
    _guardiansSub = repository.watchForProfile(widget.profileId).listen((
      guardians,
    ) {
      if (!mounted) return;
      setState(() => _guardians = guardians);
    });
  }

  void _rewatchPrediction() {
    _predictionStream = _predictionService?.watch(
      widget.profileId,
      today: widget.todayProvider,
    );
    _historyStream = _historyService?.watch(
      widget.profileId,
      today: widget.todayProvider,
    );
  }

  @override
  void didUpdateWidget(MonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _rewatchPrediction();
      _watchGuardians();
      _resetToTodaysMonth();
      // A different profile invalidates whatever window the old one's
      // subscription covered — force a fresh subscription below rather
      // than trusting the previous profile's now-irrelevant bounds. Reset
      // immediately (not just on the new subscription's first tick), the
      // same discipline [_watchGuardians] already applies, so a profile
      // switch never keeps rendering the previous profile's days in the
      // meantime — unlike a same-profile window crossing, this is a
      // genuinely different data set, not a case [_entries] should bridge.
      _entries = null;
      _entriesWindowFrom = null;
      _entriesWindowTo = null;
      _maybeRewatchEntriesFor(_displayedYear, _displayedMonth);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(
          _pageIndexFor(_displayedYear, _displayedMonth),
        );
      }
    }
  }

  /// (Re)subscribes [_entries] to a window covering the displayed month
  /// [year]/[month] only when the current subscription (if any) doesn't
  /// already fully cover it (issue #197) — paging within an already-fetched
  /// window must not force a new stream/query on every swipe, only a
  /// genuine move past its edge should. On a rewatch the new window is
  /// [calendarEntriesWindowFor] centered on [year]/[month], not a minimal
  /// extension of the old one, so repeated one-month-at-a-time navigation
  /// past the edge still only resubscribes occasionally rather than on
  /// every step.
  ///
  /// Review follow-up: the old subscription is only cancelled here, not
  /// unsubscribed-and-forgotten via a fresh `StreamBuilder(stream: ...)` —
  /// [_entries] itself is left untouched until the new subscription's
  /// first emission lands, so a window crossing keeps rendering the
  /// previous window's entries in the meantime (see [_entries]'s own doc).
  void _maybeRewatchEntriesFor(int year, int month) {
    final firstOfMonth = _firstOfMonth(year, month);
    final lastOfMonth = _lastOfMonth(year, month);
    final from = _entriesWindowFrom;
    final to = _entriesWindowTo;
    final covered = from != null &&
        to != null &&
        !firstOfMonth.isBefore(from) &&
        !lastOfMonth.isAfter(to);
    if (covered) return;
    final (newFrom, newTo) = calendarEntriesWindowFor(year, month);
    _entriesWindowFrom = newFrom;
    _entriesWindowTo = newTo;
    _entriesSub?.cancel();
    _entriesSub = _repository
        .watchForProfile(widget.profileId, from: newFrom, to: newTo)
        .listen((entries) {
      if (!mounted) return;
      setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    _entriesSub?.cancel();
    _entriesSub = null;
    _guardiansSub?.cancel();
    _guardiansSub = null;
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    _pageController.dispose();
    super.dispose();
  }

  /// R14/R15: read-only when the profile is archived (existing
  /// [MonthCalendar.readOnly]) OR the caller's accepted role is `viewer`.
  /// Fails open on an unknown role - no guardian rows yet, no signed-in
  /// operator, or no row matching the current user (Issue #3 gap-closure
  /// plan, Unit U6) - mirroring the null-vs-empty discipline
  /// `ManageGuardiansScreen._callerRoleOf` already uses; do not invert it.
  bool get _effectiveReadOnly =>
      widget.readOnly ||
      acceptedGuardianFor(_guardians, _currentUserId)?.role.canLog == false;

  void _resetToTodaysMonth() {
    final today = widget.todayProvider();
    _displayedYear = today.year;
    _displayedMonth = today.month;
  }

  /// Fixed epoch offset (issue #191): keeps every [_pageIndexFor] result
  /// non-negative for any realistic calendar year, so [_pageController]
  /// never has to reason about negative [PageView] indices.
  static const int _kPageIndexOffset = 1000000;

  int _pageIndexFor(int year, int month) =>
      _monthIndex(year, month) + _kPageIndexOffset;

  (int, int) _monthForPageIndex(int pageIndex) {
    final index = pageIndex - _kPageIndexOffset;
    return (index ~/ 12, index % 12 + 1);
  }

  /// [PageView.onPageChanged] (issue #191): keeps `_displayed*` — and so
  /// the header/legend/empty-state chrome, which reads that state directly
  /// — in sync with whichever page the swipe gesture actually settles on.
  /// A no-op guard skips the redundant `setState` [_goToMonth] already
  /// performed for a programmatic (chevron/Today/picker) navigation.
  void _onPageChanged(int pageIndex) {
    // Issue #312: a programmatic animate navigation already committed the
    // final `_displayed*` directly below in `_goToMonth` — an intermediate
    // settle event fired while that animation is still in flight is never
    // the real destination and must not overwrite it.
    if (_isAnimatingToMonth) return;
    final (year, month) = _monthForPageIndex(pageIndex);
    if (year == _displayedYear && month == _displayedMonth) return;
    _maybeRewatchEntriesFor(year, month);
    setState(() {
      _displayedYear = year;
      _displayedMonth = month;
    });
  }

  /// Programmatic navigation to one specific month (chevrons, Today, and
  /// the month/year picker all funnel through this): updates the display
  /// state immediately and drives [_pageController] to match, animated for
  /// the one-page chevron step and instant (a jump) for the
  /// possibly-many-pages-away Today/picker destinations. Both paths share
  /// the same [canDrivePageController] `hasClients` guard (issue #312 —
  /// the animate path previously lacked it).
  void _goToMonth(int year, int month, {required bool animate}) {
    final page = _pageIndexFor(year, month);
    if (canDrivePageController(hasClients: _pageController.hasClients)) {
      if (animate) {
        final token = ++_animateToken;
        _isAnimatingToMonth = true;
        unawaited(
          _pageController
              .animateToPage(
                page,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              )
              .whenComplete(() {
                if (mounted && token == _animateToken) {
                  _isAnimatingToMonth = false;
                }
              }),
        );
      } else {
        _pageController.jumpToPage(page);
      }
    }
    _maybeRewatchEntriesFor(year, month);
    setState(() {
      _displayedYear = year;
      _displayedMonth = month;
    });
  }

  void _shiftMonth(int delta) {
    final index = _monthIndex(_displayedYear, _displayedMonth) + delta;
    _goToMonth(index ~/ 12, index % 12 + 1, animate: true);
  }

  void _goToToday() {
    final today = widget.todayProvider();
    _goToMonth(today.year, today.month, animate: false);
  }

  /// Tapping the month label (issue #191): a small custom sheet in place of
  /// six-tap chevron navigation, bounded by the same forward limit
  /// [nextDisabled] already enforces on the chevron (never further ahead
  /// than [kForwardMonthLimit] months past today).
  Future<void> _openMonthYearPicker() async {
    final today = widget.todayProvider();
    final maxMonthIndex = _monthIndex(today.year, today.month) + kForwardMonthLimit;
    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteMonthYearPickerDialog),
      builder: (_) => _MonthYearPickerSheet(
        initialYear: _displayedYear,
        initialMonth: _displayedMonth,
        maxMonthIndex: maxMonthIndex,
      ),
    );
    if (result == null) return;
    _goToMonth(result.$1, result.$2, animate: false);
  }

  Future<void> _openDay(LocalDate date, DayEntry? entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: _repository,
        profileId: widget.profileId,
        date: date,
        existing: entry,
        today: widget.todayProvider(),
        mode: widget.mode,
        trackingPreferences: widget.trackingPreferences,
        isMinor: widget.isMinor,
        readOnly: _effectiveReadOnly,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: _guardians,
      ),
    );
  }

  /// KTD8: a tapped future cell opens the read-only explainer — never the
  /// log sheet — whatever the predicted state for the date is.
  Future<void> _openFutureExplainer(
    LocalDate date,
    ForecastDayCell? cell,
    List<ForecastCycle> cycles,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteFutureDayExplainerScreen),
      builder: (_) => _FutureDayExplainer(
        date: date,
        cell: cell,
        cycles: cycles,
        copy: _copy,
      ),
    );
  }

  void _toggleLayer(String code, Set<String> current) {
    final selected = current.contains(code);
    if (!selected && current.length >= kMaxSymptomLayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('layer-limit-snack'),
          content: Text(
            AppLocalizations.of(context).calendarLayerLimitSnack,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _layersUserSet = true;
      _activeLayers = selected
          ? ({...current}..remove(code))
          : {...current, code};
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.todayProvider();
    final nextDisabled =
        _monthIndex(_displayedYear, _displayedMonth) >=
        _monthIndex(today.year, today.month) + kForwardMonthLimit;
    // Review follow-up on issue #197: reads [_entries] directly (kept
    // across a window-crossing resubscribe by [_maybeRewatchEntriesFor])
    // rather than a `StreamBuilder<List<DayEntry>>` snapshot — see
    // [_entries]'s own doc for why a plain `StreamBuilder` here would risk
    // a full-bleed spinner (and the `PageView` beneath it unmounting
    // mid-swipe) every time the window moves.
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final byIso = {for (final entry in entries) entry.localDate.iso: entry};
    return StreamBuilder<CyclePrediction?>(
      stream: _predictionStream,
      builder: (context, predictionSnapshot) {
        final prediction = _predictionStream == null
            ? computePredictionFromEntries(entries: entries, today: today)
            : predictionSnapshot.data;
        if (prediction == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<CycleHistoryView?>(
          stream: _historyStream,
          builder: (context, historySnapshot) {
            final history = _historyStream == null
                ? deriveCycleHistoryFromEntries(
                    entries: entries,
                    today: today,
                  )
                : historySnapshot.data;
            if (history == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _calendar(
              context,
              byIso: byIso,
              entries: entries,
              prediction: prediction,
              history: history,
              today: today,
              nextDisabled: nextDisabled,
            );
          },
        );
      },
    );
  }

  Widget _calendar(
    BuildContext context, {
    required Map<String, DayEntry> byIso,
    required List<DayEntry> entries,
    required CyclePrediction prediction,
    required CycleHistoryView history,
    required LocalDate today,
    required bool nextDisabled,
  }) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<LunarLogColors>() ??
        LunarLogColors.forColorScheme(theme.colorScheme);
    final estimateActive = prediction is ActivePrediction;
    final cycles = estimateActive
        ? deriveForecast(prediction: prediction, history: history, today: today)
        : const <ForecastCycle>[];
    // Issue #220: the PMS band is data-driven — the estimate's own
    // 6-cycle averages anchored before the next predicted start, or null
    // (no PMS badge anywhere) below the 3-logged-interval minimum.
    final pmsEstimate = estimateActive ? prediction.pms : null;
    // Latched for the legend strip further down this same build pass
    // (field assignment, not setState — both read it in the same frame):
    // the "PMS window" legend entry only renders while a band actually
    // exists, mirroring the cells themselves.
    _pmsBandActive = pmsEstimate != null;
    final forecastByIso =
        forecastDayCells(cycles: cycles, today: today, pms: pmsEstimate);
    // Review follow-up on issue #197: `entries` here is [_entries]'s
    // windowed list (±45 days around the displayed month), not the
    // profile's full history — the default layer selection now only
    // ranks tags from within that window. Documented, not treated as a
    // bug: `lib/ui/README.md`'s "Calendar windowed entries subscription"
    // section covers why this is an accepted behaviour change rather than
    // a full-history stream kept just for this.
    final activeLayers = _layersUserSet
        ? _activeLayers
        : {for (final tag in defaultLayerTags(entries)) tag};
    final layerList = activeLayers.toList(growable: false);
    final palette = symptomLayerPalette(theme.brightness);
    final maxPageIndex =
        _pageIndexFor(today.year, today.month) + kForwardMonthLimit;
    final l10n = AppLocalizations.of(context);
    final locale = dates.calendarLocale(context);
    final fullWeekdays = dates.fullWeekdayNames(locale: locale);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.calendarPreviousMonthTooltip,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftMonth(-1),
            ),
            Expanded(
              child: InkWell(
                key: const ValueKey('month-year-label'),
                onTap: _openMonthYearPicker,
                child: Center(
                  child: Text(
                    l10n.calendarMonthYearLabel(
                      dates.monthNames(locale: locale)[_displayedMonth - 1],
                      _displayedYear,
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('today-button'),
              tooltip: l10n.calendarTodayTooltip,
              icon: const Icon(Icons.today_outlined),
              onPressed: _goToToday,
            ),
            IconButton(
              tooltip: l10n.calendarNextMonthTooltip,
              icon: const Icon(Icons.chevron_right),
              onPressed: nextDisabled ? null : () => _shiftMonth(1),
            ),
          ],
        ),
        _legendStrip(context, theme, colors),
        _layersHeader(layerList, theme),
        if (_layersExpanded) _layersPanel(activeLayers),
        Padding(
          key: const ValueKey('calendar-weekday-header'),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // #138 (B-23): the narrow initial stays the visual child, but
              // each column carries the full day name as its Semantics
              // label — two "S" and two "T" initials per week are ambiguous
              // single characters to a screen reader, "Sunday"/"Saturday"
              // and "Tuesday"/"Thursday" are not.
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Semantics(
                      container: true,
                      label: fullWeekdays[(kFirstDayOfWeek + i) % 7],
                      excludeSemantics: true,
                      child: Text(
                        weekdayHeaderLabels(locale: locale)[i],
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!estimateActive) _keepLoggingStrip(theme),
        Expanded(
          child: PageView.builder(
            key: const ValueKey('calendar-page-view'),
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: maxPageIndex + 1,
            itemBuilder: (context, pageIndex) {
              final (year, month) = _monthForPageIndex(pageIndex);
              // #138: the cell geometry derives from this page's own width
              // and the ambient text scale, so the number circle and the
              // cell row both grow with large text instead of clipping, and
              // every cell keeps a 48dp-tall touch target.
              return LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = dayCellMetricsFor(
                    constraints.maxWidth,
                    MediaQuery.textScalerOf(context),
                  );
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        // Issue #187 (B-8): a month with zero entries otherwise
                        // renders as a silent grid of bare day numbers with no
                        // guidance. The grid itself stays fully tappable (its
                        // cell/forecast rendering is #133/#191's, untouched
                        // here) — this is an explanatory banner above it, not a
                        // replacement, so logging any day in the empty month
                        // still works exactly as it did before that issue.
                        //
                        // Issue #312 review: keyed off *this page's* `year`/
                        // `month` (the page actually being built) rather than
                        // `_displayed*` — `_displayed*` only updates once
                        // `onPageChanged` settles, so reading it here made the
                        // banner appear/disappear a beat after the swipe
                        // landed and shifted the grid under the operator's
                        // thumb.
                        if (!_monthHasEntries(entries, year: year, month: month))
                          EmptyState(
                            // Issue #312 review: unique per page (previously a
                            // single constant key shared by every page in the
                            // PageView) — a `find.byKey` lookup on the shared
                            // key was ambiguous once more than one page's
                            // empty-state banner existed in the tree at once
                            // (e.g. mid-swipe, both the outgoing and incoming
                            // page built).
                            key: ValueKey('calendar-month-empty-$year-$month'),
                            title: l10n.calendarNoEntriesTitle,
                            body: l10n.calendarNoEntriesBody,
                          ),
                        GridView.count(
                          key: ValueKey('calendar-grid-$year-$month'),
                          crossAxisCount: 7,
                          // #138: derived (see [dayCellMetricsFor]) rather
                          // than the historic implicit 1.0, so rows grow to
                          // fit the scaled circle/markers — identical to the
                          // old square cells at the default text scale.
                          childAspectRatio: metrics.aspectRatio,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          physics: const NeverScrollableScrollPhysics(),
                          children: _cells(
                            year: year,
                            month: month,
                            byIso: byIso,
                            forecastByIso: forecastByIso,
                            cycles: cycles,
                            today: today,
                            theme: theme,
                            colors: colors,
                            layerList: layerList,
                            palette: palette,
                            metrics: metrics,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// The legend strip under the month header (issue #191; B-2, B-11; issue
  /// #312 review: now also keys the PMS/cramps badges and the
  /// symptom-layer dot palette, and collapses by default at large text
  /// scales — [kLegendCollapseTextScale] — so the header stack above the
  /// single `Expanded` [PageView] keeps its vertical budget). Keys every
  /// mark the grid can show except the cycle-day numeral (a plain count,
  /// not a colour/shape channel that needs a key of its own).
  Widget _legendStrip(BuildContext context, ThemeData theme, LunarLogColors colors) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final expanded = _legendExpanded ?? textScale < kLegendCollapseTextScale;
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('calendar-legend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            label: expanded ? l10n.calendarHideLegend : l10n.calendarShowLegend,
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('legend-toggle'),
              onTap: () => setState(() => _legendExpanded = !expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  const SizedBox(width: 2),
                  Text(l10n.calendarLegend, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
        if (expanded) _legendEntries(theme, colors),
      ],
    );
  }

  /// The legend's swatch rows (issue #312, split out of [_legendStrip] to
  /// keep that method's own branch count low): the four logged flow
  /// levels, a symptom-only day, today's ring, #133's predicted band, and
  /// — new in this issue — the PMS/cramps badges and the symptom-layer dot
  /// palette.
  ///
  /// Labels say "... flow"/"day" rather than the bare `flowLabel(level)`
  /// strings `DaySheet`'s flow chips use (issue #191 review): the day
  /// sheet renders as a modal over this still-mounted calendar, so a bare
  /// "Medium"/"Heavy" here would collide with `find.text` in every widget
  /// test that opens it with a chip selected.
  Widget _legendEntries(ThemeData theme, LunarLogColors colors) {
    final brightness = theme.brightness;
    final l10n = AppLocalizations.of(context);
    final entries = [
      _LegendEntry('light', colors.flowLight, l10n.calendarLegendLight),
      _LegendEntry('medium', colors.flowMedium, l10n.calendarLegendMedium),
      _LegendEntry('heavy', colors.flowHeavy, l10n.calendarLegendHeavy),
      // Issue #247: superHeavy shares heavy's ramp token, so the dot count in
      // the label is the only distinguishing signal (mirrors _flowLevelMarkCount).
      _LegendEntry('superheavy', colors.flowHeavy, l10n.calendarLegendSuperHeavy),
      _LegendEntry('symptom', colors.symptomDot, l10n.calendarLegendSymptom),
      _LegendEntry('today', theme.colorScheme.primary, l10n.calendarLegendToday, style: _LegendSwatchStyle.ring),
      _LegendEntry('predicted', colors.predictedBorder, l10n.calendarLegendPredicted, style: _LegendSwatchStyle.hatched),
      if (_copy.showsFertileWindow)
        _LegendEntry('fertile', colors.fertileBorder, _copy.fertileWindowLegend, style: _LegendSwatchStyle.dashed),
      // Issue #220: only while the prediction actually carries a PMS band
      // (3+ logged PMS intervals) — below the hard minimum the grid never
      // shows a PMS badge, so keying it here would advertise a swatch
      // that can never appear.
      if (_pmsBandActive)
        _LegendEntry('pms', pmsBadgeColor(brightness), l10n.calendarLegendPms, style: _LegendSwatchStyle.icon, icon: Icons.spa),
      _LegendEntry('cramps', crampsBadgeColor(brightness), l10n.calendarLegendCramps, style: _LegendSwatchStyle.icon, icon: Icons.bolt),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final entry in entries) _legendChip(entry, theme),
          _legendPaletteChip(symptomLayerPalette(brightness), theme),
        ],
      ),
    );
  }

  /// The three symptom-layer palette dots, keyed as one legend entry
  /// (issue #312): unlike a logged day's own [_loggedMarkers] dot, this
  /// keys the *colour channel* itself (the fixed [symptomLayerPalette]
  /// order), not any specific tag — which tags occupy which colour is the
  /// operator's own layer selection.
  Widget _legendPaletteChip(List<Color> palette, ThemeData theme) {
    return Row(
      key: const ValueKey('legend-symptom-layers'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in palette)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        const SizedBox(width: 2),
        // "Symptom layer dots", not the bare "Symptom layers" the
        // [_layersHeader] summary row already shows when no layer is
        // selected (issue #312 review) — a shared label would collide
        // with every `find.text` lookup in a widget test that opens with
        // the default (unselected) layer set. #138: Flexible for the same
        // wrap-don't-overflow reason as [_legendChip].
        Flexible(
          child: Text(
            AppLocalizations.of(context).calendarLegendLayerDots,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _legendChip(_LegendEntry entry, ThemeData theme) {
    return Row(
      key: ValueKey('legend-${entry.code}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legendSwatch(entry),
        const SizedBox(width: 4),
        // #138 (AC4): the label wraps inside the legend's Wrap rather
        // than overflowing its row — the legend only collapses by default
        // at kLegendCollapseTextScale and above, so 1.5x keeps it expanded
        // and its longest entries ("Super heavy flow (5 marks)") no
        // longer overflow a phone-class width.
        Flexible(
          child: Text(entry.label, style: theme.textTheme.labelSmall),
        ),
      ],
    );
  }

  Widget _legendSwatch(_LegendEntry entry) {
    return switch (entry.style) {
      _LegendSwatchStyle.fill => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: entry.color),
      ),
      _LegendSwatchStyle.ring => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: entry.color, width: 1.5),
        ),
      ),
      _LegendSwatchStyle.hatched => _HatchedCircle(
        color: entry.color,
        opacity: 1,
        diameter: 14,
        child: const SizedBox.shrink(),
      ),
      _LegendSwatchStyle.dashed => _DashedCircle(
        color: entry.color,
        // The legend only ever carries the border colour (`fertileBorder`)
        // via `_LegendEntry.color`; 0.16 mirrors
        // `LunarLogColors.fertileBand`'s own fixed alpha over that same
        // border colour (issue #143 review) rather than the painter's old
        // ad-hoc 0.18.
        bandColor: entry.color.withValues(alpha: 0.16),
        opacity: 1,
        diameter: 14,
        child: const SizedBox.shrink(),
      ),
      _LegendSwatchStyle.icon => Icon(entry.icon, size: 14, color: entry.color),
    };
  }

  /// Whether any entry falls within [year]/[month] — scoped to the page
  /// actually being built (issue #312 review of #187/#191: previously
  /// `_displayedYear`/`_displayedMonth`, which only updates once
  /// `onPageChanged` settles, so the banner appeared/disappeared a beat
  /// after the swipe landed), not the whole [entries] stream, so a quiet
  /// month shows the guidance banner even when other months have logged
  /// data.
  bool _monthHasEntries(List<DayEntry> entries, {required int year, required int month}) =>
      entries.any(
        (entry) => entry.localDate.year == year && entry.localDate.month == month,
      );

  /// The symptom-layers control (R2): a collapsed summary row (tap to
  /// expand) over the collapsible chip panel.
  Widget _layersHeader(List<String> layerList, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final summary = layerList.isEmpty
        ? l10n.calendarSymptomLayers
        : l10n.calendarLayersSummary(layerList.map(_displayOf).join(', '));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('symptom-layers-toggle'),
            tooltip: _layersExpanded
                ? l10n.calendarHideSymptomLayers
                : l10n.calendarShowSymptomLayers,
            icon: Icon(_layersExpanded ? Icons.expand_less : Icons.expand_more),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _layersExpanded = !_layersExpanded),
          ),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _layersPanel(Set<String> activeLayers) {
    return Padding(
      key: const ValueKey('symptom-layers-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 0,
        children: [
          for (final tag in kTagTaxonomy)
            FilterChip(
              key: ValueKey('layer-chip-${tag.code}'),
              label: Text(tag.display),
              selected: activeLayers.contains(tag.code),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _toggleLayer(tag.code, activeLayers),
            ),
        ],
      ),
    );
  }

  /// KTD7: with no active estimate, quiet months carry the keep-logging
  /// strip instead of empty bands. Issue #221/A2-12: a long-open cycle no
  /// longer produces its own paused wording here — it stays an
  /// [ActivePrediction] (rolled forward, irregular tier) and renders bands
  /// like any other estimate, so the only caller left of this strip is
  /// [NotEnoughHistory].
  Widget _keepLoggingStrip(ThemeData theme) {
    final message = AppLocalizations.of(context).calendarKeepLogging;
    return Padding(
      key: const ValueKey('keep-logging-strip'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cells({
    required int year,
    required int month,
    required Map<String, DayEntry> byIso,
    required Map<String, ForecastDayCell> forecastByIso,
    required List<ForecastCycle> cycles,
    required LocalDate today,
    required ThemeData theme,
    required LunarLogColors colors,
    required List<String> layerList,
    required List<Color> palette,
    required DayCellMetrics metrics,
  }) {
    final firstOfMonth = LocalDate(year, month, 1);
    final firstOfNext = month == 12
        ? LocalDate(year + 1, 1, 1)
        : LocalDate(year, month + 1, 1);
    final daysInMonth = firstOfNext.difference(firstOfMonth);
    // Issue #160: the grid's week start is the explicit [kFirstDayOfWeek]
    // seam (today Sunday), no longer `weekday % 7` arithmetic.
    final leadingBlanks = leadingBlanksFor(year, month);
    return [
      // #138 (B-23): the blanks before day 1 are layout filler with no
      // meaning — explicitly excluded so no screen reader step lands on
      // them. Keyed per month for direct widget-test lookup (a plain
      // `ExcludeSemantics` count also matches the `Icon`s inside, since
      // every Material `Icon` wraps itself in one).
      for (var blank = 0; blank < leadingBlanks; blank++)
        ExcludeSemantics(
          key: ValueKey('calendar-leading-blank-$year-$month-$blank'),
          child: const SizedBox.shrink(),
        ),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCell(
          firstOfMonth.addDays(day - 1),
          byIso: byIso,
          forecastByIso: forecastByIso,
          cycles: cycles,
          today: today,
          theme: theme,
          colors: colors,
          layerList: layerList,
          palette: palette,
          metrics: metrics,
        ),
    ];
  }

  Widget _dayCell(
    LocalDate date, {
    required Map<String, DayEntry> byIso,
    required Map<String, ForecastDayCell> forecastByIso,
    required List<ForecastCycle> cycles,
    required LocalDate today,
    required ThemeData theme,
    required LunarLogColors colors,
    required List<String> layerList,
    required List<Color> palette,
    required DayCellMetrics metrics,
  }) {
    final iso = date.iso;
    final entry = byIso[iso];
    final isFuture = date.isAfter(today);
    final isToday = date == today;
    // KTD3: a logged day always renders as logged — forecast markers only
    // ever pair a future date that has no entry. `_cellForMode` (issue
    // #143) strips the fertile-window flag when the care mode hides it.
    final forecastCell = _cellForMode(
      entry == null && isFuture ? forecastByIso[iso] : null,
    );
    final bleedLevel = entry != null && isBleed(entry.flow) ? entry.flow : null;
    final selectable = !isFuture && (!_effectiveReadOnly || entry != null);
    final tapHandler = _cellTapHandler(
      selectable: selectable,
      isFuture: isFuture,
      date: date,
      entry: entry,
      forecastCell: forecastCell,
      cycles: cycles,
    );
    // #138: the semantics node wraps the InkWell (not the other way
    // around) so every cell is its own focus stop carrying its label,
    // button, and selected flags — an inert cell (read-only, no entry)
    // has no InkWell tap semantics for a label to merge into, which
    // previously let its label dissolve up into the grid's scroll node.
    // The wrapper carries the same tap handler as the visible InkWell,
    // so screen-reader activation and finger taps run one code path.
    return Semantics(
      // #138 (B-23): only a cell that actually opens something is a
      // button, and today carries the selected flag on top of its
      // label's own "today" fragment.
      button: tapHandler != null,
      selected: isToday,
      label: dayCellSemanticLabel(
        date: date,
        entry: entry,
        today: today,
        cell: forecastCell,
        l10n: AppLocalizations.of(context),
        monthNames: dates.monthNames(locale: dates.calendarLocale(context)),
        weekdayNames: dates.fullWeekdayNames(
          locale: dates.calendarLocale(context),
        ),
        readOnly: _effectiveReadOnly,
        fertileWindowLabel: _copy.fertileWindowLabel,
      ),
      onTap: tapHandler,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('day-cell-$iso'),
        onTap: tapHandler,
        child: _cellColumn(
          date,
          entry: entry,
          bleedLevel: bleedLevel,
          forecastCell: forecastCell,
          isFuture: isFuture,
          isToday: isToday,
          theme: theme,
          colors: colors,
          layerList: layerList,
          palette: palette,
          metrics: metrics,
        ),
      ),
    );
  }

  /// The cell's visual column, split out of [_dayCell] so that method stays
  /// under the quality gate's per-method CRAP cap. #138: the old
  /// `Opacity(futureCellOpacity(...))` layer is gone — the same decision
  /// now drives a text-colour dim on the plain-future day's number only
  /// (`_dayCircle`'s `dimmed`), which does not drag the today ring or any
  /// marker below usable contrast the way a whole-cell 0.35 [Opacity] did.
  Widget _cellColumn(
    LocalDate date, {
    required DayEntry? entry,
    required FlowLevel? bleedLevel,
    required ForecastDayCell? forecastCell,
    required bool isFuture,
    required bool isToday,
    required ThemeData theme,
    required LunarLogColors colors,
    required List<String> layerList,
    required List<Color> palette,
    required DayCellMetrics metrics,
  }) {
    final dimmed = futureCellOpacity(isFuture, forecastCell != null) < 1;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dayCircle(
          date,
          bleedLevel: bleedLevel,
          forecastCell: forecastCell,
          isToday: isToday,
          theme: theme,
          colors: colors,
          metrics: metrics,
          dimmed: dimmed,
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: metrics.markersHeight,
          child: isFuture
              ? _futureMarkers(forecastCell, theme, date.iso)
              : _loggedMarkers(
                  entry,
                  layerList: layerList,
                  palette: palette,
                ),
        ),
      ],
    );
  }

  /// A logged day (or a past day the operator may open) opens the day
  /// sheet; a future day opens the read-only explainer (KTD8); anything
  /// else is inert.
  VoidCallback? _cellTapHandler({
    required bool selectable,
    required bool isFuture,
    required LocalDate date,
    required DayEntry? entry,
    required ForecastDayCell? forecastCell,
    required List<ForecastCycle> cycles,
  }) {
    if (selectable) return () => _openDay(date, entry);
    if (isFuture) return () => _openFutureExplainer(date, forecastCell, cycles);
    return null;
  }

  /// The day-number circle: a `flow*`-ramp-graded fill for a logged bleed
  /// day (key `bleed-<iso>`; issue #191 B-2 — spotting is a ring plus a
  /// small centre dot rather than a full fill, light/medium/heavy climb the
  /// ramp's saturation), a hatched predicted band for a forecast bleed day
  /// (key `predicted-<iso>` — hatched, never filled, KTD3), a dashed
  /// fertile-window ring for a forecast fertile day (key `fertile-<iso>` —
  /// issue #143, a deliberately different pattern from the predicted
  /// band's hatch so the two estimates stay distinguishable without
  /// colour), otherwise a thin primary ring when the cell is today.
  /// [#138] The circle's diameter comes from [DayCellMetrics.circleSize]
  /// (text-scale-aware, floored at the historic 34px) rather than a fixed
  /// 34, so a 200%-scaled day number no longer clips inside it; and a
  /// plain future day's number carries the [#138] dim text colour instead
  /// of sitting under a whole-cell [Opacity].
  Widget _dayCircle(
    LocalDate date, {
    required FlowLevel? bleedLevel,
    required ForecastDayCell? forecastCell,
    required bool isToday,
    required ThemeData theme,
    required LunarLogColors colors,
    required DayCellMetrics metrics,
    required bool dimmed,
  }) {
    final iso = date.iso;
    final level = bleedLevel;
    if (level != null) {
      return _flowCircle(
        date,
        level,
        theme,
        colors,
        isToday: isToday,
        circleSize: metrics.circleSize,
      );
    }
    final label = Text(
      '${date.day}',
      style: dimmed
          ? TextStyle(
              color: theme.colorScheme.onSurface.withValues(
                alpha: kFutureDayTextAlpha,
              ),
            )
          : null,
    );
    final predictedBleed = forecastCell?.predictedBleed ?? false;
    if (predictedBleed) {
      return _HatchedCircle(
        key: ValueKey('predicted-$iso'),
        color: colors.predictedBorder,
        opacity: forecastBandOpacity(forecastCell!.tier),
        borderOpacity: forecastBorderOpacity(forecastCell.tier),
        diameter: metrics.circleSize,
        child: label,
      );
    }
    if (forecastCell?.fertileWindow ?? false) {
      // Issue #143 review: the fertile window's own tier
      // (`fertileTier`), not `tier` — the cell's `tier` belongs to
      // whichever cycle's band/numeral claimed this date first, which can
      // be an earlier, higher-confidence cycle than the one whose fertile
      // window is actually drawn here.
      final fertileTier = forecastCell!.fertileTier ?? forecastCell.tier;
      return _DashedCircle(
        key: ValueKey('fertile-$iso'),
        color: colors.fertileBorder,
        bandColor: colors.fertileBand,
        opacity: forecastBandOpacity(fertileTier),
        borderOpacity: forecastBorderOpacity(fertileTier),
        diameter: metrics.circleSize,
        child: label,
      );
    }
    return Container(
      width: metrics.circleSize,
      height: metrics.circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: label,
    );
  }

  /// The graded fill for one bleed [level] (issue #191 B-2): the `flow*`
  /// ramp token carries the colour channel; [_flowLevelMarkCount] small
  /// dots keyed `flow-level-<level>-<iso>` carry a second, non-colour
  /// channel (1 dot for spotting climbing to 4 for heavy) so the same
  /// distinction survives for an operator who can't rely on hue alone.
  /// Spotting additionally renders as a ring plus a small centre dot,
  /// never a full fill, per the issue's own proposed design. Issue #312
  /// review of #191: [isToday] now draws the same outer ring the plain
  /// (no-bleed) today cell and the legend's "Today" swatch already use —
  /// previously a bleed day dropped it entirely, the ring the legend
  /// advertises never actually showing on a day that was both logged and
  /// today.
  Widget _flowCircle(
    LocalDate date,
    FlowLevel level,
    ThemeData theme,
    LunarLogColors colors, {
    required bool isToday,
    required double circleSize,
  }) {
    final iso = date.iso;
    final tone = _flowTone(level, colors);
    // Issue #247: unreachable in practice now (the `isBleed` gate above
    // this widget's only caller never passes the deprecated `spotting`
    // alias through), kept only so this comparison still compiles against
    // every FlowLevel value without a runtime branch this file can't test.
    // ignore: deprecated_member_use_from_same_package
    final isSpotting = level == FlowLevel.spotting;
    final textColor = isSpotting ? theme.colorScheme.onSurface : tone.onFill;
    // Issue #312 review: `textColor` (onSurface) sits directly over the
    // 8px spotting centre dot, and in dark mode the two can land close
    // enough in luminance that the digit is unreadable where its glyph
    // crosses the dot — `flowSpotting` is only solved against
    // `surfaceContainerLow`, not against `onSurface` text on top of it. A
    // thin `surface`-coloured halo behind the numeral keeps it legible
    // regardless of what colour happens to sit underneath.
    final numeral = isSpotting
        ? _haloedDayNumber(
            '${date.day}',
            theme.textTheme.bodyMedium,
            textColor,
            theme.colorScheme.surface,
          )
        : DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: Text('${date.day}'),
          );
    // Issue #312 (BLOCKING — today-ring overflow): the ring must stay
    // within the same outer box the plain (no-bleed) today cell already
    // uses (`_dayCircle`) — the fill circle shrinks by 4px so the ring
    // itself can draw on an unchanged outer box below without growing the
    // cell. #138: both sizes now derive from the text-scale-aware
    // [circleSize] instead of the fixed 34/30 pair, preserving the same
    // 4px inset at every scale.
    final innerSize = isToday ? circleSize - 4 : circleSize;
    final circle = Container(
      key: ValueKey('bleed-$iso'),
      width: innerSize,
      height: innerSize,
      decoration: isSpotting
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tone.fill, width: 2),
            )
          : BoxDecoration(shape: BoxShape.circle, color: tone.fill),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isSpotting)
            Container(
              key: ValueKey('flow-spotting-dot-$iso'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.fill),
            ),
          numeral,
          Positioned(
            bottom: 3,
            child: Row(
              key: ValueKey('flow-level-${level.name}-$iso'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _flowLevelMarkCount(level); i++)
                  Container(
                    key: ValueKey('flow-mark-$i-$iso'),
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: textColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!isToday) return circle;
    return Container(
      key: ValueKey('today-ring-$iso'),
      width: circleSize,
      height: circleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.primary, width: 1.5),
      ),
      child: circle,
    );
  }

  /// Markers under a future day's number: the PMS and cramps badges
  /// (fixed offsets off the estimate, KTD7) and the cycle-day numeral
  /// (first predicted cycle only, KTD5).
  Widget? _futureMarkers(ForecastDayCell? cell, ThemeData theme, String iso) {
    if (cell == null) return null;
    final brightness = theme.brightness;
    return Row(
      key: ValueKey('future-markers-$iso'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (cell.pmsBadge)
          Icon(
            Icons.spa,
            key: ValueKey('pms-badge-$iso'),
            size: 12,
            color: pmsBadgeColor(brightness),
          ),
        if (cell.crampsBadge)
          Icon(
            Icons.bolt,
            key: ValueKey('cramps-badge-$iso'),
            size: 12,
            color: crampsBadgeColor(brightness),
          ),
        if (cell.cycleDayNumber != null)
          Text(
            '${cell.cycleDayNumber}',
            key: ValueKey('cycle-day-numeral-$iso'),
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
      ],
    );
  }

  /// Markers under a logged day's number: one colored dot per active layer
  /// the day carries, falling back to the generic symptom-only dot (a
  /// symptom-only day never renders completely bare).
  Widget? _loggedMarkers(
    DayEntry? entry, {
    required List<String> layerList,
    required List<Color> palette,
  }) {
    if (entry == null) return null;
    final iso = entry.localDate.iso;
    final matching = <(String, Color)>[
      for (var i = 0; i < layerList.length; i++)
        if (layerMatches(entry, layerList[i]))
          (layerList[i], palette[i.clamp(0, palette.length - 1)]),
    ];
    if (matching.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (tag, color) in matching)
            Container(
              key: ValueKey('layer-dot-$tag-$iso'),
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
        ],
      );
    }
    // Issue #249: pain_free is a positive "none today" assertion, never a
    // symptom — it cannot earn the symptom-only dot by itself.
    final symptomOnly =
        !isBleed(entry.flow) &&
        (hasSymptomTags(entry.tags) || entry.note != null);
    if (!symptomOnly) return null;
    return Container(
      key: ValueKey('symptom-dot-$iso'),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The same token the legend's 'Symptom day' swatch draws (#176's
        // symptomDot, solved for >= 3:1 against surface) so the legend keys
        // the mark it actually explains (review finding on #191).
        color: Theme.of(context).extension<LunarLogColors>()?.symptomDot ??
            LunarLogColors.forColorScheme(Theme.of(context).colorScheme)
                .symptomDot,
      ),
    );
  }
}

String _displayOf(String code) => tagByCode(code)?.display ?? code;

/// A predicted bleed band: a circle outlined and hatched in [color] at
/// [opacity] (confidence-appropriate weight), never solidly filled — the
/// hatched-vs-filled split against logged bleed days is the at-a-glance
/// estimated/factual distinction (KTD3), in both themes.
class _HatchedCircle extends StatelessWidget {
  const _HatchedCircle({
    super.key,
    required this.color,
    required this.opacity,
    required this.child,
    this.diameter = 34,
    double? borderOpacity,
  }) : borderOpacity = borderOpacity ?? opacity;

  final Color color;
  final double opacity;
  final Widget child;

  /// Defaults to the grid cell's own 34px circle; the legend swatch
  /// (issue #191) passes a smaller value for the same hatch pattern.
  final double diameter;

  /// The ring's own alpha, independent of [opacity] (issue #312, review of
  /// #191 KTD4): only the outer stroke needs [forecastBorderOpacity]'s
  /// floor to stay legible at low confidence tiers; the hatch fill lines
  /// keep the full tier-weighted [opacity]. Defaults to [opacity] (the
  /// legend swatch's constant `opacity: 1` call site is unaffected either
  /// way).
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HatchPainter(color: color, opacity: opacity, borderOpacity: borderOpacity),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(child: child),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({
    required this.color,
    required this.opacity,
    required this.borderOpacity,
  });

  final Color color;
  final double opacity;
  final double borderOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final hatchTint = color.withValues(alpha: opacity);
    final ring = Paint()
      ..color = color.withValues(alpha: borderOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final line = Paint()
      ..color = hatchTint
      ..strokeWidth = 1.5;
    final radius = size.shortestSide / 2;
    canvas.drawCircle(size.center(Offset.zero), radius, ring);
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    const step = 4.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.borderOpacity != borderOpacity;
}

/// A fertile-window calendar cell (issue #143): a faint circular wash plus
/// a *dashed* ring, deliberately not the predicted band's solid hatch —
/// the two estimates need to stay distinguishable without relying on
/// [LunarLogColors.fertileBorder] vs. [LunarLogColors.predictedBorder]
/// alone (same non-colour-channel rule [_HatchedCircle] follows).
class _DashedCircle extends StatelessWidget {
  const _DashedCircle({
    super.key,
    required this.color,
    required this.bandColor,
    required this.opacity,
    required this.child,
    this.diameter = 34,
    double? borderOpacity,
  }) : borderOpacity = borderOpacity ?? opacity;

  final Color color;

  /// The fill wash colour (issue #143 review): [LunarLogColors.fertileBand]
  /// — its own low-chroma token, not an ad-hoc alpha scaled off [color] —
  /// mirroring how [_HatchedCircle] would use [LunarLogColors.predictedBand]
  /// if that sibling token were wired the same way.
  final Color bandColor;
  final double opacity;
  final Widget child;

  /// Defaults to the grid cell's own 34px circle; the legend swatch passes
  /// a smaller value, mirroring [_HatchedCircle.diameter].
  final double diameter;

  /// The dashed ring's own alpha, independent of [opacity] — mirrors
  /// [_HatchedCircle.borderOpacity]'s confidence-floor reasoning.
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(
        color: color,
        bandColor: bandColor,
        opacity: opacity,
        borderOpacity: borderOpacity,
      ),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(child: child),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({
    required this.color,
    required this.bandColor,
    required this.opacity,
    required this.borderOpacity,
  });

  final Color color;
  final Color bandColor;
  final double opacity;
  final double borderOpacity;

  /// How many dash segments make up the ring, and what fraction of each
  /// segment is drawn (the remainder is the gap) — a fixed, named pattern
  /// so the dashes read the same at every cell size.
  static const int _dashCount = 10;
  static const double _dashFraction = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    // Issue #143 review: [bandColor] (`LunarLogColors.fertileBand`) already
    // carries its own fixed low-chroma alpha — scale that by the
    // confidence-tier `opacity` rather than re-deriving a wash alpha from
    // [color] with an ad-hoc constant.
    final wash = Paint()
      ..color = bandColor.withValues(alpha: bandColor.a * opacity);
    canvas.drawCircle(center, radius, wash);
    final dash = Paint()
      ..color = color.withValues(alpha: borderOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final segment = 2 * math.pi / _dashCount;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < _dashCount; i++) {
      canvas.drawArc(rect, segment * i, segment * _dashFraction, false, dash);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.bandColor != bandColor ||
      oldDelegate.opacity != opacity ||
      oldDelegate.borderOpacity != borderOpacity;
}

/// The read-only explainer for a tapped future cell (KTD8): what is
/// predicted for the date and why, with the fixed non-medical disclaimer.
/// Never a logging surface.
class _FutureDayExplainer extends StatelessWidget {
  const _FutureDayExplainer({
    required this.date,
    required this.cell,
    required this.cycles,
    required this.copy,
  });

  final LocalDate date;
  final ForecastDayCell? cell;
  final List<ForecastCycle> cycles;

  /// The mounting calendar's care-mode vocabulary (issue #143 review): the
  /// fertile-window explainer sentence names [CareModeCopy.fertileWindowLabel]
  /// rather than a hardcoded "estimated fertile window" phrase, so `teen`'s
  /// plainer wording matches what the Analysis tab and legend already say.
  final CareModeCopy copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        key: const ValueKey('future-explainer'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dates.formatMonthDayYear(
                DateTime(date.year, date.month, date.day),
                locale: dates.calendarLocale(context),
              ),
              key: const ValueKey('future-explainer-date'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._body(theme, AppLocalizations.of(context)),
            const SizedBox(height: 16),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('future-explainer-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(ThemeData theme, AppLocalizations l10n) {
    final body = theme.textTheme.bodyMedium;
    if (cycles.isEmpty) {
      return [
        Text(
          l10n.futureExplainerNoEstimate,
          key: const ValueKey('future-explainer-no-estimate'),
          style: body,
        ),
      ];
    }
    final cell = this.cell;
    if (cell == null) {
      return [
        Text(
          l10n.futureExplainerNone,
          key: const ValueKey('future-explainer-none'),
          style: body,
        ),
      ];
    }
    final spread = _spreadFor(cell);
    return [
      if (cell.predictedBleed)
        Text(
          cell.cycleDayNumber == null
              ? l10n.futureExplainerBand(spread)
              : l10n.futureExplainerBandWithCycleDay(cell.cycleDayNumber!, spread),
          key: const ValueKey('future-explainer-band'),
          style: body,
        ),
      if (cell.pmsBadge)
        Text(
          l10n.futureExplainerPms,
          key: const ValueKey('future-explainer-pms'),
          style: body,
        ),
      if (cell.crampsBadge)
        Text(
          l10n.futureExplainerCramps,
          key: const ValueKey('future-explainer-cramps'),
          style: body,
        ),
      ..._fertileWindowExplainer(cell, body),
      if (cell.cycleDayNumber != null && !cell.predictedBleed)
        Text(
          l10n.futureExplainerNumeral(cell.cycleDayNumber!),
          key: const ValueKey('future-explainer-numeral'),
          style: body,
        ),
      const SizedBox(height: 8),
      Text(
        l10n.futureExplainerConfidence(_confidenceLabel(cell).toLowerCase()),
        key: const ValueKey('future-explainer-confidence'),
        style: body,
      ),
    ];
  }

  int _spreadFor(ForecastDayCell cell) => cycles.isEmpty
      ? 0
      : cycles[cell.cycleIndex.clamp(0, cycles.length - 1)].spreadDays;

  /// The confidence label this explainer's bottom line names (issue #143
  /// review): for a fertile-window day, [ForecastDayCell.fertileTier] —
  /// the fertile window's own source cycle, which can differ from
  /// [ForecastDayCell.tier] (the cycle whose band/numeral claimed this
  /// date first, see [ForecastDayCell.fertileTier]'s own doc comment) —
  /// rather than always the cell's general [ForecastDayCell.tier]. A day
  /// that is *also* a predicted-bleed day keeps [ForecastDayCell.tier]:
  /// that band is this cell's primary content, and (per
  /// `fertile_window.dart`'s own doc comment) a fertile window never
  /// actually overlaps its own cycle's bleed band in practice.
  String _confidenceLabel(ForecastDayCell cell) {
    final tier = cell.predictedBleed || !cell.fertileWindow
        ? cell.tier
        : (cell.fertileTier ?? cell.tier);
    return tier.label;
  }

  /// Split out of [_body] (issue #143) purely to keep that method's own
  /// branch count under the quality gate's per-method CRAP cap, same
  /// reasoning as every other `_split out of` helper in this file. Empty
  /// when the cell carries no fertile-window flag (already care-mode-gated
  /// upstream by `_MonthCalendarState._cellForMode`, so this never needs a
  /// second gate of its own). Names [copy]'s own [CareModeCopy
  /// .fertileWindowLabel] (issue #143 review) rather than a hardcoded
  /// "estimated fertile window" phrase, so `teen`'s plainer wording is
  /// used here too.
  List<Widget> _fertileWindowExplainer(ForecastDayCell cell, TextStyle? body) {
    if (!cell.fertileWindow) return const [];
    return [
      Text(
        '${copy.fertileWindowLabel} — the days around estimated ovulation, '
        'back-calculated from the predicted period date.',
        key: const ValueKey('future-explainer-fertile'),
        style: body,
      ),
      Text(
        kFertileWindowDisclaimer,
        key: const ValueKey('future-explainer-fertile-disclaimer'),
        style: body,
      ),
    ];
  }
}

/// The month/year picker sheet (issue #191): tapping the month label opens
/// this instead of six-tap chevron navigation. Bounded by [maxMonthIndex]
/// (the same forward limit the chevron's `nextDisabled` already enforces)
/// so a month past today + [kForwardMonthLimit] can never be selected;
/// there is no backward bound, matching the chevrons' own unlimited past
/// navigation. Pops the chosen `(year, month)`, or nothing if dismissed.
class _MonthYearPickerSheet extends StatefulWidget {
  const _MonthYearPickerSheet({
    required this.initialYear,
    required this.initialMonth,
    required this.maxMonthIndex,
  });

  final int initialYear;
  final int initialMonth;
  final int maxMonthIndex;

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
  }

  bool _monthDisabled(int month) =>
      _monthIndex(_year, month) > widget.maxMonthIndex;

  void _shiftYear(int delta) => setState(() => _year += delta);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final nextYearDisabled = _monthIndex(_year + 1, 1) > widget.maxMonthIndex;
    return SafeArea(
      child: Padding(
        key: const ValueKey('month-year-picker'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('month-picker-prev-year'),
                  tooltip: l10n.monthPickerPreviousYear,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftYear(-1),
                ),
                Text(
                  '$_year',
                  key: const ValueKey('month-picker-year'),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  key: const ValueKey('month-picker-next-year'),
                  tooltip: l10n.monthPickerNextYear,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: nextYearDisabled ? null : () => _shiftYear(1),
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: 3,
              // Button-shaped cells, not square tiles (issue #191 review):
              // the default 1:1 ratio made four rows of a 12-month grid
              // tall enough to overflow a phone-height sheet.
              childAspectRatio: 2.4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var month = 1; month <= 12; month++) _monthButton(month),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthButton(int month) {
    final disabled = _monthDisabled(month);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: OutlinedButton(
        key: ValueKey('month-picker-$_year-$month'),
        onPressed: disabled
            ? null
            : () => Navigator.of(context).pop((_year, month)),
        child: Text(
          dates.shortMonthNames(
            locale: dates.calendarLocale(context),
          )[month - 1],
        ),
      ),
    );
  }
}
