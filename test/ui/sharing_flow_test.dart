import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';

import '../support/fake_auth_service.dart';

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

      expect(find.text('An unexpected error occurred.'), findsOneWidget);
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
            guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
              guardiansRepository: ProfileGuardiansRepository(storage),
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
          'an expired invitation returned by a stale load renders without '
          'crashing (negative time remaining is clamped)', (tester) async {
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
              guardiansRepository: ProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('expired'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    });
  });

  group('Invite deep links (R9/F2)', () {
    Future<void> pumpAppWithInvite(
      WidgetTester tester,
      FakeAuthService auth, {
      Stream<Uri>? inviteLinks,
      String? initialInviteCode,
      String? initialInviteProfileId,
      bool useSharing = true,
    }) async {
      await tester.pumpWidget(LunarLogApp(
        db: db,
        authService: auth,
        sharingService: useSharing ? sharingService : null,
        inviteLinks: inviteLinks,
        initialInviteCode: initialInviteCode,
        initialInviteProfileId: initialInviteProfileId,
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

      await tester.pumpWidget(LunarLogApp(
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
