/// The three-option late resolver (issue #132, R6/F3): replaces the old
/// single-line late banner wherever a period is overdue.
///
/// * **Log it** opens the day sheet for today (the panel passes the
///   callback; logging shifts the anchor and the whole prediction
///   recomputes — this is also the way through the paused state, AC7).
/// * **Skip this cycle** appends the open cycle's start to the device-local
///   omission list: the estimate advances one averaged cycle now, and the
///   skipped cycle's eventual length is excluded from the average.
/// * **Remind me in 3 days** writes the device-local snooze date; the
///   resolver stays quiet (a one-line note instead) until that date.
///
/// Read-only callers (archived profile, or a viewer-role guardian) see the
/// informational line only — no actions. Vocabulary is cycle-only (R13).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart' show kMonthNames;
import 'package:lunarlog/ui/overview/overview_panel.dart'
    show kEstimateDisclaimer;

String _formatDate(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}';

class LateResolver extends StatefulWidget {
  const LateResolver({
    super.key,
    required this.profileId,
    required this.prediction,
    required this.exclusions,
    required this.settings,
    required this.onLogIt,
    required this.todayProvider,
    this.readOnly = false,
  });

  final String profileId;

  /// The state that triggered the resolver: an [ActivePrediction] that is
  /// late, or a [PausedAwaitingNextPeriod] (an open cycle past sixty days
  /// still resolves through "log it" — issue AC).
  final CyclePrediction prediction;

  final CycleExclusionList exclusions;
  final SettingsStore settings;
  final VoidCallback onLogIt;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  final bool readOnly;

  @override
  State<LateResolver> createState() => _LateResolverState();
}

class _LateResolverState extends State<LateResolver> {
  /// The open cycle's start — the key "skip this cycle" appends to the
  /// omission list. Only the two open-cycle states reach this widget.
  LocalDate get _openCycleStart => switch (widget.prediction) {
    ActivePrediction(:final lastEpisodeStart) => lastEpisodeStart,
    PausedAwaitingNextPeriod(:final lastEpisodeStart) => lastEpisodeStart,
    NotEnoughHistory() => throw StateError(
      'LateResolver shown without an open cycle',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<String?>(
      stream: widget.settings.watch(lateSnoozeSettingKey(widget.profileId)),
      builder: (context, snapshot) {
        final snoozeUntil = parseLateSnooze(snapshot.data);
        final today = widget.todayProvider();
        if (isLateSnoozed(today: today, snoozeUntil: snoozeUntil)) {
          return _snoozedLine(context, snoozeUntil!);
        }
        return _resolverCard(context, theme, snoozeUntil != null);
      },
    );
  }

  Widget _snoozedLine(BuildContext context, LocalDate until) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('late-snoozed'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.alarm, size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'We will check back on ${_formatDate(until)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
          if (!widget.readOnly)
            TextButton(
              key: const ValueKey('late-snooze-show-now'),
              onPressed: () => widget.settings.set(
                lateSnoozeSettingKey(widget.profileId),
                '',
              ),
              child: const Text('Show options'),
            ),
        ],
      ),
    );
  }

  Widget _resolverCard(BuildContext context, ThemeData theme, bool wasSnoozed) {
    final lateLine = switch (widget.prediction) {
      ActivePrediction() => 'Period is late',
      PausedAwaitingNextPeriod(:final daysSinceLastEpisodeStart) =>
        'No period logged for $daysSinceLastEpisodeStart days',
      _ => 'Period is overdue',
    };
    return Container(
      key: const ValueKey('late-resolver'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  lateLine,
                  key: const ValueKey('late-resolver-title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            wasSnoozed
                ? 'Still nothing logged — what would you like to do?'
                : 'What would you like to do?',
            key: const ValueKey('late-resolver-prompt'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _option(
                  key: 'resolver-log',
                  icon: Icons.edit,
                  label: 'Log it',
                  onPressed: widget.onLogIt,
                  emphasized: true,
                ),
                _option(
                  key: 'resolver-skip',
                  icon: Icons.skip_next,
                  label: 'Skip this cycle',
                  onPressed: () =>
                      widget.exclusions.omit(widget.profileId, _openCycleStart),
                ),
                _option(
                  key: 'resolver-remind',
                  icon: Icons.alarm,
                  label: 'Remind me in 3 days',
                  onPressed: () => widget.settings.set(
                    lateSnoozeSettingKey(widget.profileId),
                    encodeLateSnooze(
                      widget.todayProvider().addDays(kLateSnoozeDays),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            kEstimateDisclaimer,
            key: const ValueKey('late-resolver-disclaimer'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    if (emphasized) {
      return FilledButton.icon(
        key: ValueKey(key),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      key: ValueKey(key),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
