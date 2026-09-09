/// Profile detail (U5 + U6): the active profile's two surfaces — the
/// overview of predictions (U6, plus issue #132's history section and
/// late resolver) and the month calendar of logged days (U5) — behind a
/// simple in-place toggle. Both are scoped to exactly one profile (R3).
/// Archived profiles open in read-only mode (view-only day sheets, no
/// logging affordances, and the overview's resolver and history omit
/// actions hidden) with an unarchive action.
///
/// Issue #314 follow-up: [OverviewPanel] stopped mounting
/// [CycleHistorySection] once the Analysis tab became its sole home, but
/// this screen's archived read-only path has no app shell and so no
/// Insights tab for [OverviewPanel]'s "See cycle history" link to reach —
/// leaving an archived profile with no history surface at all, a
/// regression of #132. The Overview tab here mounts [CycleHistorySection]
/// itself, directly below [OverviewPanel], read-only, whenever this screen
/// is archived.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:lunarlog/ui/sharing/open_manage_guardians.dart';
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
          // Issue #128: the profile's shared care notes and visit-prep
          // checklist, reachable from the profile itself. Same storage
          // gating as the Activity feed button above.
          if (storage != null)
            CareNotesButton(
              profile: widget.profile,
              repository: DriftCareContentRepository(storage),
              guardiansRepository:
                  guardiansRepository ?? ProfileGuardiansRepository(storage),
              readOnly: widget.readOnly,
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
          // Issue #126: a co-managed profile reads as co-managed right
          // below its header — no menu to open. Solo profiles render
          // nothing here.
          if (guardiansRepository != null)
            _sharedChip(context, guardiansRepository),
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
                ? _overviewContent(guardiansRepository)
                : MonthCalendar(
                    profileId: widget.profile.id,
                    readOnly: widget.readOnly,
                    mode: widget.profile.mode,
                    trackingPreferences: widget.profile.trackingPreferences,
                    isMinor: widget.profile.isMinor,
                    todayProvider: widget.todayProvider,
                    timezoneProvider: widget.timezoneProvider,
                    guardiansRepository: guardiansRepository,
                  ),
          ),
        ],
      ),
    );
  }

  /// Issue #126 shared chip: visible only when the local guardian rows
  /// show more than one accepted guardian. Routes to Manage Guardians
  /// when the build can open it; otherwise a plain (disabled) indicator.
  /// Local rows render offline, so this never errors or spins.
  Widget _sharedChip(
    BuildContext context,
    ProfileGuardiansRepository guardiansRepository,
  ) {
    return StreamBuilder<List<ProfileGuardian>>(
      stream: guardiansRepository.watchForProfile(widget.profile.id),
      builder: (context, snapshot) {
        final accepted = [
          for (final guardian in snapshot.data ?? const <ProfileGuardian>[])
            if (guardian.status == GuardianStatus.accepted) guardian,
        ];
        if (accepted.length < 2) return const SizedBox.shrink();
        final sharing =
            Provider.of<SharingService?>(context, listen: false);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              key: const ValueKey('profile-shared-chip'),
              avatar: const Icon(Icons.people_outline, size: 18),
              label: Text('Shared · ${accepted.length} guardians'),
              onPressed: sharing == null
                  ? null
                  : () => openManageGuardians(context, widget.profile),
            ),
          ),
        );
      },
    );
  }

  /// The Overview tab's content. Not archived: just [OverviewPanel], same  /// as before #314's follow-up. Archived: [OverviewPanel] with the
  /// read-only [CycleHistorySection] this screen's doc comment explains
  /// passed as [OverviewPanel.trailingChildren] so both render inside the
  /// panel's own single [ListView] (issue #314 review item 3) instead of
  /// the two independently-scrolling half-height panes this used to stack
  /// -- which left the bottom half blank whenever there was no history.
  Widget _overviewContent(ProfileGuardiansRepository? guardiansRepository) {
    return OverviewPanel(
      profileId: widget.profile.id,
      mode: widget.profile.mode,
      trackingPreferences: widget.profile.trackingPreferences,
      isMinor: widget.profile.isMinor,
      todayProvider: widget.todayProvider,
      readOnly: widget.readOnly,
      timezoneProvider: widget.timezoneProvider,
      guardiansRepository: guardiansRepository,
      trailingChildren: !widget.readOnly
          ? const []
          : [
              CycleHistorySection(
                profileId: widget.profile.id,
                todayProvider: widget.todayProvider,
                readOnly: true,
                showStatistics: true,
                showDisclaimer: true,
              ),
            ],
    );
  }
}
