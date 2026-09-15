/// The single shell every active profile mounts inside (issue #182): a
/// Material 3 [NavigationBar] with four destinations -- Today (the
/// existing [OverviewPanel], now topped by the #209 cycle wheel/Today card),
/// Calendar (the
/// existing [MonthCalendar]), Insights (the real Analysis tab, issue #223's
/// [AnalysisTab]), and More (the existing [SettingsScreen], unmodified,
/// including its own app bar). Today is the default/first tab (paired with
/// #209).
///
/// Issue #209 item 4a: a [TodayLogFab] floats over Today and Calendar
/// (not Insights/More, where logging today makes no sense), opening the
/// day sheet for today's date directly; it hides itself for a
/// `viewer`-role guardian.
///
/// The app bar shared by Today/Calendar/Insights (not rebuilt per screen,
/// and not shown at all on More -- [SettingsScreen] carries its own) holds
/// the active profile name as a tappable quick switcher (issue #241: a
/// popup listing active profiles for in-place switching, with a "Manage
/// profiles…" entry that opens the existing picker via
/// [ProfileController.openPicker] -- the same mechanism
/// `ProfileDetailScreen`'s old "Switch profile" action used), the
/// [SyncStatusGlyph] (previously picker-only), and a Settings action that
/// simply switches to the More tab rather than pushing a second copy of
/// [SettingsScreen] on top of the shell.
///
/// Each tab is built the first time it's selected and stays mounted under
/// an [IndexedStack] from then on (a lazy `IndexedStack`, not an eager one)
/// so switching tabs preserves that tab's own state -- scroll position, an
/// in-flight month navigation, a half-typed note -- instead of rebuilding
/// it from scratch. Building all four eagerly, before the operator ever
/// taps Calendar/Insights/More, would start every tab's live streams and
/// animations immediately -- including an indeterminate sync spinner that
/// can run inside Settings' Account section and never let `pumpAndSettle`
/// converge.
///
/// Issue #313: the body is wrapped in an [AppShellScope] so tab content can
/// switch tabs itself (issue #314's "See cycle history" link on
/// [OverviewPanel] is the first caller) without reaching into this file's
/// private state -- see `app_shell_scope.dart`. The whole shell is also
/// wrapped in a [PopScope] (issue #313): the shell is the app's root route,
/// so with no guard system back from Calendar/Insights/More would exit the
/// app outright; instead the first back press returns to Today and only a
/// second one (already on Today) is allowed through, matching Material's
/// "up returns to the first destination before exiting" guidance.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/components/profile_card.dart' show ProfileAvatar;
import 'package:lunarlog/ui/components/today_log_fab.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:lunarlog/ui/sharing/guardian_watch_mixin.dart';
import 'package:lunarlog/ui/theme/haptics.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

import 'app_shell_scope.dart';

