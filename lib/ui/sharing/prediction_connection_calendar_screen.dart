/// The recipient's phase-only calendar for a prediction-only connection
/// (issue #151). Renders exactly what the projection carries — period,
/// fertile, ovulation, and PMS days — and nothing else: there is no day
/// tap target, no route, and no data from which a day sheet could render,
/// because no day-level content is ever sent to this device. AC:
/// "The recipient's calendar has no route into a day sheet or any per-day
/// detail screen."
///
/// Data is fetched on demand from the projection RPC
/// ([PredictionConnectionService.fetchProjection]); a null result after a
/// revocation renders the "connection ended" state — revocation takes
/// effect on the recipient's next fetch with no residual view.
///
/// Issue #151 fix-up: a null projection is ambiguous on its own — it is
/// the same result whether the connection was revoked/never existed, or
/// the connection is freshly active and the sharer just hasn't published
/// a first snapshot yet (arming happens before `recipient_user_id` is
/// set, so nothing is published to publish to at that moment, and the
/// sharer's device only self-corrects on its own next prediction change
/// or foreground — which can lag by a long time). So a null projection is
/// disambiguated against [PredictionConnectionService.listIncomingConnections]:
/// an active connection for this profile with nothing published yet shows
/// a distinct "waiting for the first update" state instead of "connection
/// ended".
library;

import 'package:flutter/material.dart';

import '../../domain/models/local_date.dart';
import '../../domain/sharing/prediction_connection_service.dart';
import '../../domain/sharing/prediction_projection.dart';
import '../components/inline_error.dart';

class PredictionConnectionCalendarScreen extends StatefulWidget {
  const PredictionConnectionCalendarScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.service,
  });

  final String profileId;
  final String profileName;
  final PredictionConnectionService service;

  @override
  State<PredictionConnectionCalendarScreen> createState() =>
      _PredictionConnectionCalendarScreenState();
}

