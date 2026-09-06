/// Month calendar for one profile's day entries (U5, R8/R10): month
/// navigation with today's month as default, bleed-day markers (flow above
/// none), a small secondary dot for symptom-only days (tags/note without a
/// bleed), and a future-date lock — days after today render dimmed and are
/// not selectable, and navigation never moves past the current month.
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
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
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

int _monthIndex(int year, int month) => year * 12 + (month - 1);

class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.profileId,
    this.readOnly = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.guardiansRepository,
  });

  final String profileId;
  final bool readOnly;

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

  @override
  void initState() {
    super.initState();
    _repository = context.read<DayEntriesRepository>();
    _entriesStream = _repository.watchForProfile(widget.profileId);
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
    _guardiansSub =
        repository.watchForProfile(widget.profileId).listen((guardians) {
      if (!mounted) return;
      setState(() => _guardians = guardians);
    });
  }

  @override
  void didUpdateWidget(MonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _entriesStream = _repository.watchForProfile(widget.profileId);
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
      builder: (_) => DaySheet(
        repository: _repository,
        profileId: widget.profileId,
        date: date,
        existing: entry,
        today: widget.todayProvider(),
        readOnly: _effectiveReadOnly,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: _guardians,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = widget.todayProvider();
    final nextDisabled = _monthIndex(_displayedYear, _displayedMonth) >=
        _monthIndex(today.year, today.month);
    return StreamBuilder<List<DayEntry>>(
      stream: _entriesStream,
      builder: (context, snapshot) {
        final entries = snapshot.data;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final byIso = {
          for (final entry in entries) entry.localDate.iso: entry,
        };
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
                  onPressed:
                      nextDisabled ? null : () => _shiftMonth(1),
                ),
              ],
            ),
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
            Expanded(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _cells(byIso, today, theme),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _cells(
    Map<String, DayEntry> byIso,
    LocalDate today,
    ThemeData theme,
  ) {
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
        _dayCell(firstOfMonth.addDays(day - 1), byIso, today, theme),
    ];
  }

  /// Per-cell derived state: whether the day has a logged bleed, whether it
  /// has symptom-only data (tags/note without a bleed), whether it's after
  /// today (dimmed, locked), and whether it can be tapped open.
  ({bool bleed, bool symptomOnly, bool isFuture, bool selectable})
      _dayCellFlags(
    DayEntry? entry,
    LocalDate date,
    LocalDate today,
  ) {
    final bleed = entry != null && isBleed(entry.flow);
    final symptomOnly = entry != null &&
        !bleed &&
        (entry.tags.isNotEmpty || entry.note != null);
    final isFuture = date.isAfter(today);
    final selectable = !isFuture && (!_effectiveReadOnly || entry != null);
    return (
      bleed: bleed,
      symptomOnly: symptomOnly,
      isFuture: isFuture,
      selectable: selectable,
    );
  }

  /// The day-number circle's fill/border: solid primary fill for a bleed
  /// day, otherwise a thin primary ring when the cell is today.
  BoxDecoration _dayCellDecoration(bool bleed, bool isToday, ThemeData theme) {
    return BoxDecoration(
      shape: BoxShape.circle,
      color: bleed ? theme.colorScheme.primary : null,
      border: isToday && !bleed
          ? Border.all(color: theme.colorScheme.primary, width: 1.5)
          : null,
    );
  }

  /// The day-number text style: on-primary text over a bleed day's solid
  /// fill, otherwise the ambient text style.
  TextStyle? _dayCellLabelStyle(bool bleed, ThemeData theme) {
    return bleed ? TextStyle(color: theme.colorScheme.onPrimary) : null;
  }

  /// The small secondary dot marking a symptom-only day (tags/note without
  /// a bleed), or nothing.
  Widget? _dayCellSymptomDot(bool symptomOnly, ThemeData theme, String iso) {
    if (!symptomOnly) return null;
    return Container(
      key: ValueKey('symptom-dot-$iso'),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.tertiary,
      ),
    );
  }

  Widget _dayCell(
    LocalDate date,
    Map<String, DayEntry> byIso,
    LocalDate today,
    ThemeData theme,
  ) {
    final iso = date.iso;
    final entry = byIso[iso];
    final flags = _dayCellFlags(entry, date, today);
    final bleed = flags.bleed;
    final isFuture = flags.isFuture;
    final selectable = flags.selectable;
    return InkWell(
      key: ValueKey('day-cell-$iso'),
      onTap: selectable ? () => _openDay(date, entry) : null,
      child: Opacity(
        opacity: isFuture ? 0.35 : 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              key: bleed ? ValueKey('bleed-$iso') : null,
              width: 34,
              height: 34,
              decoration: _dayCellDecoration(bleed, date == today, theme),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: _dayCellLabelStyle(bleed, theme),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 6,
              child: _dayCellSymptomDot(flags.symptomOnly, theme, iso),
            ),
          ],
        ),
      ),
    );
  }
}
