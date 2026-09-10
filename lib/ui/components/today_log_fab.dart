/// Shell-level "Log today" quick action (issue #209 item 4a): a
/// [FloatingActionButton.extended] that opens the day sheet for
/// [todayProvider]'s date directly -- the same day-sheet entry point
/// [OverviewPanel]'s late resolver already opens ("Log it"), so every
/// "Log today" affordance in the app converges on the one
/// `DayEntriesRepository` write path.
///
/// Hidden entirely (renders nothing) for a `viewer`-role guardian
/// (`GuardianRole.canLog`) -- the same guardian-watch shape
/// [OverviewPanel]/`MonthCalendar` already use for their own
/// `_effectiveReadOnly`, duplicated here in miniature since neither widget
/// exposes it publicly and this button lives one layer up, in the shell
/// rather than either tab.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

class TodayLogFab extends StatefulWidget {
  const TodayLogFab({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.guardiansRepository,
  });

  final String profileId;

  /// The profile's care mode (Issue #131): category headings and
  /// surfacing order in the day sheet this button opens.
  final ProfileMode mode;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Provider for the resolved IANA time zone identifier (paired with
  /// #38); passed through to the day sheet.
  final String Function()? timezoneProvider;

  /// Source of this profile's guardians for the viewer-role check; null in
  /// local-only use (the button then fails open, matching
  /// `acceptedGuardianFor`'s own null-vs-empty discipline).
  final ProfileGuardiansRepository? guardiansRepository;

  @override
  State<TodayLogFab> createState() => _TodayLogFabState();
}

class _TodayLogFabState extends State<TodayLogFab> {
  StreamSubscription<List<ProfileGuardian>>? _guardiansSub;
  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    _watchGuardians();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

  void _watchGuardians() {
    _guardiansSub?.cancel();
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

  @override
  void didUpdateWidget(covariant TodayLogFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _watchGuardians();
    }
  }

  @override
  void dispose() {
    _guardiansSub?.cancel();
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Fails open on an unknown role (R14/R16's rule, same as
  /// [OverviewPanel]/`MonthCalendar`): a null guardian match is never
  /// treated as read-only.
  bool get _canLog =>
      acceptedGuardianFor(_guardians, _currentUserId)?.role.canLog != false;

  Future<void> _openTodaySheet() async {
    final repository = context.read<DayEntriesRepository>();
    final today = widget.todayProvider();
    final existing = await repository.find(widget.profileId, today);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: repository,
        profileId: widget.profileId,
        date: today,
        existing: existing,
        today: today,
        mode: widget.mode,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: _guardians,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canLog) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      key: const ValueKey('today-log-fab'),
      onPressed: _openTodaySheet,
      icon: const Icon(Icons.edit_calendar_outlined),
      label: const Text('Log today'),
    );
  }
}
