/// Profile picker (home when no valid active profile): active profiles by
/// sort order, tap to make active; rename/archive from the row menu; archived
/// profiles live in a collapsed section at the bottom with one-tap unarchive.
/// The app bar carries the sync status glyph when the build has a sync
/// engine (U6); tapping it opens Settings.
///
/// Issue #126: active profiles are grouped into "My profiles" (held as
/// primary guardian, or not yet known) and "Shared with me" (held via
/// membership, with the operator's role shown). A profile with more than
/// one accepted guardian carries a small shared indicator, and a profile
/// with an outstanding invitation carries a badge — both without opening
/// any menu. Badges are best-effort: offline they render badge-free with
/// no error and no spinner.
///
/// Issue #803 (the household view): once the operator manages two or more
/// active profiles, every row also carries the per-profile attention
/// signals — timing (expected/late, #853-framed), silence (nothing logged
/// for N days), and changes (the feed's unread count) — plus a "Log today"
/// action that opens that profile's day sheet for today without switching
/// the active profile; the sheet's dismissal lands back here. A
/// single-profile account sees none of it: the rows render exactly as
/// before. Signal providers are optional — a tree without one renders that
/// signal absent, never a guessed line.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/mode_intervals.dart' show hasModeIntervalExclusion;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/household_signals.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/components/list_section_header.dart';
import 'package:lunarlog/ui/components/profile_card.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/profiles/mode_exit_exclusion.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/sharing/prediction_connections_screen.dart';
import 'package:lunarlog/ui/sharing/open_manage_guardians.dart';
import 'package:lunarlog/ui/sharing/sharing_overview_controller.dart';
import 'package:provider/provider.dart';

String formatCreatedDate(DateTime utc, {String locale = dates.kFallbackLocale}) =>
    dates.formatShortDate(utc.toLocal(), locale: locale);

