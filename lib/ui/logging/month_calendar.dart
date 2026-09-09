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
/// [FlowLevel] with the #176 `flow*` ramp tokens (spotting a ring + centre
/// dot, light/medium/heavy climbing the ramp's saturation), plus a
/// non-colour dot-count channel so the same distinction survives without
/// colour; a legend strip keys every mark the grid can show; the month
/// grid is a swipeable [PageView] (the chevrons drive the same
/// controller); a "Today" header action jumps to and highlights the
/// current month; and tapping the month label opens a month/year picker
/// sheet bounded by the same forward limit the chevron already enforced.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
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
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart'
    show kEstimateDisclaimer;
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

const List<String> kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> kWeekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// Forward navigation may move at most this many months past the current
/// one (R1); [kForecastHorizonMonths] in the forecast module covers it.
const int kForwardMonthLimit = kForecastHorizonMonths;

/// Confidence-appropriate band weight (KTD4): a hatched band's opacity by
/// its cycle's tier. `high` reads strongest, `irregular` faintest — and
/// every cycle past the first has already stepped down one tier, so bands
/// fade with distance too.
double forecastBandOpacity(CycleConfidence tier) => switch (tier) {
  CycleConfidence.high => 0.9,
  CycleConfidence.learning => 0.6,
  CycleConfidence.irregular => 0.35,
};

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

/// A logged bleed [level]'s fill/on-fill pair from the #176 `flow*` ramp
/// (issue #191 B-2). `spotting`'s `fill` doubles as its ring/centre-dot
/// colour in [_MonthCalendarState._flowCircle] — it never fills the whole
/// circle. [_MonthCalendarState._dayCircle] only ever calls this with a
/// bleed level (`isBleed(level)`, which excludes `none`); `none` shares
/// spotting's case rather than adding a branch no caller can reach.
({Color fill, Color onFill}) _flowTone(FlowLevel level, LunarLogColors colors) =>
    switch (level) {
      FlowLevel.none || FlowLevel.spotting => (
        fill: colors.flowSpotting,
        onFill: colors.onFlowSpotting,
      ),
      FlowLevel.light => (fill: colors.flowLight, onFill: colors.onFlowLight),
      FlowLevel.medium => (fill: colors.flowMedium, onFill: colors.onFlowMedium),
      FlowLevel.heavy => (fill: colors.flowHeavy, onFill: colors.onFlowHeavy),
    };

/// The non-colour intensity channel (issue #191 B-2): a small dot count
/// climbing from 1 (spotting) to 4 (heavy), independent of the `flow*`
/// ramp's hue/saturation — asserted directly in widget tests via the
/// `flow-mark-<i>-<iso>` keys [_MonthCalendarState._flowCircle] renders.
/// See [_flowTone] on why `none` shares spotting's case.
int _flowLevelMarkCount(FlowLevel level) => switch (level) {
  FlowLevel.none || FlowLevel.spotting => 1,
  FlowLevel.light => 2,
  FlowLevel.medium => 3,
  FlowLevel.heavy => 4,
};

Color pmsBadgeColor(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFF5E35B1)
    : const Color(0xFFB39DDB);

Color crampsBadgeColor(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFF9A6A00)
    : const Color(0xFFFFCC80);

String _formatDate(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}, ${date.year}';

/// The semantic (screen-reader) label for one day cell (#133 brief: the
/// predicted/logged distinction must be semantic, not just visual). Public
/// for direct testing; the calendar wraps every cell's contents with it.
String dayCellSemanticLabel({
  required LocalDate date,
  required DayEntry? entry,
  required LocalDate today,
  required ForecastDayCell? cell,
}) {
  if (!date.isAfter(today)) return _loggedDaySemanticLabel(date, entry);
  final safeCell = cell;
  return safeCell == null
      ? '${_dateLabel(date)}, future date, not yet loggable'
      : _predictedDaySemanticLabel(date, safeCell);
}

String _dateLabel(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}';

