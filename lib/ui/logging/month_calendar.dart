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
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart'
    show kEstimateDisclaimer;
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
    _historyStream = _historyService?.watch(widget.profileId);
  }

  @override
  void didUpdateWidget(MonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _entriesStream = _repository.watchForProfile(widget.profileId);
      _rewatchPrediction();
      _watchGuardians();
      _resetToTodaysMonth();
    }
  }

  @override
  void dispose() {
    _guardiansSub?.cancel();
    _guardiansSub = null;
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
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

  void _shiftMonth(int delta) {
    setState(() {
      final index = _monthIndex(_displayedYear, _displayedMonth) + delta;
      _displayedYear = index ~/ 12;
      _displayedMonth = index % 12 + 1;
    });
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
                    ? deriveCycleHistoryFromEntries(entries: entries)
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

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftMonth(-1),
            ),
            Text(
              '${kMonthNames[_displayedMonth - 1]} $_displayedYear',
              style: theme.textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: nextDisabled ? null : () => _shiftMonth(1),
            ),
          ],
        ),
        _layersHeader(layerList, theme),
        if (_layersExpanded) _layersPanel(activeLayers),
        Padding(
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
        if (!estimateActive) _keepLoggingStrip(theme, prediction),
        Expanded(
          child: SingleChildScrollView(
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: _cells(
                byIso: byIso,
                forecastByIso: forecastByIso,
                cycles: cycles,
                today: today,
                theme: theme,
                layerList: layerList,
                palette: palette,
              ),
            ),
          ),
        ),
      ],
    );
  }

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
  /// strip instead of empty bands.
  Widget _keepLoggingStrip(ThemeData theme, CyclePrediction prediction) {
    final message = prediction is PausedAwaitingNextPeriod
        ? 'Predictions are paused — log the next period to resume forecasts.'
        : 'Keep logging — predicted bands appear once a few cycles are '
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
    required Map<String, DayEntry> byIso,
    required Map<String, ForecastDayCell> forecastByIso,
    required List<ForecastCycle> cycles,
    required LocalDate today,
    required ThemeData theme,
    required List<String> layerList,
    required List<Color> palette,
  }) {
    final firstOfMonth = LocalDate(_displayedYear, _displayedMonth, 1);
    final firstOfNext = _displayedMonth == 12
        ? LocalDate(_displayedYear + 1, 1, 1)
        : LocalDate(_displayedYear, _displayedMonth + 1, 1);
    final daysInMonth = firstOfNext.difference(firstOfMonth);
    // DateTime.weekday is 1=Monday..7=Sunday; the grid starts on Sunday.
    final leadingBlanks =
        DateTime(_displayedYear, _displayedMonth, 1).weekday % 7;
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
    required List<String> layerList,
    required List<Color> palette,
  }) {
    final iso = date.iso;
    final entry = byIso[iso];
    final isFuture = date.isAfter(today);
    // KTD3: a logged day always renders as logged — forecast markers only
    // ever pair a future date that has no entry.
    final forecastCell = entry == null && isFuture ? forecastByIso[iso] : null;
    final bleed = entry != null && isBleed(entry.flow);
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
                bleed: bleed,
                forecastCell: forecastCell,
                isToday: date == today,
                theme: theme,
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

  /// The day-number circle: solid primary fill for a logged bleed day
  /// (key `bleed-<iso>`), a hatched primary band for a predicted bleed day
  /// (key `predicted-<iso>` — hatched, never filled, KTD3), otherwise a
  /// thin primary ring when the cell is today.
  Widget _dayCircle(
    LocalDate date, {
    required bool bleed,
    required ForecastDayCell? forecastCell,
    required bool isToday,
    required ThemeData theme,
  }) {
    final iso = date.iso;
    final label = Text('${date.day}');
    if (bleed) {
      return Container(
        key: ValueKey('bleed-$iso'),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary,
        ),
        alignment: Alignment.center,
        child: Text(
          '${date.day}',
          style: TextStyle(color: theme.colorScheme.onPrimary),
        ),
      );
    }
    final predictedBleed = forecastCell?.predictedBleed ?? false;
    if (predictedBleed) {
      return _HatchedCircle(
        key: ValueKey('predicted-$iso'),
        color: theme.colorScheme.primary,
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
  });

  final Color color;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HatchPainter(color: color, opacity: opacity),
      child: SizedBox(width: 34, height: 34, child: Center(child: child)),
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
