// Standalone tests for ClaimProfileSheet (Issue #4, U10; R11, R27, R28),
// mirroring how sharing_flow_test.dart's 'AcceptInviteSheet' group pumps
// AcceptInviteSheet directly inside a MaterialApp/Scaffold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';

/// Hand-written [OwnershipTransferService] fake, scoped to [claimProfile]
/// only - the arm/cancel paths belong to U9's own tests.
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
  group('ClaimProfileSheet', () {
    testWidgets(
        'allows entering child and parent display names and claiming',
        (tester) async {
      final service = FakeOwnershipTransferService();
      ClaimedProfileResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimProfileSheet(
              rawToken: 'test-raw-token',
              service: service,
              onClaimed: (r) => result = r,
            ),
          ),
        ),
      );

      expect(find.text('Become the Owner'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Luna');
      await tester.enterText(fields.at(1), 'Dad');
      await tester.tap(find.text('Become Owner'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.profileName, 'Luna');
      expect(result!.parentRole, 'co_parent');
      expect(result!.entriesTransferred, 12);
      expect(service.claimCalls, hasLength(1));
      expect(service.claimCalls.single.rawToken, 'test-raw-token');
      expect(service.claimCalls.single.childDisplayName, 'Luna');
      expect(service.claimCalls.single.parentDisplayName, 'Dad');
    });

    testWidgets('sends null display names when the fields are left blank',
        (tester) async {
      final service = FakeOwnershipTransferService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimProfileSheet(
              rawToken: 'test-raw-token',
              service: service,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Become Owner'));
      await tester.pumpAndSettle();

      expect(service.claimCalls.single.childDisplayName, isNull);
      expect(service.claimCalls.single.parentDisplayName, isNull);
    });

    testWidgets('renders TransferFailure.expired() and leaves the sheet open',
        (tester) async {
      final failingService = FakeOwnershipTransferService()
        ..scriptedClaimError = const TransferFailure.expired();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimProfileSheet(
              rawToken: 'test-raw-token',
              service: failingService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Become Owner'));
      await tester.pumpAndSettle();

      expect(find.text('This transfer link has expired.'), findsOneWidget);
      expect(find.byType(ClaimProfileSheet), findsOneWidget);
    });

    testWidgets(
        'renders TransferFailure.selfTransfer() and leaves the sheet open',
        (tester) async {
      final failingService = FakeOwnershipTransferService()
        ..scriptedClaimError = const TransferFailure.selfTransfer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimProfileSheet(
              rawToken: 'test-raw-token',
              service: failingService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Become Owner'));
      await tester.pumpAndSettle();

      expect(
        find.text("You can't claim a transfer you created yourself."),
        findsOneWidget,
      );
      expect(find.byType(ClaimProfileSheet), findsOneWidget);
    });

    testWidgets('shows a generic message on an unexpected exception',
        (tester) async {
      final failingService = FakeOwnershipTransferService()
        ..scriptedClaimError = Exception('network crashed');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimProfileSheet(
              rawToken: 'test-raw-token',
              service: failingService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Become Owner'));
      await tester.pumpAndSettle();

      expect(find.text('An unexpected error occurred.'), findsOneWidget);
      expect(find.byType(ClaimProfileSheet), findsOneWidget);
    });
  });
}
