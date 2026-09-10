/// Per-profile Activity feed (issue #124): a reverse-chronological list of
/// what changed on a shared profile, who changed it, and when — one row per
/// day entry (its latest state, from the server-stamped attribution
/// columns), plus device-local merge-outcome rows and revoked-guardian rows.
///
/// Honest by construction: the row copy is derived only from what the
/// attribution stamps can support (see `buildActivityFeed`), the list header
/// states that earlier edits by the same caregiver are not separately
/// recorded, and no row ever shows note text, tag codes, or a raw uuid.
///
/// Nothing here mutates profile data: the screen is read-only plumbing whose
/// only writes are the device-local last-seen stamp, and its one navigation
/// target — the day sheet — opens in the caller's existing read-only mode
/// for a `viewer` (issue #124: a viewer can read the feed and cannot mutate
/// anything from it).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/models/flow_level.dart' show flowLabel;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:provider/provider.dart';

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({
    super.key,
    required this.profile,
    required this.repository,
    this.readOnly = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.nowProvider,
  });

  final Profile profile;
  final ActivityFeedRepository repository;

  /// The archived-profile passthrough (additive with the viewer gate, which
  /// is derived per snapshot below).
  final bool readOnly;

  /// Device-local civil date; passed to the day sheet.
  final LocalDate Function() todayProvider;

  /// Resolved IANA zone for new logs opened from a tap-through.
  final String Function()? timezoneProvider;

  /// Clock for relative ages; injectable for tests. Defaults to
  /// [DateTime.now].
  final DateTime Function()? nowProvider;

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  late final Stream<ActivityFeedSnapshot> _feedStream;
  late final DayEntriesRepository _entriesRepository;
  String? _currentUserId;
  AuthController? _auth;

  /// The last-seen stamp as it was when this visit opened — frozen for the
  /// whole visit so "New" chips do not vanish the moment [markSeen]
  /// overwrites the stored value (R8).
  DateTime? _lastSeenAtOpen;

  /// Guards the one-time stamping pass after the first snapshot.
  bool _seenStamped = false;

  @override
  void initState() {
    super.initState();
    _feedStream = widget.repository.watch(widget.profile.id);
    _entriesRepository = context.read<DayEntriesRepository>();
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.profile.displayName} Activity')),
      body: StreamBuilder<ActivityFeedSnapshot>(
        stream: _feedStream,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _onFirstSnapshot(data);
          if (!data.isShared) {
            return _singleGuardianState(context);
          }
          if (data.items.isEmpty) {
            return _noActivityState(context);
          }
          return _list(context, data);
        },
      ),
    );
  }

  /// Freezes the pre-stamp last-seen value and schedules the one-time
  /// re-stamp for this visit. Runs during build without setState — plain
  /// field writes only; the stream drives the next frame.
  void _onFirstSnapshot(ActivityFeedSnapshot data) {
    if (_seenStamped) return;
    _seenStamped = true;
    _lastSeenAtOpen ??= data.lastSeen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.repository.markSeen(widget.profile.id);
    });
  }

  Widget _singleGuardianState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Just you for now', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'This profile has one caregiver, so there is no shared activity '
              'to review. When a second caregiver joins, both of your changes '
              'appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noActivityState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No activity yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Changes either caregiver makes to this profile will appear '
              'here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, ActivityFeedSnapshot data) {
    final theme = Theme.of(context);
    return ListView.builder(
      key: const ValueKey('activity-feed-list'),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: data.items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Newest first. Each row shows a day\u2019s latest change — '
              'earlier edits by the same caregiver are not recorded '
              'separately.',
              key: const ValueKey('activity-feed-caption'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        final item = data.items[index - 1];
        return _row(context, item, data);
      },
    );
  }

  Widget _row(
    BuildContext context,
    ActivityItem item,
    ActivityFeedSnapshot data,
  ) {
    final theme = Theme.of(context);
    final localDateIso = item.localDateIso;
    return ListTile(
      key: ValueKey('activity-item-${item.id}'),
      leading: Icon(
        _iconFor(item.kind),
        color: item.kind == ActivityKind.removed ||
                item.kind == ActivityKind.mergeOutcome
            ? theme.colorScheme.tertiary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(_title(item, data)),
      subtitle: Text(_subtitle(item, data)),
      trailing: _trailing(context, item),
      onTap:
          localDateIso == null ? null : () => _openDay(localDateIso, data),
    );
  }

  IconData _iconFor(ActivityKind kind) => switch (kind) {
        ActivityKind.logged => Icons.edit_note,
        ActivityKind.updated => Icons.edit,
        ActivityKind.removed => Icons.delete_outline,
        ActivityKind.mergeOutcome => Icons.call_merge,
        ActivityKind.accessRemoved => Icons.person_remove_outlined,
      };

  String _possessive(String label) =>
      label == 'you' ? 'your' : "$label's";

  String _title(ActivityItem item, ActivityFeedSnapshot data) {
    final actor =
        activityActorLabel(item.actorId, _currentUserId, data.guardians);
    switch (item.kind) {
      case ActivityKind.logged:
        return _byLine('Logged', actor);
      case ActivityKind.updated:
        return _byLine('Updated', actor);
      case ActivityKind.removed:
        return _byLine('Removed', actor);
      case ActivityKind.mergeOutcome:
        return actor == null
            ? 'Sync merge kept one version'
            : 'Sync merge kept ${_possessive(actor)} version';
      case ActivityKind.accessRemoved:
        return actor == null
            ? 'A caregiver no longer has access'
            : '$actor no longer has access';
    }
  }

  /// '`verb` by `actor`', or an actor-less '`Entry verb`' form for an
  /// unattributed row — never an invented actor (issue #124's legacy-row
  /// AC).
  String _byLine(String verb, String? actor) =>
      actor == null ? 'Entry ${verb.toLowerCase()}' : '$verb by $actor';

  String _subtitle(ActivityItem item, ActivityFeedSnapshot data) {
    switch (item.kind) {
      case ActivityKind.mergeOutcome:
        return _mergeSubtitle(item, data);
      case ActivityKind.accessRemoved:
        return 'Access to this profile was removed';
      case ActivityKind.logged:
      case ActivityKind.updated:
      case ActivityKind.removed:
        return _entrySubtitle(item, data);
    }
  }

  /// Entry facts at calendar-glance level only: the date the entry is for,
  /// the original logger on edited rows, the flow *label*, the tag *count*,
  /// and whether a note exists. Removed rows show the date alone — a
  /// deleted day must not restate health detail the calendar no longer
  /// shows. Never note text, never tag codes.
  String _entrySubtitle(ActivityItem item, ActivityFeedSnapshot data) {
    final parts = <String>[
      if (item.localDateIso != null) 'for ${item.localDateIso}',
      if (item.kind == ActivityKind.updated && item.secondaryActorId != null)
        'logged by '
            '${activityActorLabel(item.secondaryActorId, _currentUserId, data.guardians) ?? 'a guardian'}',
      if (item.flow != null) flowLabel(item.flow!),
      if (item.tagCount > 0)
        '${item.tagCount} tag${item.tagCount == 1 ? '' : 's'}',
      if (item.hasNote) 'note',
    ];
    return parts.join(' \u2022 ');
  }

  String _mergeSubtitle(ActivityItem item, ActivityFeedSnapshot data) {
    final loser = activityActorLabel(
            item.secondaryActorId, _currentUserId, data.guardians) ??
        'one caregiver';
    final what = item.discardedNote && item.discardedFlow
        ? 'flow and note values were'
        : item.discardedNote
            ? 'note was'
            : 'flow value was';
    return '${_possessive(loser)} $what discarded in a same-date merge';
  }

  Widget _trailing(BuildContext context, ActivityItem item) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          relativeActivityAge(
              item.occurredAt, widget.nowProvider ?? DateTime.now),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (isActivityNew(item, _lastSeenAtOpen)) ...[
          const SizedBox(height: 2),
          Container(
            key: ValueKey('activity-new-${item.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'New',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onPrimary),
            ),
          ),
        ],
      ],
    );
  }

  /// R5: tapping a row opens that date's day sheet. The live entry is
  /// fetched at tap time (it may have changed since the row was rendered),
  /// and the sheet opens read-only for a `viewer` or an archived profile —
  /// the same additive rule `MonthCalendar` applies.
  Future<void> _openDay(String localDateIso, ActivityFeedSnapshot data) async {
    final date = LocalDate.fromIso(localDateIso);
    final existing = await _entriesRepository.find(widget.profile.id, date);
    if (!mounted) return;
    final viewerReadOnly =
        acceptedGuardianFor(data.guardians, _currentUserId)?.role.canLog ==
            false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: _entriesRepository,
        profileId: widget.profile.id,
        date: date,
        existing: existing,
        today: widget.todayProvider(),
        readOnly: widget.readOnly || viewerReadOnly,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: data.guardians,
      ),
    );
  }
}

