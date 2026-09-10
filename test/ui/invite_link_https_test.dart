import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/accept_prediction_connection_sheet.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';

import '../support/fake_auth_service.dart';

/// Minimal [SharingService] stub: only the accept path matters for routing.
class _StubSharingService implements SharingService {
  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) =>
      throw UnimplementedError();

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) async =>
      const AcceptedInviteResult(
        profileId: 'p-1',
        profileName: 'Luna',
        role: GuardianRole.coParent,
      );

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async => const [];

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) =>
      throw UnimplementedError();

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) =>
      throw UnimplementedError();
}

/// Minimal [OwnershipTransferService] stub: only the claim path matters.
class _StubTransferService implements OwnershipTransferService {
  @override
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) =>
      throw UnimplementedError();

  @override
  Future<void> cancelTransfer({required String transferId}) =>
      throw UnimplementedError();

  @override
  Future<ActiveTransfer?> getActiveTransfer({required String profileId}) async =>
      null;

  @override
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  }) async =>
      const ClaimedProfileResult(
        profileId: 'p-1',
        profileName: 'Luna',
        parentRole: 'co_parent',
        entriesTransferred: 3,
      );
}

/// Minimal [PredictionConnectionService] stub: the sheet only calls it on
/// accept, which routing tests never tap.
class _StubPredictionService implements PredictionConnectionService {
  @override
  Future<GeneratedPredictionInvite> createConnection({
    required String profileId,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) =>
      throw UnimplementedError();

  @override
  Future<AcceptedPredictionConnection> acceptConnection({required String rawToken}) =>
      throw UnimplementedError();

  @override
  Future<void> revokeConnection({required String connectionId}) =>
      throw UnimplementedError();

  @override
  Future<ActivePredictionConnection?> getActiveConnection({required String profileId}) async =>
      null;

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async => const {};

  @override
  Future<List<IncomingPredictionConnection>> listIncomingConnections() async => const [];

  @override
  Future<PredictionProjection?> fetchProjection({required String profileId}) async => null;

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) =>
      throw UnimplementedError();
}

void main() {
  late LunarLogDatabase db;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(
    WidgetTester tester,
    FakeAuthService auth, {
    Stream<Uri>? inviteLinks,
    String? initialInviteCode,
    String? initialInviteProfileId,
    String? initialInviteKind,
  }) async {
    await tester.pumpWidget(LunarLogApp(
      db: db,
      authService: auth,
      sharingService: _StubSharingService(),
      ownershipTransferService: _StubTransferService(),
      predictionConnectionService: _StubPredictionService(),
      inviteLinks: inviteLinks,
      initialInviteCode: initialInviteCode,
      initialInviteProfileId: initialInviteProfileId,
      initialInviteKind: initialInviteKind,
    ));
    await tester.pumpAndSettle();
  }

  FakeAuthService signedInAuth() {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'user-dad'));
    return auth;
  }

  group('HTTPS universal-link routing (issue #129)', () {
    // Split under test: `lib/main.dart`'s filter decides which form is
    // honoured for a configured domain (pure logic, covered by
    // `test/domain/sharing/invite_links_test.dart`, including the
    // empty-domain AC5 case). `LunarLogApp` itself is form-agnostic — it
    // only reads the query — so these tests prove an HTTPS-form link
    // arriving on the stream routes to the same sheet as its
    // custom-scheme twin (AC1/AC2), and that kind=prediction is unchanged
    // (AC3).
    testWidgets('a warm HTTPS invite link opens AcceptInviteSheet',
        (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(Uri.parse(
            'https://links.example.com/invite?code=https-token&profile=p-1')),
      );

      expect(find.byType(AcceptInviteSheet), findsOneWidget);
      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a warm HTTPS claim link opens ClaimProfileSheet',
        (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(Uri.parse(
            'https://links.example.com/invite?code=https-token&profile=p-1&kind=claim')),
      );

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a warm HTTPS prediction link opens '
        'AcceptPredictionConnectionSheet', (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(Uri.parse(
            'https://links.example.com/invite?code=https-token&kind=prediction')),
      );

      expect(find.byType(AcceptPredictionConnectionSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      expect(find.byType(ClaimProfileSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a warm custom-scheme invite link opens AcceptInviteSheet',
        (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(
            Uri.parse('lunarlog://invite?code=raw-token&profile=p-1')),
      );

      expect(find.byType(AcceptInviteSheet), findsOneWidget);
      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a warm custom-scheme claim link opens ClaimProfileSheet',
        (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(Uri.parse(
            'lunarlog://invite?code=raw-token&profile=p-1&kind=claim')),
      );

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'a warm custom-scheme prediction link opens '
        'AcceptPredictionConnectionSheet', (tester) async {
      await pumpApp(
        tester,
        signedInAuth(),
        inviteLinks: Stream.value(Uri.parse(
            'lunarlog://invite?code=raw-token&kind=prediction')),
      );

      expect(find.byType(AcceptPredictionConnectionSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      expect(find.byType(ClaimProfileSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a cold-start invite code opens AcceptInviteSheet after sign-in',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(tester, auth, initialInviteCode: 'cold-token');

      expect(find.byType(AcceptInviteSheet), findsNothing);

      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'));
      await tester.pumpAndSettle();

      expect(find.byType(AcceptInviteSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a cold-start claim code opens ClaimProfileSheet after sign-in',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        auth,
        initialInviteCode: 'cold-claim-token',
        initialInviteProfileId: 'p-1',
        initialInviteKind: 'claim',
      );

      expect(find.byType(ClaimProfileSheet), findsNothing);

      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'));
      await tester.pumpAndSettle();

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      expect(find.byType(AcceptInviteSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
