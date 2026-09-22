/// Widget tests for AppShell (issue #182): four bottom-nav destinations,
/// per-tab state preservation across a switch, the sync glyph on every tab
/// except More, the profile switcher's quick-switcher popup and its
/// "Manage profiles…" route to the existing picker (issue #241), and
/// Settings reachable from every tab without going through "Switch
/// profile". Issue #223: the Insights destination now mounts the real
/// [AnalysisTab] rather than the placeholder `_InsightsTab` #182 shipped —
/// that widget's own rendering is covered by `test/ui/analysis_tab_test
/// .dart`, so this file only pins that the placeholder is gone. Issue
/// #314: the "See cycle history" link's tab switch, and that
/// [CycleHistorySection] mounts exactly once across the shell once both
/// Today and Insights have been visited (it used to mount twice — once
/// per tab, each running its own `CycleHistoryService.watch` subscription
/// — until Overview stopped embedding its own copy). Issue #313: Android
/// back returns to Today before it exits, the Activity Feed action in the
/// shared app bar, and the `didUpdateWidget` reset-to-Today seam.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/mappers.dart' show flowFromDomain;
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/activity/merge_events.dart'
    show activityLastSeenKey;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';
import 'package:lunarlog/ui/components/app_shell.dart' show AppShell;
import 'package:lunarlog/ui/components/app_shell_scope.dart' show AppTab;
import 'package:lunarlog/ui/components/today_log_fab.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';

/// A gate that never requires unlocking (issue #313's launch-payload test
/// needs a [GateController] wired in, but nothing here exercises the
/// device-credential path itself).
class _NoLockGate implements AppGate {
  @override
  bool get requiresUnlock => false;

  @override
  Future<bool> canAuthenticate() async => true;

  @override
  Future<bool> requestAccess() async => true;
}

