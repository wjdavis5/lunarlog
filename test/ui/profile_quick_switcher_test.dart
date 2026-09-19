/// App-level tests for issue #241: the app shell's quick profile switcher
/// (popup listing active profiles with avatars + "Manage profiles…"), and
/// the picker's ProfileCard rows (avatar, cycle status, overflow menu).
/// Month preservation across a quick switch is asserted here end-to-end
/// through the real shell; the calendar's own switch decision (and the
/// pure `hasEntriesInMonth` predicate) is covered by
/// `test/ui/calendar_navigation_test.dart`, and the card's per-state
/// rendering by `test/ui/components/profile_card_test.dart`.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/components/app_shell.dart' show AppShell;
import 'package:lunarlog/ui/l10n/dates.dart' show monthNames;

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  final FakeAuthService auth = FakeAuthService();
  final FakeSyncEngine engine = FakeSyncEngine();

  String? aliceId;
  String? bobId;
  String? charlieId;

  /// Three profiles; [seedEntries] runs after they exist but before the
  /// widget pumps. With no [activeProfile] the app opens on the picker;
  /// with one set ('alice'/'bob'/'charlie') it opens on that profile's
  /// AppShell.
  Future<void> pump({
    Future<void> Function(DriftDayEntriesRepository entries)? seedEntries,
    String? activeProfile,
  }) async {
    final profiles = DriftProfilesRepository(db.storage);
    final alice =
        await profiles.create(displayName: 'Alice', isMinor: false);
    final bob = await profiles.create(displayName: 'Bob', isMinor: false);
    final charlie =
        await profiles.create(displayName: 'Charlie', isMinor: false);
    aliceId = alice.id;
    bobId = bob.id;
    charlieId = charlie.id;
    final entries = DriftDayEntriesRepository(db.storage);
    if (seedEntries != null) {
      await seedEntries(entries);
    }
    final active = switch (activeProfile) {
      'alice' => alice.id,
      'bob' => bob.id,
      'charlie' => charlie.id,
      _ => null,
    };
    if (active != null) {
      await DriftSettingsStore(db.storage)
          .set(SettingsKeys.lastActiveProfile, active);
    }
    await tester.pumpWidget(LunarLogApp.withCollaborators(
      db: db,
      authService: auth,
      syncEngine: engine,
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

DayEntry _bleed(String profileId, LocalDate date) => DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the quick switcher lists active profiles with avatars and '
      'switches in place', (tester) async {
    final h = Harness(tester);
    await h.pump(activeProfile: 'alice');

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-shell-profile-switcher')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('quick-switcher-profile-${h.aliceId}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('quick-switcher-profile-${h.bobId}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('quick-switcher-profile-${h.charlieId}')),
        findsOneWidget,
        reason: 'every active profile is listed');
    expect(
        find.byKey(ValueKey('profile-avatar-${h.bobId}')), findsOneWidget,
        reason: 'the listed rows carry the ProfileCard avatar');

    await tester.tap(find.byKey(ValueKey('quick-switcher-profile-${h.bobId}')));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget,
        reason: 'the switch happened in place — no picker round trip');
    expect(find.text('Bob'), findsOneWidget,
        reason: "the app bar now names the newly selected profile");
    await h.dispose();
  });

  testWidgets('the app bar shows the active profile avatar, and the '
      'switcher rows show each profile\'s cycle status (issue #811)',
      (tester) async {
    final h = Harness(tester);
    await h.pump(activeProfile: 'alice');

    // Issue #811: the active profile is identifiable on every tab without
    // opening the switcher — the app-bar avatar carries its initial.
    expect(find.byKey(ValueKey('profile-avatar-${h.aliceId}')),
        findsOneWidget);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-shell-profile-switcher')));
    await tester.pumpAndSettle();

    // Issue #811: every switcher row now carries the same one-line status
    // the picker's ProfileCard renders (reused, not reinvented).
    for (final id in [h.aliceId, h.bobId, h.charlieId]) {
      expect(find.byKey(ValueKey('profile-cycle-status-$id')),
          findsOneWidget);
    }
    expect(find.text('No history yet'), findsNWidgets(3));
    await h.dispose();
  });

  testWidgets('the picker\'s rows are ProfileCards: avatar, cycle status, '
      'and the per-row overflow menu preserved (issue #241)', (tester) async {
    final h = Harness(tester);
    await h.pump();

    expect(find.text('Profiles'), findsOneWidget);
    for (final id in [h.aliceId, h.bobId, h.charlieId]) {
      expect(find.byKey(ValueKey('profile-avatar-$id')), findsOneWidget,
          reason: 'each active row carries its deterministic-hue avatar');
      expect(find.byKey(ValueKey('profile-cycle-status-$id')), findsOneWidget);
    }
    // No profile has any entry yet, so every status reads the
    // no-history line (sourced from CyclePredictionService).
    expect(find.text('No history yet'), findsNWidgets(3));
    // The pre-#241 created-date subtitle survives as the secondary line.
    expect(find.textContaining('Created'), findsNWidgets(3));

    // The overflow menu is preserved on the card: every action the bare
    // ListTile used to carry is still reachable.
    await tester.tap(find.byTooltip('Profile actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Guardians'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('a logged history reads as a cycle-day status line',
      (tester) async {
    final h = Harness(tester);
    final today = LocalDate.today();
    // Bob: four completed 28-day cycles, the current one open on a bleed
    // that started yesterday — "Period, day 2".
    await h.pump(
      seedEntries: (entries) async {
        for (var k = 4; k >= 1; k--) {
          final start = today.addDays(-1 - 28 * k);
          for (var i = 0; i < 4; i++) {
            await entries.save(_bleed(h.bobId!, start.addDays(i)));
          }
        }
        for (var i = 0; i < 4; i++) {
          await entries.save(_bleed(h.bobId!, today.addDays(-1 + i)));
        }
      },
    );

    expect(find.text('Period, day 2'), findsOneWidget,
        reason: "Bob's row reads the in-period cycle status");
    expect(find.text('No history yet'), findsNWidgets(2),
        reason: 'Alice and Charlie still read the no-history line');
    await h.dispose();
  });

  testWidgets('a quick switch keeps the displayed calendar month when the '
      'new profile has entries in it, and resets when it does not',
      (tester) async {
    final h = Harness(tester);
    final today = LocalDate.today();
    // The month two months back is what the test navigates to; Alice and
    // Bob both have an entry there, Charlie does not.
    var targetYear = today.year;
    var targetMonth = today.month - 2;
    if (targetMonth <= 0) {
      targetMonth += 12;
      targetYear -= 1;
    }
    final targetLabel = '${monthNames()[targetMonth - 1]} $targetYear';
    await h.pump(
      activeProfile: 'alice',
      seedEntries: (entries) async {
        await entries.save(
            _bleed(h.aliceId!, LocalDate(targetYear, targetMonth, 15)));
        await entries.save(
            _bleed(h.bobId!, LocalDate(targetYear, targetMonth, 20)));
      },
    );

    await tester.tap(find.byKey(const ValueKey('app-shell-tab-calendar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(targetLabel), findsOneWidget);

    // Switch to Bob: he has an entry in the displayed month, so the
    // calendar keeps its place (issue #241 B-16).
    await tester.tap(find.byKey(const ValueKey('app-shell-profile-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('quick-switcher-profile-${h.bobId}')));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(targetLabel), findsOneWidget,
        reason: 'the quick switch preserved the displayed month');

    // Switch to Charlie: no entry there, so the calendar falls back to
    // today's month (the pre-#241 behavior).
    await tester.tap(find.byKey(const ValueKey('app-shell-profile-switcher')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('quick-switcher-profile-${h.charlieId}')));
    await tester.pumpAndSettle();
    final todayLabel = '${monthNames()[today.month - 1]} ${today.year}';
    expect(find.text(todayLabel), findsOneWidget,
        reason: "the empty profile reset the calendar to today's month");
    await h.dispose();
  });
}
