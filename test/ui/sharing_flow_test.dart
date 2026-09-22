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
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/sharing/transfer_ownership_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_notification_preferences_service.dart';
import '../support/fake_settings_store.dart';

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
    bool subject = false,
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
          inviteUri: Uri.parse(
            'lunarlog://invite?code=raw-token-xyz&profile=$profileId',
          ),
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

  /// Issue #594: null by default (the "not available" state), matching
  /// [previewInvite]'s uniform-null contract - a test opts into the
  /// "ready" state by scripting a value.
  InvitePreview? scriptedPreview;
  Object? scriptedPreviewError;
  final previewCalls = <String>[];

  /// Lets a test observe the loading state mid-flight, mirroring
  /// [revokeHold] above - set before pumping, then complete once the
  /// test has asserted the loading indicator shows.
  Completer<void>? previewHold;

  @override
  Future<InvitePreview?> previewInvite({required String rawToken}) async {
    previewCalls.add(rawToken);
    final hold = previewHold;
    if (hold != null) await hold.future;
    if (scriptedPreviewError != null) {
      throw scriptedPreviewError!;
    }
    return scriptedPreview;
  }

  Object? scriptedRevokeError;

  /// #544: lets a test observe the busy state mid-flight — set before the
  /// tap, then complete once the test has asserted the trigger disabled
  /// itself.
  Completer<void>? revokeHold;

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {
    final hold = revokeHold;
    if (hold != null) await hold.future;
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
      <
        ({String rawToken, String? childDisplayName, String? parentDisplayName})
      >[];

  @override
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    bool subject = false,
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

/// Issue #535 (d): a minimal [SharingService] whose [createInvite] throws a
/// scripted, reassignable [SharingFailure] - proves InviteGuardianDialog's
/// own catch clause maps each failure type to its distinct
/// [SharingFailure.userFacingMessage] rather than collapsing everything
/// into one generic string.
class _ThrowingSharingService implements SharingService {
  _ThrowingSharingService(this.failure);

  SharingFailure failure;

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    bool subject = false,
    Duration ttl = const Duration(hours: 48),
  }) async => throw failure;

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) => throw UnimplementedError('not exercised by these tests');

  @override
  Future<InvitePreview?> previewInvite({required String rawToken}) =>
      throw UnimplementedError('not exercised by these tests');

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) => throw UnimplementedError('not exercised by these tests');

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) =>
      throw UnimplementedError('not exercised by these tests');

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) =>
      throw UnimplementedError('not exercised by these tests');

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) => throw UnimplementedError('not exercised by these tests');
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
    testProfile = profileToDomain(
      await storage.upsertProfile(displayName: 'Luna', isMinor: true),
    );
  });

  // Deliberately unawaited (issue #241): `await db.close()` from this
  // group-level tearDown deadlocks whenever any drift `watch()` stream
  // was subscribed during the test — a pre-existing drift/fake-async
  // hazard, reproducible on `origin/main` with a bare
  // `select(...).watch().listen()` and no app code at all: the stream
  // teardown work drift schedules lives in the test's fake-async zone,
  // which nothing advances once the body has returned, so the real-zone
  // teardown await can never resolve. #241's picker ProfileCard is the
  // first surface this suite reaches (a signed-in accept-invite pump with
  // the seeded profile) that holds such a subscription, so the invite
  // deep-link group hung at teardown. Closing without awaiting lets the
  // test complete; nothing touches the database after this point.
  tearDown(() async {
    unawaited(db.close());
  });

  group('InviteGuardianDialog', () {
    testWidgets('creates invite link and shows copy action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InviteGuardianDialog(
              profileId: testProfile.id,
              profileName: testProfile.displayName,
              sharingService: sharingService,
            ),
          ),
        ),
      );

      expect(find.text('Invite guardian to Luna'), findsOneWidget);
      expect(find.text('Create Link'), findsOneWidget);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(find.text('Invitation Created'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(sharingService.lastCreatedRole, 'co_parent');
    });

    // Issue #535 (c): share_plus is already a dependency; a Share button
    // sits beside Copy Link so the invite link isn't limited to a manual
    // copy-paste.
    testWidgets('shows a Share action beside Copy Link once a link exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          // Issue #802: the generated-link copy is localized
          // (inviteCreatedShareGuardian/Subject), so this pump needs the
          // delegates like every other one in this group.
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InviteGuardianDialog(
              profileId: testProfile.id,
              profileName: testProfile.displayName,
              sharingService: sharingService,
            ),
          ),
        ),
      );

      // Not offered before a link exists.
      expect(find.text('Share'), findsNothing);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    // Issue #535 (d): distinct SharingFailure types get their own accurate
    // copy via userFacingMessage, rather than every failure - including
    // unauthorized - collapsing into the generic "check your connection"
    // message (AcceptInviteSheet's catch clause already gets this right;
    // this mirrors it).
    testWidgets('unauthorized and network SharingFailures produce distinct '
        'userFacingMessage copy, not the generic collapse', (tester) async {
      // createInvite has no scriptedError hook on FakeSharingService, so a
      // dedicated throwing fake proves the dialog's own catch-clause
      // behavior independent of what the fake happens to script.
      final failing = _ThrowingSharingService(
        const SharingFailure.unauthorized(),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InviteGuardianDialog(
              profileId: testProfile.id,
              profileName: testProfile.displayName,
              sharingService: failing,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission for this action.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Failed to generate invite. Please check your connection and try again.',
        ),
        findsNothing,
      );

      // A network failure gets its own distinct copy too, not the same
      // unauthorized text and not the generic collapse either.
      failing.failure = const SharingFailure.network();
      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      expect(
        find.text('You do not have permission for this action.'),
        findsNothing,
      );
    });
  });

  group('AcceptInviteSheet', () {
    testWidgets('allows entering display name and accepting invite', (
      tester,
    ) async {
      AcceptedInviteResult? result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    // Issue #535 (a): no server RPC returns a profile's name or role before
    // acceptance (accept_guardian_invitation is the only call, and it
    // commits the acceptance as part of returning them - see
    // SupabaseSharingService.acceptInvite and this issue's investigation
    // notes). The pre-accept copy must therefore never assume a minor's
    // profile - the previous hardcoded "child" wording was wrong whenever
    // two adults share one adult's profile.
    testWidgets('never renders the hardcoded child wording, and shows neutral '
        'profile copy instead of assuming a minor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AcceptInviteSheet(
              rawToken: 'test-raw-token',
              sharingService: sharingService,
            ),
          ),
        ),
      );

      expect(find.textContaining('child'), findsNothing);
      expect(
        find.text(
          "You've been invited to a shared profile in lunarlog. "
          'Accepting will sync its cycle calendar and health logs to '
          'this device.',
        ),
        findsOneWidget,
      );
    });

    // Issue #594: the pre-accept preview RPC and its four client states.
    group('pre-accept preview (Issue #594)', () {
      Finder previewKey(String value) => find.byKey(ValueKey(value));

      testWidgets('shows a loading indicator before the preview resolves', (
        tester,
      ) async {
        final service = FakeSharingService()..previewHold = Completer<void>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AcceptInviteSheet(
                rawToken: 'test-raw-token',
                sharingService: service,
              ),
            ),
          ),
        );

        expect(previewKey('accept-invite-preview-loading'), findsOneWidget);
        expect(previewKey('accept-invite-preview-ready'), findsNothing);
        expect(previewKey('accept-invite-preview-unavailable'), findsNothing);
        expect(previewKey('accept-invite-preview-error'), findsNothing);

        service.previewHold!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets(
        'a live preview replaces the neutral copy with the profile name '
        'and role',
        (tester) async {
          final service = FakeSharingService()
            ..scriptedPreview = InvitePreview(
              profileDisplayName: 'Riley',
              role: GuardianRole.caregiver,
              // Issue #949: fixed fixture expiry; this sheet renders the name
              // and role, never the expiry against the real clock.
              expiresAt: DateTime.utc(2026, 9, 20),
            );

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: AcceptInviteSheet(
                  rawToken: 'preview-token',
                  sharingService: service,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(service.previewCalls, ['preview-token']);
          expect(previewKey('accept-invite-preview-ready'), findsOneWidget);
          expect(find.textContaining('Riley'), findsOneWidget);
          expect(
            find.text(
              "You've been invited to a shared profile in lunarlog. "
              'Accepting will sync its cycle calendar and health logs to '
              'this device.',
            ),
            findsNothing,
            reason: 'the personalized sentence replaces the neutral one',
          );
        },
      );

      testWidgets(
        'a null preview (uniform not-available) shows the unavailable '
        'note and leaves Accept usable',
        (tester) async {
          final service = FakeSharingService()..scriptedPreview = null;
          AcceptedInviteResult? accepted;

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: AcceptInviteSheet(
                  rawToken: 'dead-token',
                  sharingService: service,
                  onAccepted: (r) => accepted = r,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(previewKey('accept-invite-preview-unavailable'), findsOneWidget);
          expect(previewKey('accept-invite-preview-error'), findsNothing);
          expect(previewKey('accept-invite-preview-ready'), findsNothing);

          await tester.tap(find.text('Accept & Sync'));
          await tester.pumpAndSettle();
          expect(service.previewCalls, ['dead-token']);
          expect(accepted, isNotNull,
              reason: 'the not-available preview never blocks Accept');
        },
      );

      testWidgets(
        'a preview fetch failure shows the error note and leaves Accept '
        'usable',
        (tester) async {
          final service = FakeSharingService()
            ..scriptedPreviewError = const SharingFailure.network();
          AcceptedInviteResult? accepted;

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: AcceptInviteSheet(
                  rawToken: 'test-raw-token',
                  sharingService: service,
                  onAccepted: (r) => accepted = r,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(previewKey('accept-invite-preview-error'), findsOneWidget);
          expect(previewKey('accept-invite-preview-unavailable'), findsNothing);
          expect(previewKey('accept-invite-preview-ready'), findsNothing);

          await tester.tap(find.text('Accept & Sync'));
          await tester.pumpAndSettle();
          expect(accepted, isNotNull,
              reason: 'accept still succeeds despite the preview failure');
        },
      );
    });

    testWidgets(
        'renders with no overflow at 320×568, 200% text scale, and a '
        'keyboard-sized bottom inset (issue #642, LLA-012)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2.0),
              viewInsets: const EdgeInsets.only(bottom: 260),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: AcceptInviteSheet(
              rawToken: 'test-raw-token',
              sharingService: sharingService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AcceptInviteSheet), findsOneWidget);
    });
  });

  group('ManageGuardiansScreen', () {
    RemoteProfileGuardianRow guardianRow(
      String id,
      String userId,
      String role,
      String? displayName, {
      int serverVersion = 1,
    }) => RemoteProfileGuardianRow(
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

    testWidgets('renders active guardians and handles revocation', (
      tester,
    ) async {
      // The server always carries the creator's primary row; seed it so
      // the caller's role resolves (mom = primary_guardian).
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Dad'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove Dad?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(sharingService.lastRevokedUserId, 'user-dad');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
      'issue #558: once the single-use link is generated, a stray tap '
      'outside the dialog cannot dismiss it, "Copy Link" shows its '
      'confirmation inside the dialog, and Done closes it',
      (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.person_add));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Link'));
        await tester.pumpAndSettle();
        expect(find.text('Invitation Created'), findsOneWidget);

        // A tap on the scrim (the barrier), well away from the dialog card
        // itself, must not dismiss it now that the link exists.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(
          find.text('Invitation Created'),
          findsOneWidget,
          reason:
              'barrierDismissible: false -- the server never stores '
              'this raw token again, so a stray tap must not destroy '
              'access to it',
        );

        expect(
          find.byKey(const ValueKey('invite-copied-confirmation')),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Copy Link'));
        await tester.pump();
        expect(
          find.text('Copied to clipboard'),
          findsOneWidget,
          reason:
              'shown inside the dialog -- a ScaffoldMessenger SnackBar '
              'here would paint behind this dialog\'s own barrier',
        );

        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('Invitation Created'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('hides invite and revocation controls from a caregiver (U8)', (
      tester,
    ) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('co-parent cannot remove the primary guardian (R4)', (
      tester,
    ) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
        expect(
          find.byKey(const ValueKey('change-role-user-sue')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('change-role-user-mom')),
          findsNothing,
        );

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
      },
    );

    testWidgets('cancelling the role confirmation changes nothing', (
      tester,
    ) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sue', 'viewer', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('role change failure surfaces an error message', (
      tester,
    ) async {
      sharingService.scriptedRoleChangeError =
          const SharingUnauthorizedFailure();
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-2', 'user-sue', 'viewer', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('co-parent sees a role control only on caregiver/viewer rows', (
      tester,
    ) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        guardianRow('g-2', 'user-sue', 'caregiver', 'Sue'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      expect(
        find.byKey(const ValueKey('change-role-user-sue')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('change-role-user-mom')), findsNothing);
      expect(find.byKey(const ValueKey('change-role-user-dad')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('narrowing copy names the read-only outcome (Issue #127)', (
      tester,
    ) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      'would reject it',
      (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
      },
    );

    testWidgets('a primary guardian can leave once another accepted primary '
        'guardian exists (#5)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'primary_guardian', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      'reason instead of a generic connection error (#5)',
      (tester) async {
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: failingService,
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Mom'),
            matching: find.byIcon(Icons.remove_circle_outline),
          ),
        );
        await tester.pumpAndSettle();
        // Issue #1003: the caller's own row leaves, so the confirm reads
        // "Leave" rather than "Remove".
        await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "You're now the only primary guardian, so you can't "
            'leave. Add another primary guardian first, then try again.',
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('a failed revoke of someone else falls back to the generic '
        'connection message', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);
      final failingService = FakeSharingService()
        ..scriptedRevokeError = Exception('boom');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: failingService,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Dad'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to remove guardian. Check connection.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('#544: the revoke trigger disables itself while its RPC is in '
        'flight, and re-enables once it settles', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);
      final hold = Completer<void>();
      final service = FakeSharingService()..revokeHold = hold;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: service,
            currentUserId: 'user-mom',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Dad'),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('revoke-user-dad')),
        findsNothing,
        reason: 'the trigger itself is gone while the RPC is in flight',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();

      expect(service.lastRevokedUserId, 'user-dad');
      expect(
        find.byKey(const ValueKey('revoke-user-dad')),
        findsOneWidget,
        reason:
            're-enabled once the RPC settles (the fake service does '
            "not itself touch local storage, so Dad's row is unchanged)",
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('revoke-user-dad')))
            .onPressed,
        isNotNull,
      );

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('a currentUserId with no matching synced guardian row sees no '
        'controls (#13)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('shows the invite action before any guardian row has synced, '
        'rather than hiding it (#13)', (tester) async {
      // No applyRemoteRows call: this profile was just created locally and
      // nothing has written a guardian row for it yet.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      expect(find.text('No guardians linked yet'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    group('signed-out operator (issue #885)', () {
      testWidgets(
        'makes no listPendingInvites call, shows no red failure, renders the '
        'sign-in prompt, and hides the Invite FAB',
        (tester) async {
          // A scripted list failure would be shown if the screen called out
          // at all; the assertion below that no call happened is what proves
          // the calm state is not just masking it.
          sharingService.scriptedListError =
              const SharingUnauthorizedFailure();

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ManageGuardiansScreen(
                profile: testProfile,
                guardiansRepository: DriftProfileGuardiansRepository(storage),
                sharingService: sharingService,
                currentUserId: null,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            sharingService.listPendingInvitesCallCount,
            0,
            reason: 'a signed-out screen must not hit the network at all',
          );
          expect(
            find.byKey(const ValueKey('pending-invites-error')),
            findsNothing,
            reason: 'no session is not a permissions failure',
          );
          expect(
            find.text('Could not load pending invitations.'),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('sharing-needs-account')),
            findsOneWidget,
          );
          expect(
            find.text(
              'Sharing needs an account. Sign in to invite a guardian.',
            ),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.person_add),
            findsNothing,
            reason: 'there is nobody to invite, and the RPC could only be '
                'refused',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        'the sign-in prompt routes to the existing SignInScreen',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);
          final controller = AuthController(authService: auth);
          addTearDown(controller.dispose);
          final settings = FakeSettingsStore();
          addTearDown(settings.close);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthController>.value(
                  value: controller,
                ),
                Provider<SettingsStore>.value(value: settings),
              ],
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ManageGuardiansScreen(
                  profile: testProfile,
                  guardiansRepository: DriftProfileGuardiansRepository(storage),
                  sharingService: sharingService,
                  currentUserId: null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(const ValueKey('sharing-sign-in-action')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(SignInScreen),
            findsOneWidget,
            reason: 'reuse the existing auth screen, never a new route',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        'a signed-in operator whose guardian rows are still null keeps the '
        'Invite FAB enabled (#13 must not regress)',
        (tester) async {
          // No applyRemoteRows: rows are still null, the not-yet-synced case
          // the FAB gate deliberately fails open for.
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
            find.byKey(const ValueKey('sharing-needs-account')),
            findsNothing,
            reason: 'the calm state is only for the no-session branch',
          );
          expect(find.byIcon(Icons.person_add), findsOneWidget);

          // Enabled, not merely present: tapping it opens the real dialog.
          await tester.tap(find.byIcon(Icons.person_add));
          await tester.pumpAndSettle();
          expect(
            find.text('Invite guardian to ${testProfile.displayName}'),
            findsOneWidget,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );
    });

    testWidgets("#544: shows a spinner before the guardian stream's first "
        'emission, never "No guardians linked yet" (which would read as '
        'a synced, empty profile rather than still loading)', (tester) async {
      await storage.applyRemoteRows([
        guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
      ]);

      // Deliberately no settle after this pump: the Drift watch's first
      // emission needs at least one microtask/async gap, so the single
      // frame `pumpWidget` itself performs is still before it.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ManageGuardiansScreen(
            profile: testProfile,
            guardiansRepository: DriftProfileGuardiansRepository(storage),
            sharingService: sharingService,
            currentUserId: 'user-mom',
          ),
        ),
      );

      expect(
        find.text('No guardians linked yet'),
        findsNothing,
        reason:
            'must not flash the empty state before the first real '
            'answer arrives',
      );
      // Also still waiting on the pending-invitations FutureBuilder at
      // this point, so more than one spinner is expected here.
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(
        find.text('Mom'),
        findsOneWidget,
        reason: 'the real (non-empty) answer renders once it lands',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    group('pending invitations (Issue #3 gap-closure plan, Unit U3)', () {
      PendingInvite pendingInvite({
        String id = 'inv-1',
        GuardianRole role = GuardianRole.caregiver,
        String? recipientLabel = 'Sitter',
        DateTime? expiresAt,
      }) => PendingInvite(
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
        'with their roles and labels',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          ]);
          sharingService.scriptedPendingInvites = [
            pendingInvite(
              id: 'inv-1',
              role: GuardianRole.caregiver,
              recipientLabel: 'Sitter',
            ),
            pendingInvite(
              id: 'inv-2',
              role: GuardianRole.viewer,
              recipientLabel: 'Grandma',
            ),
          ];

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
        },
      );

      testWidgets(
        'co-parent sees the pending section (R3 allows them to cancel '
        'some invitations)',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
            guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
          ]);
          sharingService.scriptedPendingInvites = [
            pendingInvite(
              id: 'inv-1',
              role: GuardianRole.caregiver,
              recipientLabel: 'Sitter',
            ),
          ];

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
          expect(
            find.byIcon(Icons.cancel_outlined),
            findsOneWidget,
            reason: 'a co-parent may cancel a caregiver invitation (R3)',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets('caregiver does not see the pending section at all', (
        tester,
      ) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-2', 'user-sitter', 'caregiver', 'Sue'),
        ]);
        sharingService.scriptedPendingInvites = [pendingInvite()];

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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

      testWidgets('viewer does not see the pending section at all', (
        tester,
      ) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-3', 'user-aunt', 'viewer', 'Aunt'),
        ]);
        sharingService.scriptedPendingInvites = [pendingInvite()];

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
        'a not-a-manager state',
        (tester) async {
          // No applyRemoteRows call, matching "before any guardian row has
          // synced" above (#13's null-vs-empty discipline).
          sharingService.scriptedPendingInvites = [pendingInvite()];

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
        },
      );

      testWidgets(
        'tapping cancel shows a confirmation dialog; dismissing it makes '
        'no service call',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          ]);
          sharingService.scriptedPendingInvites = [
            pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
          ];

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
          expect(
            find.text('Sitter'),
            findsOneWidget,
            reason: 'dismissing the dialog leaves the row in place',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        "confirming cancel calls cancelInvite with that invitation's id "
        'and removes the row on refresh',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          ]);
          sharingService.scriptedPendingInvites = [
            pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
          ];
          sharingService.scriptedCancelOutcome = InviteCancellation.revoked;

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
          await tester.tap(
            find.widgetWithText(FilledButton, 'Cancel Invitation'),
          );
          await tester.pumpAndSettle();

          expect(sharingService.lastCancelledInvitationId, 'inv-1');
          expect(find.text('Sitter'), findsNothing);
          expect(find.text('No pending invitations'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets('a co-parent viewing a co_parent invitation created by the '
          'primary guardian sees no cancel control on that row (R3)', (
        tester,
      ) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          guardianRow('g-1', 'user-dad', 'co_parent', 'Dad'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(
            id: 'inv-1',
            role: GuardianRole.coParent,
            recipientLabel: 'Second Co-Parent',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: sharingService,
              currentUserId: 'user-dad',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Second Co-Parent'),
          findsOneWidget,
          reason: 'visible but not actionable (Q2)',
        );
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
        'cancelInvite returning alreadyAccepted refreshes rather than '
        'leaving a stale pending row on screen',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          ]);
          sharingService.scriptedPendingInvites = [
            pendingInvite(id: 'inv-1', recipientLabel: 'Sitter'),
          ];
          sharingService.scriptedCancelOutcome =
              InviteCancellation.alreadyAccepted;

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
          await tester.tap(
            find.widgetWithText(FilledButton, 'Cancel Invitation'),
          );
          await tester.pumpAndSettle();

          expect(find.text('Sitter'), findsNothing);
          expect(
            find.text('That invitation was already accepted'),
            findsOneWidget,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        'a listPendingInvites failure renders the retry affordance and '
        'leaves the guardian list rendered',
        (tester) async {
          await storage.applyRemoteRows([
            guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
          ]);
          sharingService.scriptedListError = Exception('offline');

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
            find.text('Mom'),
            findsOneWidget,
            reason: 'the guardian list (local Drift) keeps working offline',
          );
          expect(
            find.text('Could not load pending invitations.'),
            findsOneWidget,
          );
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
        },
      );

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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
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
        },
      );

      testWidgets('an expired invitation renders as an Expired row with Resend '
          '(negative time remaining is never shown)', (tester) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(
            id: 'inv-1',
            recipientLabel: 'Sitter',
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(hours: 2),
            ),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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

      testWidgets('Resend on an expired row re-opens the invite flow', (
        tester,
      ) async {
        await storage.applyRemoteRows([
          guardianRow('g-0', 'user-mom', 'primary_guardian', 'Mom'),
        ]);
        sharingService.scriptedPendingInvites = [
          pendingInvite(
            id: 'inv-1',
            recipientLabel: 'Sitter',
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(hours: 2),
            ),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
        expect(find.text('Invite guardian to Luna'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    });
  });

  group('ManageGuardiansScreen notification tile (Issue #5, U8)', () {
    testWidgets(
      'with a service provided, shows the Notifications tile and tapping it pushes the screen',
      (tester) async {
        final notificationPreferencesService =
            FakeNotificationPreferencesService();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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

        expect(
          find.byKey(const ValueKey('notifications-action')),
          findsOneWidget,
        );

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
        expect(
          kSentryRouteNames,
          contains(kRouteNotificationPreferencesScreen),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('with no service provided, the tile is absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
    testWidgets('the primary guardian sees the action and it pushes '
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      double topInset = 0,
    }) async {
      final app = LunarLogApp.withCollaborators(
        db: db,
        authService: auth,
        sharingService: useSharing ? sharingService : null,
        ownershipTransferService: ownershipTransferService,
        inviteLinks: inviteLinks,
        initialInviteCode: initialInviteCode,
        initialInviteProfileId: initialInviteProfileId,
        initialInviteKind: initialInviteKind,
      );
      // Issue #1022: inject the status-bar inset the banner and the screens
      // beneath it share, without disturbing the ambient test surface's own
      // size. `copyWith` preserves the view metrics; only the top inset
      // changes, so a non-zero [topInset] is a real status-bar pad.
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(top: topInset),
                viewPadding: media.viewPadding.copyWith(top: topInset),
              ),
              child: app,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a live link presents the accept sheet when signed in', (
      tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-dad'),
      );

      await pumpAppWithInvite(
        tester,
        auth,
        inviteLinks: Stream.value(
          Uri.parse('lunarlog://invite?code=raw-token&profile=p-1'),
        ),
      );

      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a cold-start code waits for sign-in, then presents (R9)', (
      tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpAppWithInvite(tester, auth, initialInviteCode: 'cold-token');

      expect(find.text('Join Shared Profile'), findsNothing);

      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-dad'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Join Shared Profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    // Issue #535 (b): a latched invite code was previously consumed once,
    // silently, on sign-in - a signed-out recipient who doesn't sign in
    // right away got no feedback at all that an invite was waiting.
    group('pending-invite sign-in banner (Issue #535 b)', () {
      testWidgets(
        'renders while the invite is latched and the recipient is signed '
        'out, and disappears once signed in',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);

          await pumpAppWithInvite(
            tester,
            auth,
            initialInviteCode: 'cold-token',
          );

          expect(
            find.byKey(const Key('pending-invite-sign-in-banner')),
            findsOneWidget,
          );
          expect(find.text('Sign in to accept your invite'), findsOneWidget);

          auth.emit(
            AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-dad'),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('pending-invite-sign-in-banner')),
            findsNothing,
          );
          expect(find.text('Join Shared Profile'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets('is absent when there is no pending invite', (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);

        await pumpAppWithInvite(tester, auth);

        expect(
          find.byKey(const Key('pending-invite-sign-in-banner')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets("tapping the banner's action routes to sign-in", (
        tester,
      ) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);

        await pumpAppWithInvite(tester, auth, initialInviteCode: 'cold-token');

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets(
        'LLA-005: a session arriving while the pushed SignInScreen is on '
        'screen pops the sign-in screen, not the invite sheet it just '
        'presented',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);

          await pumpAppWithInvite(
            tester,
            auth,
            initialInviteCode: 'cold-token',
          );

          await tester.tap(find.text('Sign In'));
          await tester.pumpAndSettle();
          expect(find.byType(SignInScreen), findsOneWidget);

          // A session arrives while SignInScreen is on top (a magic link
          // opened on this device, or any provider's early event) - both
          // the app-level listener (presents the sheet) and SignInScreen's
          // own listener (pops itself) react to the same notification.
          auth.emit(
            AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-dad'),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(SignInScreen),
            findsNothing,
            reason: 'the sign-in screen must be the one popped',
          );
          expect(
            find.text('Join Shared Profile'),
            findsOneWidget,
            reason: 'the invite sheet must still be showing',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      // Issue #1022: the banner's own SafeArea consumes the status-bar inset
      // once for the whole strip, and the Navigator beneath it must see a
      // MediaQuery with `padding.top` removed — otherwise every screen's own
      // AppBar/SafeArea padded for the status bar a second time, leaving a
      // dead band between the banner and the content.
      testWidgets(
        'consumes the status-bar inset exactly once: content sits flush '
        'under the banner',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);

          await pumpAppWithInvite(
            tester,
            auth,
            initialInviteCode: 'cold-token',
            topInset: 44,
          );

          final banner = find.byKey(
            const Key('pending-invite-sign-in-banner'),
          );
          final appBar = find.byType(AppBar);
          expect(banner, findsOneWidget);
          expect(appBar, findsOneWidget);

          final bannerBottom = tester.getBottomLeft(banner).dy;
          final appBarBottom = tester.getBottomLeft(appBar).dy;
          expect(
            appBarBottom - bannerBottom,
            kToolbarHeight,
            reason: 'the banner already consumed the 44pt status-bar inset, '
                'so the pushed-down screen must not pad its app bar for it a '
                'second time — the dead band issue #1022 reports',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        'with no banner the screen still consumes the inset itself '
        '(unchanged)',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);

          await pumpAppWithInvite(tester, auth, topInset: 44);

          final appBar = find.byType(AppBar);
          expect(appBar, findsOneWidget);

          expect(
            tester.getTopLeft(appBar).dy,
            0,
            reason: 'with no banner above it, the screen starts at the top of '
                'the app',
          );
          expect(
            tester.getBottomLeft(appBar).dy,
            44 + kToolbarHeight,
            reason: 'and the app bar carries exactly one status-bar pad — the '
                'fix must not change the no-banner case',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets(
        'rotation / inset-less device: banner and content stay flush at the '
        'top',
        (tester) async {
          final auth = FakeAuthService();
          addTearDown(auth.dispose);

          await pumpAppWithInvite(
            tester,
            auth,
            initialInviteCode: 'cold-token',
            topInset: 0,
          );

          final banner = find.byKey(
            const Key('pending-invite-sign-in-banner'),
          );
          final appBar = find.byType(AppBar);
          expect(banner, findsOneWidget);
          expect(appBar, findsOneWidget);

          final bannerTop = tester.getTopLeft(banner).dy;
          final bannerBottom = tester.getBottomLeft(banner).dy;
          expect(bannerTop, 0);
          expect(
            tester.getBottomLeft(appBar).dy - bannerBottom,
            kToolbarHeight,
            reason: 'with no top inset there is nothing to consume, and the '
                'content must still sit flush under the banner',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        },
      );

      testWidgets('the close control dismisses the banner for this session', (
        tester,
      ) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);

        await pumpAppWithInvite(
          tester,
          auth,
          initialInviteCode: 'cold-token',
        );

        expect(
          find.byKey(const Key('pending-invite-sign-in-banner')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('pending-invite-banner-dismiss')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('pending-invite-sign-in-banner')),
          findsNothing,
          reason: 'the invite link is single-use and still in the '
              "recipient's messages, so a session-local close loses nothing",
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    });

    testWidgets('links without a code are ignored', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-dad'),
      );

      await pumpAppWithInvite(
        tester,
        auth,
        inviteLinks: Stream.value(Uri.parse('lunarlog://other')),
      );

      expect(find.text('Join Shared Profile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('links do nothing when no sharing service is configured', (
      tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-dad'),
      );

      await pumpAppWithInvite(
        tester,
        auth,
        useSharing: false,
        inviteLinks: Stream.value(
          Uri.parse('lunarlog://invite?code=raw-token&profile=p-1'),
        ),
      );

      expect(find.text('Join Shared Profile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
      'a kind=claim link while signed in opens ClaimProfileSheet, not '
      'AcceptInviteSheet',
      (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);
        auth.emit(
          AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'),
        );
        final transferService = FakeOwnershipTransferService();

        await pumpAppWithInvite(
          tester,
          auth,
          ownershipTransferService: transferService,
          inviteLinks: Stream.value(
            Uri.parse(
              'lunarlog://invite?code=raw-token&profile=p-1&kind=claim',
            ),
          ),
        );

        expect(find.byType(ClaimProfileSheet), findsOneWidget);
        expect(find.byType(AcceptInviteSheet), findsNothing);
        expect(find.text('Become the Owner'), findsOneWidget);
        expect(find.text('Join Shared Profile'), findsNothing);
        // Issue #182: the claim sheet is pushed as a named route, visible to
        // the Sentry route observer.
        final claimRoute = ModalRoute.of(
          tester.element(find.byType(ClaimProfileSheet)),
        );
        expect(claimRoute?.settings.name, kRouteClaimProfileSheet);
        expect(kSentryRouteNames, contains(kRouteClaimProfileSheet));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'a link with an unrecognised kind still opens AcceptInviteSheet',
      (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);
        auth.emit(
          AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-dad'),
        );

        await pumpAppWithInvite(
          tester,
          auth,
          inviteLinks: Stream.value(
            Uri.parse(
              'lunarlog://invite?code=raw-token&profile=p-1&kind=something-else',
            ),
          ),
        );

        expect(find.byType(AcceptInviteSheet), findsOneWidget);
        expect(find.byType(ClaimProfileSheet), findsNothing);
        expect(find.text('Join Shared Profile'), findsOneWidget);
        // Issue #182: the accept sheet is pushed as a named route too.
        final acceptRoute = ModalRoute.of(
          tester.element(find.byType(AcceptInviteSheet)),
        );
        expect(acceptRoute?.settings.name, kRouteAcceptInviteSheet);
        expect(kSentryRouteNames, contains(kRouteAcceptInviteSheet));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'a claim link received while signed out is latched, and opens the '
      'claim sheet once signed in (R27)',
      (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);
        final transferService = FakeOwnershipTransferService();

        await pumpAppWithInvite(
          tester,
          auth,
          ownershipTransferService: transferService,
          inviteLinks: Stream.value(
            Uri.parse(
              'lunarlog://invite?code=cold-claim-token&profile=p-1&kind=claim',
            ),
          ),
        );

        expect(find.byType(ClaimProfileSheet), findsNothing);
        expect(find.byType(AcceptInviteSheet), findsNothing);

        auth.emit(
          AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ClaimProfileSheet), findsOneWidget);
        expect(find.byType(AcceptInviteSheet), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'LLA-005: a session arriving while SignInScreen is pushed for a '
      'latched claim link pops the sign-in screen, not the claim sheet',
      (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);
        final transferService = FakeOwnershipTransferService();

        await pumpAppWithInvite(
          tester,
          auth,
          ownershipTransferService: transferService,
          initialInviteCode: 'cold-claim-token',
          initialInviteProfileId: 'p-1',
          initialInviteKind: 'claim',
        );

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();
        expect(find.byType(SignInScreen), findsOneWidget);

        auth.emit(
          AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsNothing,
            reason: 'the sign-in screen must be the one popped');
        expect(find.byType(ClaimProfileSheet), findsOneWidget,
            reason: 'the claim sheet must still be showing');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'a cold-start claim link supplied as the initial link opens the '
      'sheet after the first frame',
      (tester) async {
        final auth = FakeAuthService();
        addTearDown(auth.dispose);
        auth.emit(
          AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-child'),
        );
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
      },
    );

    testWidgets('two claim links in quick succession open one sheet, not two', (
      tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-child'),
      );
      final transferService = FakeOwnershipTransferService();
      final controller = StreamController<Uri>();
      addTearDown(controller.close);

      await pumpAppWithInvite(
        tester,
        auth,
        ownershipTransferService: transferService,
        inviteLinks: controller.stream,
      );

      controller.add(
        Uri.parse('lunarlog://invite?code=raw-token&profile=p-1&kind=claim'),
      );
      controller.add(
        Uri.parse('lunarlog://invite?code=raw-token-2&profile=p-1&kind=claim'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClaimProfileSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Profile picker caregivers action', () {
    testWidgets('opens the manage screen for the signed-in guardian', (
      tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-mom'),
      );
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

      await tester.pumpWidget(
        LunarLogApp.withCollaborators(
          db: db,
          authService: auth,
          sharingService: sharingService,
        ),
      );
      await tester.pumpAndSettle();

      final lunaTile = find.ancestor(
        of: find.text('Luna'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: lunaTile,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardians'));
      await tester.pumpAndSettle();

      expect(find.text('Luna Guardians'), findsOneWidget);

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
