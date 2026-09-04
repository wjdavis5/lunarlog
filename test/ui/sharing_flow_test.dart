import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';

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

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {
    lastRevokedUserId = targetUserId;
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
    testWidgets('renders active guardians and handles revocation', (tester) async {
      // Add a guardian to storage
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-1',
          profileId: testProfile.id,
          userId: 'user-dad',
          role: 'co_parent',
          status: 'accepted',
          displayName: 'Dad',
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          serverVersion: 1,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ManageGuardiansScreen(
            profile: testProfile,
            storage: storage,
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('Co-Parent'), findsOneWidget);

      // Tap revoke icon
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('Remove Dad?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRevokedUserId, 'user-dad');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