/// The Activity entry point: an app-bar icon with a "new" dot whenever any
/// row predates this device's last-seen stamp (R8). Shared by the profile
/// screen and Manage Guardians so both reach the same screen.
class ActivityFeedButton extends StatefulWidget {
  const ActivityFeedButton({
    super.key,
    required this.profile,
    required this.repository,
    this.readOnly = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
  });

  final Profile profile;
  final ActivityFeedRepository repository;
  final bool readOnly;
  final LocalDate Function() todayProvider;
  final String Function()? timezoneProvider;

  @override
  State<ActivityFeedButton> createState() => _ActivityFeedButtonState();
}

class _ActivityFeedButtonState extends State<ActivityFeedButton> {
  late Stream<ActivityFeedSnapshot> _feedStream;

  @override
  void initState() {
    super.initState();
    // Allocated once: a fresh stream per build would re-subscribe four
    // Drift watches on every frame (see StreamBuilder.didUpdateWidget).
    _feedStream = widget.repository.watch(widget.profile.id);
  }

  // The shell (#313) keeps this button mounted across an in-place profile
  // switch, so re-watch when the profile changes -- the same pattern
  // OverviewPanel/MonthCalendar/AnalysisTab use (review finding on #330).
  @override
  void didUpdateWidget(covariant ActivityFeedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _feedStream = widget.repository.watch(widget.profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ActivityFeedSnapshot>(
      stream: _feedStream,
      builder: (context, snapshot) {
        final hasNew = snapshot.data?.hasNewItems ?? false;
        return IconButton(
          key: const ValueKey('activity-feed-button'),
          tooltip: 'Activity',
          icon: hasNew
              ? const Badge(
                  key: ValueKey('activity-feed-button-new'),
                  smallSize: 9,
                  child: Icon(Icons.history),
                )
              : const Icon(Icons.history),
          onPressed: () => Navigator.of(context).push(
            buildNamedRoute<void>(
              name: kRouteActivityFeedScreen,
              builder: (_) => ActivityFeedScreen(
                profile: widget.profile,
                repository: widget.repository,
                readOnly: widget.readOnly,
                todayProvider: widget.todayProvider,
                timezoneProvider: widget.timezoneProvider,
              ),
            ),
          ),
        );
      },
    );
  }
}
