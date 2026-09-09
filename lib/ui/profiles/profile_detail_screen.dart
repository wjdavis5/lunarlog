/// Profile detail (U5 + U6): the active profile's two surfaces — the
/// overview of predictions (U6, plus issue #132's history section and
/// late resolver) and the month calendar of logged days (U5) — behind a
/// simple in-place toggle. Both are scoped to exactly one profile (R3).
/// Archived profiles open in read-only mode (view-only day sheets, no
/// logging affordances, and the overview's resolver and history omit
/// actions hidden) with an unarchive action.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:provider/provider.dart';

enum _DetailTab { overview, calendar }

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.initiallyShowOverview = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
  });

  final Profile profile;
  final bool readOnly;

  /// Opens on the Overview tab instead of the Calendar — used by the U7
  /// launch payload seam (notification tap → firing profile's overview).
  final bool initiallyShowOverview;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Provider for the resolved IANA time zone identifier (paired with #38).
  /// Passed to [MonthCalendar].
  final String Function()? timezoneProvider;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  late _DetailTab _tab = widget.initiallyShowOverview
      ? _DetailTab.overview
      : _DetailTab.calendar;

  @override
  void didUpdateWidget(ProfileDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The widget is recreated in place when the active profile changes (the
    // home gate swaps it at the same tree position), so this State survives.
    // Normal profile switches keep the operator's current tab; only the U7
    // launch payload (initiallyShowOverview) forces the new profile open on
    // its overview.
    if (widget.profile.id != oldWidget.profile.id &&
        widget.initiallyShowOverview) {
      _tab = _DetailTab.overview;
    }
  }

  Future<void> _unarchive() async {
    final controller = context.read<ProfileController>();
    await controller.unarchiveProfile(widget.profile.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ProfileController>();
    final storage = context.read<LunarLogStorage?>();
    final guardiansRepository =
        storage == null ? null : ProfileGuardiansRepository(storage);
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.profile.displayName}${widget.readOnly ? ' (archived)' : ''}'),
        actions: [
          // Issue #124: the per-profile Activity feed, reachable from the
          // profile itself. Hidden when no storage is wired (local-only
          // test trees), exactly like the guardians repository above.
          if (storage != null)
            ActivityFeedButton(
              profile: widget.profile,
              repository: ActivityFeedRepository(storage),
              readOnly: widget.readOnly,
              todayProvider: widget.todayProvider,
              timezoneProvider: widget.timezoneProvider,
            ),
          if (widget.readOnly)
            TextButton(
              onPressed: _unarchive,
              child: const Text('Unarchive'),
            )
          else
            IconButton(
              tooltip: 'Switch profile',
              icon: const Icon(Icons.swap_horiz),
              onPressed: context.read<ProfileController>().openPicker,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_DetailTab>(
              key: const ValueKey('detail-tab-toggle'),
              segments: const [
                ButtonSegment(
                  value: _DetailTab.overview,
                  label: Text('Overview'),
                ),
                ButtonSegment(
                  value: _DetailTab.calendar,
                  label: Text('Calendar'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          Expanded(
            child: _tab == _DetailTab.overview
                ? OverviewPanel(
                    profileId: widget.profile.id,
                    mode: widget.profile.mode,
                    todayProvider: widget.todayProvider,
                    readOnly: widget.readOnly,
                    timezoneProvider: widget.timezoneProvider,
                    guardiansRepository: guardiansRepository,
                  )
                : MonthCalendar(
                    profileId: widget.profile.id,
                    readOnly: widget.readOnly,
                    mode: widget.profile.mode,
                    todayProvider: widget.todayProvider,
                    timezoneProvider: widget.timezoneProvider,
                    guardiansRepository: guardiansRepository,
                  ),
          ),
        ],
      ),
    );
  }
}
