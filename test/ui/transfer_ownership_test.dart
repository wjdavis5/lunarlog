import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/sharing/transfer_ownership_screen.dart';

import 'sharing_flow_test.dart' show FakeSharingService;

class FakeOwnershipTransferService implements OwnershipTransferService {
  GeneratedTransfer? scriptedTransfer;
  Object? scriptedCreateError;
  Object? scriptedCancelError;
  ActiveTransfer? scriptedActiveTransfer;
  Object? scriptedGetActiveTransferError;

  String? lastCreatedProfileId;
  ParentPostTransferRole? lastCreatedRole;
  String? lastCreatedRecipientLabel;
  String? lastCancelledTransferId;
  String? lastGetActiveTransferProfileId;

  @override
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) async {
    lastCreatedProfileId = profileId;
    lastCreatedRole = parentPostTransferRole;
    lastCreatedRecipientLabel = recipientLabel;
    if (scriptedCreateError != null) {
      throw scriptedCreateError!;
    }
    return scriptedTransfer ??
        GeneratedTransfer(
          transferId: 'transfer-1',
          profileId: profileId,
          parentPostTransferRole: parentPostTransferRole,
          rawToken: 'raw-transfer-token',
          tokenHash: 'transfer-token-hash',
          claimUri: Uri.parse(
              'lunarlog://invite?code=raw-transfer-token&profile=$profileId&kind=claim'),
          expiresAt: DateTime.utc(2026, 9, 9, 12, 30),
        );
  }

  @override
  Future<void> cancelTransfer({required String transferId}) async {
    lastCancelledTransferId = transferId;
    if (scriptedCancelError != null) {
      throw scriptedCancelError!;
    }
  }

  @override
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  }) {
    throw UnimplementedError('not exercised by this unit');
  }

  @override
  Future<ActiveTransfer?> getActiveTransfer({required String profileId}) async {
    lastGetActiveTransferProfileId = profileId;
    if (scriptedGetActiveTransferError != null) {
      throw scriptedGetActiveTransferError!;
    }
    return scriptedActiveTransfer;
  }
}

