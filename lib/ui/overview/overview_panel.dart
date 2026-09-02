/// Overview panel (U6, R11/R13/R17): the prediction summary for one
/// profile, rendered from the U3 [CyclePredictionService] stream so it
/// refreshes as entries are logged (F4 in-app half).
///
/// Wording is date-based only — no fertility vocabulary in any state (R13)
/// — and every estimate sits next to the fixed non-medical disclaimer
/// (R17). No drift types cross into this file.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart' show kMonthNames;
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:provider/provider.dart';

const String kEstimateDisclaimer = 'Estimates only — not medical advice.';

String _formatDate(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}, ${date.year}';

class OverviewPanel extends StatefulWidget {
  const OverviewPanel({
    super.key,
    required this.profileId,
    this.todayProvider = LocalDate.today,
  });

  final String profileId;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  @override
  State<OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends State<OverviewPanel> {
  late CyclePredictionService _service;
  late Stream<CyclePrediction> _predictions;

  @override
  void initState() {
    super.initState();
    _service = context.read<CyclePredictionService>();
    _predictions =
        _service.watch(widget.profileId, today: widget.todayProvider);
  }

  @override
  void didUpdateWidget(covariant OverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _predictions =
          _service.watch(widget.profileId, today: widget.todayProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = context
        .watch<NotificationPermissionState>()
        .value;
    return StreamBuilder<CyclePrediction>(
      stream: _predictions,
      builder: (context, snapshot) {
        final prediction = snapshot.data;
        if (prediction == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (prediction) {
              ActivePrediction() => _activeCard(context, prediction),
              PausedAwaitingNextPeriod() => _awaitingCard(context),
              NotEnoughHistory() => _notEnoughCard(context),
            },
            if (availability == NotificationAvailability.denied)
              const _ReminderHint(),
          ],
        );
      },
    );
  }

  Widget _activeCard(BuildContext context, ActivePrediction prediction) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-active'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key: const ValueKey('overview-phase'),
              prediction.duringEpisode ? 'Period' : 'Cycle day ${prediction.cycleDay}',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Next period estimate: ${_formatDate(prediction.estimatedNextStart)}',
              key: const ValueKey('overview-next-period'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            if (prediction.isLate)
              Container(
                key: const ValueKey('overview-late'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule,
                        size: 18, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Period is late — log it when it starts',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                prediction.untilNextPeriodLabel,
                key: const ValueKey('overview-days-until'),
                style: theme.textTheme.bodyLarge,
              ),
            const SizedBox(height: 12),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('overview-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _awaitingCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-awaiting'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Awaiting next period', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Predictions are paused until the next period is logged.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notEnoughCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-not-enough'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not enough history yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Keep logging — estimates appear once a few cycles are recorded.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderHint extends StatelessWidget {
  const _ReminderHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('reminder-hint'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.notifications_off,
              size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reminders unavailable — notifications are off',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.tertiary),
            ),
          ),
        ],
      ),
    );
  }
}
