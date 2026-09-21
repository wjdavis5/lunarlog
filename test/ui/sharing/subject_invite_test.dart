/// Issue #802 client coverage, part 1 (invite + accept surfaces):
/// * the invite dialog offers (and preselects) the "her own profile"
///   preset exactly when the caller says the profile is the invitee's
///   own, and creating from it asks the service for caregiver + subject;
/// * a plain offer keeps the pre-#802 shape (no subject item, co-parent
///   default, subject: false);
/// * the accept sheet replaces the role sentence with the plain-language
///   "This is your profile…" intro (#800) when the preview carries the
///   subject preset, and keeps the ordinary preview copy otherwise;
/// * the Manage Guardians rows mark the subject member with a badge
///   (AC3: distinguishable without reading a uuid).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/minimum_age_acknowledgement_copy.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';

/// Minimal fake recording what the dialog asked for; previews and accept
/// results are scriptable for the sheet tests.
class _FakeSharing implements SharingService {
  String? lastCreatedRole;
  bool? lastCreatedSubject;
  InvitePreview? scriptedPreview;

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    bool subject = false,
    Duration ttl = const Duration(hours: 48),
  }) async {
    lastCreatedRole = role.toDb();
    lastCreatedSubject = subject;
    return GeneratedInvite(
      invitationId: 'inv-1',
      profileId: profileId,
      role: role,
      rawToken: 'raw',
      tokenHash: 'hash',
      inviteUri: Uri.parse('lunarlog://invite?code=raw&profile=$profileId'),
      expiresAt: DateTime.utc(2026, 9, 20),
    );
  }

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) async =>
      const AcceptedInviteResult(
        profileId: 'p-1',
        profileName: 'Riley',
        role: GuardianRole.caregiver,
        isSubject: true,
      );

  @override
  Future<InvitePreview?> previewInvite({required String rawToken}) async =>
      scriptedPreview;

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {}

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) async =>
      InviteCancellation.revoked;

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) async {}
}

class _FakeGuardiansRepository implements ProfileGuardiansRepository {
  _FakeGuardiansRepository(this.rows);

  List<ProfileGuardian> rows;

  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      Stream.value(rows);

  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async => rows;
}

Profile _profile() => Profile(
      id: 'p-subject',
      displayName: 'Riley',
      isMinor: true,
      mode: ProfileMode.standard,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      relationship: ProfileRelationship.daughter,
    );

