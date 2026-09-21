/// Widget tests for the household view (issue #803): the profile picker's
/// multi-profile enrichment — per-profile timing/silence/changes signals
/// on one screen, the log-for-her flow (opens that profile's day sheet for
/// today without switching the active profile, and the dismissal lands
/// back on the household view), the single-profile behaviour-unchanged
/// contract, the viewer role's missing log action, and the
/// content-discretion rule (no note body, no symptom label — ever).
///
/// Harness: the real app tree over an in-memory drift database
/// (`LunarLogApp.withCollaborators`), the same shape `profiles_test.dart`
/// uses, so the signals read the same streams production does — the
/// prediction service, the derived activity feed, and the day-entries
/// watcher. All dates are computed relative to the real `LocalDate.today()`
/// because the picker has no injected today provider.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/mappers.dart' show flowFromDomain;
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';

import '../../support/fake_auth_service.dart';

/// Wide viewport: three enriched rows must fit without scrolling so the
/// one-screen assertion below is honest. The returned db must be released
/// with [_disposeHousehold] as the last statement of the test body — the
/// same discipline `profiles_test.dart`'s [disposeApp] documents: the
/// binding does its own tree cleanup before addTearDown callbacks may
/// pump, so the drift query-stream close timers must be drained inside
/// the body.
Future<LunarLogDatabase> _pumpHousehold(
  WidgetTester tester, {
  required Future<void> Function(LunarLogDatabase db) seed,
  FakeAuthService? auth,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  await seed(db);
  await tester.pumpWidget(
    LunarLogApp.withCollaborators(db: db, authService: auth),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Must run as the last statement of every test that used
/// [_pumpHousehold] (see its doc comment).
Future<void> _disposeHousehold(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

Future<Profile> _profile(
  LunarLogDatabase db,
  String name, {
  ProfileMode mode = ProfileMode.standard,
}) =>
    DriftProfilesRepository(db.storage)
        .create(displayName: name, isMinor: false, mode: mode);

Future<void> _entry(
  LunarLogDatabase db,
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.medium,
  String? note,
  List<String> tags = const [],
  DateTime? updatedAt,
}) => db.storage.upsertDayEntry(
  profileId: profileId,
  localDate: date.iso,
  tz: 'UTC',
  flow: flowFromDomain(flow),
  note: note,
  tags: tags,
  updatedAt: updatedAt,
);

/// The guardian-row fixture `activity_feed_test.dart` uses, local to this
/// file so the viewer test can stamp roles for the signed-in operator.
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String userId,
  String role,
) => RemoteProfileGuardianRow(
  id: 'g-$profileId-$userId',
  profileId: profileId,
  userId: userId,
  role: role,
  status: 'accepted',
  displayName: null,
  invitedBy: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  testWidgets(
    'an account holding three profiles shows timing, silence and change '
    'signals for them on one screen, without opening any profile (AC)',
    (tester) async {
      final today = LocalDate.today();
      late final String aliceId;
      late final String barbId;
      late final String clareId;
      final db = await _pumpHousehold(
        tester,
        seed: (db) async {
          final alice = await _profile(db, 'Alice');
          final barb = await _profile(db, 'Barb');
          final clare = await _profile(db, 'Clare');
          aliceId = alice.id;
          barbId = barb.id;
          clareId = clare.id;
          // Alice: history, but the last log is 12 days old — silence at the
          // unconfigured default threshold.
          await _entry(db, alice.id, today.addDays(-12));
          // Barb: logged today, and that write landed after the feed's
          // last-seen baseline — one unread change.
          await _entry(db, barb.id, today, updatedAt: DateTime.now());
          await db.storage.setSetting(
            key: activityLastSeenKey(barb.id),
            value: DateTime.now()
                .subtract(const Duration(days: 5))
                .toIso8601String(),
          );
          // Clare: fresh profile — neither silent nor unread, so no signal
          // lines at all.
        },
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Barb'), findsOneWidget);
      expect(find.text('Clare'), findsOneWidget);

      expect(
        find.byKey(ValueKey('household-silence-$aliceId')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('household-silence-$aliceId')))
            .data,
        'Nothing logged for 12 days',
      );
      expect(find.byKey(ValueKey('household-changes-$barbId')), findsOneWidget);
      expect(
        find.byKey(ValueKey('household-silence-$barbId')),
        findsNothing,
        reason: 'logged today: not silent',
      );
      expect(
        find.byKey(ValueKey('household-silence-$clareId')),
        findsNothing,
        reason: 'a fresh profile is never "silent" — it has no history',
      );
      expect(
        find.byKey(ValueKey('household-changes-$clareId')),
        findsNothing,
        reason: 'never opened the feed: no baseline, never "new"',
      );
      // One episode only: the prediction carries no timing line, so the row
      // shows silence alone.
      expect(find.byKey(ValueKey('household-timing-$aliceId')), findsNothing);
      expect(
        find.byKey(ValueKey('log-today-$aliceId')),
        findsOneWidget,
        reason: 'the row also carries the log-for-her action',
      );
      await _disposeHousehold(tester, db);
    },
  );

  testWidgets(
    'a single-profile account sees no household enrichment — rows render '
    'exactly as before (AC behaviour unchanged)',
    (tester) async {
      final db = await _pumpHousehold(
        tester,
        seed: (db) async {
          await _profile(db, 'Alice');
        },
      );

      expect(find.text('Alice'), findsOneWidget);
      final aliceId = (await DriftProfilesRepository(
        db.storage,
      ).list()).single.id;
      expect(
        find.byKey(ValueKey('log-today-$aliceId')),
        findsNothing,
        reason: 'no log-for-her action on a single-profile account',
      );
      expect(
        find.byKey(ValueKey('household-silence-$aliceId')),
        findsNothing,
        reason: 'no signal lines on a single-profile account',
      );
      expect(find.byKey(ValueKey('household-changes-$aliceId')), findsNothing);
      await _disposeHousehold(tester, db);
    },
  );

  testWidgets(
    'log-for-her: "Log today" on Barb\'s row opens Barb\'s day sheet for '
    'today without switching profiles, the write lands on Barb, and the '
    'dismissal returns to the household view (AC)',
    (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-me', email: 'me@example.com'),
      );
      addTearDown(auth.dispose);
      final today = LocalDate.today();
      final db = await _pumpHousehold(
        tester,
        auth: auth,
        seed: (db) async {
          await _profile(db, 'Alice');
          await _profile(db, 'Barb');
        },
      );

      final rows = await DriftProfilesRepository(db.storage).list();
      final barb = rows.singleWhere((p) => p.displayName == 'Barb');
      final alice = rows.singleWhere((p) => p.displayName == 'Alice');

      // Tap 1: the row action (tap 2 was opening the household view).
      await tester.tap(find.byKey(ValueKey('log-today-${barb.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);

      // The sheet autosaves on change (#198); tap Medium and give the
      // debounce a beat.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
      await tester.pump(const Duration(milliseconds: 700));

      // Dismissal flushes the change and lands back on the household view.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // The write landed on Barb, for today, with the tapped flow.
      final repository = DriftDayEntriesRepository(db.storage);
      final saved = await repository.find(barb.id, today);
      expect(saved, isNotNull, reason: 'the day-sheet save landed on Barb');
      expect(saved!.flow, FlowLevel.medium);
      expect(
        await repository.find(alice.id, today),
        isNull,
        reason: 'the other profile is untouched',
      );
      expect(find.byType(DaySheet), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Barb'), findsOneWidget);
      expect(
        await db.storage.getSetting(SettingsKeys.lastActiveProfile),
        isNull,
        reason: 'the active-profile pointer never moved: no manual switch',
      );
      await _disposeHousehold(tester, db);
    },
  );

  testWidgets(
    'AC: an irregular-mode profile never reads "late" on the household '
    'view, while the standard profile beside it does (#853)',
    (tester) async {
      final today = LocalDate.today();
      // Four 4-day episodes on 28-day gaps, the last starting 32 days ago:
      // the standard profile's estimate is ~4 days past due; the irregular
      // profile carries the same history under the #853 framing.
      late final String aliceId;
      late final String clareId;
      final db = await _pumpHousehold(
        tester,
        seed: (db) async {
          final alice = await _profile(db, 'Alice');
          final clare = await _profile(
            db,
            'Clare',
            mode: ProfileMode.irregular,
          );
          aliceId = alice.id;
          clareId = clare.id;
          for (final profileId in [alice.id, clare.id]) {
            for (final start in [
              today.addDays(-116),
              today.addDays(-88),
              today.addDays(-60),
              today.addDays(-32),
            ]) {
              for (var i = 0; i < 4; i++) {
                await _entry(db, profileId, start.addDays(i));
              }
            }
          }
        },
      );

      final standardLine = tester
          .widget<Text>(find.byKey(ValueKey('household-timing-$aliceId')))
          .data!;
      expect(standardLine, '4 days past the estimate');

      final framedLine = tester
          .widget<Text>(find.byKey(ValueKey('household-timing-$clareId')))
          .data!;
      expect(
        framedLine.contains('late'),
        isFalse,
        reason: 'the #853 framing never says late',
      );
      expect(framedLine, 'Last period 32 days ago');
      await _disposeHousehold(tester, db);
    },
  );

  testWidgets(
    'a viewer-role guardian gets no "Log today" action on the shared row '
    '(constraint: a viewer sees status, not the action)',
    (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-me', email: 'me@example.com'),
      );
      addTearDown(auth.dispose);
      final db = await _pumpHousehold(
        tester,
        auth: auth,
        seed: (db) async {
          final alice = await _profile(db, 'Alice');
          final barb = await _profile(db, 'Barb');
          await db.storage.applyRemoteRows([
            guardianRow(alice.id, 'user-me', 'viewer'),
            guardianRow(barb.id, 'user-me', 'primary_guardian'),
          ]);
        },
      );

      final rows = await DriftProfilesRepository(db.storage).list();
      final alice = rows.singleWhere((p) => p.displayName == 'Alice');
      final barb = rows.singleWhere((p) => p.displayName == 'Barb');
      expect(
        find.byKey(ValueKey('log-today-${alice.id}')),
        findsNothing,
        reason: 'viewer: no log action',
      );
      expect(
        find.byKey(ValueKey('log-today-${barb.id}')),
        findsOneWidget,
        reason: 'primary guardian keeps the action',
      );
      await _disposeHousehold(tester, db);
    },
  );

  testWidgets('content discretion: a note body and a symptom label are never '
      'rendered on the household view (AC)', (tester) async {
    final today = LocalDate.today();
    final db = await _pumpHousehold(
      tester,
      seed: (db) async {
        final alice = await _profile(db, 'Alice');
        final barb = await _profile(db, 'Barb');
        await _entry(
          db,
          alice.id,
          today.addDays(-12),
          note: 'Confidential cramping details xyzzy',
          tags: const ['headache'],
        );
        await _entry(db, barb.id, today.addDays(-9));
      },
    );

    expect(
      find.textContaining('Confidential'),
      findsNothing,
      reason: 'no note body on the household view',
    );
    expect(find.textContaining('xyzzy'), findsNothing);
    expect(
      find.textContaining('Headache'),
      findsNothing,
      reason: 'no symptom labels — status words and counts only',
    );
    expect(find.textContaining('headache'), findsNothing);
    await _disposeHousehold(tester, db);
  });
}