/// Issue #313: the app-bar title ([_ProfileSwitcher]) stays fresh across a
/// profile rename or switch only because `profile_home_gate.dart`'s
/// `ProfileHomeGate` does `context.watch<ProfileController>()` and rebuilds
/// this whole shell with a new `widget.profile` -- nothing in this file
/// listens for profile changes itself.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.profile,
    this.launchToken,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
  });

  final Profile profile;

  /// U7 launch-payload seam (`lib/ui/profiles/profile_home_gate.dart`'s
  /// `_overviewLaunchSeq`): non-null, and a fresh value, exactly when this
  /// rebuild is routing a notification tap to this profile. Today is
  /// already the shell's default/first tab regardless (issue #182), so
  /// this only matters for an in-place reset back to it (see
  /// [_AppShellState.didUpdateWidget]) -- without it, an operator who was
  /// on the Calendar tab would stay there for the profile the notification
  /// named, rather than landing on that profile's Today tab as U7 intends.
  ///
  /// LLA-008 (issue #623): a plain `bool` here could only ever distinguish
  /// "this profile" from "not this profile" -- it could not tell "another
  /// notification just named the profile that is *already* active" from
  /// "nothing new happened", so a second tap on the same child's alert
  /// while already viewing them silently failed to reset the tab. Every
  /// value from [ProfileHomeGate]'s monotonic counter is distinct, so
  /// [_AppShellState.didUpdateWidget] resets on every genuinely new launch,
  /// same-profile relaunches included, not only on a profile switch.
  ///
  /// Issue #313 follow-up: renamed from `initiallyShowOverview`, a name
  /// left over from the pre-#182 `ProfileDetailScreen` seam this replaced
  /// -- it never affects this shell's *initial* tab (always Today), only
  /// whether an in-place rebuild resets back to it.
  final int? launchToken;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Provider for the resolved IANA time zone identifier (paired with #38).
  final String Function()? timezoneProvider;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppTab _tab = AppTab.today;

  /// Tabs built at least once (issue #182: "each tab's own state" survives a
  /// switch away and back via [IndexedStack] -- but building all four up
  /// front, before the operator ever taps Calendar/Insights/More, would
  /// start every tab's live streams and animations immediately, including
  /// an indeterminate sync spinner that can run inside Settings' Account
  /// section and never lets `pumpAndSettle` converge. A tab is built lazily,
  /// the first time it's selected, and stays alive (and in this set) for
  /// every later switch, matching a standard lazy `IndexedStack`.
  final Set<AppTab> _everShown = {AppTab.today};

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The widget is recreated in place whenever the home gate rebuilds (a
    // profile switch included), so this State survives -- same shape as
    // the pre-#182 ProfileDetailScreen seam this replaces. An ordinary
    // profile switch keeps the operator's current tab; only a genuinely
    // new launch-payload token forces Today -- LLA-008 (issue #623): a
    // same-profile relaunch carries a new token with no profile.id change
    // at all, so the reset can no longer be gated on that id changing.
    final token = widget.launchToken;
    if (token != null && token != oldWidget.launchToken) {
      _tab = AppTab.today;
    }
  }

  void _openPicker() => context.read<ProfileController>().openPicker();

  void _openMoreTab() => _selectTab(AppTab.more);

  void _selectTab(AppTab tab) =>
      setState(() {
        _tab = tab;
        _everShown.add(tab);
      });

  /// The widget for one tab position, or a placeholder for a tab never
  /// selected yet (see [_everShown]'s doc comment). Extracted out of
  /// [build] to keep that method's branching low (CRAP gate).
  Widget _tabContent(
    AppTab tab,
    ProfileGuardiansRepository? guardiansRepository,
  ) {
    if (!_everShown.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      AppTab.today => _withFabClearance(
          tab,
          OverviewPanel(
            profileId: widget.profile.id,
            mode: widget.profile.mode,
            trackingPreferences: widget.profile.trackingPreferences,
            isMinor: widget.profile.isMinor,
            todayProvider: widget.todayProvider,
            timezoneProvider: widget.timezoneProvider,
            guardiansRepository: guardiansRepository,
          ),
        ),
      AppTab.calendar => _withFabClearance(
          tab,
          MonthCalendar(
            profileId: widget.profile.id,
            mode: widget.profile.mode,
            trackingPreferences: widget.profile.trackingPreferences,
            isMinor: widget.profile.isMinor,
            todayProvider: widget.todayProvider,
            timezoneProvider: widget.timezoneProvider,
            guardiansRepository: guardiansRepository,
            bbtUnit: widget.profile.bbtUnit,
            weightUnit: widget.profile.weightUnit,
          ),
        ),
      AppTab.insights => AnalysisTab(
          profileId: widget.profile.id,
          mode: widget.profile.mode,
          todayProvider: widget.todayProvider,
          guardiansRepository: guardiansRepository,
          bbtUnit: widget.profile.bbtUnit,
        ),
      AppTab.more => const SettingsScreen(),
    };
  }

  /// Reserves room at the bottom of Today/Calendar (issue #316 review item
  /// 4) so [TodayLogFab] -- an extended FAB floating over exactly those two
  /// tabs -- never sits on top of the calendar's last row or the overview's
  /// last card. [MediaQuery.removePadding] keeps the reserved space from
  /// stacking on top of the view's own bottom safe-area inset (a
  /// notch/gesture-bar device); [_kFabClearance] alone covers the FAB's
  /// own height plus its default screen margin. Keyed per tab -- both
  /// bodies stay mounted side by side under the shell's [IndexedStack], so
  /// a shared key across siblings would collide.
  static const double _kFabClearance = 72;

  Widget _withFabClearance(AppTab tab, Widget child) => MediaQuery.removePadding(
        key: ValueKey('app-shell-tab-clearance-${tab.name}'),
        context: context,
        removeBottom: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _kFabClearance),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final guardiansRepository = context.read<ProfileGuardiansRepository?>();
    final activityRepository = context.read<ActivityFeedRepository?>();
    // listen: false -- only existence is read here; the glyph does its own
    // watch, and listening would rebuild the whole IndexedStack on every
    // sync snapshot (review finding on #182).
    final hasSync =
        Provider.of<SyncStatusController?>(context, listen: false) != null;
    // Issue #313: the seam wraps the whole Scaffold (not just its body) so
    // it is reachable from anywhere under this shell -- app bar included --
    // even though today's only caller (#314's "See cycle history" link)
    // only needs it from the body.
    return PopScope(
      // Issue #313: canPop only on Today, so a non-Today tab's system back
      // press is intercepted (didPop is then false below) rather than
      // popping this root route and exiting the app; a second back press,
      // now on Today, is let through.
      canPop: _tab == AppTab.today,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(AppTab.today);
      },
      child: AppShellScope(
        current: _tab,
        select: _selectTab,
        child: Scaffold(
          appBar: _tab == AppTab.more
              ? null
              : _shellAppBar(hasSync, guardiansRepository, activityRepository),
          body: IndexedStack(
            index: _tab.index,
            children: [
              for (final tab in AppTab.values)
                _tabContent(tab, guardiansRepository),
            ],
          ),
          // Issue #209 item 4a: "Log today" opens the day sheet directly,
          // only where logging today makes sense (Today/Calendar) -- not
          // Insights or More. Hidden for a viewer-role guardian by
          // TodayLogFab itself.
          floatingActionButton: _tab == AppTab.today || _tab == AppTab.calendar
              ? TodayLogFab(
                  profileId: widget.profile.id,
                  mode: widget.profile.mode,
                  trackingPreferences: widget.profile.trackingPreferences,
                  isMinor: widget.profile.isMinor,
                  todayProvider: widget.todayProvider,
                  timezoneProvider: widget.timezoneProvider,
                  guardiansRepository: guardiansRepository,
                  bbtUnit: widget.profile.bbtUnit,
                  weightUnit: widget.profile.weightUnit,
                )
              : null,
          bottomNavigationBar: NavigationBar(
            key: const ValueKey('app-shell-nav-bar'),
            selectedIndex: _tab.index,
            onDestinationSelected: (index) => _selectTab(AppTab.values[index]),
            destinations: const [
              NavigationDestination(
                key: ValueKey('app-shell-tab-today'),
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: 'Today',
              ),
              NavigationDestination(
                key: ValueKey('app-shell-tab-calendar'),
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              NavigationDestination(
                key: ValueKey('app-shell-tab-insights'),
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Insights',
              ),
              NavigationDestination(
                key: ValueKey('app-shell-tab-more'),
                icon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The app bar shared by Today/Calendar/Insights (issue #182 AC2/AC3/AC5):
  /// the profile switcher, the Activity feed action (issue #313 -- #124's
  /// [ActivityFeedButton], reachable again now that the shell replaced
  /// `ProfileDetailScreen` as where the active profile lives), the sync
  /// glyph (only when a build has one), and a Settings action. Extracted
  /// out of [build] to keep that method's branching low (CRAP gate).
  AppBar _shellAppBar(
    bool hasSync,
    ProfileGuardiansRepository? guardiansRepository,
    ActivityFeedRepository? activityRepository,
  ) =>
      AppBar(
        title: _ProfileSwitcher(
          profile: widget.profile,
          onManageProfiles: _openPicker,
          guardiansRepository: guardiansRepository,
        ),
        actions: [
          if (activityRepository != null)
            ActivityFeedButton(
              profile: widget.profile,
              repository: activityRepository,
              todayProvider: widget.todayProvider,
              timezoneProvider: widget.timezoneProvider,
            ),
          if (hasSync) SyncStatusGlyph(onPressed: _openMoreTab),
          IconButton(
            key: const ValueKey('app-shell-settings-action'),
            tooltip: AppLocalizations.of(context).settingsTooltip,
            icon: const Icon(Icons.settings),
            onPressed: _openMoreTab,
          ),
        ],
      );
}

/// The active profile name as a tappable quick switcher (issue #182 AC2;
/// issue #241 B-16 makes it a popup): tapping opens a menu listing every
/// active profile with its [ProfileAvatar] -- selecting one makes it
/// active in place, replacing the three-tap round trip through the
/// full-screen picker -- plus a "Manage profiles…" entry that opens the
/// full picker via [ProfileController.openPicker] (create, rename,
/// archive, sharing -- everything the menu does not do).
///
/// Issue #126: carries the co-managed mark ([_SharedMark]) right after the
/// name, so a co-managed record always reads as one without opening any
/// menu. Solo profiles render nothing extra.
class _ProfileSwitcher extends StatelessWidget {
  const _ProfileSwitcher(
      {required this.profile,
      required this.onManageProfiles,
      required this.guardiansRepository});

  /// The menu value of the "Manage profiles…" entry. Profile ids are
  /// ULIDs, so this can never collide with a real id.
  static const String _kManageProfilesValue = '__manage__';

  final Profile profile;

  /// Opens the full picker ([_AppShellState._openPicker]).
  final VoidCallback onManageProfiles;

  final ProfileGuardiansRepository? guardiansRepository;

  /// The popup's position: a [RelativeRect] anchoring the menu directly
  /// under this button, in the Overlay's coordinate space.
  RelativeRect _menuPosition(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
  }

  /// One menu row per active profile (avatar, name, a check on the
  /// active one), then the divider and the "Manage profiles…" entry.
  List<PopupMenuEntry<String>> _menuItems(
    BuildContext context,
    List<Profile> active,
  ) =>
      [
        for (final other in active)
          PopupMenuItem<String>(
            key: ValueKey('quick-switcher-profile-${other.id}'),
            value: other.id,
            height: 56,
            child: Row(
              children: [
                ProfileAvatar(profileId: other.id, radius: 14),
                const SizedBox(width: LLSpace.space3),
                Expanded(
                  child: Text(
                    other.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Fixed-width slot either way, so every name aligns in
                // one column whether or not the check renders.
                other.id == profile.id
                    ? const Icon(Icons.check, size: 18)
                    : const SizedBox(width: 18),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const ValueKey('quick-switcher-manage'),
          value: _kManageProfilesValue,
          child: Row(
            children: [
              const Icon(Icons.manage_accounts_outlined),
              const SizedBox(width: LLSpace.space3),
              // Flexible + ellipsis: the label never forces the menu wider
              // than its bounded item width (a wide locale or the test
              // binding's wide Ahem font).
              Flexible(
                child: Text(
                  AppLocalizations.of(context).quickSwitcherManageProfiles,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ];

  /// Shows the switcher menu and applies the selection: a profile id
  /// makes that profile active in place; the manage entry opens the full
  /// picker. The menu itself is named (issue #313's route-name
  /// discipline) so the popup shows in the Sentry navigation trail.
  Future<void> _showMenu(BuildContext context) async {
    final controller = context.read<ProfileController>();
    final selected = await showMenu<String>(
      context: context,
      routeSettings:
          const RouteSettings(name: kRouteQuickProfileSwitcherMenu),
      position: _menuPosition(context),
      items: _menuItems(context, controller.activeProfiles),
    );
    if (selected == null || !context.mounted) return;
    if (selected == _kManageProfilesValue) {
      onManageProfiles();
      return;
    }
    await context.read<ProfileController>().selectProfile(selected);
  }

  @override
  Widget build(BuildContext context) {
    final repository = guardiansRepository;
    return Tooltip(
      message: AppLocalizations.of(context).appShellProfileSwitcherTooltip,
      child: InkWell(
        key: const ValueKey('app-shell-profile-switcher'),
        borderRadius: BorderRadius.circular(LLRadius.rMd),
        onTap: () {
          LLHaptics.selection();
          unawaited(_showMenu(context));
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LLSpace.space2,
              vertical: LLSpace.space1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    profile.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (repository != null)
                  _SharedMark(
                      repository: repository, profileId: profile.id),
                const SizedBox(width: LLSpace.space1),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Issue #126 co-managed mark: a small, non-alarming indicator next to the
/// active profile's name whenever the local guardian rows show more than
/// one accepted guardian. Local rows render offline, so this never errors
/// or spins — unknown or solo reads as nothing.
class _SharedMark extends StatelessWidget {
  const _SharedMark({required this.repository, required this.profileId});

  final ProfileGuardiansRepository repository;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProfileGuardian>>(
      stream: watchGuardiansForProfileSafely(repository, profileId),
      builder: (context, snapshot) {
        final accepted = [
          for (final guardian
              in snapshot.data ?? const <ProfileGuardian>[])
            if (guardian.status == GuardianStatus.accepted) guardian,
        ];
        if (accepted.length < 2) return const SizedBox.shrink();
        return Tooltip(
          message: 'Shared · ${accepted.length} guardians',
          child: const Padding(
            padding: EdgeInsets.only(left: LLSpace.space1),
            child: Icon(
              Icons.people_outline,
              key: ValueKey('profile-shared-indicator'),
              size: 18,
            ),
          ),
        );
      },
    );
  }
}