ProfileGuardian _guardian(
  String userId,
  GuardianRole role, {
  bool isSubject = false,
  String? name,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p-subject',
      userId: userId,
      role: role,
      status: GuardianStatus.accepted,
      displayName: name,
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isSubject: isSubject,
    );

Widget _localized(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    );

void main() {
  group('InviteGuardianDialog subject preset (Issue #802)', () {
    testWidgets('offers and preselects "her own profile"; create asks for '
        'caregiver + subject', (tester) async {
      final sharing = _FakeSharing();
      await tester.pumpWidget(_localized(InviteGuardianDialog(
        profileId: 'p-subject',
        profileName: 'Riley',
        sharingService: sharing,
        subjectInviteAvailable: true,
      )));

      expect(find.byKey(const ValueKey('invite-preset-subject')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('invite-preset-dropdown')), findsOneWidget);
      // Preselected: the preset's consequence line is visible without any
      // interaction (the two-tap path: open the dialog, Create Link).
      expect(find.byKey(const ValueKey('invite-preset-subject-detail')),
          findsOneWidget);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(sharing.lastCreatedRole, 'caregiver');
      expect(sharing.lastCreatedSubject, isTrue);
      expect(find.byKey(const ValueKey('invite-created-share-subject')),
          findsOneWidget);
      expect(
        find.byKey(const ValueKey('invite-created-share-guardian')),
        findsNothing,
      );
    });

    testWidgets('a helper-only offer keeps the pre-#802 dialog exactly',
        (tester) async {
      final sharing = _FakeSharing();
      await tester.pumpWidget(_localized(InviteGuardianDialog(
        profileId: 'p-subject',
        profileName: 'Riley',
        sharingService: sharing,
      )));

      expect(find.byKey(const ValueKey('invite-preset-subject')),
          findsNothing);
      expect(find.byKey(const ValueKey('invite-preset-subject-detail')),
          findsNothing);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(sharing.lastCreatedRole, 'co_parent');
      expect(sharing.lastCreatedSubject, isFalse);
      expect(find.byKey(const ValueKey('invite-created-share-guardian')),
          findsOneWidget);
    });

    testWidgets('selecting a helper role after the subject default sends no '
        'subject marker', (tester) async {
      final sharing = _FakeSharing();
      await tester.pumpWidget(_localized(InviteGuardianDialog(
        profileId: 'p-subject',
        profileName: 'Riley',
        sharingService: sharing,
        subjectInviteAvailable: true,
      )));
      await tester.tap(find.byKey(const ValueKey('invite-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewer (Read-only access)').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-preset-subject-detail')),
          findsNothing);

      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();

      expect(sharing.lastCreatedRole, 'viewer');
      expect(sharing.lastCreatedSubject, isFalse);
    });
  });

  group('AcceptInviteSheet subject copy (Issue #802, per #800)', () {
    testWidgets('a subject preview promises "This is your profile"',
        (tester) async {
      final sharing = _FakeSharing()
        ..scriptedPreview = InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.caregiver,
          expiresAt: DateTime.utc(2026, 9, 22),
          isSubject: true,
        );
      await tester.pumpWidget(_localized(
        AcceptInviteSheet(rawToken: 'raw', sharingService: sharing),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('accept-invite-subject-ready')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('accept-invite-preview-ready')),
          findsNothing);
      expect(find.textContaining('This is your profile.'), findsOneWidget);
      // The mislabel the issue exists to kill: never "as Caregiver".
      expect(find.textContaining('as Caregiver'), findsNothing);
    });

    testWidgets('an ordinary preview keeps the role sentence', (tester) async {
      final sharing = _FakeSharing()
        ..scriptedPreview = InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.caregiver,
          expiresAt: DateTime.utc(2026, 9, 22),
        );
      await tester.pumpWidget(_localized(
        AcceptInviteSheet(rawToken: 'raw', sharingService: sharing),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('accept-invite-preview-ready')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('accept-invite-subject-ready')),
          findsNothing);
    });
  });

  group('AcceptInviteSheet parent-invite acknowledgement (Issue #957)', () {
    const parentInviteLabel =
        'My parent or guardian created this profile and invited me to use it';

    testWidgets('a subject preview shows the parent-invite wording, never the '
        'flat 13-or-older affirmation', (tester) async {
      final sharing = _FakeSharing()
        ..scriptedPreview = InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.caregiver,
          expiresAt: DateTime.utc(2026, 9, 22),
          isSubject: true,
        );
      await tester.pumpWidget(_localized(
        AcceptInviteSheet(rawToken: 'raw', sharingService: sharing),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('accept-invite-subject-acknowledgement')),
        findsOneWidget,
      );
      expect(find.text(parentInviteLabel), findsOneWidget);
      expect(
        find.text('I am 13 or older, or a guardian managing a family profile'),
        findsNothing,
      );
    });

    testWidgets('an ordinary (non-subject) preview shows no acknowledgement',
        (tester) async {
      final sharing = _FakeSharing()
        ..scriptedPreview = InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.caregiver,
          expiresAt: DateTime.utc(2026, 9, 22),
        );
      await tester.pumpWidget(_localized(
        AcceptInviteSheet(rawToken: 'raw', sharingService: sharing),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('accept-invite-subject-acknowledgement')),
        findsNothing,
      );
    });

    testWidgets('the injected context is the seam: it renders the parent-invite '
        'wording even when the preview is unavailable', (tester) async {
      // No scripted preview => _PreviewState.unavailable, so the derivation
      // alone could never pick the subject wording; the injected context does.
      final sharing = _FakeSharing();
      await tester.pumpWidget(_localized(
        AcceptInviteSheet(
          rawToken: 'raw',
          sharingService: sharing,
          acknowledgementContext: MinimumAgeAcknowledgementContext.parentInvite,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('accept-invite-subject-acknowledgement')),
        findsOneWidget,
      );
      expect(find.text(parentInviteLabel), findsOneWidget);
    });
  });

  group('ManageGuardiansScreen subject badge (AC3)', () {
    testWidgets('the subject member row carries the "(her profile)" badge '
        'and the parents\' rows do not', (tester) async {
      final sharing = _FakeSharing();
      final repo = _FakeGuardiansRepository([
        _guardian('user-mom', GuardianRole.primaryGuardian, name: 'Mom'),
        _guardian('user-dad', GuardianRole.coParent, name: 'Dad'),
        _guardian('user-daughter', GuardianRole.caregiver,
            isSubject: true, name: 'Riley'),
      ]);
      await tester.pumpWidget(_localized(ManageGuardiansScreen(
        profile: _profile(),
        guardiansRepository: repo,
        sharingService: sharing,
        currentUserId: 'user-mom',
      )));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('guardian-subject-badge-user-daughter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('guardian-subject-badge-user-mom')),
        findsNothing,
      );
      expect(find.text('(her profile)'), findsOneWidget);
      // Every parent's row keeps its role badge copy (subtitle).
      expect(find.text('Primary Guardian'), findsOneWidget);
      expect(find.text('Co-Parent'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);
    });

    testWidgets('the invite sheet opened from a daughter profile offers the '
        'subject preset', (tester) async {
      final sharing = _FakeSharing();
      final repo = _FakeGuardiansRepository([
        _guardian('user-mom', GuardianRole.primaryGuardian, name: 'Mom'),
      ]);
      await tester.pumpWidget(_localized(ManageGuardiansScreen(
        profile: _profile(),
        guardiansRepository: repo,
        sharingService: sharing,
        currentUserId: 'user-mom',
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite guardian'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('invite-preset-subject')),
          findsOneWidget);
    });
  });
}
