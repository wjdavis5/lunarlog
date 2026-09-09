/// Discoverability surfaces for family sharing (Issue #126):
/// owned-vs-shared grouping + role label, the co-managed indicator without
/// opening a menu, the outstanding-invitation badge outside Manage
/// Guardians (and cleared on cancel), offline badge-free rendering, and
/// viewer read-only surfaces.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_picker_screen.dart';
import 'package:lunarlog/ui/settings/family_sharing_section.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/sharing/open_manage_guardians.dart';
import 'package:lunarlog/ui/sharing/pending_invite_badge.dart';
import 'package:lunarlog/ui/sharing/profile_sharing_tile.dart';
import 'package:lunarlog/ui/sharing/sharing_overview_controller.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_settings_store.dart';

/// Compact [SharingService] fake: scripted pending invites per profile,
/// an optional list failure (offline), and a cancel that removes the row
/// like the server's terminal outcomes do.
class FakeSharing126 implements SharingService {
  final Map<String, List<PendingInvite>> pendingByProfile = {};
  Object? listError;
  InviteCancellation cancelOutcome = InviteCancellation.revoked;
  String? lastCancelledId;

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async {
    final error = listError;
    if (error != null) throw error;
    return List.of(pendingByProfile[profileId] ?? const []);
  }

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) async {
    lastCancelledId = invitationId;
    for (final invites in pendingByProfile.values) {
      invites.removeWhere((i) => i.invitationId == invitationId);
    }
    return cancelOutcome;
  }

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) =>
      throw UnimplementedError('not exercised by issue #126 tests');

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) =>
      throw UnimplementedError('not exercised by issue #126 tests');

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {}

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) async {}
}

/// Minimal [PredictionConnectionService] fake for the #151 merge-
/// integration coverage: the discoverability suite never arms, redeems,
/// or publishes — it only needs the Manage Guardians predictions section
/// to see a configured service that reports no live connection.
class _FakePredictionConnection151 implements PredictionConnectionService {
  @override
  Future<GeneratedPredictionInvite> createConnection({
    required String profileId,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) =>
      throw UnimplementedError('not exercised by issue #126 tests');

  @override
  Future<AcceptedPredictionConnection> acceptConnection({
    required String rawToken,
  }) =>
      throw UnimplementedError('not exercised by issue #126 tests');

  @override
  Future<void> revokeConnection({required String connectionId}) async {}

  @override
  Future<ActivePredictionConnection?> getActiveConnection(
          {required String profileId}) async =>
      null;

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async => const {};

  @override
  Future<List<IncomingPredictionConnection>> listIncomingConnections() async =>
      const [];

  @override
  Future<PredictionProjection?> fetchProjection(
          {required String profileId}) async =>
      null;

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) async {}
}

PendingInvite _invite(
  String profileId,
  String id, {
  GuardianRole role = GuardianRole.caregiver,
  String? label = 'Sitter',
}) =>
    PendingInvite(
      invitationId: id,
      profileId: profileId,
      role: role,
      recipientLabel: label,
      createdAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 9, 9),
    );