class _PredictionConnectionCalendarScreenState
    extends State<PredictionConnectionCalendarScreen> {
  late Future<PredictionProjection?> _projectionFuture;

  /// Only fetched (and only consulted in [build]) when the projection
  /// comes back null — it disambiguates "connection ended" from
  /// "connection is active, nothing published yet" without adding a
  /// round trip to the common case where a projection is already there.
  Future<List<IncomingPredictionConnection>>? _connectionsFuture;
  late LocalDate _month;

  @override
  void initState() {
    super.initState();
    _month = LocalDate.today();
    _projectionFuture = widget.service.fetchProjection(profileId: widget.profileId);
  }

  void _reload() {
    setState(() {
      _projectionFuture =
          widget.service.fetchProjection(profileId: widget.profileId);
      _connectionsFuture = null;
    });
  }

  Future<List<IncomingPredictionConnection>> _connections() {
    return _connectionsFuture ??= widget.service.listIncomingConnections();
  }

  void _shiftMonth(int delta) {
    setState(() {
      final total = _month.year * 12 + (_month.month - 1) + delta;
      _month = LocalDate(total ~/ 12, total % 12 + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.profileName), actions: [
        IconButton(
          key: const ValueKey('prediction-refresh'),
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ]),
      body: FutureBuilder<PredictionProjection?>(
        future: _projectionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: InlineError(
                key: const ValueKey('prediction-calendar-error'),
                message: 'Could not load the shared predictions.',
                onRetry: _reload,
              ),
            );
          }

          final projection = snapshot.data;
          if (projection == null) {
            return FutureBuilder<List<IncomingPredictionConnection>>(
              future: _connections(),
              builder: (context, connSnapshot) {
                if (connSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                // Issue #151 fix: a live connection to this profile with
                // nothing published yet is not "ended" - the sharer just
                // hasn't emitted a first snapshot. Only when no active
                // connection for this profile turns up (revoked, or the
                // lookup itself failed) do we fall back to "ended".
                final hasActiveConnection = connSnapshot.data
                        ?.any((c) => c.profileId == widget.profileId) ??
                    false;
                if (hasActiveConnection) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        key: const ValueKey('prediction-waiting-for-update'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('Waiting for the first update',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            "You're connected. Their predictions will "
                            'appear here as soon as they are shared.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      key: const ValueKey('prediction-connection-ended'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('Connection ended',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'This prediction connection is no longer active.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          final phases = projection.phasesByDate();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Text(_monthLabel(_month), style: theme.textTheme.titleMedium),
                    IconButton(
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _shiftMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _PhaseMonthGrid(
                  key: ValueKey(
                      'prediction-grid-${_month.year}-${_month.month}'),
                  month: _month,
                  phases: phases,
                ),
                const SizedBox(height: 16),
                const _PhaseLegend(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One month grid of phase marks. Days are plain, non-interactive cells —
/// deliberately no InkWell/GestureDetector/onTap exists in this subtree,
/// so no navigation out of the calendar is even expressible.
class _PhaseMonthGrid extends StatelessWidget {
  const _PhaseMonthGrid({
    super.key,
    required this.month,
    required this.phases,
  });

  final LocalDate month;
  final Map<LocalDate, Set<PredictionPhase>> phases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // LocalDate carries no weekday; the grid is pure calendar math on the
    // civil date, so Dart's DateTime gives the weekday (1=Mon..7=Sun).
    final leadingBlanks =
        (DateTime(month.year, month.month, 1).weekday - DateTime.sunday) % 7;
    final daysInMonth = _daysInMonth(month);
    final cells = <Widget>[
      for (final label in _weekdayHeaderLabels)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _PhaseDayCell(
          date: LocalDate(month.year, month.month, day),
          phases: phases[LocalDate(month.year, month.month, day)] ?? const {},
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.0,
      children: cells,
    );
  }
}

class _PhaseDayCell extends StatelessWidget {
  const _PhaseDayCell({
    required this.date,
    required this.phases,
  });

  final LocalDate date;
  final Set<PredictionPhase> phases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? background;
    Color? foreground;
    Border? border;
    if (phases.contains(PredictionPhase.period)) {
      background = theme.colorScheme.errorContainer;
      foreground = theme.colorScheme.onErrorContainer;
    } else if (phases.contains(PredictionPhase.fertile)) {
      background = theme.colorScheme.tertiaryContainer;
      foreground = theme.colorScheme.onTertiaryContainer;
    } else if (phases.contains(PredictionPhase.pms)) {
      background = theme.colorScheme.secondaryContainer;
      foreground = theme.colorScheme.onSecondaryContainer;
    }
    if (phases.contains(PredictionPhase.ovulation)) {
      // Ovulation is a ring around whatever fill the day carries.
      border = Border.all(color: theme.colorScheme.primary, width: 2);
    }

    return Container(
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: Text(
        '${date.day}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: foreground ?? theme.colorScheme.onSurface,
          fontWeight:
              phases.isEmpty ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _PhaseLegend extends StatelessWidget {
  const _PhaseLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget entry(Color swatch, String label, {bool ring = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ring ? null : swatch,
                shape: BoxShape.circle,
                border: ring ? Border.all(color: swatch, width: 2) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        entry(theme.colorScheme.errorContainer, 'Period'),
        entry(theme.colorScheme.tertiaryContainer, 'Fertile'),
        entry(theme.colorScheme.primary, 'Ovulation', ring: true),
        entry(theme.colorScheme.secondaryContainer, 'PMS'),
      ],
    );
  }
}

const List<String> _weekdayHeaderLabels = [
  'S',
  'M',
  'T',
  'W',
  'T',
  'F',
  'S',
];

int _daysInMonth(LocalDate month) {
  final nextMonth = month.month == 12
      ? LocalDate(month.year + 1, 1, 1)
      : LocalDate(month.year, month.month + 1, 1);
  return nextMonth.addDays(-1).day;
}

String _monthLabel(LocalDate month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${names[month.month - 1]} ${month.year}';
}
