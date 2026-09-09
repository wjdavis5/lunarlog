/// The single shell every active profile mounts inside (issue #182): a
/// Material 3 [NavigationBar] with four destinations -- Today (for now the
/// existing [OverviewPanel]; the cycle wheel is #209), Calendar (the
/// existing [MonthCalendar]), Insights (a placeholder hosting the existing
/// [CycleHistorySection] until #223 lands the real Analysis tab -- no
/// analysis UI belongs here), and More (the existing [SettingsScreen],
/// unmodified, including its own app bar). Today is the default/first tab
/// (paired with #209).
///
/// The app bar shared by Today/Calendar/Insights (not rebuilt per screen,
/// and not shown at all on More -- [SettingsScreen] carries its own) holds
/// the active profile name as a tappable switcher opening the existing
/// picker ([ProfileController.openPicker], same mechanism
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
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

/// The shell's four destinations, in NavigationBar order (issue #182's
/// documented assumption: Clue's own B-9/B-29 ordering, no owner sign-off
/// obtained on the exact labels or order).
enum AppTab { today, calendar, insights, more }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.profile,
    this.initiallyShowOverview = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
  });

  final Profile profile;

  /// U7 launch-payload seam (`lib/ui/profiles/profile_home_gate.dart`'s
  /// `_overviewLaunchId`, unchanged): true when this shell mounted because
  /// a notification named this profile. Today is already the shell's
  /// default/first tab regardless (issue #182), so this only matters on an
  /// in-place profile *switch* (see [_AppShellState.didUpdateWidget]) --
  /// without it, an operator who was on the Calendar tab for the previous
  /// profile would stay there for the profile the notification named,
  /// rather than landing on that profile's Today/overview as U7 intends.
  final bool initiallyShowOverview;

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
    // The widget is recreated in place when the active profile changes (the
    // home gate swaps it at the same tree position), so this State survives
    // -- same shape as the pre-#182 ProfileDetailScreen seam this replaces.
    // An ordinary profile switch keeps the operator's current tab; only the
    // U7 launch payload forces the new profile open on Today.
    if (widget.profile.id != oldWidget.profile.id &&
        widget.initiallyShowOverview) {
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
    LunarLogStorage? storage,
    ProfileGuardiansRepository? guardiansRepository,
  ) {
    if (!_everShown.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      AppTab.today => OverviewPanel(
          profileId: widget.profile.id,
          mode: widget.profile.mode,
          todayProvider: widget.todayProvider,
          timezoneProvider: widget.timezoneProvider,
          guardiansRepository: guardiansRepository,
        ),
      AppTab.calendar => MonthCalendar(
          profileId: widget.profile.id,
          mode: widget.profile.mode,
          todayProvider: widget.todayProvider,
          timezoneProvider: widget.timezoneProvider,
          guardiansRepository: guardiansRepository,
        ),
      AppTab.insights => _InsightsTab(
          profileId: widget.profile.id,
          todayProvider: widget.todayProvider,
        ),
      AppTab.more => const SettingsScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<LunarLogStorage?>();
    final guardiansRepository =
        storage == null ? null : ProfileGuardiansRepository(storage);
    final hasSync = Provider.of<SyncStatusController?>(context) != null;
    return Scaffold(
      appBar: _tab == AppTab.more ? null : _shellAppBar(hasSync),
      body: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in AppTab.values)
            _tabContent(tab, storage, guardiansRepository),
        ],
      ),
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
    );
  }

  /// The app bar shared by Today/Calendar/Insights (issue #182 AC2/AC3/AC5):
  /// the profile switcher, the sync glyph (only when a build has one), and
  /// a Settings action. Extracted out of [build] to keep that method's
  /// branching low (CRAP gate).
  AppBar _shellAppBar(bool hasSync) => AppBar(
        title: _ProfileSwitcher(profile: widget.profile, onTap: _openPicker),
        actions: [
          if (hasSync) SyncStatusGlyph(onPressed: _openMoreTab),
          IconButton(
            key: const ValueKey('app-shell-settings-action'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openMoreTab,
          ),
        ],
      );
}

/// The active profile name as a tappable switcher (issue #182 AC2): opens
/// the existing picker via [ProfileController.openPicker], the same
/// mechanism `ProfileDetailScreen`'s "Switch profile" `IconButton` used --
/// wrapped in the same [Tooltip] message so it stays findable the same way.
class _ProfileSwitcher extends StatelessWidget {
  const _ProfileSwitcher({required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Switch profile',
      child: InkWell(
        key: const ValueKey('app-shell-profile-switcher'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  profile.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Issue #182: a placeholder hosting the existing [CycleHistorySection]
/// until #223 lands the real Analysis tab -- no analysis UI belongs here.
class _InsightsTab extends StatelessWidget {
  const _InsightsTab({required this.profileId, required this.todayProvider});

  final String profileId;
  final LocalDate Function() todayProvider;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CycleHistorySection(
          profileId: profileId,
          todayProvider: todayProvider,
        ),
      ],
    );
  }
}
