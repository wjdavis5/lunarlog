/// Widget tests for the per-profile Activity feed (issue #124): row copy
/// and actor naming, the frozen unread marker, merge-outcome rows,
/// tap-through to the day sheet, the single-guardian quiet state, the
/// viewer's read-only path, and the two entry points.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/mappers.dart' show flowFromDomain;
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/fake_auth_service.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);
final DateTime kNow = DateTime.utc(2026, 8, 31, 12);

RemoteProfileGuardianRow guardianRow(
  String profileId,
  String userId,
  String role, {
  String? displayName,
  String status = 'accepted',
  DateTime? updatedAt,
}) =>
    RemoteProfileGuardianRow(
      id: 'g-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
    );

RemoteDayEntryRow entryRow(
  String profileId,
  String id,
  LocalDate date, {
  DateTime? updatedAt,
  String? loggedByUserId,
  String? lastModifiedByUserId,
  DateTime? deletedAt,
  FlowLevel flow = FlowLevel.medium,
  List<String> tags = const ['cramps'],
  String? note,
}) =>
    RemoteDayEntryRow(
      id: id,
      profileId: profileId,
      localDate: date.iso,
      tz: 'UTC',
      flow: flowFromDomain(flow),
      tags: tags,
      note: note,
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 20),
      deletedAt: deletedAt,
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

class Harness {
  Harness(this.db, this.profile, this.auth, this.authController);

  final LunarLogDatabase db;
  final Profile profile;
  final FakeAuthService? auth;
  final AuthController? authController;
}

/// The standard two-guardian seed: Mom (primary) and Dad (co-parent).
Future<void> seedShared(LunarLogDatabase db, String profileId) async {
  await db.storage.applyRemoteRows([
    guardianRow(profileId, 'user-mom', 'primary_guardian',
        displayName: 'Mom'),
    guardianRow(profileId, 'user-dad', 'co_parent', displayName: 'Dad'),
  ]);
}

Future<Harness> pumpActivity(
  WidgetTester tester, {
  FakeAuthService? auth,
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
  Widget Function(Profile profile, ActivityFeedRepository repository,
      LunarLogDatabase db)? screen,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) {
    await seed(db, profile.id);
  }
  final authController = auth == null ? null : AuthController(authService: auth);
  final activity = ActivityFeedRepository(db.storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: settings),
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
        Provider<LunarLogStorage>.value(value: db.storage),
        // ProfileDetailScreen reads this (switch-profile action).
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: profiles,
            settingsStore: settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
        home: screen == null
            ? _defaultScreen(profile, activity)
            : screen(profile, activity, db),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, profile, auth, authController);
}

Widget _defaultScreen(Profile profile, ActivityFeedRepository repository) =>
    ActivityFeedScreen(
      profile: profile,
      repository: repository,
      todayProvider: () => kToday,
      nowProvider: () => kNow,
    );

Future<void> disposeActivity(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  h.authController?.dispose();
  await h.auth?.dispose();
  await h.db.close();
}

