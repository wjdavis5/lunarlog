/// Month calendar for one profile's day entries (U5, R8/R10): month
/// navigation with today's month as default, bleed-day markers (flow above
/// none), a small secondary dot for symptom-only days (tags/note without a
/// bleed), and a future-date lock — days after today render dimmed and are
/// not selectable, and navigation never moves past the current month.
///
/// Active-profile scoping (R3): the calendar operates on exactly one
/// profile id and one repository stream; no drift types cross here.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
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
  });

  final String profileId;
  final bool readOnly;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DayEntriesRepository _repository;
  late Stream<List<DayEntry>> _entriesStream;
  int _displayedYear = 1970;
  int _displayedMonth = 1;

  @override
  void initState() {
    super.initState();
    _repository = context.read<DayEntriesRepository>();
    _entriesStream = _repository.watchForProfile(widget.profileId);
    _resetToTodaysMonth();
  }

  @override
  void didUpdateWidget(MonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _entriesStream = _repository.watchForProfile(widget.profileId);
      _resetToTodaysMonth();
    }
  }

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
        readOnly: widget.readOnly,
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

  Widget _dayCell(
    LocalDate date,
    Map<String, DayEntry> byIso,
    LocalDate today,
    ThemeData theme,
  ) {
    final iso = date.iso;
    final entry = byIso[iso];
    final bleed = entry != null && isBleed(entry.flow);
    final symptomOnly = entry != null &&
        !bleed &&
        (entry.tags.isNotEmpty || entry.note != null);
    final isFuture = date.isAfter(today);
    final selectable =
        !isFuture && (!widget.readOnly || entry != null);
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bleed ? theme.colorScheme.primary : null,
                border: date == today && !bleed
                    ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: bleed
                    ? TextStyle(color: theme.colorScheme.onPrimary)
                    : null,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 6,
              child: symptomOnly
                  ? Container(
                      key: ValueKey('symptom-dot-$iso'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.tertiary,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
