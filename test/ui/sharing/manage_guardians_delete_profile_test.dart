/// Issue #472 widget coverage for `ManageGuardiansScreen`'s "Danger zone":
/// the primary guardian sees "Delete profile permanently" and no one else
/// does, the double-confirmation dialog sequence, a successful delete pops
/// the screen without touching local storage itself (the fake service
/// stands in for [ProfileErasureService], which owns that), and a failed
/// delete surfaces honest copy and leaves the screen open.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';

class _NoInvitesSharingService implements SharingService {
  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeProfileErasureService implements ProfileErasureService {
  String? lastDeletedProfileId;
  int deleteCalls = 0;
  Object? deleteError;

  @override
  Future<void> deleteProfile({required String profileId}) async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    lastDeletedProfileId = profileId;
  }

  @override
  Future<void> purgeImportedData({
    required String profileId,
    required PurgeableImportSource source,
  }) =>
      throw UnimplementedError('not exercised by this test file');
}

void main() {
  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late Profile testProfile;
  late _FakeProfileErasureService erasureService;

  RemoteProfileGuardianRow guardianRow(String userId, String role) =>
      RemoteProfileGuardianRow(
        id: 'g-$userId',
        profileId: testProfile.id,
        userId: userId,
        role: role,
        status: 'accepted',
        displayName: null,
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        serverVersion: 1,
      );

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    erasureService = _FakeProfileErasureService();
    testProfile = profileToDomain(
      await storage.upsertProfile(displayName: 'Riley', isMinor: false),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required String callerRole,
    ProfileErasureService? service,
  }) async {
    await storage.applyRemoteRows([guardianRow('user-mom', callerRole)]);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => ManageGuardiansScreen(
              profile: testProfile,
              guardiansRepository: DriftProfileGuardiansRepository(storage),
              sharingService: _NoInvitesSharingService(),
              currentUserId: 'user-mom',
              profileErasureService: service ?? erasureService,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'the primary guardian sees the Danger zone and its delete action',
    (tester) async {
      await pumpScreen(tester, callerRole: 'primary_guardian');

      expect(find.text('Danger zone'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('delete-profile-permanently')),
        findsOneWidget,
      );

      await unmount(tester);
    },
  );

  for (final role in ['co_parent', 'caregiver', 'viewer']) {
    testWidgets(
      'a $role never sees the delete action',
      (tester) async {
        await pumpScreen(tester, callerRole: role);

        expect(find.text('Danger zone'), findsNothing);
        expect(
          find.byKey(const ValueKey('delete-profile-permanently')),
          findsNothing,
        );

        await unmount(tester);
      },
    );
  }

  testWidgets('no ProfileErasureService configured hides the section '
      'entirely, even for the primary guardian', (tester) async {
    await storage.applyRemoteRows([
      guardianRow('user-mom', 'primary_guardian'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ManageGuardiansScreen(
          profile: testProfile,
          guardiansRepository: DriftProfileGuardiansRepository(storage),
          sharingService: _NoInvitesSharingService(),
          currentUserId: 'user-mom',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Danger zone'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'cancelling the first confirmation step never calls the service',
    (tester) async {
      await pumpScreen(tester, callerRole: 'primary_guardian');

      await tester.tap(
        find.byKey(const ValueKey('delete-profile-permanently')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete Riley permanently?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(erasureService.deleteCalls, 0);
      expect(find.text('Delete Riley permanently?'), findsNothing);

      await unmount(tester);
    },
  );

  testWidgets(
    'cancelling the second (final) confirmation step never calls the '
    'service',
    (tester) async {
      await pumpScreen(tester, callerRole: 'primary_guardian');

      await tester.tap(
        find.byKey(const ValueKey('delete-profile-permanently')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Are you absolutely sure?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(erasureService.deleteCalls, 0);

      await unmount(tester);
    },
  );

  testWidgets(
    'confirming both steps calls deleteProfile and pops the screen',
    (tester) async {
      await pumpScreen(tester, callerRole: 'primary_guardian');

      await tester.tap(
        find.byKey(const ValueKey('delete-profile-permanently')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(erasureService.deleteCalls, 1);
      expect(erasureService.lastDeletedProfileId, testProfile.id);
      // The screen popped: its own AppBar title is gone.
      expect(find.text('Riley Guardians'), findsNothing);

      await unmount(tester);
    },
  );

  testWidgets(
    'a failed delete surfaces an error and leaves the screen open',
    (tester) async {
      erasureService.deleteError = const ProfileErasureFailure.network();
      await pumpScreen(tester, callerRole: 'primary_guardian');

      await tester.tap(
        find.byKey(const ValueKey('delete-profile-permanently')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(erasureService.deleteCalls, 1);
      // Renders through InlineError (lib/ui/README.md: a delete's own
      // failure is an in-place, retryable failure), not a SnackBar.
      expect(find.byKey(const ValueKey('delete-profile-error')), findsOneWidget);
      expect(
        find.text(
          "Can't delete while offline. Check your connection and try "
          'again.',
        ),
        findsOneWidget,
      );
      // The screen is still open (its AppBar title is present) and the
      // delete action is tappable again.
      expect(find.text('Riley Guardians'), findsOneWidget);
      expect(
        tester
            .widget<DestructiveButton>(find.byWidgetPredicate(
              (w) => w is DestructiveButton,
            ))
            .onPressed,
        isNotNull,
      );

      await unmount(tester);
    },
  );
}
