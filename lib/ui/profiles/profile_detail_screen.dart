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
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';
import 'package:lunarlog/ui/insights/cycle_comparison_screen.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:lunarlog/ui/sharing/guardian_watch_mixin.dart';
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

class _ProfileDetailScreenState extends State<ProfileDetailScreen>
    with GuardianWatchMixin<ProfileDetailScreen> {
  late _DetailTab _tab = widget.initiallyShowOverview
      ? _DetailTab.overview
      : _DetailTab.calendar;

  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];

  /// Issue #850 (U8 follow-up): the lens a guardian reads this profile
  /// through, resolved exactly as [OverviewPanel] resolves it (D-1) so the
  /// archived-profile comparison push can hand [CycleComparisonScreen] the
  /// same lens the surrounding screen renders with. Presentation only —
  /// fail open, so an unwired or local-only tree keeps the subject lens.
  GuardianLens get _lens => guardianLensFor(_guardians, _currentUserId);

  /// Issue #820: minor status derives from birth year when present (falling
  /// back to the stored flag), evaluated against the injected today seam.
  bool get _isMinor =>
      widget.profile.isMinorAsOfYear(widget.todayProvider().year);

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
    watchGuardiansForProfile(
      context.read<ProfileGuardiansRepository?>(),
      widget.profile.id,
      (guardians) => setState(() => _guardians = guardians),
    );
  }

  @override
  void dispose() {
    disposeGuardianWatch();
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

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
    // Issue #850 (U8 follow-up): re-resolve the lens for the new profile's
    // own guardian rows when this State is reused across a profile switch.
    if (widget.profile.id != oldWidget.profile.id) {
      _watchGuardians();
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
    final l10n = AppLocalizations.of(context);
    final guardiansRepository = context.read<ProfileGuardiansRepository?>();
    final activityRepository = context.read<ActivityFeedRepository?>();
    final careContentRepository = context.read<CareContentRepository?>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.profile.displayName}${widget.readOnly ? l10n.profileDetailArchivedSuffix : ''}'),
        actions: [
          // Issue #124: the per-profile Activity feed, reachable from the
          // profile itself. Hidden when no feed repository is wired
          // (local-only test trees), exactly like the guardians repository
          // above.
          if (activityRepository != null)
            ActivityFeedButton(
              profile: widget.profile,
              repository: activityRepository,
              readOnly: widget.readOnly,
              todayProvider: widget.todayProvider,
              timezoneProvider: widget.timezoneProvider,
            ),
          // Issue #128: the profile's shared care notes and visit-prep
          // checklist, reachable from the profile itself. Same repository
          // gating as the Activity feed button above.
          if (careContentRepository != null && guardiansRepository != null)
            CareNotesButton(
              profile: widget.profile,
              repository: careContentRepository,
              guardiansRepository: guardiansRepository,
              readOnly: widget.readOnly,
            ),
          if (widget.readOnly)
            TextButton(
              onPressed: _unarchive,
              child: Text(l10n.profileDetailUnarchive),
            )
          else
            IconButton(
              tooltip: AppLocalizations.of(context).profileDetailSwitchProfileTooltip,
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
              segments: [
                ButtonSegment(
                  value: _DetailTab.overview,
                  label: Text(l10n.profileDetailOverviewTab),
                ),
                ButtonSegment(
                  value: _DetailTab.calendar,
                  label: Text(l10n.profileDetailCalendarTab),
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
                    isMinor: _isMinor,
                    todayProvider: widget.todayProvider,
                    timezoneProvider: widget.timezoneProvider,
                    guardiansRepository: guardiansRepository,
                    bbtUnit: widget.profile.bbtUnit,
                    weightUnit: widget.profile.weightUnit,
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
      stream: watchGuardiansForProfileSafely(
          guardiansRepository, widget.profile.id),
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
              label: Text(AppLocalizations.of(context)
                  .profileDetailSharedGuardians(accepted.length)),
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
      profile: widget.profile,
      mode: widget.profile.mode,
      irregularFraming: widget.profile.irregularFraming,
      trackingPreferences: widget.profile.trackingPreferences,
      isMinor: _isMinor,
      todayProvider: widget.todayProvider,
      readOnly: widget.readOnly,
      timezoneProvider: widget.timezoneProvider,
      guardiansRepository: guardiansRepository,
      subjectName: widget.profile.displayName,
      trailingChildren: !widget.readOnly
          ? const []
          : [
              CycleHistorySection(
                profileId: widget.profile.id,
                todayProvider: widget.todayProvider,
                readOnly: true,
                showStatistics: true,
                showDisclaimer: true,
                // Issue #235: an archived profile has no Insights tab of
                // its own to reach the comparison feature through (see
                // this screen's own doc comment), so this mount wires it
                // directly, the same as AnalysisTab's does.
                //
                // Issue #850 (U8 follow-up): this push carries the lens this
                // screen resolved, so a guardian's comparison empty state
                // reads third-person exactly like AnalysisTab's guardian
                // push does.
                onCompareSelected: (cycleAStart, cycleBStart) =>
                    Navigator.of(context).push(
                      CycleComparisonScreen.route(
                        profileId: widget.profile.id,
                        cycleAStart: cycleAStart,
                        cycleBStart: cycleBStart,
                        todayProvider: widget.todayProvider,
                        lens: _lens,
                      ),
                    ),
              ),
            ],
    );
  }
}
