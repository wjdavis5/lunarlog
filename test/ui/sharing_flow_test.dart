import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/sharing/transfer_ownership_screen.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_notification_preferences_service.dart';

class FakeSharingService implements SharingService {
  GeneratedInvite? scriptedInvite;
  AcceptedInviteResult? scriptedAccept;
  String? lastRevokedUserId;
  String? lastCreatedRole;

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) async {
    lastCreatedRole = role.toDb();
    return scriptedInvite ??
        GeneratedInvite(
          invitationId: 'inv-1',
          profileId: profileId,
          role: role,
          rawToken: 'raw-token-xyz',
          tokenHash: 'token-hash-xyz',
          inviteUri: Uri.parse('lunarlog://invite?code=raw-token-xyz&profile=$profileId'),
          expiresAt: DateTime.utc(2026, 9, 6),
        );
  }

  Object? scriptedError;

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) async {
    if (scriptedError != null) {
      throw scriptedError!;
    }
    return scriptedAccept ??
        const AcceptedInviteResult(
          profileId: 'p-1',
          profileName: 'Luna',
          role: GuardianRole.coParent,
        );
  }

  Object? scriptedRevokeError;

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {
    if (scriptedRevokeError != null) {
      throw scriptedRevokeError!;
    }
    lastRevokedUserId = targetUserId;
  }

  List<PendingInvite> scriptedPendingInvites = const [];
  Object? scriptedListError;
  int listPendingInvitesCallCount = 0;

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async {
    listPendingInvitesCallCount++;
    if (scriptedListError != null) {
      throw scriptedListError!;
    }
    return scriptedPendingInvites;
  }

  InviteCancellation scriptedCancelOutcome = InviteCancellation.revoked;
  Object? scriptedCancelError;
  String? lastCancelledInvitationId;

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) async {
    lastCancelledInvitationId = invitationId;
    if (scriptedCancelError != null) {
      throw scriptedCancelError!;
    }
    // Every outcome is terminal (R5): the row would no longer satisfy a
    // fresh listPendingInvites' live-invitation filter either way, so a
    // scripted fake mirrors that instead of requiring each test to
    // manually re-script the list after cancelling.
    scriptedPendingInvites = scriptedPendingInvites
        .where((i) => i.invitationId != invitationId)
        .toList();
    return scriptedCancelOutcome;
  }

  String? lastRoleChangeUserId;
  GuardianRole? lastRoleChangeNewRole;
  Object? scriptedRoleChangeError;

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) async {
    if (scriptedRoleChangeError != null) {
      throw scriptedRoleChangeError!;
    }
    lastRoleChangeUserId = targetUserId;
    lastRoleChangeNewRole = newRole;
  }
}

/// Hand-written [OwnershipTransferService] fake for U10's claim-sheet and
/// deep-link routing tests. Only [claimProfile] is exercised here; the
/// arm/cancel paths belong to U9's own tests.
class FakeOwnershipTransferService implements OwnershipTransferService {
  ClaimedProfileResult? scriptedClaim;
  Object? scriptedClaimError;
  final claimCalls =
      <({String rawToken, String? childDisplayName, String? parentDisplayName})>[];

  @override
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<void> cancelTransfer({required String transferId}) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<ActiveTransfer?> getActiveTransfer({required String profileId}) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  }) async {
    claimCalls.add((
      rawToken: rawToken,
      childDisplayName: childDisplayName,
      parentDisplayName: parentDisplayName,
    ));
    if (scriptedClaimError != null) {
      throw scriptedClaimError!;
    }
    return scriptedClaim ??
        const ClaimedProfileResult(
          profileId: 'p-1',
          profileName: 'Luna',
          parentRole: 'co_parent',
          entriesTransferred: 12,
        );
  }
}