String _loggedDaySemanticLabel(LocalDate date, DayEntry? entry) {
  final label = _dateLabel(date);
  if (entry == null) return '$label, not logged';
  if (isBleed(entry.flow)) return '$label, logged period day';
  if (entry.tags.isNotEmpty || entry.note != null) {
    return '$label, logged symptoms';
  }
  return '$label, logged';
}

String _predictedDaySemanticLabel(LocalDate date, ForecastDayCell cell) {
  final parts = <String>[
    if (cell.predictedBleed)
      'predicted period day'
          '${cell.cycleDayNumber == null ? '' : ', cycle day ${cell.cycleDayNumber}'}',
    if (!cell.predictedBleed && cell.cycleDayNumber != null)
      'cycle day ${cell.cycleDayNumber} of the first predicted cycle',
    if (cell.pmsBadge) 'predicted premenstrual window',
    if (cell.crampsBadge) 'predicted cramps window',
  ];
  if (parts.isEmpty) parts.add('no prediction for this date');
  return '${_dateLabel(date)}, ${parts.join(', ')}';
}

int _monthIndex(int year, int month) => year * 12 + (month - 1);

/// How [_MonthCalendarState._legendSwatch] draws one legend entry's swatch
/// — mirrors the three shapes the grid itself uses so the legend key
/// actually matches what a cell renders (a plain fill, spotting/today's
/// ring, or #133's hatched predicted band).
enum _LegendSwatchStyle { fill, ring, hatched }

/// One row of the legend strip (issue #191; B-2, B-11): a swatch plus its
/// label, keyed by [code] (`legend-<code>`) for direct widget-test lookup.
class _LegendEntry {
  const _LegendEntry(
    this.code,
    this.color,
    this.label, {
    this.style = _LegendSwatchStyle.fill,
  });

  final String code;
  final Color color;
  final String label;
  final _LegendSwatchStyle style;
}