class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  SharingOverviewController? _overview;

  @override
  void initState() {
    super.initState();
    final guardiansRepository =
        Provider.of<ProfileGuardiansRepository?>(context, listen: false);
    if (guardiansRepository != null) {
      final controller = SharingOverviewController(
        guardiansRepository: guardiansRepository,
        currentUserId: Provider.of<AuthController?>(context, listen: false)
            ?.currentUserId,
      );
      controller.addListener(_onOverviewChanged);
      _overview = controller;
    }
  }

  void _onOverviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overview?.removeListener(_onOverviewChanged);
    _overview?.dispose();
    _overview = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final active = controller.activeProfiles;
    final archived = controller.archivedProfiles;
    final hasSync = Provider.of<SyncStatusController?>(context) != null;
    void openSettings() => pushNamedScreen<void>(context, kRouteSettingsScreen);
    final overview = _overview;
    if (overview != null) {
      overview.observeProfiles([for (final profile in active) profile.id]);
    }
    final sharing = Provider.of<SharingService?>(context);
    final l10n = AppLocalizations.of(context);
    // Issue #803: the household enrichment is a multi-profile operator's
    // surface — a single-profile account keeps today's picker exactly as
    // it was (AC: "behaviour unchanged").
    final household = active.length >= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          if (hasSync) SyncStatusGlyph(onPressed: openSettings),
          const SharedWithMeAction(),
          IconButton(
            tooltip: l10n.settingsTooltip,
            icon: const Icon(Icons.settings),
            onPressed: openSettings,
          ),
          IconButton(
            tooltip: l10n.profilePickerAddProfileTooltip,
            icon: const Icon(Icons.person_add),
            onPressed: () => _addProfile(context),
          ),
        ],
      ),
      body: active.isEmpty && archived.isEmpty
          ? EmptyState(
              key: const ValueKey('profile-picker-empty'),
              title: 'No profiles yet',
              body: 'Add a profile to start tracking.',
              primaryActionLabel: 'Add profile',
              onPrimaryAction: () => _addProfile(context),
            )
          : ListView(
              children: [
                ..._activeRows(context, overview, sharing, active, household),
                if (archived.isNotEmpty)
                  ExpansionTile(
                    key: const Key('archived-section'),
                    title: Text('Archived (${archived.length})'),
                    children: [
                      for (final profile in archived)
                        ListTile(
                          title: Text(profile.displayName),
                          subtitle: Text(
                              'Created ${formatCreatedDate(profile.createdAt, locale: dates.calendarLocale(context))}'),
                          onTap: () => Navigator.of(context).push(
                            buildNamedRoute<void>(
                              name: kRouteProfileDetailScreen,
                              builder: (_) => ProfileDetailScreen(
                                profile: profile,
                                readOnly: true,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: l10n.profilePickerUnarchiveTooltip,
                            icon: const Icon(Icons.unarchive),
                            onPressed: () =>
                                controller.unarchiveProfile(profile.id),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }

  /// Active rows partitioned into "My profiles" and "Shared with me".
  /// Without sharing state (unconfigured build, or nobody shared with
  /// you) this is exactly the old flat list — no headers.
  ///
  /// [household] (issue #803) only enriches the rows — the #126/#966
  /// grouping itself is untouched, so a subject's "My profiles" view reads
  /// exactly as it did before this issue.
  List<Widget> _activeRows(
    BuildContext context,
    SharingOverviewController? overview,
    SharingService? sharing,
    List<Profile> active,
    bool household,
  ) {
    if (overview == null) {
      return [
        for (final profile in active)
          _row(context, null, sharing, profile, household),
      ];
    }
    final owned = [
      for (final profile in active)
        if (overview.infoFor(profile.id).group == ProfileSharingGroup.owned)
          profile,
    ];
    final shared = [
      for (final profile in active)
        if (overview.infoFor(profile.id).group ==
            ProfileSharingGroup.sharedWithMe)
          profile,
    ];
    if (shared.isEmpty) {
      return [
        for (final profile in owned)
          _row(context, overview, sharing, profile, household),
      ];
    }
    return [
      const ListSectionHeader(
        key: ValueKey('my-profiles-header'),
        title: 'My profiles',
      ),
      for (final profile in owned)
        _row(context, overview, sharing, profile, household),
      const ListSectionHeader(
        key: ValueKey('shared-with-me-header'),
        title: 'Shared with me',
      ),
      for (final profile in shared)
        _row(context, overview, sharing, profile, household),
    ];
  }

  Widget _row(
    BuildContext context,
    SharingOverviewController? overview,
    SharingService? sharing,
    Profile profile,
    bool household,
  ) {
    final l10n = AppLocalizations.of(context);
    final info = overview?.infoFor(profile.id) ?? const SharingProfileInfo.unknown();
    final roleSubtitle = sharingProfileRoleSubtitle(l10n, info);
    // Issue #241: the picker row is a ProfileCard — avatar, cycle status
    // (when a prediction service exists; an unconfigured tree keeps the
    // bare name/subtitle row), and the #126 badges, replacing the bare
    // sharing tile.
    //
    // Issue #803: a household row adds the per-profile signal lines under
    // the subtitle and — for a role that may log (#531's fail-open
    // discipline: an unknown role is not a viewer) — the log-for-her
    // action beside the overflow menu.
    final canLog = info.myRole?.canLog ?? true;
    return ProfileCard(
      key: ValueKey('profile-row-${profile.id}'),
      profile: profile,
      info: info,
      predictionService: Provider.of<CyclePredictionService?>(context),
      subtitleExtra: household
          ? HouseholdRowSignals(
              profile: profile,
              predictionService: Provider.of<CyclePredictionService?>(context),
              feedRepository: Provider.of<ActivityFeedRepository?>(
                context,
                listen: false,
              ),
              dayEntriesRepository: Provider.of<DayEntriesRepository?>(
                context,
                listen: false,
              ),
              reminderConfigs: Provider.of<ReminderConfigService?>(
                context,
                listen: false,
              ),
            )
          : null,
      sharingService: sharing,
      refreshToken: overview?.badgeEpoch ?? 0,
      subtitle: roleSubtitle ??
          'Created ${formatCreatedDate(profile.createdAt, locale: dates.calendarLocale(context))}',
      onTap: () => context.read<ProfileController>().selectProfile(profile.id),
      trailing: household && canLog
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: l10n.householdLogTodayFor(profile.displayName),
                  child: TextButton(
                    key: ValueKey('log-today-${profile.id}'),
                    onPressed: () => _logTodayFor(context, profile, info),
                    child: Text(l10n.householdLogToday),
                  ),
                ),
                _rowMenu(context, profile, info),
              ],
            )
          : _rowMenu(context, profile, info),
    );
  }

  /// The row's overflow menu (the pre-#803 trailing control, unchanged).
  PopupMenuButton<String> _rowMenu(
    BuildContext context,
    Profile profile,
    SharingProfileInfo info,
  ) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l10n.profilePickerActionsTooltip,
      onSelected: (action) => _onRowAction(context, profile, action),
      itemBuilder: (context) {
        // Issue #531: an unknown role (null - the guardian rows haven't
        // synced, or this is a local-only/not-yet-shared profile) fails
        // open to the full menu, matching the #3 null-vs-empty
        // discipline documented on `acceptedGuardianFor` - only a known,
        // resolved role that is actually insufficient hides an item.
        final role = info.myRole;
        final canEdit = role == null || role.canEditProfile;
        final canDelete = role == null || role.canDeleteProfile;
        return [
          const PopupMenuItem(value: 'caregivers', child: Text('Guardians')),
          if (canEdit)
            PopupMenuItem(
                value: 'rename', child: Text(l10n.editProfileAction)),
          if (canDelete)
            const PopupMenuItem(value: 'archive', child: Text('Archive')),
        ];
      },
    );
  }

  /// Issue #803's log-for-her action: opens [profile]'s day sheet for
  /// today through the same surface the overview's "log it" uses — the
  /// ordinary day sheet, not a second write path — without switching the
  /// active profile. The sheet closes by dismissal (its autosave model),
  /// so returning from it lands back on the household view with the
  /// active pointer untouched.
  ///
  /// A resolved role that cannot log ([GuardianRole.canLog] false, the
  /// viewer) never gets here from the row; the re-check is defense in
  /// depth. An unknown role fails open (#531).
  Future<void> _logTodayFor(
    BuildContext context,
    Profile profile,
    SharingProfileInfo info,
  ) async {
    if (info.myRole?.canLog == false) return;
    final DayEntriesRepository repository;
    try {
      repository = context.read<DayEntriesRepository>();
    } on ProviderNotFoundException {
      return;
    }
    final today = LocalDate.today();
    final existing = await repository.find(profile.id, today);
    if (!context.mounted) return;
    final modes = Provider.of<ProfileModesRepository?>(context, listen: false);
    final modeRow = await modes?.find(profile.id);
    if (!context.mounted) return;
    final guardiansRepository =
        Provider.of<ProfileGuardiansRepository?>(context, listen: false);
    final guardians = guardiansRepository == null
        ? const <ProfileGuardian>[]
        : await guardiansRepository.getForProfile(profile.id);
    if (!context.mounted) return;
    final currentUserId =
        Provider.of<AuthController?>(context, listen: false)?.currentUserId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: repository,
        profileId: profile.id,
        date: today,
        existing: existing,
        today: today,
        mode: profile.mode,
        lifecycleMode: modeRow?.mode ?? LifecycleMode.tracking,
        trackingPreferences: profile.trackingPreferences,
        isMinor: profile.isMinor,
        readOnly: false,
        timezoneProvider: null,
        currentUserId: currentUserId,
        guardians: guardians,
        bbtUnit: profile.bbtUnit,
        weightUnit: profile.weightUnit,
      ),
    );
  }

  Future<void> _addProfile(BuildContext context) async {
    final controller = context.read<ProfileController>();
    final result = await showProfileEditDialog(context);
    if (result == null) return;
    final profile = await controller.createProfile(
      displayName: result.displayName,
      isMinor: result.isMinor,
      mode: result.mode,
      irregularFraming: result.irregularFraming,
      birthYear: result.birthYear,
      relationship: result.relationship,
    );
    if (!context.mounted) return;
    await _recordCycleAnswers(context, profile.id, result);
  }

  Future<void> _onRowAction(
    BuildContext context, Profile profile, String action) async {
    final controller = context.read<ProfileController>();
    if (action == 'caregivers') {
      // Returning from Manage Guardians may have cancelled an invitation:
      // refresh outside badges so the change surfaces without a restart.
      // The shared push site carries the #151 prediction-connection wiring
      // too — this must stay a single push of the screen.
      unawaited(
        openManageGuardians(context, profile)
            ?.then((_) => _overview?.refreshBadges()),
      );
    } else if (action == 'rename') {
      await _onRenameAction(context, profile, controller);
    } else if (action == 'archive') {
      if (await confirmArchiveProfile(context, profile)) {
        await controller.archiveProfile(profile.id);
      }
    }
  }

  /// The rename/edit action, extracted from [_onRowAction] for the same
  /// complexity reason every other seam hook there was (the CRAP gate).
  ///
  /// Issue #192: the profile's pregnancy state is captured BEFORE the
  /// edit dialog opens — leaving Pregnancy mode auto-offers exclusion of
  /// the pregnancy interval from cycle averages once the switch itself
  /// has landed. Issue #455 generalizes the same seam to Postpartum mode:
  /// whichever discrete-interval mode the profile was in, the offer is
  /// made against the *pre-edit* row, so the interval's start is honest.
  /// Read up front (not after the dialog) so the awaited dialog
  /// round-trip never leaves this lookup on an unmounted context, and so
  /// the row is the pre-edit one by construction.
  Future<void> _onRenameAction(
    BuildContext context,
    Profile profile,
    ProfileController controller,
  ) async {
    final modes = Provider.of<ProfileModesRepository?>(context, listen: false);
    final priorModeRow = await modes?.find(profile.id);
    if (!context.mounted) return;
    // Issue #923: bound a new birth year against the profile's earliest
    // live entry, read through the existing DayEntriesRepository.
    final earliestEntryYear = await _earliestEntryYear(context, profile.id);
    if (!context.mounted) return;
    final result = await showProfileEditDialog(
      context,
      existing: profile,
      earliestEntryYear: earliestEntryYear,
    );
    if (result == null) return;
    final priorMode = priorModeRow?.mode ?? LifecycleMode.tracking;
    final priorStartedOn = priorModeRow?.modeStartedOn;
    final priorDueDate = priorModeRow?.estimatedDueDate;
    await controller.renameProfile(
      profile,
      displayName: result.displayName,
      isMinor: result.isMinor,
      mode: result.mode,
      // Issue #853: always passed explicitly — the dialog result already
      // carries the profile's stored tri-state for an untouched control.
      irregularFraming: result.irregularFraming,
      birthYear: result.birthYear,
      relationship: result.relationship,
    );
    if (!context.mounted) return;
    await _recordCycleAnswers(context, profile.id, result);
    if (context.mounted &&
        hasModeIntervalExclusion(priorMode) &&
        result.lifecycleMode != priorMode) {
      await offerModeExitExclusionFromTree(
        context,
        exitedMode: priorMode,
        profileId: profile.id,
        modeStartedOn: priorStartedOn,
        estimatedDueDate: priorDueDate,
      );
    }
  }

  /// Issue #923: the calendar year of [profileId]'s earliest live day
  /// entry, or null when it has none. Read through the existing
  /// [DayEntriesRepository] (`listForProfile`) rather than a new query; a
  /// tree without that repository (some tests) gets no cross-field bound.
  Future<int?> _earliestEntryYear(
    BuildContext context,
    String profileId,
  ) async {
    final DayEntriesRepository repository;
    try {
      repository = context.read<DayEntriesRepository>();
    } on ProviderNotFoundException {
      return null;
    }
    final entries = await repository.listForProfile(profileId);
    if (entries.isEmpty) return null;
    var earliest = entries.first.localDate;
    for (final entry in entries) {
      if (entry.localDate.isBefore(earliest)) earliest = entry.localDate;
    }
    return earliest.year;
  }

  /// Persists the #216 onboarding answers that are editable from the
  /// profile edit dialog (life-stage mode, birth-control method, and —
  /// Issue #192 — the pregnancy estimated due date) through the same
  /// recorder seam the first-run flow uses — no-op on a tree with no
  /// storage wired or when nothing changed.
  Future<void> _recordCycleAnswers(
    BuildContext context,
    String profileId,
    ProfileEditResult result,
  ) async {
    final recorder =
        Provider.of<OnboardingCycleAnswersRecorder?>(context, listen: false);
    if (recorder == null) return;
    await recorder.record(
      profileId,
      OnboardingCycleAnswers(
        lifecycleMode: result.lifecycleMode,
        birthControlMethod:
            birthControlStoredValue(result.birthControlChoice),
        estimatedDueDate: result.estimatedDueDate,
        postpartumBirthDate: result.postpartumBirthDate,
      ),
    );
  }
}

/// Issue #151: the app-bar entry point for prediction-only connections
/// shared WITH this account. Present only when a
/// [PredictionConnectionService] is configured - an unconfigured build
/// keeps the app bar exactly as before (R26's null-gating discipline).
class SharedWithMeAction extends StatelessWidget {
  const SharedWithMeAction({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<PredictionConnectionService?>(
        context, listen: false);
    if (service == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('shared-with-me'),
      tooltip: AppLocalizations.of(context).profilePickerSharedWithMeTooltip,
      icon: const Icon(Icons.calendar_month),
      onPressed: () => Navigator.of(context).push(
        buildNamedRoute<void>(
          name: kRoutePredictionConnectionsScreen,
          builder: (_) => PredictionConnectionsScreen(
            service: service,
          ),
        ),
      ),
    );
  }
}