/// Materializes a server-authored guardian row locally (mirrors
/// `test/ui/logging_test.dart`'s helper of the same name).
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role,
) => RemoteProfileGuardianRow(
  id: id,
  profileId: profileId,
  userId: userId,
  role: role,
  status: 'accepted',
  invitedBy: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverVersion: 1,
);

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  final FakeAuthService auth = FakeAuthService();
  final FakeSyncEngine engine = FakeSyncEngine();

  /// Set by [pump] once the seeded profile's id is known -- for a test
  /// that needs to seed a guardian row before pumping (issue #316 review
  /// item 3).
  String? profileId;

  /// Seeds one profile and marks it active, so the app opens directly on
  /// its AppShell (no picker in between). [seedGuardians] runs after the
  /// profile exists but before the widget pumps. [seedEntries] (issue
  /// #314) does the same for day entries -- so a test can seed real cycle
  /// history before the shell's streams start, rather than saving through
  /// a repository after the fact and waiting on `pumpAndSettle`.
  Future<void> pump({
    bool withSync = true,
    Future<void> Function(LunarLogDatabase db, String profileId)?
        seedGuardians,
    Future<void> Function(LunarLogDatabase db, String profileId)?
        seedEntries,
  }) async {
    final profile = await DriftProfilesRepository(db.storage)
        .create(displayName: 'Alice', isMinor: false);
    profileId = profile.id;
    await DriftSettingsStore(db.storage)
        .set(SettingsKeys.lastActiveProfile, profile.id);
    if (seedGuardians != null) {
      await seedGuardians(db, profile.id);
    }
    if (seedEntries != null) {
      await seedEntries(db, profile.id);
    }
    await tester.pumpWidget(LunarLogApp.withCollaborators(
      db: db,
      authService: auth,
      syncEngine: withSync ? engine : null,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
    await auth.dispose();
  }
}

Finder tabKey(String name) => find.byKey(ValueKey('app-shell-tab-$name'));

/// Two 4-day bleed episodes -- just enough for [CycleHistorySection] to
/// render a populated card (issue #314's tests below only need a
/// non-empty history, not any particular confidence tier).
Future<void> seedEpisodes(LunarLogDatabase db, String profileId) async {
  final entries = DriftDayEntriesRepository(db.storage);
  for (final start in [LocalDate(2026, 1, 1), LocalDate(2026, 2, 1)]) {
    for (var i = 0; i < 4; i++) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: start.addDays(i),
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
    }
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('renders the four destinations, Today selected by default',
      (tester) async {
    final h = Harness(tester);
    await h.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // Calendar (a lazily-built tab) is not mounted before it's selected.
    expect(find.byType(MonthCalendar), findsNothing);
    await h.dispose();
  });

  testWidgets(
      'switching tabs preserves each tab\'s own state (Calendar keeps its '
      'navigated month across a switch away and back)', (tester) async {
    final h = Harness(tester);
    await h.pump();

    await tester.tap(tabKey('calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsOneWidget);

    // Two months back from today's real month/year (the calendar defaults
    // to "today" -- LunarLogApp passes no todayProvider override).
    final today = LocalDate.today();
    var year = today.year;
    var month = today.month - 2;
    if (month <= 0) {
      month += 12;
      year -= 1;
    }
    final twoMonthsBackLabel = '${monthNames()[month - 1]} $year';

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(twoMonthsBackLabel), findsOneWidget);

    await tester.tap(tabKey('today'));
    await tester.pumpAndSettle();
    await tester.tap(tabKey('calendar'));
    await tester.pumpAndSettle();

    expect(find.text(twoMonthsBackLabel), findsOneWidget,
        reason: 'the calendar kept its navigated month, not reset to today');
    await h.dispose();
  });

  testWidgets(
      'issue #809: the tab-switch fade is paint-only -- the IndexedStack '
      'stays mounted through the transition', (tester) async {
    final h = Harness(tester);
    await h.pump();

    expect(find.byType(IndexedStack), findsOneWidget,
        reason: 'the retained tab host is a real IndexedStack, not a fade '
            'wrapper that swaps it out');

    await tester.tap(tabKey('calendar'));
    // Mid-fade the IndexedStack (and so every tab's State under it) is still
    // in the tree -- this is what keeps per-tab state across the switch.
    await tester.pump();
    expect(find.byType(IndexedStack, skipOffstage: false), findsOneWidget,
        reason: 'the fade overlay must not replace the IndexedStack');

    await tester.pumpAndSettle();
    expect(find.byType(IndexedStack, skipOffstage: false), findsOneWidget);
    await h.dispose();
  });

  testWidgets(
      'the sync glyph renders on Today, Calendar and Insights but not More',
      (tester) async {
    final h = Harness(tester);
    await h.pump();

    expect(find.byType(SyncStatusGlyph), findsOneWidget,
        reason: 'Today (the default tab)');

    await tester.tap(tabKey('calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusGlyph), findsOneWidget);

    await tester.tap(tabKey('insights'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusGlyph), findsOneWidget);

    await tester.tap(tabKey('more'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusGlyph), findsNothing,
        reason: "More is Settings' own screen/app bar, not the shell's");
    expect(find.byType(SettingsScreen), findsOneWidget);
    await h.dispose();
  });

  testWidgets('no sync engine: no glyph on any tab, nothing crashes',
      (tester) async {
    final h = Harness(tester);
    await h.pump(withSync: false);

    expect(find.byType(SyncStatusGlyph), findsNothing);
    await tester.tap(tabKey('calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusGlyph), findsNothing);
    await h.dispose();
  });

  testWidgets(
      'tapping the sync glyph shows a readable status via a SnackBar, not '
      'only a tooltip', (tester) async {
    final h = Harness(tester);
    await h.pump();
    h.engine.emitPhase(SyncPhase.pulling);
    // Two pumps: notifyListeners() updates the controller field in the
    // first, and marks its InheritedWidget dependents (the glyph) dirty
    // for the frame after -- matching account_test.dart's own
    // emitPhase-then-settle pattern for this exact controller.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(SyncStatusGlyph));
    await tester.pump();

    expect(find.byKey(const ValueKey('sync-status-snackbar')), findsOneWidget);
    expect(find.text(AppLocalizationsEn().accountSyncStatusSyncing), findsWidgets);
    await h.dispose();
  });

  group('issue #568: sync failure banner', () {
    testWidgets(
        'session expired shows banner, tapping action selects More tab',
        (tester) async {
      final h = Harness(tester);
      await h.pump();
      h.engine.emitPhase(SyncPhase.error, lastError: SyncErrorKind.auth);
      // Issue #809: the banner now grows in via AnimatedSize, so it must be
      // settled before its action is hit-testable -- a bare pump leaves the
      // banner clipped to (almost) zero height.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sync-failure-banner')),
        findsOneWidget,
      );
      expect(find.text(AppLocalizationsEn().accountSyncStatusSignInAgain), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sync-failure-banner-action')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      await h.dispose();
    });

    testWidgets(
        'persistent error while signed in shows banner, tapping retry requests sync',
        (tester) async {
      final h = Harness(tester);
      await h.pump();
      h.auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'test@example.com'),
      );
      h.engine.emitPhase(SyncPhase.error, lastError: SyncErrorKind.network);
      // Issue #809: settle the banner's AnimatedSize growth before tapping.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sync-failure-banner')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sync-failure-banner-action')));
      await tester.pump();

      expect(h.engine.requestSyncCalls, 1);
      await h.dispose();
    });

    testWidgets('idle phase shows no banner', (tester) async {
      final h = Harness(tester);
      await h.pump();
      h.engine.emitPhase(SyncPhase.idle);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('sync-failure-banner')), findsNothing);
      await h.dispose();
    });
  });

  group('issue #826: the sync-failure banner sits below the AppBar on every '
      'tab', () {
    /// The banner must never float above the AppBar it belongs under. On
    /// Today the AppBar is the shell's; on More it used to be Settings'
    /// own inner one, with the shell-level banner rendered above it.
    Rect appBarRect(WidgetTester tester) =>
        tester.getRect(find.byType(AppBar));
    Rect bannerRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('sync-failure-banner')));

    testWidgets('banner renders beneath the AppBar on Today and on More',
        (tester) async {
      final h = Harness(tester);
      await h.pump();
      h.engine.emitPhase(SyncPhase.error, lastError: SyncErrorKind.auth);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('sync-failure-banner')),
          findsOneWidget);
      expect(bannerRect(tester).top,
          greaterThanOrEqualTo(appBarRect(tester).bottom),
          reason: 'Today: the banner must sit under the shell AppBar');

      await tester.tap(tabKey('more'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget,
          reason: 'More must have exactly one AppBar -- the shell now owns '
              'it and Settings must not double it');
      expect(find.byKey(const ValueKey('sync-failure-banner')),
          findsOneWidget);
      expect(bannerRect(tester).top,
          greaterThanOrEqualTo(appBarRect(tester).bottom),
          reason: 'More must obey the same one-AppBar rule as every other '
              'tab, not render the banner above Settings\' own title');
      await h.dispose();
    });

    testWidgets('no failure: no banner on Today or More', (tester) async {
      final h = Harness(tester);
      await h.pump();
      expect(find.byKey(const ValueKey('sync-failure-banner')), findsNothing);

      await tester.tap(tabKey('more'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-failure-banner')), findsNothing);
      await h.dispose();
    });

    testWidgets('"Go to Settings" still works from Today and from More',
        (tester) async {
      final h = Harness(tester);
      await h.pump();
      h.engine.emitPhase(SyncPhase.error, lastError: SyncErrorKind.auth);
      // Issue #809: settle the banner's AnimatedSize growth before tapping.
      await tester.pumpAndSettle();

      // From Today: the action switches the shell to More.
      await tester.tap(find.byKey(const ValueKey('sync-failure-banner-action')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget,
          reason: 'a tab switch, not a pushed route');

      // From More: the action is inert but must not push a duplicate or
      // throw. The banner is still the body's first child below the AppBar.
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-failure-banner-action')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(bannerRect(tester).top,
          greaterThanOrEqualTo(appBarRect(tester).bottom));
      await h.dispose();
    });
  });

  testWidgets(
      'tapping the profile switcher opens the quick-switcher popup, whose '
      '"Manage profiles…" entry opens the full picker (issue #241)',
      (tester) async {
    final h = Harness(tester);
    await h.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    final switcherFinder =
        find.byKey(const ValueKey('app-shell-profile-switcher'));
    final size = tester.getSize(switcherFinder);
    expect(size.width, greaterThanOrEqualTo(48.0),
        reason: 'Profile switcher width must satisfy >= 48dp touch target');
    expect(size.height, greaterThanOrEqualTo(48.0),
        reason: 'Profile switcher height must satisfy >= 48dp touch target');

    await tester.tap(switcherFinder);
    await tester.pumpAndSettle();

    // Issue #241: the tap opens the quick-switcher popup over the shell,
    // not the full picker — the shell (and its tab state) stays mounted.
    expect(find.byKey(ValueKey('quick-switcher-profile-${h.profileId}')),
        findsOneWidget,
        reason: 'the active profile is listed with its avatar');
    expect(find.byKey(const ValueKey('quick-switcher-manage')),
        findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the popup is an overlay; the picker has not replaced home');

    await tester.tap(find.byKey(const ValueKey('quick-switcher-manage')));
    await tester.pumpAndSettle();

    expect(find.text('Profiles'), findsOneWidget,
        reason: '"Manage profiles…" opened the existing full picker');
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'the picker is not the shell');
    await h.dispose();
  });

  testWidgets(
      "the shell app bar's Settings action reaches Settings without going "
      'through Switch profile', (tester) async {
    final h = Harness(tester);
    await h.pump();

    await tester.tap(find.byKey(const ValueKey('app-shell-settings-action')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'still inside the shell (a tab switch, not a picker visit)');
    await h.dispose();
  });

  testWidgets(
      'Insights mounts the real Analysis tab (issue #223), not the old '
      '#182 placeholder', (tester) async {
    final h = Harness(tester);
    await h.pump();

    await tester.tap(tabKey('insights'));
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisTab), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Insights are on the way'), findsNothing,
        reason: 'the #182 placeholder copy is gone');
    await h.dispose();
  });

  group('issue #209: the "Log today" FAB', () {
    testWidgets('floats over Today and Calendar, but not Insights or More',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      expect(find.byType(TodayLogFab), findsOneWidget,
          reason: 'Today (the default tab)');

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayLogFab), findsOneWidget);

      await tester.tap(tabKey('insights'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayLogFab), findsNothing);

      await tester.tap(tabKey('more'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayLogFab), findsNothing);
      await h.dispose();
    });

    testWidgets('tapping it opens the day sheet for today directly',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('today-log-fab')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.byKey(const ValueKey('autosave-status')), findsOneWidget);
      await h.dispose();
    });
  });

  group('issue #316 review item 3: viewer-role gate on the "Log today" '
      'FAB', () {
    testWidgets('an accepted viewer guardian hides the FAB entirely -- '
        'deleting TodayLogFab\'s own "if (!_canLog) return '
        'SizedBox.shrink()" guard must fail this test', (tester) async {
      final h = Harness(tester);
      h.auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-doc'));
      await h.pump(
        seedGuardians: (db, profileId) => db.storage.applyRemoteRows([
          guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
        ]),
      );

      expect(find.byKey(const ValueKey('today-log-fab')), findsNothing);
      await h.dispose();
    });

    testWidgets('an accepted co-parent guardian keeps the FAB visible',
        (tester) async {
      final h = Harness(tester);
      h.auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-parent'));
      await h.pump(
        seedGuardians: (db, profileId) => db.storage.applyRemoteRows([
          guardianRow(profileId, 'g-parent', 'user-parent', 'co_parent'),
        ]),
      );

      expect(find.byKey(const ValueKey('today-log-fab')), findsOneWidget);
      await h.dispose();
    });
  });

  group('issue #316 review item 4: the FAB never covers Today/Calendar '
      'content', () {
    testWidgets('the overview\'s content sits above the FAB\'s top edge',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      final contentRect = tester.getRect(find.byType(OverviewPanel));
      final fabRect =
          tester.getRect(find.byKey(const ValueKey('today-log-fab')));
      expect(contentRect.bottom, lessThanOrEqualTo(fabRect.top),
          reason: 'the overview\'s own bottom edge must never reach into '
              'the FAB\'s footprint');
      await h.dispose();
    });

    testWidgets('the calendar\'s content sits above the FAB\'s top edge',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();

      final contentRect = tester.getRect(find.byType(MonthCalendar));
      final fabRect =
          tester.getRect(find.byKey(const ValueKey('today-log-fab')));
      expect(contentRect.bottom, lessThanOrEqualTo(fabRect.top),
          reason: 'the calendar\'s own bottom edge must never reach into '
              'the FAB\'s footprint');
      await h.dispose();
    });
  });

  group('issue #314: cycle history lives only on Insights', () {
    testWidgets(
        'exactly one history-card mounts once Today and Insights have '
        'both been visited -- CycleHistorySection is not duplicated '
        'across the shell\'s IndexedStack', (tester) async {
      final h = Harness(tester);
      await h.pump(seedEntries: seedEpisodes);

      // Today is the default tab: Overview must not mount its own copy.
      expect(find.byType(CycleHistorySection), findsNothing);
      expect(find.byKey(const ValueKey('history-card')), findsNothing);

      await tester.tap(tabKey('insights'));
      await tester.pumpAndSettle();
      expect(find.byType(CycleHistorySection), findsOneWidget);
      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);

      // Today stays mounted alongside Insights under the lazy
      // IndexedStack (issue #182) -- switching back must not surface a
      // second one.
      await tester.tap(tabKey('today'));
      await tester.pumpAndSettle();
      // Insights is still built under the IndexedStack (issue #182's lazy
      // keep-alive), just not the painted tab any more -- Flutter's
      // finders skip offstage elements by default, so `skipOffstage:
      // false` is what proves it is still there rather than disposed.
      expect(
        find.byType(CycleHistorySection, skipOffstage: false),
        findsOneWidget,
        reason: 'Insights stays built in the background, but Overview '
            'never adds a second CycleHistorySection',
      );
      expect(
        find.byKey(const ValueKey('history-card'), skipOffstage: false),
        findsOneWidget,
      );
      await h.dispose();
    });

    testWidgets(
        '"See cycle history" on Overview switches the shell to Insights '
        'via the #313 tab-switch seam', (tester) async {
      final h = Harness(tester);
      await h.pump(seedEntries: seedEpisodes);

      expect(
        find.byKey(const ValueKey('overview-see-history-link')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('overview-see-history-link')));
      await tester.pumpAndSettle();

      expect(find.byType(AnalysisTab), findsOneWidget);
      final navBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.insights.index,
          reason: 'the link switched the shell\'s own selected tab, not '
              'just pushed a new screen on top of it');
      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      await h.dispose();
    });
  });

  group('issue #313: Android back returns to Today before it exits', () {
    testWidgets(
        'system back from Calendar is intercepted and switches the shell '
        'back to Today rather than exiting', (tester) async {
      final h = Harness(tester);
      await h.pump();

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(popped, isTrue,
          reason: 'PopScope intercepted the pop, so the framework treats '
              'it as handled');
      expect(find.byType(NavigationBar), findsOneWidget,
          reason: 'still inside the shell -- the app did not exit');
      final navBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.today.index);
      expect(find.byType(MonthCalendar), findsNothing,
          reason: 'Calendar is no longer the painted tab -- a real tab '
              'switch, not a route pop');
      expect(find.byType(OverviewPanel), findsOneWidget,
          reason: 'Today is the painted tab now');
      await h.dispose();
    });

    testWidgets(
        'the shell\'s PopScope only blocks the pop away from Today',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      // `find.byType` requires an exact generic match and `PopScope`'s type
      // argument is inferred, not declared, at the app_shell.dart call
      // site -- a predicate keyed on `is PopScope` (dynamic's type-test
      // wildcard) finds it regardless of what that argument resolves to.
      // Scoped to descendants of AppShell so a PopScope mounted elsewhere in
      // the tree (e.g. by a route this test pushes later) can never make
      // `.single` ambiguous.
      PopScope popScope() => tester
          .widgetList<PopScope>(find.descendant(
            of: find.byType(AppShell),
            matching: find.byWidgetPredicate((w) => w is PopScope),
          ))
          .single;

      expect(popScope().canPop, isTrue,
          reason: 'Today is the default tab -- a back press here may exit');
      expect(await tester.binding.handlePopRoute(), isFalse,
          reason: 'canPop is true on Today, so PopScope lets the pop '
              'through; with nothing left to pop, the framework hands it '
              'back to the platform instead of handling it itself');

      await tester.tap(tabKey('insights'));
      await tester.pumpAndSettle();
      expect(popScope().canPop, isFalse);

      await tester.tap(tabKey('more'));
      await tester.pumpAndSettle();
      expect(popScope().canPop, isFalse);
      await h.dispose();
    });
  });

  group('issue #313: the Activity Feed action in the shell app bar', () {
    testWidgets(
        'present on Today, Calendar and Insights; absent on More (which '
        'carries its own app bar)', (tester) async {
      final h = Harness(tester);
      await h.pump();

      expect(find.byKey(const ValueKey('activity-feed-button')),
          findsOneWidget,
          reason: 'Today (the default tab)');

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('activity-feed-button')), findsOneWidget);

      await tester.tap(tabKey('insights'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('activity-feed-button')), findsOneWidget);

      await tester.tap(tabKey('more'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-feed-button')), findsNothing,
          reason: "More is Settings' own app bar, not the shell's");
      await h.dispose();
    });

    testWidgets(
        'tapping it opens the Activity feed through the app\'s one named '
        'route path', (tester) async {
      final h = Harness(tester);
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('activity-feed-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ActivityFeedScreen), findsOneWidget);
      final route =
          ModalRoute.of(tester.element(find.byType(ActivityFeedScreen)));
      expect(route?.settings.name, kRouteActivityFeedScreen);
      expect(kSentryRouteNames, contains(kRouteActivityFeedScreen));
      await h.dispose();
    });
  });

  group('issue #806: care notes are reachable for an active profile', () {
    testWidgets(
        'the shell app bar exposes care notes and opens them writable',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      expect(
        find.byKey(const ValueKey('care-notes-button')),
        findsOneWidget,
        reason: 'an active profile must not have to be archived to reach '
            'its care notes',
      );
      await tester.tap(find.byKey(const ValueKey('care-notes-button')));
      await tester.pumpAndSettle();

      expect(find.byType(CareNotesScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('care-note-field')),
        findsOneWidget,
        reason: 'a guardian whose role can log writes from the active '
            'profile',
      );
      await h.dispose();
    });

    testWidgets(
        'a viewer reaches the notes but gets no write affordance',
        (tester) async {
      final h = Harness(tester);
      h.auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-doc'));
      await h.pump(
        seedGuardians: (db, profileId) => db.storage.applyRemoteRows([
          guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
        ]),
      );

      await tester.tap(find.byKey(const ValueKey('care-notes-button')));
      await tester.pumpAndSettle();

      expect(find.byType(CareNotesScreen), findsOneWidget,
          reason: 'a viewer still reads the notes');
      expect(find.byKey(const ValueKey('care-note-field')), findsNothing);
      expect(find.byKey(const ValueKey('visit-prep-field')), findsNothing);
      expect(
        find.byKey(const ValueKey('care-read-only-reason')),
        findsOneWidget,
      );
      await h.dispose();
    });
  });

  group('issue #313: didUpdateWidget resets to Today only for a '
      'launch-payload profile switch', () {
    testWidgets(
        'GateController.setPendingLaunchProfileId resets an off-Today tab '
        'back to Today once the switch lands', (tester) async {
      final h = Harness(tester);
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);

      final profiles = DriftProfilesRepository(h.db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: false);
      await DriftSettingsStore(h.db.storage)
          .set(SettingsKeys.lastActiveProfile, alice.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<GateController>.value(
          value: gate,
          child: LunarLogApp.withCollaborators(db: h.db, authService: h.auth, syncEngine: h.engine),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);

      gate.setPendingLaunchProfileId(bob.id);
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget,
          reason: 'the launch payload switched the active profile');
      expect(find.byType(MonthCalendar), findsNothing,
          reason: 'the launch-payload switch reset the shell to Today');
      final navBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.today.index);
      await h.dispose();
    });

    testWidgets(
        'an ordinary profile switch (no launch payload) keeps the '
        'operator\'s current tab', (tester) async {
      final h = Harness(tester);
      final profiles = DriftProfilesRepository(h.db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: false);
      await DriftSettingsStore(h.db.storage)
          .set(SettingsKeys.lastActiveProfile, alice.id);

      await tester.pumpWidget(
          LunarLogApp.withCollaborators(db: h.db, authService: h.auth, syncEngine: h.engine));
      await tester.pumpAndSettle();

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);

      final controller =
          tester.element(find.byType(MonthCalendar)).read<ProfileController>();
      await controller.selectProfile(bob.id);
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget,
          reason: 'the switch happened');
      expect(find.byType(MonthCalendar), findsOneWidget,
          reason: 'an ordinary switch (no launch payload) keeps the tab '
              'the operator was on');
      await h.dispose();
    });
  });

  group('issue #623 (LLA-008): every launch-payload event is routed, not '
      'deduplicated for the profile\'s whole lifetime', () {
    testWidgets(
        'a notification naming the profile that is already active still '
        'resets the tab to Today', (tester) async {
      final h = Harness(tester);
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);

      final profiles = DriftProfilesRepository(h.db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await DriftSettingsStore(h.db.storage)
          .set(SettingsKeys.lastActiveProfile, alice.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<GateController>.value(
          value: gate,
          child: LunarLogApp.withCollaborators(
              db: h.db, authService: h.auth, syncEngine: h.engine),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);

      // Alice is already the active profile -- a plain `profile.id`
      // comparison (the pre-fix `resetToTodayOnProfileSwitch` shape) never
      // changes here, so AppShell's didUpdateWidget never saw a reason to
      // reset. A fresh launch token must still force Today.
      gate.setPendingLaunchProfileId(alice.id);
      await tester.pumpAndSettle();

      expect(find.byType(MonthCalendar), findsNothing,
          reason: 'a same-active-profile relaunch must still reset to '
              'Today -- LLA-008');
      final navBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.today.index);
      await h.dispose();
    });

    testWidgets(
        'a repeat notification for a profile is not silently dropped by the '
        'consumption guard', (tester) async {
      final h = Harness(tester);
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);

      final profiles = DriftProfilesRepository(h.db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: false);
      await DriftSettingsStore(h.db.storage)
          .set(SettingsKeys.lastActiveProfile, alice.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<GateController>.value(
          value: gate,
          child: LunarLogApp.withCollaborators(
              db: h.db, authService: h.auth, syncEngine: h.engine),
        ),
      );
      await tester.pumpAndSettle();

      // First launch for Bob: consumed, switches to Bob.
      gate.setPendingLaunchProfileId(bob.id);
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);

      // The operator switches back to Alice by hand (not a notification)
      // and moves off Today, exactly like the finding's repro.
      final controller =
          tester.element(find.byType(NavigationBar)).read<ProfileController>();
      await controller.selectProfile(alice.id);
      await tester.pumpAndSettle();
      await tester.tap(tabKey('calendar'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(MonthCalendar), findsOneWidget);

      // A second notification for the *same* profile (Bob) that the first
      // one already named: pre-fix, `_consuming` was left permanently set
      // to Bob's id after the first consumption, so this was silently
      // dropped and the app stayed on Alice/Calendar forever.
      gate.setPendingLaunchProfileId(bob.id);
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget,
          reason: 'the second Bob notification must still be routed -- '
              'LLA-008');
      expect(find.byType(MonthCalendar), findsNothing,
          reason: 'and it resets to Today like any other launch payload');
      await h.dispose();
    });
  });

  group(
      'issue #313 review: the Activity Feed action re-watches the feed on '
      'an in-place profile switch', () {
    testWidgets(
        'the new-activity badge follows whichever profile is active -- '
        'deleting _ActivityFeedButtonState.didUpdateWidget must fail this '
        'test', (tester) async {
      final h = Harness(tester);
      final profiles = DriftProfilesRepository(h.db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: false);
      await DriftSettingsStore(h.db.storage)
          .set(SettingsKeys.lastActiveProfile, alice.id);

      // Alice has one entry newer than her device-local last-seen stamp
      // (unseen activity, so the badge should show); Bob has no last-seen
      // stamp at all -- a first-ever visit marks nothing New, so his badge
      // should never show, on this device or any other.
      await h.db.storage.applyRemoteRows([
        RemoteDayEntryRow(
          id: 'e-alice',
          profileId: alice.id,
          localDate: LocalDate(2026, 8, 19).iso,
          tz: 'UTC',
          flow: flowFromDomain(FlowLevel.medium),
          tags: const ['cramps'],
          note: null,
          updatedAt: DateTime.utc(2026, 8, 20),
          deletedAt: null,
          loggedByUserId: 'user-dad',
        ),
      ]);
      await h.db.storage.setSetting(
        key: activityLastSeenKey(alice.id),
        value: DateTime.utc(2026, 8, 19).toIso8601String(),
      );

      await tester.pumpWidget(
          LunarLogApp.withCollaborators(db: h.db, authService: h.auth, syncEngine: h.engine));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-feed-button-new')),
          findsOneWidget,
          reason: 'Alice has activity newer than her last-seen stamp');

      final controller = tester
          .element(find.byType(NavigationBar))
          .read<ProfileController>();
      await controller.selectProfile(bob.id);
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget,
          reason: 'the in-place profile switch landed');
      expect(find.byKey(const ValueKey('activity-feed-button-new')),
          findsNothing,
          reason: 'the button must re-watch Bob\'s own feed rather than '
              'keep rendering Alice\'s stale snapshot from before the '
              'switch');

      await controller.selectProfile(alice.id);
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-feed-button-new')),
          findsOneWidget,
          reason: 'switching back re-watches Alice\'s feed again, so her '
              'still-unseen activity reappears');
      await h.dispose();
    });
  });
}