class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.profileId,
    this.readOnly = false,
    this.mode = ProfileMode.standard,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.guardiansRepository,
  });

  final String profileId;
  final bool readOnly;

  /// The profile's care mode (Issue #131): forwarded to [DaySheet] for its
  /// category headings and surfacing order. Presentation only.
  final ProfileMode mode;

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
  late Stream<List<DayEntry>> _entriesStream;
  int _displayedYear = 1970;
  int _displayedMonth = 1;

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

  /// Swipe navigation (issue #191): one page per month, indexed by
  /// [_pageIndexFor]/[_monthForPageIndex] against a fixed epoch offset so
  /// page indices never go negative for any real calendar year.
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _repository = context.read<DayEntriesRepository>();
    _entriesStream = _repository.watchForProfile(widget.profileId);
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
      _entriesStream = _repository.watchForProfile(widget.profileId);
      _rewatchPrediction();
      _watchGuardians();
      _resetToTodaysMonth();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(
          _pageIndexFor(_displayedYear, _displayedMonth),
        );
      }
    }
  }

  @override
  void dispose() {
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
    final (year, month) = _monthForPageIndex(pageIndex);
    if (year == _displayedYear && month == _displayedMonth) return;
    setState(() {
      _displayedYear = year;
      _displayedMonth = month;
    });
  }

  /// Programmatic navigation to one specific month (chevrons, Today, and
  /// the month/year picker all funnel through this): updates the display
  /// state immediately and drives [_pageController] to match, animated for
  /// the one-page chevron step and instant (a jump) for the
  /// possibly-many-pages-away Today/picker destinations.
  void _goToMonth(int year, int month, {required bool animate}) {
    final page = _pageIndexFor(year, month);
    if (animate) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(page);
    }
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
      builder: (_) =>
          _FutureDayExplainer(date: date, cell: cell, cycles: cycles),
    );
  }

  void _toggleLayer(String code, Set<String> current) {
    final selected = current.contains(code);
    if (!selected && current.length >= kMaxSymptomLayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey('layer-limit-snack'),
          content: Text('Up to three symptom layers at once'),
          duration: Duration(seconds: 2),
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
    return StreamBuilder<List<DayEntry>>(
      stream: _entriesStream,
      builder: (context, snapshot) {
        final entries = snapshot.data;
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
    final forecastByIso = forecastDayCells(cycles: cycles, today: today);
    final activeLayers = _layersUserSet
        ? _activeLayers
        : {for (final tag in defaultLayerTags(entries)) tag};
    final layerList = activeLayers.toList(growable: false);
    final palette = symptomLayerPalette(theme.brightness);
    final maxPageIndex =
        _pageIndexFor(today.year, today.month) + kForwardMonthLimit;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftMonth(-1),
            ),
            Expanded(
              child: InkWell(
                key: const ValueKey('month-year-label'),
                onTap: _openMonthYearPicker,
                child: Center(
                  child: Text(
                    '${kMonthNames[_displayedMonth - 1]} $_displayedYear',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('today-button'),
              tooltip: 'Today',
              icon: const Icon(Icons.today_outlined),
              onPressed: _goToToday,
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: nextDisabled ? null : () => _shiftMonth(1),
            ),
          ],
        ),
        _legendStrip(theme, colors),
        _layersHeader(layerList, theme),
        if (_layersExpanded) _layersPanel(activeLayers),
        Padding(
          key: const ValueKey('calendar-weekday-header'),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final label in kWeekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(label, style: theme.textTheme.labelSmall),
                  ),
                ),
            ],
          ),
        ),
        if (!estimateActive) _keepLoggingStrip(theme),
        // Issue #187 (B-8): a month with zero entries otherwise renders as
        // a silent grid of bare day numbers with no guidance. The grid
        // itself stays fully tappable (its cell/forecast rendering is
        // #133/#191's, untouched here) — this is an explanatory banner
        // above it, not a replacement, so logging any day in the empty
        // month still works exactly as it did before this issue.
        if (!_monthHasEntries(entries))
          const EmptyState(
            key: ValueKey('calendar-month-empty'),
            title: 'No entries this month',
            body: 'Tap a day to log it',
          ),
        Expanded(
          child: PageView.builder(
            key: const ValueKey('calendar-page-view'),
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: maxPageIndex + 1,
            itemBuilder: (context, pageIndex) {
              final (year, month) = _monthForPageIndex(pageIndex);
              return SingleChildScrollView(
                child: GridView.count(
                  key: ValueKey('calendar-grid-$year-$month'),
                  crossAxisCount: 7,
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
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The legend strip under the month header (issue #191; B-2, B-11): keys
  /// every mark the grid can show — the four logged flow levels, a
  /// symptom-only day, today's ring, and #133's predicted band — so the
  /// colour-graded fills and the hatched forecast are readable without
  /// having to guess what a swatch means.
  Widget _legendStrip(ThemeData theme, LunarLogColors colors) {
    // Labels say "... flow"/"day" rather than the bare `flowLabel(level)`
    // strings `DaySheet`'s flow chips use (issue #191 review): the day
    // sheet renders as a modal over this still-mounted calendar, so a bare
    // "Medium"/"Heavy" here would collide with `find.text` in every widget
    // test that opens it with a chip selected.
    final entries = [
      _LegendEntry('spotting', colors.flowSpotting, 'Spotting flow', style: _LegendSwatchStyle.ring),
      _LegendEntry('light', colors.flowLight, 'Light flow'),
      _LegendEntry('medium', colors.flowMedium, 'Medium flow'),
      _LegendEntry('heavy', colors.flowHeavy, 'Heavy flow'),
      _LegendEntry('symptom', colors.symptomDot, 'Symptom day'),
      _LegendEntry('today', theme.colorScheme.primary, 'Today', style: _LegendSwatchStyle.ring),
      _LegendEntry('predicted', colors.predictedBorder, 'Predicted day', style: _LegendSwatchStyle.hatched),
    ];
    return Padding(
      key: const ValueKey('calendar-legend'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [for (final entry in entries) _legendChip(entry, theme)],
      ),
    );
  }

  Widget _legendChip(_LegendEntry entry, ThemeData theme) {
    return Row(
      key: ValueKey('legend-${entry.code}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendSwatch(entry),
        const SizedBox(width: 4),
        Text(entry.label, style: theme.textTheme.labelSmall),
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
    };
  }

  /// Whether any entry falls within the displayed month (issue #187) —
  /// scoped to `_displayedYear`/`_displayedMonth`, not the whole [entries]
  /// stream, so navigating to a quiet month shows the guidance banner even
  /// when other months have logged data.
  bool _monthHasEntries(List<DayEntry> entries) => entries.any(
        (entry) =>
            entry.localDate.year == _displayedYear &&
            entry.localDate.month == _displayedMonth,
      );

  /// The symptom-layers control (R2): a collapsed summary row (tap to
  /// expand) over the collapsible chip panel.
  Widget _layersHeader(List<String> layerList, ThemeData theme) {
    final summary = layerList.isEmpty
        ? 'Symptom layers'
        : 'Layers: ${layerList.map(_displayOf).join(', ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('symptom-layers-toggle'),
            tooltip: _layersExpanded
                ? 'Hide symptom layers'
                : 'Show symptom layers',
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
    const message =
        'Keep logging — predicted bands appear once a few cycles are '
        'recorded.';
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
  }) {
    final firstOfMonth = LocalDate(year, month, 1);
    final firstOfNext = month == 12
        ? LocalDate(year + 1, 1, 1)
        : LocalDate(year, month + 1, 1);
    final daysInMonth = firstOfNext.difference(firstOfMonth);
    // DateTime.weekday is 1=Monday..7=Sunday; the grid starts on Sunday.
    final leadingBlanks = DateTime(year, month, 1).weekday % 7;
    return [
      for (var blank = 0; blank < leadingBlanks; blank++)
        const SizedBox.shrink(),
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
  }) {
    final iso = date.iso;
    final entry = byIso[iso];
    final isFuture = date.isAfter(today);
    // KTD3: a logged day always renders as logged — forecast markers only
    // ever pair a future date that has no entry.
    final forecastCell = entry == null && isFuture ? forecastByIso[iso] : null;
    final bleedLevel = entry != null && isBleed(entry.flow) ? entry.flow : null;
    final selectable = !isFuture && (!_effectiveReadOnly || entry != null);
    return InkWell(
      key: ValueKey('day-cell-$iso'),
      onTap: _cellTapHandler(
        selectable: selectable,
        isFuture: isFuture,
        date: date,
        entry: entry,
        forecastCell: forecastCell,
        cycles: cycles,
      ),
      child: Semantics(
        label: dayCellSemanticLabel(
          date: date,
          entry: entry,
          today: today,
          cell: forecastCell,
        ),
        excludeSemantics: true,
        child: Opacity(
          opacity: futureCellOpacity(isFuture, forecastCell != null),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dayCircle(
                date,
                bleedLevel: bleedLevel,
                forecastCell: forecastCell,
                isToday: date == today,
                theme: theme,
                colors: colors,
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 14,
                child: isFuture
                    ? _futureMarkers(forecastCell, theme, iso)
                    : _loggedMarkers(
                        entry,
                        layerList: layerList,
                        palette: palette,
                      ),
              ),
            ],
          ),
        ),
      ),
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
  /// (key `predicted-<iso>` — hatched, never filled, KTD3), otherwise a
  /// thin primary ring when the cell is today.
  Widget _dayCircle(
    LocalDate date, {
    required FlowLevel? bleedLevel,
    required ForecastDayCell? forecastCell,
    required bool isToday,
    required ThemeData theme,
    required LunarLogColors colors,
  }) {
    final iso = date.iso;
    final label = Text('${date.day}');
    final level = bleedLevel;
    if (level != null) {
      return _flowCircle(iso, level, label, theme, colors);
    }
    final predictedBleed = forecastCell?.predictedBleed ?? false;
    if (predictedBleed) {
      return _HatchedCircle(
        key: ValueKey('predicted-$iso'),
        color: colors.predictedBorder,
        opacity: forecastBandOpacity(forecastCell!.tier),
        child: label,
      );
    }
    return Container(
      width: 34,
      height: 34,
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
  /// never a full fill, per the issue's own proposed design.
  Widget _flowCircle(
    String iso,
    FlowLevel level,
    Widget dayLabel,
    ThemeData theme,
    LunarLogColors colors,
  ) {
    final tone = _flowTone(level, colors);
    final isSpotting = level == FlowLevel.spotting;
    final textColor = isSpotting ? theme.colorScheme.onSurface : tone.onFill;
    return Container(
      key: ValueKey('bleed-$iso'),
      width: 34,
      height: 34,
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
          DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: dayLabel,
          ),
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
    final symptomOnly =
        !isBleed(entry.flow) && (entry.tags.isNotEmpty || entry.note != null);
    if (!symptomOnly) return null;
    return Container(
      key: ValueKey('symptom-dot-$iso'),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.tertiary,
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
  });

  final Color color;
  final double opacity;
  final Widget child;

  /// Defaults to the grid cell's own 34px circle; the legend swatch
  /// (issue #191) passes a smaller value for the same hatch pattern.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HatchPainter(color: color, opacity: opacity),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(child: child),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final tinted = color.withValues(alpha: opacity);
    final ring = Paint()
      ..color = tinted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final line = Paint()
      ..color = tinted
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
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}

/// The read-only explainer for a tapped future cell (KTD8): what is
/// predicted for the date and why, with the fixed non-medical disclaimer.
/// Never a logging surface.
class _FutureDayExplainer extends StatelessWidget {
  const _FutureDayExplainer({
    required this.date,
    required this.cell,
    required this.cycles,
  });

  final LocalDate date;
  final ForecastDayCell? cell;
  final List<ForecastCycle> cycles;

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
              _formatDate(date),
              key: const ValueKey('future-explainer-date'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._body(theme),
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

  List<Widget> _body(ThemeData theme) {
    final body = theme.textTheme.bodyMedium;
    if (cycles.isEmpty) {
      return [
        Text(
          'No estimates yet — keep logging. Predicted bands appear on the '
          'calendar once a few cycles are recorded.',
          key: const ValueKey('future-explainer-no-estimate'),
          style: body,
        ),
      ];
    }
    final cell = this.cell;
    if (cell == null) {
      return [
        Text(
          'No prediction for this date. Days can be logged once they '
          'arrive.',
          key: const ValueKey('future-explainer-none'),
          style: body,
        ),
      ];
    }
    final spread = _spreadFor(cell);
    return [
      if (cell.predictedBleed)
        Text(
          'Predicted period day'
          '${cell.cycleDayNumber == null ? '' : ' — cycle day ${cell.cycleDayNumber} of the first predicted cycle'}. '
          'The date may shift by about $spread day${spread == 1 ? '' : 's'} '
          'either way as new periods are logged.',
          key: const ValueKey('future-explainer-band'),
          style: body,
        ),
      if (cell.pmsBadge)
        Text(
          'Inside the predicted premenstrual window — symptoms like mood '
          'shifts and bloating often show up in the week before a period.',
          key: const ValueKey('future-explainer-pms'),
          style: body,
        ),
      if (cell.crampsBadge)
        Text(
          'Inside the predicted cramps window — cramps commonly occur '
          'within two days of a period start.',
          key: const ValueKey('future-explainer-cramps'),
          style: body,
        ),
      if (cell.cycleDayNumber != null && !cell.predictedBleed)
        Text(
          'Cycle day ${cell.cycleDayNumber} of the first predicted cycle. '
          'Only the first predicted cycle is counted day by day — '
          'estimates compound too much further out.',
          key: const ValueKey('future-explainer-numeral'),
          style: body,
        ),
      const SizedBox(height: 8),
      Text(
        'Estimate confidence: ${cell.tier.label.toLowerCase()}.',
        key: const ValueKey('future-explainer-confidence'),
        style: body,
      ),
    ];
  }

  int _spreadFor(ForecastDayCell cell) => cycles.isEmpty
      ? 0
      : cycles[cell.cycleIndex.clamp(0, cycles.length - 1)].spreadDays;
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
                  tooltip: 'Previous year',
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
                  tooltip: 'Next year',
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
        child: Text(kMonthNames[month - 1].substring(0, 3)),
      ),
    );
  }
}