/// Minimal [SharingService] fake: every method returns a stub; the
/// Manage-Guardians entry-point tests never invoke them.
class _StubSharingService implements SharingService {
  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) async {
    throw UnimplementedError();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a shared profile renders named rows, newest first, with the '
      'honesty caption', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-old', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-mom'),
          entryRow(profileId, 'e-new', LocalDate(2026, 8, 19),
              updatedAt: DateTime.utc(2026, 8, 21),
              loggedByUserId: 'user-dad'),
        ]);
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-feed-caption')),
        findsOneWidget);
    expect(find.text('Logged by Dad'), findsOneWidget);
    expect(find.text('Logged by Mom'), findsOneWidget);
    // Order: the newer row's title appears before the older one's.
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles.indexOf('Logged by Dad'), lessThan(titles.indexOf('Logged by Mom')));
    expect(find.byKey(const ValueKey('activity-item-entry:e-new')),
        findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('the current user\u2019s own rows read as "you" (AC2)',
      (tester) async {
    final auth = FakeAuthService()
      ..emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-mom'));
    final h = await pumpActivity(
      tester,
      auth: auth,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-mine', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-mom'),
          entryRow(profileId, 'e-dads', LocalDate(2026, 8, 19),
              loggedByUserId: 'user-dad'),
          // Mom logged, Dad edited: "Updated by Dad", "logged by you".
          entryRow(profileId, 'e-edited', LocalDate(2026, 8, 20),
              updatedAt: DateTime.utc(2026, 8, 22),
              loggedByUserId: 'user-mom',
              lastModifiedByUserId: 'user-dad'),
        ]);
      },
    );
    expect(find.text('Logged by you'), findsOneWidget);
    expect(find.text('Logged by Dad'), findsOneWidget);
    expect(find.text('Updated by Dad'), findsOneWidget);
    expect(
      find.textContaining('logged by you'),
      findsOneWidget,
      reason: 'the secondary-actor phrase must resolve "you" too',
    );

    // Signing out mid-visit re-resolves "you" to the guardian's name.
    auth.emit(AuthSessionState.signedOut);
    await tester.pumpAndSettle();
    expect(find.text('Logged by you'), findsNothing);
    expect(find.text('Logged by Mom'), findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('an unattributed (legacy/offline) row renders without an actor '
      'and without crashing (AC8)', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-legacy', LocalDate(2026, 8, 18)),
        ]);
      },
    );
    expect(find.text('Entry logged'), findsOneWidget);
    expect(find.textContaining('uuid'), findsNothing);
    expect(find.textContaining('by null'), findsNothing);
    await disposeActivity(tester, h);
  });

  testWidgets('a removed entry reads "Removed by <name>" and carries no '
      'payload facts', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-gone', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-dad',
              lastModifiedByUserId: 'user-dad',
              deletedAt: DateTime.utc(2026, 8, 22),
              updatedAt: DateTime.utc(2026, 8, 22)),
        ]);
      },
    );
    expect(find.text('Removed by Dad'), findsOneWidget);
    // The glance facts of the tombstoned payload never render.
    expect(find.textContaining('Medium'), findsNothing);
    await disposeActivity(tester, h);
  });

  testWidgets('a merge row says whose value was kept and whose was '
      'discarded (AC4)', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.setSetting(
          key: activityMergeEventsKey(profileId),
          value: encodeMergeEvents([
            MergeEvent(
              id: 'e-loser@2026-08-22T00:00:00.000Z',
              profileId: profileId,
              localDateIso: '2026-08-19',
              occurredAt: DateTime.utc(2026, 8, 22),
              winnerActorId: 'user-dad',
              loserActorId: 'user-mom',
              discardedNote: true,
              discardedFlow: false,
            ),
          ]),
        );
      },
    );
    expect(find.text("Sync merge kept Dad's version"), findsOneWidget);
    expect(find.textContaining("Mom's note was discarded"), findsOneWidget);
    // Tap-through still opens the surviving date's sheet (#198: its title
    // is the human-readable date now, not the raw ISO string).
    await tester.tap(find.byIcon(Icons.call_merge));
    await tester.pumpAndSettle();
    expect(find.text('Wed 19 Aug 2026'), findsOneWidget);
    await dismissSheet(tester);
    await disposeActivity(tester, h);
  });

  testWidgets('a revoked guardian row appears and names the removed guardian',
      (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await db.storage.applyRemoteRows([
          guardianRow(profileId, 'user-mom', 'primary_guardian',
              displayName: 'Mom'),
          guardianRow(profileId, 'user-dad', 'co_parent',
              displayName: 'Dad'),
          guardianRow(profileId, 'user-nanny', 'caregiver',
              displayName: 'Nanny',
              status: 'revoked',
              updatedAt: DateTime.utc(2026, 8, 21)),
          entryRow(profileId, 'e', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-mom'),
        ]);
      },
    );
    expect(find.text('Nanny no longer has access'), findsOneWidget);
    expect(find.text('Access to this profile was removed'), findsOneWidget);
    // A revoked-only row does not make the profile read as un-shared: mom
    // and dad are still accepted, so the feed renders.
    expect(find.text('Logged by Mom'), findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('tapping an entry row opens that date\u2019s day sheet (AC5)',
      (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-tap', LocalDate(2026, 8, 19),
              loggedByUserId: 'user-dad',
              note: 'tap note'),
        ]);
      },
    );
    await tester.tap(find.byKey(const ValueKey('activity-item-entry:e-tap')));
    await tester.pumpAndSettle();
    expect(find.text('2026-08-19'), findsWidgets);
    expect(find.byKey(const ValueKey('autosave-status')), findsOneWidget,
        reason: 'a non-viewer opens the sheet editable, as from the calendar');
    await dismissSheet(tester);
    await disposeActivity(tester, h);
  });

  testWidgets('a single-guardian profile shows the quiet state, not a feed '
      '(AC6)', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await db.storage.applyRemoteRows([
          guardianRow(profileId, 'user-mom', 'primary_guardian',
              displayName: 'Mom'),
          entryRow(profileId, 'e', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-mom'),
        ]);
      },
    );
    expect(find.text('Just you for now'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-feed-list')), findsNothing);
    await disposeActivity(tester, h);
  });

  testWidgets('a guardian-less (local-only) profile also shows the quiet '
      'state', (tester) async {
    final h = await pumpActivity(tester);
    expect(find.text('Just you for now'), findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('a shared profile with no entries shows "No activity yet"',
      (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
      },
    );
    expect(find.text('No activity yet'), findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('a viewer can read the feed and gets the read-only day sheet '
      '(AC7)', (tester) async {
    final auth = FakeAuthService()
      ..emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-viewer'));
    final h = await pumpActivity(
      tester,
      auth: auth,
      seed: (db, profileId) async {
        await db.storage.applyRemoteRows([
          guardianRow(profileId, 'user-mom', 'primary_guardian',
              displayName: 'Mom'),
          guardianRow(profileId, 'user-viewer', 'viewer',
              displayName: 'Grandma'),
          entryRow(profileId, 'e', LocalDate(2026, 8, 19),
              loggedByUserId: 'user-mom'),
        ]);
      },
    );
    // The feed itself renders for the viewer, naming the writer.
    expect(find.text('Logged by Mom'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-item-entry:e')));
    await tester.pumpAndSettle();
    // The sheet opens in the viewer read-only mode, with its named reason.
    expect(find.text('You have view-only access to this profile.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('autosave-status')), findsNothing);
    await dismissSheet(tester);
    await disposeActivity(tester, h);
  });

  testWidgets('rows newer than the last-seen stamp are marked New, the chips '
      'stay for the visit, and opening re-stamps (AC unread)', (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e-old', LocalDate(2026, 8, 18),
              updatedAt: DateTime.utc(2026, 8, 18),
              loggedByUserId: 'user-mom'),
          entryRow(profileId, 'e-new', LocalDate(2026, 8, 19),
              updatedAt: DateTime.utc(2026, 8, 20),
              loggedByUserId: 'user-dad'),
        ]);
        await db.storage.setSetting(
          key: activityLastSeenKey(profileId),
          value: DateTime.utc(2026, 8, 19).toIso8601String(),
        );
      },
    );
    expect(
      find.byKey(const ValueKey('activity-new-entry:e-new')),
      findsOneWidget,
      reason: 'the row stamped after the last-seen baseline is marked New',
    );
    expect(
      find.byKey(const ValueKey('activity-new-entry:e-old')),
      findsNothing,
    );
    // Opening the feed stamped a fresh baseline (device-local)...
    final stamped = await h.db.storage
        .getSetting(activityLastSeenKey(h.profile.id));
    expect(stamped, isNotNull);
    expect(DateTime.parse(stamped!), isNot(DateTime.utc(2026, 8, 19)));
    // ...but the chips are frozen for this visit.
    expect(find.byKey(const ValueKey('activity-new-entry:e-new')),
        findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('a first-ever visit (no baseline) marks nothing New',
      (tester) async {
    final h = await pumpActivity(
      tester,
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e', LocalDate(2026, 8, 18),
              loggedByUserId: 'user-mom'),
        ]);
      },
    );
    expect(find.text('New'), findsNothing);
    await disposeActivity(tester, h);
  });

  testWidgets('the profile screen offers the Activity action and it opens '
      'the feed', (tester) async {
    final h = await pumpActivity(
      tester,
      screen: (profile, repository, db) => ProfileDetailScreen(
        profile: profile,
        todayProvider: () => kToday,
      ),
      seed: (db, profileId) async {
        await seedShared(db, profileId);
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-feed-button')));
    await tester.pumpAndSettle();
    expect(find.text('Alice Activity'), findsOneWidget);
    await disposeActivity(tester, h);
  });

  testWidgets('the profile screen\u2019s Activity button shows the new dot '
      'only when something is newer than the baseline', (tester) async {
    // With an old baseline and a newer row: the dot shows.
    var h = await pumpActivity(
      tester,
      screen: (profile, repository, db) => ProfileDetailScreen(
        profile: profile,
        todayProvider: () => kToday,
      ),
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e', LocalDate(2026, 8, 19),
              updatedAt: DateTime.utc(2026, 8, 20),
              loggedByUserId: 'user-dad'),
        ]);
        await db.storage.setSetting(
          key: activityLastSeenKey(profileId),
          value: DateTime.utc(2026, 8, 19).toIso8601String(),
        );
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-button-new')),
        findsOneWidget);
    await disposeActivity(tester, h);

    // First-ever visit (no baseline): nothing is new, no dot.
    h = await pumpActivity(
      tester,
      screen: (profile, repository, db) => ProfileDetailScreen(
        profile: profile,
        todayProvider: () => kToday,
      ),
      seed: (db, profileId) async {
        await seedShared(db, profileId);
        await db.storage.applyRemoteRows([
          entryRow(profileId, 'e', LocalDate(2026, 8, 19),
              updatedAt: DateTime.utc(2026, 8, 20),
              loggedByUserId: 'user-dad'),
        ]);
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-button-new')),
        findsNothing);
    await disposeActivity(tester, h);
  });

  testWidgets('Manage Guardians offers the Activity action when handed a '
      'repository, and hides it when not', (tester) async {
    final h = await pumpActivity(
      tester,
      screen: (profile, repository, db) => ManageGuardiansScreen(
        profile: profile,
        guardiansRepository: ProfileGuardiansRepository(db.storage),
        sharingService: _StubSharingService(),
        currentUserId: null,
        activityRepository: repository,
      ),
      seed: (db, profileId) async {
        await seedShared(db, profileId);
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-feed-button')));
    await tester.pumpAndSettle();
    expect(find.text('Alice Activity'), findsOneWidget);
    await disposeActivity(tester, h);

    final h2 = await pumpActivity(
      tester,
      screen: (profile, repository, db) => ManageGuardiansScreen(
        profile: profile,
        guardiansRepository: ProfileGuardiansRepository(db.storage),
        sharingService: _StubSharingService(),
        currentUserId: null,
      ),
      seed: (db, profileId) async {
        await seedShared(db, profileId);
      },
    );
    expect(find.byKey(const ValueKey('activity-feed-button')), findsNothing);
    await disposeActivity(tester, h2);
  });
}

Future<void> dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}