void main() {
  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late FakeSharingService sharingService;
  late FakeOwnershipTransferService transferService;
  late Profile testProfile;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    sharingService = FakeSharingService();
    transferService = FakeOwnershipTransferService();
    testProfile = profileToDomain(
        await storage.upsertProfile(displayName: 'Luna', isMinor: true));
  });

  tearDown(() async {
    await db.close();
  });

  RemoteProfileGuardianRow guardianRow(
    String id,
    String userId,
    String role,
    String? displayName,
  ) =>
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
      );

  Future<void> pumpManageScreen(
    WidgetTester tester, {
    required String currentUserId,
    OwnershipTransferService? ownershipTransferService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManageGuardiansScreen(
          profile: testProfile,
          guardiansRepository: ProfileGuardiansRepository(storage),
          sharingService: sharingService,
          currentUserId: currentUserId,
          ownershipTransferService: ownershipTransferService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ManageGuardiansScreen transfer entry point (U9, R26)', () {
    testWidgets('present for a caller resolved as primaryGuardian',
        (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
      ]);

      await pumpManageScreen(
        tester,
        currentUserId: 'user-mom',
        ownershipTransferService: transferService,
      );

      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('absent for a co-parent', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await pumpManageScreen(
        tester,
        currentUserId: 'user-dad',
        ownershipTransferService: transferService,
      );

      expect(find.byIcon(Icons.compare_arrows), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('absent for a caregiver', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await pumpManageScreen(
        tester,
        currentUserId: 'user-sitter',
        ownershipTransferService: transferService,
      );

      expect(find.byIcon(Icons.compare_arrows), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('absent for a viewer', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-3', 'user-aunt', 'viewer', 'Aunt'),
      ]);

      await pumpManageScreen(
        tester,
        currentUserId: 'user-aunt',
        ownershipTransferService: transferService,
      );

      expect(find.byIcon(Icons.compare_arrows), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'absent when ownershipTransferService is null, even for a '
        'primaryGuardian caller (unconfigured build)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
      ]);

      await pumpManageScreen(
        tester,
        currentUserId: 'user-mom',
        ownershipTransferService: null,
      );

      expect(find.byIcon(Icons.compare_arrows), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('TransferOwnershipScreen', () {
    Future<void> pumpTransferScreen(
      WidgetTester tester, {
      OwnershipTransferService? service,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TransferOwnershipScreen(
            profile: testProfile,
            service: service ?? transferService,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('submitting without choosing a role is blocked',
        (tester) async {
      await pumpTransferScreen(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Transfer Ownership'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();

      expect(transferService.lastCreatedProfileId, isNull);
    });

    testWidgets(
        'a successful arm displays the claim URI and formatted expiry',
        (tester) async {
      await pumpTransferScreen(tester);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AlertDialog, 'Transfer ownership?'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(transferService.lastCreatedProfileId, testProfile.id);
      expect(transferService.lastCreatedRole, ParentPostTransferRole.coManager);

      final linkFinder = find.byWidgetPredicate(
        (w) => w is SelectableText && w.data != null && w.data!.contains('kind=claim'),
      );
      expect(linkFinder, findsOneWidget);
      expect(
        find.textContaining(
          formatTransferExpiry(DateTime.utc(2026, 9, 9, 12, 30)),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'cancel calls cancelTransfer with the returned id and returns to '
        'the pre-arm state', (tester) async {
      await pumpTransferScreen(tester);

      await tester.tap(find.text(ParentPostTransferRole.viewer.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Ready'), findsOneWidget);

      await tester.tap(find.text('Cancel transfer'));
      await tester.pumpAndSettle();

      expect(transferService.lastCancelledTransferId, 'transfer-1');
      expect(find.text('Transfer Ready'), findsNothing);
      expect(find.text('What changes'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Transfer Ownership'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a failed cancelTransfer renders its message and leaves the live '
        'transfer visible (not stuck loading, nothing silently cleared)',
        (tester) async {
      await pumpTransferScreen(tester);

      await tester.tap(find.text(ParentPostTransferRole.viewer.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Ready'), findsOneWidget);

      transferService.scriptedCancelError = const TransferFailure.network();
      await tester.tap(find.text('Cancel transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      // The live transfer is untouched: cancellation failed server-side, so
      // the screen must not have silently discarded the claim link.
      expect(find.text('Transfer Ready'), findsOneWidget);
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel transfer'),
      );
      expect(cancelButton.onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a non-TransferFailure error from cancelTransfer shows the generic '
        'message', (tester) async {
      await pumpTransferScreen(tester);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      transferService.scriptedCancelError = StateError('boom');
      await tester.tap(find.text('Cancel transfer'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget);
      expect(find.text('Transfer Ready'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a TransferFailure.unauthorized() from createTransfer renders its '
        'message and leaves the screen armable', (tester) async {
      final failing = FakeOwnershipTransferService()
        ..scriptedCreateError = const TransferFailure.unauthorized();

      await pumpTransferScreen(tester, service: failing);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission for this action.'),
        findsOneWidget,
      );
      // Still armable: the confirm button is visible and enabled again
      // (not stuck loading), and no claim link is shown.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Transfer Ownership'),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('Transfer Ready'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: an active transfer discovered on open shows the '
        'pending-cancel body instead of the armable form', (tester) async {
      final withActive = FakeOwnershipTransferService()
        ..scriptedActiveTransfer = ActiveTransfer(
          transferId: 'orphaned-1',
          profileId: testProfile.id,
          parentPostTransferRole: ParentPostTransferRole.coManager,
          expiresAt: DateTime.utc(2026, 9, 10, 8, 0),
        );

      await pumpTransferScreen(tester, service: withActive);

      expect(withActive.lastGetActiveTransferProfileId, testProfile.id);
      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);
      expect(find.text('What changes'), findsNothing);
      expect(
        find.textContaining(formatTransferExpiry(DateTime.utc(2026, 9, 10, 8, 0))),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel Pending Transfer'));
      await tester.pumpAndSettle();

      expect(withActive.lastCancelledTransferId, 'orphaned-1');
      expect(find.text('A Transfer Is Already Pending'), findsNothing);
      expect(find.text('What changes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a TransferAlreadyArmedFailure from createTransfer '
        'falls back to showing the discovered active transfer', (tester) async {
      final failing = FakeOwnershipTransferService()
        ..scriptedCreateError = const TransferFailure.alreadyArmed();

      // Nothing active on open (the initState check below sees null) - the
      // transfer becomes discoverable only once the create attempt below
      // hits the alreadyArmed failure, mirroring a transfer that was armed
      // by a lost createTransfer response *during* this session.
      await pumpTransferScreen(tester, service: failing);
      expect(find.text('What changes'), findsOneWidget);

      failing.scriptedActiveTransfer = ActiveTransfer(
        transferId: 'orphaned-2',
        profileId: testProfile.id,
        parentPostTransferRole: ParentPostTransferRole.viewer,
        expiresAt: DateTime.utc(2026, 9, 11, 9, 0),
        recipientLabel: 'Sam',
      );

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);
      expect(
        find.textContaining(formatTransferExpiry(DateTime.utc(2026, 9, 11, 9, 0))),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a TransferAlreadyArmedFailure with no discoverable '
        'active transfer (e.g. it was cancelled just after) still renders '
        'the failure message on the armable form', (tester) async {
      final failing = FakeOwnershipTransferService()
        ..scriptedCreateError = const TransferFailure.alreadyArmed();

      await pumpTransferScreen(tester, service: failing);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A transfer is already pending for this profile. Cancel it before starting a new one.',
        ),
        findsOneWidget,
      );
      expect(find.text('A Transfer Is Already Pending'), findsNothing);
      expect(find.text('What changes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a TransferFailure from the fallback getActiveTransfer '
        'call renders its own message', (tester) async {
      final failing = FakeOwnershipTransferService()
        ..scriptedCreateError = const TransferFailure.alreadyArmed()
        ..scriptedGetActiveTransferError = const TransferFailure.network();

      await pumpTransferScreen(tester, service: failing);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      expect(find.text('A Transfer Is Already Pending'), findsNothing);
      expect(find.text('What changes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a non-TransferFailure error from the fallback '
        'getActiveTransfer call still renders the original alreadyArmed '
        'message', (tester) async {
      final failing = FakeOwnershipTransferService()
        ..scriptedCreateError = const TransferFailure.alreadyArmed()
        ..scriptedGetActiveTransferError = StateError('boom');

      await pumpTransferScreen(tester, service: failing);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A transfer is already pending for this profile. Cancel it before starting a new one.',
        ),
        findsOneWidget,
      );
      expect(find.text('A Transfer Is Already Pending'), findsNothing);
      expect(find.text('What changes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a failed cancel of the discovered active transfer '
        'renders its message and leaves the pending body visible',
        (tester) async {
      final withActive = FakeOwnershipTransferService()
        ..scriptedActiveTransfer = ActiveTransfer(
          transferId: 'orphaned-3',
          profileId: testProfile.id,
          parentPostTransferRole: ParentPostTransferRole.coManager,
          expiresAt: DateTime.utc(2026, 9, 12, 8, 0),
        )
        ..scriptedCancelError = const TransferFailure.network();

      await pumpTransferScreen(tester, service: withActive);
      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);

      await tester.tap(find.text('Cancel Pending Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'Review item #2: a non-TransferFailure error cancelling the '
        'discovered active transfer shows the generic message', (tester) async {
      final withActive = FakeOwnershipTransferService()
        ..scriptedActiveTransfer = ActiveTransfer(
          transferId: 'orphaned-4',
          profileId: testProfile.id,
          parentPostTransferRole: ParentPostTransferRole.viewer,
          expiresAt: DateTime.utc(2026, 9, 13, 8, 0),
        )
        ..scriptedCancelError = StateError('boom');

      await pumpTransferScreen(tester, service: withActive);
      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);

      await tester.tap(find.text('Cancel Pending Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('A Transfer Is Already Pending'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'dismissing the confirm dialog does not call createTransfer',
        (tester) async {
      await pumpTransferScreen(tester);

      await tester.tap(find.text(ParentPostTransferRole.coManager.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer Ownership'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AlertDialog, 'Transfer ownership?'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(transferService.lastCreatedProfileId, isNull);
      expect(find.text('Transfer Ready'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
