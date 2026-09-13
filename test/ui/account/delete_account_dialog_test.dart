/// Widget tests for [DeleteAccountDialog]'s blast-radius disclosure (Issue
/// #533): deleting your account cascades every profile you own, taking any
/// co-guardian's access with it, while entries you logged as a caregiver on
/// someone else's profile are kept and re-attributed. This dialog must
/// enumerate that before its confirm button is enabled, require an extra
/// acknowledgement when it applies, offer "Transfer ownership first", and
/// style the confirm action as destructive - see `test/ui/account_deletion_
/// test.dart` for the pre-existing coverage of the rest of the delete flow
/// (credential gate, export, Apple ceremony, failure copy), unchanged by
/// this issue and not duplicated here.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/delete_account_dialog.dart';
import 'package:lunarlog/ui/sharing/transfer_ownership_screen.dart';
import 'package:provider/provider.dart';

import '../../support/fake_auth_service.dart';

Finder key(String value) => find.byKey(ValueKey(value));

class FakeProfilesRepository implements ProfilesRepository {
  List<Profile> profiles = const [];

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileGuardiansRepository implements ProfileGuardiansRepository {
  Map<String, List<ProfileGuardian>> guardiansByProfile = const {};

  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async =>
      guardiansByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never actually exercised end-to-end here (that belongs to `test/ui/
/// transfer_ownership_test.dart`) - only enough to prove "Transfer ownership
/// first" reuses the real screen/route rather than building a new one.
/// `getActiveTransfer` is called from that screen's own `initState` and its
/// own try/catch already treats any thrown error as "best effort, nothing
/// found" (see its doc comment), so the inherited `noSuchMethod` fallback is
/// enough - no override needed.
class FakeOwnershipTransferService implements OwnershipTransferService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(String id, String name, {bool isMinor = true}) {
  final now = DateTime.utc(2026, 9, 1);
  return Profile(
    id: id,
    displayName: name,
    isMinor: isMinor,
    createdAt: now,
    updatedAt: now,
  );
}

ProfileGuardian _guardian(String profileId, String userId, GuardianRole role) {
  final now = DateTime.utc(2026, 9, 1);
  return ProfileGuardian(
    id: '$profileId-$userId',
    profileId: profileId,
    userId: userId,
    role: role,
    status: GuardianStatus.accepted,
    createdAt: now,
    updatedAt: now,
  );
}

class DialogHarness {
  DialogHarness({
    List<Profile> profiles = const [],
    Map<String, List<ProfileGuardian>> guardiansByProfile = const {},
    bool provideGuardiansRepository = true,
    bool provideOwnershipTransferService = true,
  }) : profilesRepository = FakeProfilesRepository()..profiles = profiles,
       guardiansRepository = provideGuardiansRepository
           ? (FakeProfileGuardiansRepository()
               ..guardiansByProfile = guardiansByProfile)
           : null,
       ownershipTransferService = provideOwnershipTransferService
           ? FakeOwnershipTransferService()
           : null {
    auth.emit(
      AuthSessionState.signedIn,
      user: const AuthUser(id: 'u1', email: 'owner@example.com'),
    );
    controller = AuthController(authService: auth);
  }

  final FakeAuthService auth = FakeAuthService();
  late final AuthController controller;
  final FakeProfilesRepository profilesRepository;
  final FakeProfileGuardiansRepository? guardiansRepository;
  final FakeOwnershipTransferService? ownershipTransferService;

  DeleteAccountDecision? decision;
  int exportCalls = 0;

  Future<void> pump(WidgetTester tester) async {
    // `MultiProvider` wraps `MaterialApp` here (not the other way around,
    // unlike some older harnesses in this suite) to match `lib/app.dart`'s
    // actual tree: `showDeleteAccountDialog` pushes onto the *root*
    // navigator, so its route's own subtree only inherits providers that
    // are ancestors of `MaterialApp` itself - a `MultiProvider` nested
    // inside `MaterialApp.home` would never be visible to it.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: controller),
          Provider<ProfilesRepository>.value(value: profilesRepository),
          if (guardiansRepository != null)
            Provider<ProfileGuardiansRepository>.value(
              value: guardiansRepository!,
            ),
          if (ownershipTransferService != null)
            Provider<OwnershipTransferService>.value(
              value: ownershipTransferService!,
            ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  decision = await showDeleteAccountDialog(
                    context,
                    onExport: () async {
                      exportCalls++;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(key('open'));
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
    unawaited(auth.dispose());
  }
}

void main() {
  group('#533 (a): no owned/shared profiles - the plain flow', () {
    testWidgets(
      'no blast-radius copy, no acknowledgement checkbox, no transfer '
      'action, and the destructive-styled confirm is enabled immediately',
      (tester) async {
        final h = DialogHarness();
        addTearDown(h.dispose);
        await h.pump(tester);
        await h.open(tester);

        expect(key('account-delete-blast-radius'), findsNothing);
        expect(key('account-delete-ack-checkbox'), findsNothing);
        expect(key('account-delete-transfer-first'), findsNothing);

        final confirm = tester.widget<FilledButton>(
          key('account-delete-confirm'),
        );
        expect(
          confirm.onPressed,
          isNotNull,
          reason: 'nothing to acknowledge, so confirm is enabled outright',
        );

        await tester.tap(key('account-delete-confirm'));
        await tester.pumpAndSettle();
        expect(h.decision, DeleteAccountDecision.delete);
      },
    );

    testWidgets('an owned profile with no other guardian still names it, '
        'but requires no checkbox and leaves confirm enabled', (tester) async {
      final h = DialogHarness(
        profiles: [_profile('p1', 'Riley', isMinor: false)],
        guardiansByProfile: {
          'p1': [_guardian('p1', 'u1', GuardianRole.primaryGuardian)],
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);
      await h.open(tester);

      expect(
        tester.widget<Text>(key('account-delete-blast-radius')).data,
        contains('Riley'),
      );
      expect(key('account-delete-ack-checkbox'), findsNothing);
      expect(key('account-delete-transfer-first'), findsNothing);
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNotNull,
      );
    });
  });

  group('#533 (b): an owned profile shared with another guardian', () {
    testWidgets('shows the blast-radius copy naming the profile and the other-'
        'guardian count, offers Transfer ownership first, and gates confirm '
        'on the acknowledgement checkbox', (tester) async {
      final h = DialogHarness(
        profiles: [_profile('p1', 'Maya')],
        guardiansByProfile: {
          'p1': [
            _guardian('p1', 'u1', GuardianRole.primaryGuardian),
            _guardian('p1', 'u2', GuardianRole.coParent),
          ],
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);
      await h.open(tester);

      final blastRadiusText = tester
          .widget<Text>(key('account-delete-blast-radius'))
          .data;
      expect(blastRadiusText, contains('Maya'));
      expect(blastRadiusText, contains('1 other guardian'));

      expect(key('account-delete-transfer-first'), findsOneWidget);

      // Disabled before the checkbox is checked.
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNull,
        reason: 'a shared owned profile requires the checkbox first',
      );

      await tester.ensureVisible(key('account-delete-ack-checkbox'));
      await tester.tap(key('account-delete-ack-checkbox'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNotNull,
        reason: 'checking the box enables confirm',
      );

      // Unchecking it disables confirm again.
      await tester.tap(key('account-delete-ack-checkbox'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNull,
      );

      await tester.tap(key('account-delete-ack-checkbox'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();
      expect(h.decision, DeleteAccountDecision.delete);
    });

    testWidgets(
      '"Transfer ownership first" cancels the deletion and pushes the '
      'existing TransferOwnershipScreen for that profile - no new UI',
      (tester) async {
        final h = DialogHarness(
          profiles: [_profile('p1', 'Maya')],
          guardiansByProfile: {
            'p1': [
              _guardian('p1', 'u1', GuardianRole.primaryGuardian),
              _guardian('p1', 'u2', GuardianRole.coParent),
            ],
          },
        );
        addTearDown(h.dispose);
        await h.pump(tester);
        await h.open(tester);

        await tester.tap(key('account-delete-transfer-first'));
        await tester.pumpAndSettle();

        expect(
          find.text('Delete account?'),
          findsNothing,
          reason: 'the confirmation dialog itself is gone',
        );
        expect(
          h.decision,
          DeleteAccountDecision.cancel,
          reason: 'transferring instead is treated as cancelling the delete',
        );
        expect(find.byType(TransferOwnershipScreen), findsOneWidget);
        expect(find.text("Transfer Maya's Profile"), findsOneWidget);
      },
    );
  });

  group('#533 (c): the confirm action is styled as destructive in both '
      'cases', () {
    for (final MapEntry(key: description, value: harnessBuilder)
        in <String, DialogHarness Function()>{
          'no owned/shared profiles': () => DialogHarness(),
          'a shared owned profile': () => DialogHarness(
            profiles: [_profile('p1', 'Maya')],
            guardiansByProfile: {
              'p1': [
                _guardian('p1', 'u1', GuardianRole.primaryGuardian),
                _guardian('p1', 'u2', GuardianRole.coParent),
              ],
            },
          ),
        }.entries) {
      testWidgets(description, (tester) async {
        final h = harnessBuilder();
        addTearDown(h.dispose);
        await h.pump(tester);
        await h.open(tester);

        final context = tester.element(key('account-delete-confirm'));
        final colorScheme = Theme.of(context).colorScheme;
        final confirm = tester.widget<FilledButton>(
          key('account-delete-confirm'),
        );
        final resolvedBackground = confirm.style?.backgroundColor?.resolve(
          <WidgetState>{},
        );
        final resolvedForeground = confirm.style?.foregroundColor?.resolve(
          <WidgetState>{},
        );
        expect(resolvedBackground, colorScheme.error);
        expect(resolvedForeground, colorScheme.onError);
      });
    }
  });
}