void main() {
  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late FakeSharingService sharingService;
  late Profile testProfile;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    sharingService = FakeSharingService();
    testProfile = profileToDomain(await storage.upsertProfile(displayName: 'Luna', isMinor: true));
  });

  tearDown(() async {
    await db.close();
  });

  group('InviteGuardianDialog', () {
    testWidgets('creates invite link and shows copy action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InviteGuardianDialog(
              profileId: testProfile.id,
              profileName: testProfile.displayName,
              sharingService: sharingService,
            ),
          ),
        ),
      );

      expect(find.text('Invite Caregiver to Luna'), findsOneWidget);
      expect(find.text('Create Link'), findsOneWidget);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(find.text('Invitation Created'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(sharingService.lastCreatedRole, 'co_parent');
    });
  });

  group('AcceptInviteSheet', () {
    testWidgets('allows entering display name and accepting invite', (tester) async {
      AcceptedInviteResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AcceptInviteSheet(
              rawToken: 'test-raw-token',
              sharingService: sharingService,
              onAccepted: (r) => result = r,
            ),
          ),
        ),
      );

      expect(find.text('Join Shared Profile'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Dad');
      await tester.tap(find.text('Accept & Sync'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.profileName, 'Luna');
      expect(result!.role, GuardianRole.coParent);
    });

    testWidgets('shows error message when acceptInvite fails', (tester) async {
      final failingService = FakeSharingService()
        ..scriptedError = const SharingFailure.expired();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AcceptInviteSheet(
              rawToken: 'test-raw-token',
              sharingService: failingService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Accept & Sync'));
      await tester.pumpAndSettle();

      expect(find.text('This invitation has expired.'), findsOneWidget);
    });

    testWidgets('shows error message on unexpected exception', (tester) async {
      final failingService = FakeSharingService()
        ..scriptedError = Exception('network crashed');
      final log = BreadcrumbLog();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AcceptInviteSheet(
              rawToken: 'test-raw-token',
              sharingService: failingService,
              breadcrumbLog: log,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Accept & Sync'));
      await tester.pumpAndSettle();

      expect(find.text('An unexpected error occurred.'), findsOneWidget);
      expect(log.snapshot(), ['sharing: _Exception']);
      expect(log.snapshot().single, isNot(contains('network crashed')));
    });
  });

  group('ManageGuardiansScreen', () {
    RemoteProfileGuardianRow guardianRow(
      String id,
      String userId,
      String role,
      String? displayName, {
      int serverVersion = 1,
    }) =>
        RemoteProfileGuardianRow(
          id: id,
          profileId: testProfile.id,
          userId: userId,
          role: role,
          status: 'accepted',
          displayName: displayName,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          serverVersion: serverVersion,
        );

    testWidgets('renders active guardians and handles revocation', (tester) async {
      // The server always carries the creator's primary row; seed it so
      // the caller's role resolves (mom = primary_guardian).
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('Co-Parent'), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);

      // Tap the revoke icon on Dad's row (Mom's own row offers self-leave).
      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'Dad'),
        matching: find.byIcon(Icons.remove_circle_outline),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Remove Dad?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRevokedUserId, 'user-dad');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('hides invite and revocation controls from a caregiver (U8)',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-sitter',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No invite button for a caregiver.
      expect(find.byIcon(Icons.person_add), findsNothing);
      // No revocation for anyone else; only self-leave is offered.
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byTooltip('Leave profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('co-parent cannot remove the primary guardian (R4)',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-dad',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A co-parent can invite...
      expect(find.byIcon(Icons.person_add), findsOneWidget);
      // ...and can revoke the caregiver, but not the primary guardian or
      // another co-parent: two remove controls (Sue + self-leave), none
      // on Mom's row.
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));
      // Confirm Mom's row actually rendered before asserting it carries no
      // remove control — otherwise a rendering regression could make this
      // pass vacuously.
      expect(find.widgetWithText(ListTile, 'Mom'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Mom'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'primary guardian changes a viewer to caregiver with confirmation (Issue #127)',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sue', 'viewer', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sue's row offers a role control; Mom's own row does not (AC4: no
      // self-change, so no control on the caller's own row).
      expect(find.byKey(const ValueKey('change-role-user-sue')), findsOneWidget);
      expect(find.byKey(const ValueKey('change-role-user-mom')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('change-role-user-sue')));
      await tester.pumpAndSettle();

      // Viewer -> caregiver and co-parent are offered; viewer itself and
      // primary_guardian never are (AC5) - exactly two menu items.
      expect(find.byType(PopupMenuItem<GuardianRole>), findsNWidgets(2));
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.text('Co-Parent'), findsOneWidget);

      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();

      // The confirmation names the access being added.
      expect(find.text('Change role to Caregiver?'), findsOneWidget);
      expect(
        find.textContaining('gain the ability to log entries'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change role'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRoleChangeUserId, 'user-sue');
      expect(sharingService.lastRoleChangeNewRole, GuardianRole.caregiver);
      expect(find.text('Role updated to Caregiver'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('cancelling the role confirmation changes nothing',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sue', 'viewer', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('change-role-user-sue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRoleChangeUserId, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('role change failure surfaces an error message',
        (tester) async {
      sharingService.scriptedRoleChangeError =
          const SharingUnauthorizedFailure();
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sue', 'viewer', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('change-role-user-sue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Change role'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRoleChangeUserId, isNull);
      expect(
        find.text('You do not have permission for this action.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('co-parent sees a role control only on caregiver/viewer rows',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        guardianRow('g-2', 'user-sue', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-dad',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AC3: Sue's row offers the control; Mom's row and Dad's own row do
      // not.
      expect(find.byKey(const ValueKey('change-role-user-sue')), findsOneWidget);
      expect(find.byKey(const ValueKey('change-role-user-mom')), findsNothing);
      expect(find.byKey(const ValueKey('change-role-user-dad')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('narrowing copy names the read-only outcome (Issue #127)',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('change-role-user-dad')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewer'));
      await tester.pumpAndSettle();

      // AC2: the confirmation names the read-only outcome before it lands.
      expect(find.text('Change role to Viewer?'), findsOneWidget);
      expect(find.textContaining('read-only'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Change role'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRoleChangeUserId, 'user-dad');
      expect(sharingService.lastRoleChangeNewRole, GuardianRole.viewer);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a viewer sees no role control at all', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-3', 'user-doc', 'viewer', 'Doc'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-doc',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<GuardianRole>), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a sole primary guardian has no self-leave control (#5): the RPC '
        'would reject it', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mom can revoke Sue but has no self-leave control of her own: she's
      // the only accepted primary guardian.
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Mom'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a primary guardian can leave once another accepted primary '
        'guardian exists (#5)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'primary_guardian', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Mom'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a failed self-leave by a primary guardian reports the sole-primary '
        'reason instead of a generic connection error (#5)', (tester) async {
      // Two accepted primary guardians so the self-leave control is shown
      // client-side; the service still rejects the call, simulating a
      // concurrent revoke on another device making Mom the sole primary
      // guardian between the tap and the RPC landing.
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'primary_guardian', 'Dad'),
      ]);
      final failingService = FakeSharingService()
        ..scriptedRevokeError = Exception('object_not_in_prerequisite_state');

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: failingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'Mom'),
        matching: find.byIcon(Icons.remove_circle_outline),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(
        find.text("You're now the only primary guardian, so you can't "
            'leave. Add another primary guardian first, then try again.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a failed revoke of someone else falls back to the generic '
        'connection message', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);
      final failingService = FakeSharingService()
        ..scriptedRevokeError = Exception('boom');

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: failingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'Dad'),
        matching: find.byIcon(Icons.remove_circle_outline),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to remove guardian. Check connection.'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a viewer sees no invite action and cannot revoke others, '
        'but can leave (#13)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-3', 'user-aunt', 'viewer', 'Aunt'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-aunt',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byTooltip('Leave profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a currentUserId with no matching synced guardian row sees no '
        'controls (#13)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-stranger',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'shows the invite action before any guardian row has synced, '
        'rather than hiding it (#13)', (tester) async {
      // No applyRemoteRows call: this profile was just created locally and
      // nothing has written a guardian row for it yet.
      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsOneWidget);
      expect(find.text('No caregivers linked yet'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    group('pending invitations (Issue #3 gap-closure plan, Unit U3)', () {
      PendingInvite pendingInvite({
        String id = 'inv-1',
        GuardianRole role = GuardianRole.caregiver,
        String? recipientLabel = 'Sitter',
        DateTime? expiresAt,
      }) =>
          PendingInvite(
            invitationId: id,
            profileId: testProfile.id,
            role: role,
            recipientLabel: recipientLabel,
            createdAt: DateTime.now().toUtc(),
            expiresAt:
                expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 6)),
          );

      testWidgets(
          'primary guardian sees the pending section listing invitations '
          'with their roles and labels', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', role: GuardianRole.caregiver, recipientLabel: 'Sitter'),
          pendingInvite(id: 'inv-2', role: GuardianRole.viewer, recipientLabel: 'Grandma'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending invitations'), findsOneWidget);
        expect(find.text('Sitter'), findsOneWidget);
        expect(find.text('Grandma'), findsOneWidget);
        expect(find.textContaining('Caregiver'), findsWidgets);
        expect(find.textContaining('Viewer'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'co-parent sees the pending section (R3 allows them to cancel '
          'some invitations)', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', role: GuardianRole.caregiver, recipientLabel: 'Sitter'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-dad',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending invitations'), findsOneWidget);
        expect(find.text('Sitter'), findsOneWidget);
        expect(find.byIcon(Icons.cancel_outlined), findsOneWidget,
            reason: 'a co-parent may cancel a caregiver invitation (R3)');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets('caregiver does not see the pending section at all',
          (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
        ]);
        sharingService.scriptedPendingInvites = [pendingInvite()];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-sitter',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending invitations'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets('viewer does not see the pending section at all',
          (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-3', 'user-aunt', 'viewer', 'Aunt'),
        ]);
        sharingService.scriptedPendingInvites = [pendingInvite()];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-aunt',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending invitations'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'guardian rows not yet synced does not collapse the section into '
          'a not-a-manager state', (tester) async {
        // No applyRemoteRows call, matching "before any guardian row has
        // synced" above (#13's null-vs-empty discipline).
        sharingService.scriptedPendingInvites = [pendingInvite()];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending invitations'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'tapping cancel shows a confirmation dialog; dismissing it makes '
          'no service call', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.cancel_outlined));
        await tester.pumpAndSettle();

        expect(find.text('Cancel invitation for Sitter?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Keep Invitation'));
        await tester.pumpAndSettle();

        expect(sharingService.lastCancelledInvitationId, isNull);
        expect(find.text('Sitter'), findsOneWidget,
            reason: 'dismissing the dialog leaves the row in place');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          "confirming cancel calls cancelInvite with that invitation's id "
          'and removes the row on refresh', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
        ];
        sharingService.scriptedCancelOutcome = InviteCancellation.revoked;

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.cancel_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Cancel Invitation'));
        await tester.pumpAndSettle();

        expect(sharingService.lastCancelledInvitationId, 'inv-1');
        expect(find.text('Sitter'), findsNothing);
        expect(find.text('No pending invitations'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'a co-parent viewing a co_parent invitation created by the '
          'primary guardian sees no cancel control on that row (R3)',
          (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', role: GuardianRole.coParent, recipientLabel: 'Second Co-Parent'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-dad',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Second Co-Parent'), findsOneWidget,
            reason: 'visible but not actionable (Q2)');
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'cancelInvite returning alreadyAccepted refreshes rather than '
          'leaving a stale pending row on screen', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
        ];
        sharingService.scriptedCancelOutcome = InviteCancellation.alreadyAccepted;

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.cancel_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Cancel Invitation'));
        await tester.pumpAndSettle();

        expect(find.text('Sitter'), findsNothing);
        expect(find.text('That invitation was already accepted'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'a listPendingInvites failure renders the retry affordance and '
          'leaves the guardian list rendered', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedListError = Exception('offline');

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mom'), findsOneWidget,
            reason: 'the guardian list (local Drift) keeps working offline');
        expect(find.text('Could not load pending invitations.'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

        sharingService.scriptedListError = null;
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
        ];
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Sitter'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'no widget in the section renders a token, hash, or invite URI',
          (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('lunarlog://'), findsNothing);
        expect(find.textContaining('token'), findsNothing);
        expect(find.textContaining('hash'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
          'an expired invitation renders as an Expired row with Resend '
          '(negative time remaining is never shown)', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(
            id: 'inv-1',
            recipientLabel: 'Sitter',
            expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Expired'), findsOneWidget);
        expect(find.textContaining('expires in'), findsNothing);
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);
        expect(find.widgetWithText(TextButton, 'Resend'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets('Resend on an expired row re-opens the invite flow',
          (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(
            id: 'inv-1',
            recipientLabel: 'Sitter',
            expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Resend'));
        await tester.pumpAndSettle();
        expect(find.text('Invite Caregiver to Luna'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    });
  });

  group('ManageGuardiansScreen notification tile (Issue #5, U8)', () {
    testWidgets(
        'with a service provided, shows the Notifications tile and tapping it pushes the screen',
        (tester) async {
      final notificationPreferencesService = FakeNotificationPreferencesService();
      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
            notificationPreferencesService: notificationPreferencesService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('notifications-action')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notifications-action')));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byKey(const ValueKey('discretion-copy')), findsOneWidget);
      // Issue #313: previously pushed with no RouteSettings at all,
      // invisible to the Sentry route observer.
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('discretion-copy'))),
      );
      expect(route?.settings.name, kRouteNotificationPreferencesScreen);
      expect(kSentryRouteNames, contains(kRouteNotificationPreferencesScreen));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('with no service provided, the tile is absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('notifications-action')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('ManageGuardiansScreen Transfer ownership action (issue #313)', () {
    testWidgets(
        'the primary guardian sees the action and it pushes '
        'TransferOwnershipScreen as a named route', (tester) async {
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-0',
          profileId: testProfile.id,
          userId: 'user-mom',
          role: 'primary_guardian',
          status: 'accepted',
          displayName: 'Mom',
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      final transferService = FakeOwnershipTransferService();

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
            ownershipTransferService: transferService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Transfer ownership'), findsOneWidget);
      await tester.tap(find.byTooltip('Transfer ownership'));
      await tester.pumpAndSettle();

      expect(find.byType(TransferOwnershipScreen), findsOneWidget);
      // Issue #313: previously pushed with no RouteSettings at all,
      // invisible to the Sentry route observer.
      final route = ModalRoute.of(
        tester.element(find.byType(TransferOwnershipScreen)),
      );
      expect(route?.settings.name, kRouteTransferOwnershipScreen);
      expect(kSentryRouteNames, contains(kRouteTransferOwnershipScreen));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Invite deep links (R9/F2)', () {
    Future<void> pumpAppWithInvite(
      WidgetTester tester,
      FakeAuthService auth, {
      Stream<Uri>? inviteLinks,
      String? initialInviteCode,
      String? initialInviteProfileId,
      String? initialInviteKind,
      bool useSharing = true,
      OwnershipTransferService? ownershipTransferService,
    }) async {
      await tester.pumpWidget(LunarLogApp.withCollaborators(
        db: db,
        authService: auth,
        sharingService: useSharing ? sharingService : null,
        ownershipTransferService: ownershipTransferService,
        inviteLinks: inviteLinks,
        initialInviteCode: initialInviteCode,
        initialInviteProfileId: initialInviteProfileId,
        initialInviteKind: initialInviteKind,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a live link presents the accept sheet when signed in',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));

      await pumpAppWithInvite(
        tester,
        auth,
        inviteLinks: Stream.value(
            Uri.parse('lunarlog://invite?code=raw-token&profile=p-1')),
      );

      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a cold-start code waits for sign-in, then presents (R9)',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpAppWithInvite(tester, auth, initialInviteCode: 'cold-token');

      expect(find.text('Join Shared Profile'), findsNothing);

      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));
      await tester.pumpAndSettle();

      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('links without a code are ignored', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));

      await pumpAppWithInvite(
        tester,
        auth,
        inviteLinks: Stream.value(Uri.parse('lunarlog://other')),
      );

      expect(find.text('Join Shared Profile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('links do nothing when no sharing service is configured',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));

      await pumpAppWithInvite(
        tester,
        auth,
        useSharing: false,
        inviteLinks: Stream.value(
            Uri.parse('lunarlog://invite?code=raw-token&profile=p-1')),
      );

      expect(find.text('Join Shared Profile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a kind=claim link while signed in opens ClaimProfileSheet, not '
        'AcceptInviteSheet', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'));
      final transferService = FakeOwnershipTransferService();

      await pumpAppWithInvite(
        tester,
        auth,
        ownershipTransferService: transferService,
        inviteLinks: Stream.value(Uri.parse(
            'lunarlog://invite?code=raw-token&profile=p-1&kind=claim')),
      );

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      expect(find.text('Become the Owner'), findsOneWidget);
      expect(find.text('Join Shared Profile'), findsNothing);
      // Issue #182: the claim sheet is pushed as a named route, visible to
      // the Sentry route observer.
      final claimRoute =
          ModalRoute.of(tester.element(find.byType(ClaimProfileSheet)));
      expect(claimRoute?.settings.name, kRouteClaimProfileSheet);
      expect(kSentryRouteNames, contains(kRouteClaimProfileSheet));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a link with an unrecognised kind still opens AcceptInviteSheet',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));

      await pumpAppWithInvite(
        tester,
        auth,
        inviteLinks: Stream.value(Uri.parse(
            'lunarlog://invite?code=raw-token&profile=p-1&kind=something-else')),
      );

      expect(find.byType(AcceptInviteSheet), findsOneWidget);
      expect(find.byType(ClaimProfileSheet), findsNothing);
      expect(find.text('Join Shared Profile'), findsOneWidget);
      // Issue #182: the accept sheet is pushed as a named route too.
      final acceptRoute =
          ModalRoute.of(tester.element(find.byType(AcceptInviteSheet)));
      expect(acceptRoute?.settings.name, kRouteAcceptInviteSheet);
      expect(kSentryRouteNames, contains(kRouteAcceptInviteSheet));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a claim link received while signed out is latched, and opens the '
        'claim sheet once signed in (R27)', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final transferService = FakeOwnershipTransferService();

      await pumpAppWithInvite(
        tester,
        auth,
        ownershipTransferService: transferService,
        inviteLinks: Stream.value(Uri.parse(
            'lunarlog://invite?code=cold-claim-token&profile=p-1&kind=claim')),
      );

      expect(find.byType(ClaimProfileSheet), findsNothing);
      expect(find.byType(AcceptInviteSheet), findsNothing);

      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'));
      await tester.pumpAndSettle();

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a cold-start claim link supplied as the initial link opens the '
        'sheet after the first frame', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'));
      final transferService = FakeOwnershipTransferService();

      await pumpAppWithInvite(
        tester,
        auth,
        ownershipTransferService: transferService,
        initialInviteCode: 'cold-claim-token',
        initialInviteProfileId: 'p-1',
        initialInviteKind: 'claim',
      );

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('two claim links in quick succession open one sheet, not two',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'));
      final transferService = FakeOwnershipTransferService();
      final controller = StreamController<Uri>();
      addTearDown(controller.close);

      await pumpAppWithInvite(
        tester,
        auth,
        ownershipTransferService: transferService,
        inviteLinks: controller.stream,
      );

      controller.add(Uri.parse(
          'lunarlog://invite?code=raw-token&profile=p-1&kind=claim'));
      controller.add(Uri.parse(
          'lunarlog://invite?code=raw-token-2&profile=p-1&kind=claim'));
      await tester.pumpAndSettle();

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Profile picker caregivers action', () {
    testWidgets('opens the manage screen for the signed-in guardian',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'user-mom'));
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-0',
          profileId: testProfile.id,
          userId: 'user-mom',
          role: 'primary_guardian',
          status: 'accepted',
          displayName: 'Mom',
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      await tester.pumpWidget(LunarLogApp.withCollaborators(
        db: db,
        authService: auth,
        sharingService: sharingService,
      ));
      await tester.pumpAndSettle();

      final lunaTile =
          find.ancestor(of: find.text('Luna'), matching: find.byType(ListTile));
      await tester.tap(find.descendant(
          of: lunaTile, matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caregivers'));
      await tester.pumpAndSettle();

      expect(find.text('Luna Caregivers'), findsOneWidget);

      // U2 route naming: the pushed route is named ManageGuardiansScreen.
      final route = ModalRoute.of(
        tester.element(find.byType(ManageGuardiansScreen)),
      );
      expect(route?.settings.name, kRouteManageGuardiansScreen);
      expect(kSentryRouteNames, contains(kRouteManageGuardiansScreen));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
