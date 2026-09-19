/// The Calendar section's two tiles (Issue #226): the week-start day and
/// the compact date-order preference, both persisted through the
/// device-local [SettingsStore] and both rendered through the shared
/// `SettingsSection` header by `settings_screen.dart`.
///
/// Each tile mirrors `_AppearanceTile`'s proven shape (issue #137): a
/// `ListTile` whose subtitle shows the current value live (kept current
/// through the store's `watch`, so an external change re-renders it) and
/// which opens a radio-group picker dialog writing straight through
/// `SettingsStore.set`. The consumers (the month calendar's grid layout,
/// the day sheet's date header) watch the same keys, which is the entire
/// propagation mechanism — no controller.
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/calendar_preferences.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:provider/provider.dart';

/// The week-start tile. The subtitle names the current start day, so the
/// setting's effect is visible before the picker opens.
class FirstDayOfWeekTile extends StatefulWidget {
  const FirstDayOfWeekTile({super.key});

  @override
  State<FirstDayOfWeekTile> createState() => _FirstDayOfWeekTileState();
}

class _FirstDayOfWeekTileState extends State<FirstDayOfWeekTile> {
  CalendarFirstDay _value = CalendarFirstDay.sunday;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    // The store's watch seeds the current value on subscribe (null when
    // unset — which parses to Sunday), so one subscription covers both the
    // initial read and every later change.
    _sub = context
        .read<SettingsStore>()
        .watch(SettingsKeys.calendarFirstDayOfWeek)
        .listen((value) {
          if (mounted) {
            setState(() => _value = CalendarFirstDay.fromStored(value));
          }
        });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }

  String _label(AppLocalizations l10n) => switch (_value) {
        CalendarFirstDay.sunday => l10n.settingsFirstDaySunday,
        CalendarFirstDay.monday => l10n.settingsFirstDayMonday,
      };

  Future<void> _pick(CalendarFirstDay value) async {
    Navigator.of(context).pop();
    setState(() => _value = value);
    await context
        .read<SettingsStore>()
        .set(SettingsKeys.calendarFirstDayOfWeek, value.storedValue);
  }

  Future<void> _openPicker() async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsFirstDayTitle),
        children: [
          // `RadioGroup` (rather than per-tile `groupValue`/`onChanged`,
          // deprecated since Flutter 3.32) owns the selection, matching
          // the appearance picker's shape.
          RadioGroup<CalendarFirstDay>(
            groupValue: _value,
            onChanged: (value) {
              if (value != null) unawaited(_pick(value));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in CalendarFirstDay.values)
                  RadioListTile<CalendarFirstDay>(
                    key: ValueKey('first-day-option-${option.name}'),
                    value: option,
                    title: Text(switch (option) {
                      CalendarFirstDay.sunday => l10n.settingsFirstDaySunday,
                      CalendarFirstDay.monday => l10n.settingsFirstDayMonday,
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('first-day-of-week-tile'),
      leading: const Icon(Icons.calendar_view_week_outlined),
      title: Text(l10n.settingsFirstDayTitle),
      subtitle: Text(_label(l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _openPicker,
    );
  }
}

/// The date-order tile. Each option's label carries its own example
/// ("Day first (5 Sep)" / "Month first (Sep 5)"), so the choice needs no
/// further explanation.
class DateFormatTile extends StatefulWidget {
  const DateFormatTile({super.key});

  @override
  State<DateFormatTile> createState() => _DateFormatTileState();
}

class _DateFormatTileState extends State<DateFormatTile> {
  DateFormatPreference _value = DateFormatPreference.system;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context
        .read<SettingsStore>()
        .watch(SettingsKeys.dateFormat)
        .listen((value) {
          if (mounted) {
            setState(() => _value = DateFormatPreference.fromStored(value));
          }
        });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }

  /// Each option's label. The `system` option carries a live example
  /// resolved through the active locale (issue #884), so a month-first
  /// device sees "System default (Sep 5)" instead of a day-first claim its
  /// day sheet will contradict.
  String _optionLabel(
    AppLocalizations l10n,
    String locale,
    DateFormatPreference option,
  ) =>
      switch (option) {
        DateFormatPreference.system => l10n.settingsDateFormatSystemOption(
              dates.formatShortMonthDayExample(option, locale: locale),
            ),
        DateFormatPreference.dayMonth =>
          l10n.settingsDateFormatDayMonthOption,
        DateFormatPreference.monthDay =>
          l10n.settingsDateFormatMonthDayOption,
      };

  Future<void> _pick(DateFormatPreference value) async {
    Navigator.of(context).pop();
    setState(() => _value = value);
    await context
        .read<SettingsStore>()
        .set(SettingsKeys.dateFormat, value.storedValue);
  }

  Future<void> _openPicker() async {
    final l10n = AppLocalizations.of(context);
    final locale = dates.calendarLocale(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsDateFormatTitle),
        children: [
          RadioGroup<DateFormatPreference>(
            groupValue: _value,
            onChanged: (value) {
              if (value != null) unawaited(_pick(value));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in DateFormatPreference.values)
                  RadioListTile<DateFormatPreference>(
                    key: ValueKey('date-format-option-${option.name}'),
                    value: option,
                    title: Text(_optionLabel(l10n, locale, option)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = dates.calendarLocale(context);
    return ListTile(
      key: const ValueKey('date-format-tile'),
      leading: const Icon(Icons.date_range_outlined),
      title: Text(l10n.settingsDateFormatTitle),
      subtitle: Text(_optionLabel(l10n, locale, _value)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _openPicker,
    );
  }
}