RemoteProfileGuardianRow _row(
  String profileId,
  int index,
  String userId,
  String role,
  String name,
) =>
    RemoteProfileGuardianRow(
      id: 'g-$profileId-$index',
      profileId: profileId,
      userId: userId,
      role: role,
      status: 'accepted',
      displayName: name,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<LunarLogDatabase> _pumpApp(
  WidgetTester tester, {
  FakeAuthService? auth,
  FakeSharing126? sharing,
  PredictionConnectionService? predictionConnectionService,
}) async {
  final db = LunarLogDatabase(NativeDatabase.memory());
  await tester.pumpWidget(LunarLogApp(
    db: db,
    authService: auth,
    sharingService: sharing,
    predictionConnectionService: predictionConnectionService,
  ));
  await tester.pumpAndSettle();
  return db;
}

Future<void> _disposeApp(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

FakeAuthService _signedInAs(String userId) {
  final auth = FakeAuthService();
  auth.emit(AuthSessionState.signedIn, user: AuthUser(id: userId));
  return auth;
}

/// Seeds Alice (Mom primary + Dad co-parent: owned, co-managed) and Zoe
/// (X primary + Mom viewer: shared with Mom), returning their ids.
Future<({String alice, String zoe})> _seedFamily(LunarLogDatabase db) async {
  final profiles = DriftProfilesRepository(db.storage);
  final alice =
      await profiles.create(displayName: 'Alice', isMinor: false);
  final zoe = await profiles.create(displayName: 'Zoe', isMinor: true);
  await db.storage.applyRemoteRows([
    _row(alice.id, 0, 'user-mom', 'primary_guardian', 'Mom'),
    _row(alice.id, 1, 'user-dad', 'co_parent', 'Dad'),
    _row(zoe.id, 0, 'user-x', 'primary_guardian', 'X'),
    _row(zoe.id, 1, 'user-mom', 'viewer', 'Mom'),
  ]);
  return (alice: alice.id, zoe: zoe.id);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'timed out waiting for condition');
}

/// Minimal [ProfilesRepository] for direct (non-app) pumps: a fixed list.
class _FixedProfilesRepository implements ProfilesRepository {
  _FixedProfilesRepository(this.profiles);
  final List<Profile> profiles;

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  Stream<List<Profile>> watch() => Stream.value(profiles);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(String id, String name) => Profile(
      id: id,
      displayName: name,
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('PendingInviteBadge', () {
    testWidgets('renders the outstanding count', (tester) async {
      final sharing = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a'), _invite('p-1', 'b')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: sharing),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is Tooltip && widget.message == '2 pending invitations'),
        findsOneWidget,
      );
    });

    testWidgets('empty list renders nothing', (tester) async {
      final sharing = FakeSharing126();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: sharing),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('a list failure renders no badge, no error, no spinner',
        (tester) async {
      final sharing = FakeSharing126()
        ..listError = const SharingFailure.network();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: sharing),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('bumping refreshToken refetches and clears the badge',
        (tester) async {
      final sharing = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a')];
      int token = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  PendingInviteBadge(
                    profileId: 'p-1',
                    sharingService: sharing,
                    refreshToken: token,
                  ),
                  TextButton(
                    onPressed: () => setState(() => token++),
                    child: const Text('refresh'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsOneWidget);

      sharing.pendingByProfile['p-1'] = const [];
      await tester.tap(find.text('refresh'));
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('changing profileId refetches for the new profile',
        (tester) async {
      final sharing = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: sharing),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-2', sharingService: sharing),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('swapping the service refetches from the new service',
        (tester) async {
      final first = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a')];
      final second = FakeSharing126();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: first),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInviteBadge(
                profileId: 'p-1', sharingService: second),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsNothing);
    });
  });

  group('ProfileSharingTile', () {
    const info = SharingProfileInfo(
        myRole: GuardianRole.primaryGuardian, acceptedCount: 2);

    testWidgets('co-managed row shows the count indicator plus badge',
        (tester) async {
      final sharing = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a')];
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileSharingTile(
              profile: _profile('p-1', 'Alice'),
              info: info,
              sharingService: sharing,
              refreshToken: 0,
              subtitle: 'Primary Guardian',
              onTap: () => tapped = true,
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('shared-indicator-p-1')),
          findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.byKey(const ValueKey('pending-invite-badge-p-1')),
          findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });

    testWidgets('viewer sees shared state but no badge is fetched',
        (tester) async {
      final sharing = FakeSharing126()
        ..pendingByProfile['p-1'] = [_invite('p-1', 'a')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileSharingTile(
              profile: _profile('p-1', 'Zoe'),
              info: const SharingProfileInfo(
                  myRole: GuardianRole.viewer, acceptedCount: 2),
              sharingService: sharing,
              refreshToken: 0,
              subtitle: 'Shared with me · Viewer',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('shared-indicator-p-1')),
          findsOneWidget);
      expect(find.byType(PendingInviteBadge), findsNothing);
      expect(find.text('Shared with me · Viewer'), findsOneWidget);
    });

    testWidgets('solo row without sharing renders with no trailing at all',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileSharingTile(
              profile: _profile('p-1', 'Solo'),
              info: const SharingProfileInfo(
                  myRole: GuardianRole.primaryGuardian, acceptedCount: 1),
              sharingService: null,
              refreshToken: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solo'), findsOneWidget);
      expect(find.byKey(const ValueKey('shared-indicator-p-1')), findsNothing);
      expect(find.byType(PendingInviteBadge), findsNothing);
    });
  });

  group('SharingOverviewController', () {
    test('derives info from rows, bumps the badge epoch, drops ids',
        () async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      try {
        final profile = await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        final controller = SharingOverviewController(
          storage: db.storage,
          currentUserId: 'user-mom',
        );
        var notified = 0;
        controller.addListener(() => notified++);

        expect(controller.badgeEpoch, 0);
        expect(controller.infoFor(profile.id).group,
            ProfileSharingGroup.owned);

        controller.observeProfiles([profile.id]);
        await db.storage.applyRemoteRows([
          _row(profile.id, 0, 'user-mom', 'primary_guardian', 'Mom'),
          _row(profile.id, 1, 'user-dad', 'co_parent', 'Dad'),
        ]);
        await _waitFor(
            () => controller.infoFor(profile.id).acceptedCount == 2);
        expect(controller.infoFor(profile.id).myRole,
            GuardianRole.primaryGuardian);
        expect(notified, greaterThan(0));

        controller.refreshBadges();
        expect(controller.badgeEpoch, 1);

        controller.observeProfiles(const []);
        expect(controller.infoFor(profile.id).group,
            ProfileSharingGroup.owned);
        expect(controller.infoFor(profile.id).acceptedCount, 0);

        controller.dispose();
      } finally {
        await db.close();
      }
    });
  });

  group('openManageGuardians', () {
    testWidgets('returns null when the build cannot open the screen',
        (tester) async {
      Future<void>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    result = openManageGuardians(context, _profile('p-1', 'A')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.byType(ManageGuardiansScreen), findsNothing);
    });
  });

  group('profile picker grouping (AC2) and indicators (AC3)', () {
    testWidgets('owned vs shared sections, roles, indicator, and badge',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        final ids = await _seedFamily(db);
        sharing.pendingByProfile[ids.alice] = [_invite(ids.alice, 'inv-1')];
        sharing.pendingByProfile[ids.zoe] = [_invite(ids.zoe, 'inv-9')];
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('my-profiles-header')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('shared-with-me-header')),
            findsOneWidget);
        // Owned section sits above the shared one.
        final ownedY =
            tester.getTopLeft(find.byKey(const ValueKey('my-profiles-header'))).dy;
        final sharedY = tester
            .getTopLeft(find.byKey(const ValueKey('shared-with-me-header')))
            .dy;
        expect(ownedY, lessThan(sharedY));

        // Zoe's row names the shared group and Mom's viewer role.
        expect(find.text('Shared with me · Viewer'), findsOneWidget);
        // Alice's row names Mom's primary role.
        expect(find.text('Primary Guardian'), findsOneWidget);

        // Co-managed Alice shows the count indicator without opening a menu.
        expect(
            find.byKey(ValueKey('shared-indicator-${ids.alice}')),
            findsOneWidget);
        // Zoe is shared too (X plus Mom): her indicator shows as well —
        // but no badge, since viewers never get a badge fetch.
        expect(
            find.byKey(ValueKey('shared-indicator-${ids.zoe}')),
            findsOneWidget);
        expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
        expect(
            find.byKey(ValueKey('pending-invite-badge-${ids.alice}')),
            findsOneWidget);
        expect(
            find.byKey(ValueKey('pending-invite-badge-${ids.zoe}')),
            findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('no sharing state renders the old flat list with no headers',
        (tester) async {
      final db = await _pumpApp(tester);
      try {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsOneWidget);
        expect(find.byKey(const ValueKey('my-profiles-header')), findsNothing);
        expect(
            find.byKey(const ValueKey('shared-with-me-header')), findsNothing);
        expect(find.textContaining('Created'), findsOneWidget);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('picker without storage renders a flat list (fallback)',
        (tester) async {
      final settings = FakeSettingsStore();
      addTearDown(settings.close);
      final profiles = [_profile('p-1', 'Alice')];
      final controller = ProfileController(
        profilesRepository: _FixedProfilesRepository(profiles),
        settingsStore: settings,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ProfileController>.value(
            value: controller,
            child: const ProfilePickerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-profiles-header')), findsNothing);
    });

    testWidgets('selecting a co-managed profile marks the shell header',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        await _seedFamily(db);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        // The active profile's header carries the co-managed mark — no
        // menu opened.
        expect(find.byKey(const ValueKey('profile-shared-indicator')),
            findsOneWidget);
        expect(
          find.byWidgetPredicate((widget) =>
              widget is Tooltip && widget.message == 'Shared · 2 guardians'),
          findsOneWidget,
        );
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('selecting a solo profile marks nothing in the shell header',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final db =
          await _pumpApp(tester, auth: auth, sharing: FakeSharing126());
      try {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Solo', isMinor: false);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Solo'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('profile-shared-indicator')),
            findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('an archived co-managed profile shows the detail shared chip',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final db =
          await _pumpApp(tester, auth: auth, sharing: FakeSharing126());
      try {
        final ids = await _seedFamily(db);
        await tester.pumpAndSettle();

        // Archive Alice through her row menu, then open her archived row.
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('profile-row-${ids.alice}')),
          matching: find.byType(PopupMenuButton<String>),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Archived (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('profile-shared-chip')),
            findsOneWidget);
        expect(find.text('Shared · 2 guardians'), findsOneWidget);

        // The chip routes to her Manage Guardians screen.
        await tester.tap(find.byKey(const ValueKey('profile-shared-chip')));
        await tester.pumpAndSettle();
        expect(find.byType(ManageGuardiansScreen), findsOneWidget);
        expect(find.text('Alice Caregivers'), findsOneWidget);
      } finally {
        await _disposeApp(tester, db);
      }
    });
  });

  group('pending-invite badge outside Manage Guardians (AC4)', () {
    testWidgets('cancelling inside Manage Guardians clears the picker badge',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        final ids = await _seedFamily(db);
        sharing.pendingByProfile[ids.alice] = [_invite(ids.alice, 'inv-1')];
        await tester.pumpAndSettle();
        expect(
            find.byKey(ValueKey('pending-invite-badge-${ids.alice}')),
            findsOneWidget);

        // Open Alice's row menu and route into Manage Guardians.
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('profile-row-${ids.alice}')),
          matching: find.byType(PopupMenuButton<String>),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caregivers'));
        await tester.pumpAndSettle();
        expect(find.text('Alice Caregivers'), findsOneWidget);
        expect(find.text('Sitter'), findsOneWidget);

        // Cancel the invitation and confirm.
        await tester.tap(find.byIcon(Icons.cancel_outlined));
        await tester.pumpAndSettle();
        await tester
            .tap(find.widgetWithText(FilledButton, 'Cancel Invitation'));
        await tester.pumpAndSettle();
        expect(sharing.lastCancelledId, 'inv-1');
        expect(find.text('Sitter'), findsNothing);

        // Back on the picker the badge is gone (the widget refetched on
        // return and now renders nothing); the shared indicator stays.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(Badge), findsNothing);
        expect(find.byKey(ValueKey('shared-indicator-${ids.alice}')),
            findsOneWidget);
      } finally {
        await _disposeApp(tester, db);
      }
    });
  });

  group('#151 merge integration', () {
    testWidgets(
        'badge and prediction affordances coexist, and the picker pushes '
        'Manage Guardians exactly once with both features wired',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(
        tester,
        auth: auth,
        sharing: sharing,
        predictionConnectionService: _FakePredictionConnection151(),
      );
      try {
        final ids = await _seedFamily(db);
        sharing.pendingByProfile[ids.alice] = [_invite(ids.alice, 'inv-2')];
        await tester.pumpAndSettle();

        // On the picker itself: the outstanding-invite badge on Alice's
        // row and the app-bar "shared with me" connection affordance are
        // both present — neither feature shadows the other.
        expect(find.byKey(ValueKey('pending-invite-badge-${ids.alice}')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('shared-with-me')), findsOneWidget);

        // Alice's row menu routes into Manage Guardians — one push only —
        // and that screen carries the pending-invite section AND the
        // #151 predictions section (Mom is Alice's primary guardian).
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('profile-row-${ids.alice}')),
          matching: find.byType(PopupMenuButton<String>),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caregivers'));
        await tester.pumpAndSettle();
        expect(find.text('Alice Caregivers'), findsOneWidget);
        expect(find.text('Sitter'), findsOneWidget);
        expect(find.text('Predictions-only sharing'), findsOneWidget);
        expect(find.byKey(const ValueKey('share-predictions')),
            findsOneWidget);

        // Cancelling inside Manage Guardians and a single pop lands back
        // on the picker with the badge cleared and everything else intact.
        await tester.tap(find.byIcon(Icons.cancel_outlined));
        await tester.pumpAndSettle();
        await tester
            .tap(find.widgetWithText(FilledButton, 'Cancel Invitation'));
        await tester.pumpAndSettle();
        expect(sharing.lastCancelledId, 'inv-2');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('profile-row-${ids.alice}')),
            findsOneWidget);
        expect(find.byType(Badge), findsNothing);
        expect(find.byKey(ValueKey('shared-indicator-${ids.alice}')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('shared-with-me')), findsOneWidget);
      } finally {
        await _disposeApp(tester, db);
      }
    });
  });

  group('offline rendering (AC5)', () {
    testWidgets('picker renders badge-free with no error and no spinner',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126()
        ..listError = const SharingFailure.network();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        final ids = await _seedFamily(db);
        await tester.pumpAndSettle();

        // Local rows still group and indicate sharing.
        expect(find.byKey(const ValueKey('my-profiles-header')),
            findsOneWidget);
        expect(find.text('Shared with me · Viewer'), findsOneWidget);
        expect(find.byKey(ValueKey('shared-indicator-${ids.alice}')),
            findsOneWidget);
        // But no badge anywhere, no error copy, and no spinner — settled.
        expect(find.byType(Badge), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('Could not load'), findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('settings section renders badge-free offline', (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126()
        ..listError = const SharingFailure.network();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        await _seedFamily(db);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('family-sharing-section')),
            findsOneWidget);
        expect(find.text('Family & sharing'), findsOneWidget);
        expect(find.byType(Badge), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('Could not load'), findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });
  });

  group('viewer read-only (AC6)', () {
    testWidgets('viewer sees rows and guardians but no invite/revoke controls',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        final ids = await _seedFamily(db);
        sharing.pendingByProfile[ids.zoe] = [_invite(ids.zoe, 'inv-9')];
        await tester.pumpAndSettle();

        // No badge for the viewer even with an outstanding invitation.
        expect(find.byKey(ValueKey('pending-invite-badge-${ids.zoe}')),
            findsNothing);

        // Into Zoe's Manage Guardians: guardians visible, controls absent.
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('profile-row-${ids.zoe}')),
          matching: find.byType(PopupMenuButton<String>),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caregivers'));
        await tester.pumpAndSettle();

        expect(find.text('Zoe Caregivers'), findsOneWidget);
        expect(find.text('X'), findsOneWidget);
        // No invite action, no revocation of others, no pending section —
        // but the viewer's own self-leave control stays, matching Manage
        // Guardians' own ladder.
        expect(find.byIcon(Icons.person_add), findsNothing);
        expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
        expect(find.byTooltip('Leave profile'), findsOneWidget);
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'X'),
            matching: find.byIcon(Icons.remove_circle_outline),
          ),
          findsNothing,
        );
        expect(find.text('Pending invitations'), findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('settings rows carry no invite or revoke affordance',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        await _seedFamily(db);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        final section =
            find.byKey(const ValueKey('family-sharing-section'));
        expect(section, findsOneWidget);
        expect(
            find.descendant(
                of: section, matching: find.byIcon(Icons.person_add)),
            findsNothing);
        expect(
            find.descendant(
                of: section, matching: find.byIcon(Icons.cancel_outlined)),
            findsNothing);
        expect(
            find.descendant(
                of: section,
                matching: find.byIcon(Icons.remove_circle_outline)),
            findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });
  });

  group('settings entry point (AC1)', () {
    testWidgets('section lists profiles and routes each to Manage Guardians',
        (tester) async {
      final auth = _signedInAs('user-mom');
      addTearDown(auth.dispose);
      final sharing = FakeSharing126();
      final db = await _pumpApp(tester, auth: auth, sharing: sharing);
      try {
        final ids = await _seedFamily(db);
        sharing.pendingByProfile[ids.alice] = [_invite(ids.alice, 'inv-1')];
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        // One tap from Settings lands on the labeled section.
        expect(find.byKey(const ValueKey('family-sharing-section')),
            findsOneWidget);
        expect(find.text('Family & sharing'), findsOneWidget);
        expect(find.byKey(ValueKey('family-sharing-row-${ids.alice}')),
            findsOneWidget);
        expect(find.byKey(ValueKey('family-sharing-row-${ids.zoe}')),
            findsOneWidget);
        expect(find.text('Shared with me · Viewer'), findsOneWidget);

        // A second tap routes Zoe's row to her Manage Guardians screen.
        await tester
            .tap(find.byKey(ValueKey('family-sharing-row-${ids.zoe}')));
        await tester.pumpAndSettle();
        expect(find.byType(ManageGuardiansScreen), findsOneWidget);
        expect(find.text('Zoe Caregivers'), findsOneWidget);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('no sharing service hides the section entirely',
        (tester) async {
      final db = await _pumpApp(tester);
      try {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('family-sharing-section')),
            findsNothing);
        expect(find.text('Family & sharing'), findsNothing);
      } finally {
        await _disposeApp(tester, db);
      }
    });

    testWidgets('section hides with no profiles and without a repository',
        (tester) async {
      final settings = FakeSettingsStore();
      addTearDown(settings.close);
      // No profiles at all.
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<SettingsStore>.value(value: settings),
              Provider<ProfilesRepository>.value(
                  value: _FixedProfilesRepository(const [])),
            ],
            child: const Scaffold(body: FamilySharingSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family-sharing-section')), findsNothing);

      // And with no repository or sharing service provided at all.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FamilySharingSection()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family-sharing-section')), findsNothing);
    });
  });
}
