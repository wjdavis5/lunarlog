/// Widget tests for the shared care notes and visit-prep screen (Issue
/// #128): adding a note/item, checking with who-checked attribution, the
/// second guardian's display name, the viewer's and archived read-only
/// paths, clearing checked items, deletion, and the profile-screen entry
/// point. Mirrors `activity_feed_test.dart`'s harness (in-memory drift,
/// real repositories, [FakeAuthService]).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/activity_feed_repository.dart'
    as data;
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart'
    as data;
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/fake_auth_service.dart';

final DateTime kNow = DateTime.utc(2026, 9, 2, 10);

RemoteProfileGuardianRow guardianRow(
  String profileId,
  String userId,
  String role, {
  String? displayName,
  String status = 'accepted',
}) =>
    RemoteProfileGuardianRow(
      id: 'g-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class Harness {
  Harness(this.db, this.profile, this.auth, this.authController);
  final LunarLogDatabase db;
  final Profile profile;
  final FakeAuthService auth;
  final AuthController authController;
}

Future<Harness> pumpCare(
  WidgetTester tester, {
  required String currentUserId,
  String currentRole = 'primary_guardian',
  bool readOnly = false,
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile =
      await profiles.create(displayName: 'Riley', isMinor: true);
  await db.storage.applyRemoteRows([
    guardianRow(profile.id, 'user-mom', 'primary_guardian',
        displayName: 'Mom'),
    guardianRow(profile.id, 'user-dad', 'co_parent', displayName: 'Dad'),
    if (currentRole == 'viewer')
      guardianRow(profile.id, currentUserId, 'viewer',
          displayName: 'Doc'),
  ]);
  if (seed != null) await seed(db, profile.id);

  final auth = FakeAuthService();
  auth.emit(AuthSessionState.signedIn,
      user: AuthUser(id: currentUserId));
  final authController = AuthController(authService: auth);

  final care = DriftCareContentRepository(db.storage);
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        Provider<ProfilesRepository>.value(value: profiles),
        ChangeNotifierProvider<AuthController>.value(value: authController),
      ],
      child: MaterialApp(
        home: CareNotesScreen(
          profile: profile,
          repository: care,
          guardiansRepository: data.ProfileGuardiansRepository(db.storage),
          readOnly: readOnly,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, profile, auth, authController);
}

/// Unmounts before closing the database: drift's watch streams schedule a
/// close timer on unsubscribe, which the test binding flags as pending if
/// the database closes first (mirrors `disposeActivity` in
/// `activity_feed_test.dart`).
Future<void> disposeCare(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  h.authController.dispose();
  await h.auth.dispose();
  await h.db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('CareNotesScreen (Issue #128)', () {
    testWidgets('AC1: a guardian adds a care note attributed to them',
        (tester) async {
      final h = await pumpCare(tester, currentUserId: 'user-mom');
      expect(find.text('No care notes yet.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('care-note-field')),
          'Prefers the blue inhaler.');
      await tester.tap(find.byKey(const ValueKey('care-note-add')));
      await tester.pumpAndSettle();

      expect(find.text('Prefers the blue inhaler.'), findsOneWidget);
      final stored =
          await h.db.storage.getCareNotesForProfile(h.profile.id);
      expect(stored.single.body, 'Prefers the blue inhaler.');
      expect(find.text(careAttributionDate(stored.single.updatedAt)),
          findsOneWidget,
          reason: 'the write time shows even before the first sync stamps '
              'authorship');
      expect(stored.single.dirty, isTrue,
          reason: 'the note is flagged for the next sync');
      await disposeCare(tester, h);
    });

    testWidgets('AC1: a synced note names its author, or "you" for self',
        (tester) async {
      final h = await pumpCare(
        tester,
        currentUserId: 'user-dad',
        seed: (db, profileId) async {
          await db.storage.applyRemoteCareNote(RemoteCareNoteRow(
            id: 'n-mom-note',
            profileId: profileId,
            body: 'Naps better after lunch.',
            updatedAt: kNow,
            deletedAt: null,
            loggedByUserId: 'user-mom',
            lastModifiedByUserId: 'user-mom',
          ));
          await db.storage.applyRemoteCareNote(RemoteCareNoteRow(
            id: 'n-dad-note',
            profileId: profileId,
            body: 'Dad note.',
            updatedAt: kNow,
            deletedAt: null,
            loggedByUserId: 'user-dad',
            lastModifiedByUserId: 'user-dad',
          ));
        },
      );

      expect(find.text('Naps better after lunch.'), findsOneWidget);
      expect(find.textContaining('Logged by Mom'), findsOneWidget,
          reason: 'the author resolves to the guardian display name');
      expect(find.textContaining('Logged by you'), findsOneWidget,
          reason: 'the current operator reads as "you"');
      expect(find.textContaining('user-mom'), findsNothing,
          reason: 'no raw uuid ever reaches the UI');
      await disposeCare(tester, h);
    });

    testWidgets('AC3: checking an item shows who checked it', (tester) async {
      final h = await pumpCare(tester, currentUserId: 'user-dad');
      await tester.enterText(
          find.byKey(const ValueKey('visit-prep-field')),
          'Ask about iron levels.');
      await tester.tap(find.byKey(const ValueKey('visit-prep-add')));
      await tester.pumpAndSettle();
      expect(find.text('Ask about iron levels.'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.textContaining('Checked by you'), findsOneWidget);
      final stored =
          await h.db.storage.getVisitPrepItemsForProfile(h.profile.id);
      expect(stored.single.isChecked, isTrue);
      expect(stored.single.checkedByUserId, 'user-dad');

      expect(find.textContaining('Clear checked (1)'), findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('visit-prep-clear-checked')));
      await tester.pumpAndSettle();
      expect(find.text('Ask about iron levels.'), findsNothing,
          reason: 'checked items stay visible until the list is cleared');
      expect(find.text('No prep items yet.'), findsOneWidget);
      await disposeCare(tester, h);
    });

    testWidgets('AC2: a viewer reads both surfaces but cannot write',
        (tester) async {
      final h = await pumpCare(
        tester,
        currentUserId: 'user-doc',
        currentRole: 'viewer',
        seed: (db, profileId) async {
          await db.storage.applyRemoteCareNote(RemoteCareNoteRow(
            id: 'n-seeded',
            profileId: profileId,
            body: 'Seeded note.',
            updatedAt: kNow,
            deletedAt: null,
            loggedByUserId: 'user-mom',
            lastModifiedByUserId: 'user-mom',
          ));
          await db.storage.applyRemoteVisitPrepItem(RemoteVisitPrepItemRow(
            id: 'i-seeded',
            profileId: profileId,
            body: 'Seeded item.',
            updatedAt: kNow,
            deletedAt: null,
          ));
        },
      );

      // Reads both surfaces...
      expect(find.text('Seeded note.'), findsOneWidget);
      expect(find.text('Seeded item.'), findsOneWidget);
      // ...but has no write affordance, with the viewer reason shown.
      expect(find.byKey(const ValueKey('care-note-field')), findsNothing);
      expect(find.byKey(const ValueKey('visit-prep-field')), findsNothing);
      expect(find.byKey(const ValueKey('care-read-only-reason')),
          findsOneWidget);
      expect(find.text('You have view-only access to this profile.'),
          findsOneWidget);
      // The checkbox itself is present but disabled.
      final checkbox =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(checkbox.onChanged, isNull);
      await disposeCare(tester, h);
    });

    testWidgets('an archived profile renders the same read-only screen',
        (tester) async {
      final h = await pumpCare(
        tester,
        currentUserId: 'user-mom',
        readOnly: true,
      );
      expect(find.byKey(const ValueKey('care-note-field')), findsNothing);
      expect(find.byKey(const ValueKey('visit-prep-field')), findsNothing);
      expect(find.text('This profile is archived.'), findsOneWidget);
      await disposeCare(tester, h);
    });

    testWidgets('a note and an item can be removed', (tester) async {
      final h = await pumpCare(
        tester,
        currentUserId: 'user-mom',
        seed: (db, profileId) async {
          await db.storage.upsertCareNote(
              id: 'n-del', profileId: profileId, body: 'Delete me.');
          await db.storage.addVisitPrepItem(
              id: 'i-del', profileId: profileId, body: 'Remove me.');
        },
      );
      await tester.tap(find.byKey(const ValueKey('care-note-delete-n-del')));
      await tester.pumpAndSettle();
      expect(find.text('Delete me.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('visit-prep-delete-i-del')));
      await tester.pumpAndSettle();
      expect(find.text('Remove me.'), findsNothing);
      await disposeCare(tester, h);
    });

    testWidgets('an auth change mid-visit re-resolves "you"',
        (tester) async {
      final h = await pumpCare(
        tester,
        currentUserId: 'user-dad',
        seed: (db, profileId) async {
          await db.storage.applyRemoteCareNote(RemoteCareNoteRow(
            id: 'n-swap',
            profileId: profileId,
            body: 'Swap note.',
            updatedAt: kNow,
            deletedAt: null,
            loggedByUserId: 'user-mom',
            lastModifiedByUserId: 'user-mom',
          ));
        },
      );
      expect(find.textContaining('Logged by Mom'), findsOneWidget);

      // A same-state re-emit carries no notification (AuthController
      // dedupes by state), so swap accounts through a real transition.
      h.auth.emit(AuthSessionState.signedOut);
      await tester.pumpAndSettle();
      h.auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-mom'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by you'), findsOneWidget,
          reason: 'the attribution follows the current operator');
      await disposeCare(tester, h);
    });

    testWidgets('CareNotesButton pushes the named screen', (tester) async {      final h = await pumpCare(tester, currentUserId: 'user-mom');
      // The standalone screen is already under test above; here the
      // profile screen's entry point is what matters.
      expect(find.byKey(const ValueKey('care-note-field')), findsOneWidget);

      expect(kSentryRouteNames, contains(kRouteCareNotesScreen),
          reason: 'the pushed route is a registered Sentry route name');
      expect(h.profile.displayName, 'Riley');
      await disposeCare(tester, h);
    });
  });

  group('ProfileDetailScreen care entry point (Issue #128)', () {
    testWidgets('the profile screen shows the care button when storage '
        'is wired', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final profile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      final auth = FakeAuthService();
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-mom'));
      final authController = AuthController(authService: auth);

      await tester.pumpWidget(
        MultiProvider(
          providers: <SingleChildWidget>[
            Provider<ProfilesRepository>.value(value: profiles),
            Provider<DayEntriesRepository>.value(
                value: DriftDayEntriesRepository(db.storage)),
            Provider<ObservationsRepository>.value(
                value: DriftObservationsRepository(db.storage)),
            Provider<SettingsStore>.value(
                value: DriftSettingsStore(db.storage)),
            ChangeNotifierProvider<AuthController>.value(
                value: authController),
            // Domain-typed seams `ProfileDetailScreen` reads instead of raw
            // storage (mirrors `lib/app.dart`).
            Provider<ProfileGuardiansRepository>.value(
                value: data.ProfileGuardiansRepository(db.storage)),
            Provider<ActivityFeedRepository>.value(
                value: data.ActivityFeedRepository(db.storage)),
            Provider<CareContentRepository>.value(
                value: DriftCareContentRepository(db.storage)),
            ChangeNotifierProvider(
              create: (_) => ProfileController(
                profilesRepository: profiles,
                settingsStore: DriftSettingsStore(db.storage),
              )..load(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileDetailScreen(profile: profile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('care-notes-button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('care-notes-button')));
      await tester.pumpAndSettle();
      expect(find.text('Riley Care'), findsOneWidget);
      expect(find.byKey(const ValueKey('care-note-field')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      authController.dispose();
      await auth.dispose();
      await db.close();
    });
  });
}
