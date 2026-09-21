/// Widget tests for issue #804 — household setup in first run: the
/// "Who is this profile for?" choice on the name form, the cared-for
/// card's defaults (relationship, minor on, Teen suggested), the
/// shortened cycle step, the add-another wrap-up loop, and the invite
/// step ("Add another guardian?") with #966's guardian and subject
/// invite presets.
///
/// The single-profile regression contract lives here too: the plain
/// "Me" path is pinned to today's tap budget and never shows a household
/// step (the original first-run suite, test/ui/first_run_test.dart, runs
/// unchanged against the same screen).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

/// The injected "today" for subject-invite gating determinism.
final LocalDate kToday = LocalDate(2026, 9, 1);

/// Minimal fake recording what the invite dialog asked for (the same
/// shape subject_invite_test.dart uses for the Manage Guardians path).
class _FakeSharing implements SharingService {
  String? lastCreatedRole;
  bool? lastCreatedSubject;
  String? lastCreatedProfileId;

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
    lastCreatedProfileId = profileId;
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
      null;

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

/// Mounts a bare `FirstRunScreen` over the minimal provider set it reads,
/// mirroring test/ui/first_run_test.dart's harness plus the two optional
/// providers the invite step reads (`SharingService`, `AuthController`).
class Harness {
  Harness(this.tester, {this.sharing, this.auth})
      : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  final SharingService? sharing;
  final AuthController? auth;

  late final SettingsStore settings = DriftSettingsStore(db.storage);
  late final ProfileController profiles = ProfileController(
    profilesRepository: DriftProfilesRepository(db.storage),
    settingsStore: settings,
  );

  late final OnboardingCycleAnswersRecorder recorder =
      DriftOnboardingCycleAnswersRecorder(db.storage,
          todayProvider: () => kToday);

  Future<void> pump({
    double textScale = 1.0,
    Size physicalSize = const Size(800, 600),
  }) async {
    // Issue #994: the layout regression only reproduces on a narrow surface
    // with large type, so the harness drives the view (logical pixels equal
    // physical pixels at dpr 1.0) and the text scaler explicitly.
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Locals so the nullable provider values promote below (fields do
    // not promote).
    final sharing = this.sharing;
    final auth = this.auth;
    await profiles.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileController>.value(value: profiles),
        Provider<SettingsStore>.value(value: settings),
        Provider<OnboardingCycleAnswersRecorder>.value(value: recorder),
        if (sharing != null) Provider<SharingService>.value(value: sharing),
        if (auth != null)
          ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: FirstRunScreen(
              todayProvider: () => kToday,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    profiles.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }

  // --- step helpers -----------------------------------------------------

  Future<void> tapKey(String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> enterName(String name) async {
    await tester.enterText(find.byType(TextFormField), name);
    await tester.pumpAndSettle();
  }

  /// Acknowledged intro + minimum age, so tests land straight on the name
  /// form and only exercise the #804 surfaces.
  Future<void> pumpToNameForm({
    double textScale = 1.0,
    Size physicalSize = const Size(800, 600),
  }) async {
    final auth = this.auth;
    await settings.set(SettingsKeys.firstRunNoticeShown, 'true');
    await settings.set(SettingsKeys.minimumAgeAcknowledged, 'true');
    await pump(textScale: textScale, physicalSize: physicalSize);
    // A signed-out harness shows the account step first; "Not now" skips
    // it (the same skip a real operator chooses). The sign-in screen's
    // ListView keeps "Not now" below the fold on this surface, so drag
    // until it is built, like account_test does.
    if (auth != null && !auth.signedIn) {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('first-run-not-now')),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('first-run-not-now')));
      await tester.pumpAndSettle();
    }
  }

  /// Drives one cared-for card from the name form to a created profile.
  Future<void> createCaredForProfile(String name) async {
    await tapKey('first-run-who-someone');
    await enterName(name);
    await tapKey('first-run-continue');
    await tapKey('cycle-create');
  }
}

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('plain single-profile path (issue #804 regression contract)', () {
    testWidgets('four taps from the end of the intro — the pre-#804 '
        'budget, pinned — and no household step ever appears',
        (tester) async {
      final h = Harness(tester);
      await h.pump();

      var taps = 0;
      await h.tapKey('first-run-skip');
      taps++; // 1: skip the introduction (as before this issue)
      await h.enterName('Nova');
      await h.tapKey('first-run-age-ack-checkbox');
      taps++; // 2: the minimum-age acknowledgement (as before)
      await h.tapKey('first-run-continue');
      taps++; // 3: Continue (as before)
      expect(h.profiles.firstRunFlowActive, isFalse,
          reason: 'the Me default never arms the household flow');
      await h.tapKey('cycle-create');
      taps++; // 4: Create profile (as before)

      expect(taps, 4,
          reason: 'issue #804 AC: a parent who wants one profile and '
              'nothing else is done in the same number of taps as today');
      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.displayName, 'Nova');
      expect(profiles.single.relationship, ProfileRelationship.self,
          reason: 'issue #804 AC: choosing "me" produces self');
      expect(profiles.single.isMinor, isFalse);
      expect(profiles.single.mode, ProfileMode.standard);

      // No household step, and the gate's ordinary transition (the
      // active profile's Today) takes over exactly as before: the
      // pointer #865 set at creation is the only signal the gate needs.
      expect(find.byKey(const ValueKey('first-run-wrap-up')), findsNothing);
      expect(
          find.byKey(const ValueKey('first-run-invite-step')), findsNothing);
      expect(h.profiles.firstRunFlowActive, isFalse);
      expect(
          await h.settings.get(SettingsKeys.lastActiveProfile),
          profiles.single.id);
      await h.dispose();
    });
  });

  group('who-choice defaults (issue #804 AC2)', () {
    testWidgets('"Someone I care for" preps a daughter card: relationship '
        'dropdown, minor on, Teen suggested (never forced)', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.tapKey('first-run-who-someone');
      expect(find.byKey(const ValueKey('first-run-relationship-dropdown')),
          findsOneWidget);
      expect(find.text('Daughter'), findsOneWidget,
          reason: 'the relationship dropdown defaults to daughter');
      final minor = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile).first);
      expect(minor.value, isTrue,
          reason: 'the minor flag defaults on for a cared-for card');
      expect(find.text('Teen'), findsOneWidget,
          reason: 'Teen mode is the suggested care mode');
      expect(find.byKey(const ValueKey('first-run-teen-hint')), findsOneWidget,
          reason: 'the suggestion says it is one');
      await h.dispose();
    });

    testWidgets('relationship and who switches re-apply defaults; the '
        'operator can still override every control', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.tapKey('first-run-who-someone');
      // Partner defaults the minor flag off.
      await tester.tap(
          find.byKey(const ValueKey('first-run-relationship-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partner').last);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byType(CheckboxListTile).first)
              .value,
          isFalse);

      // Back to Me: today's defaults (adult, standard).
      await h.tapKey('first-run-who-me');
      expect(find.byKey(const ValueKey('first-run-relationship-dropdown')),
          findsNothing);
      expect(find.text('Standard'), findsOneWidget);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byType(CheckboxListTile).first)
              .value,
          isFalse);

      // Back to Someone: daughter + minor + Teen again.
      await h.tapKey('first-run-who-someone');
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byType(CheckboxListTile).first)
              .value,
          isTrue);
      expect(find.text('Teen'), findsOneWidget);

      // Every control stays changeable: uncheck minor, switch mode.
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byType(CheckboxListTile).first)
              .value,
          isFalse,
          reason: 'suggested, never forced (#131)');
      await h.dispose();
    });

    testWidgets('"Both" opens on the operator\'s own card — no relationship '
        'dropdown, full cycle questions — then loops for the family',
        (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.tapKey('first-run-who-both');
      expect(find.byKey(const ValueKey('first-run-relationship-dropdown')),
          findsNothing,
          reason: 'the Both flow starts with the operator herself');
      await h.enterName('Nova');
      await h.tapKey('first-run-continue');
      expect(find.byKey(const ValueKey('cycle-typical-cycle')), findsOneWidget,
          reason: 'the operator\'s card keeps the full five questions');

      await h.tapKey('cycle-create');
      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.relationship, ProfileRelationship.self);
      expect(find.byKey(const ValueKey('first-run-wrap-up')), findsOneWidget,
          reason: 'the household loop continues after her own profile');
      expect(h.profiles.firstRunFlowActive, isTrue);
      await h.dispose();
    });
  });

  group('someone-I-care-for creation and wrap-up loop (issue #804)', () {
    testWidgets('a cared-for card creates a relationship/minor/teen profile '
        'via the shortened cycle step, then shows the wrap-up',
        (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');

      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.displayName, 'Riley');
      expect(profiles.single.relationship, ProfileRelationship.daughter);
      expect(profiles.single.isMinor, isTrue);
      expect(profiles.single.mode, ProfileMode.teen);
      expect(find.byKey(const ValueKey('first-run-wrap-up')), findsOneWidget);
      expect(h.profiles.firstRunFlowActive, isTrue);
      await h.dispose();
    });

    testWidgets('the shortened cycle step carries only the optional '
        'last-period question', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.tapKey('first-run-who-someone');
      await h.enterName('Riley');
      await h.tapKey('first-run-continue');

      expect(find.byKey(const ValueKey('cycle-last-period-choose')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-typical-cycle')), findsNothing,
          reason: 'a parent often does not know the typical lengths; '
              '#218\'s seeding tolerates blanks');
      expect(find.byKey(const ValueKey('cycle-create')), findsOneWidget,
          reason: 'the Create button *is* the skip');
      await h.dispose();
    });

    testWidgets('"Add another person" resets the card; the flow can add '
        'a second family member', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-add-another');

      expect(find.byKey(const ValueKey('first-run-wrap-up')), findsNothing);
      expect(find.byKey(const ValueKey('first-run-who-me')), findsNothing,
          reason: 'add-loop cards are for someone else; no who-choice');
      expect(
          find.byKey(const ValueKey('first-run-relationship-dropdown')),
          findsOneWidget,
          reason: 'the fresh card is a cared-for card');
      expect(find.byKey(const ValueKey('first-run-age-ack-checkbox')),
          findsNothing,
          reason: 'the minimum-age acknowledgement already persisted');

      await h.enterName('Aster');
      await h.tapKey('first-run-continue');
      await h.tapKey('cycle-create');

      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.map((p) => p.displayName),
          ['Riley', 'Aster']);
      expect(find.byKey(const ValueKey('first-run-wrap-up')), findsOneWidget);
      await h.dispose();
    });
  });

  group('invite step (issue #804 + #966 presets)', () {
    testWidgets('without a session the step says why an account is needed, '
        'offers sign-in, and "Skip for now" always ends the flow',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final h = Harness(tester,
          sharing: _FakeSharing(),
          auth: AuthController(authService: auth));
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-wrap-up-continue');

      expect(find.byKey(const ValueKey('first-run-invite-step')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('first-run-invite-why-account')),
          findsOneWidget,
          reason: 'AC3: the step says why an account is required here');
      expect(find.byKey(const ValueKey('first-run-invite-sign-in')),
          findsOneWidget);
      expect(find.text('Invite a guardian'), findsNothing,
          reason: 'the rows wait behind the sign-in');

      // The sign-in button opens the embedded sign-in screen, and "Not
      // now" returns to the step.
      await h.tapKey('first-run-invite-sign-in');
      expect(find.byType(SignInScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('first-run-not-now')),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('first-run-not-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first-run-invite-step')),
          findsOneWidget);

      await h.tapKey('first-run-invite-skip');
      expect(h.profiles.firstRunFlowActive, isFalse);
      expect(h.profiles.pickerVisible, isFalse,
          reason: 'a single created profile lands on its Today (#865)');
      await h.dispose();
    });

    testWidgets('signed in, each created profile offers the co-parent '
        'invite, and minors additionally offer the subject preset',
        (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      addTearDown(auth.dispose);
      final sharing = _FakeSharing();
      final h = Harness(tester,
          sharing: sharing, auth: AuthController(authService: auth));
      await h.pumpToNameForm();

      // Self profile first (her own), then a daughter.
      await h.tapKey('first-run-who-both');
      await h.enterName('Nova');
      await h.tapKey('first-run-continue');
      await h.tapKey('cycle-create');
      await h.tapKey('first-run-add-another');
      await h.enterName('Riley');
      await h.tapKey('first-run-continue');
      await h.tapKey('cycle-create');
      await h.tapKey('first-run-wrap-up-continue');

      expect(find.byKey(const ValueKey('first-run-invite-step')),
          findsOneWidget);
      expect(find.text('Invite a guardian'), findsNWidgets(2));
      expect(find.text('Invite Riley to log her own profile'), findsOneWidget,
          reason: '#966\'s subject preset is offered for the minor\'s own '
              'profile');
      expect(find.text('Invite Nova to log her own profile'), findsNothing,
          reason: 'the operator\'s own profile is not a subject invite');

      // The co-parent invite rides the existing dialog and asks the
      // service for the co_parent role, no subject marker.
      await tester.tap(find.text('Invite a guardian').last);
      await tester.pumpAndSettle();
      expect(find.byType(InviteGuardianDialog), findsOneWidget);
      await tester.ensureVisible(find.text('Create Link'));
      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();
      expect(sharing.lastCreatedRole, 'co_parent');
      expect(sharing.lastCreatedSubject, isFalse);
      expect(sharing.lastCreatedProfileId,
          (await DriftProfilesRepository(h.db.storage).list())
              .singleWhere((p) => p.displayName == 'Riley')
              .id);

      await h.tapKey('invite-done');
      await h.tapKey('first-run-invite-done');
      expect(h.profiles.firstRunFlowActive, isFalse);
      await h.dispose();
    });

    testWidgets('the subject offer creates a caregiver + subject '
        'invitation through the #966 machinery', (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      addTearDown(auth.dispose);
      final sharing = _FakeSharing();
      final h = Harness(tester,
          sharing: sharing, auth: AuthController(authService: auth));
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-wrap-up-continue');

      await tester.tap(find.text('Invite Riley to log her own profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Link'));
      await tester.tap(find.text('Create Link'));
      await tester.pumpAndSettle();
      expect(sharing.lastCreatedRole, 'caregiver',
          reason: 'the subject preset grants the caregiver role');
      expect(sharing.lastCreatedSubject, isTrue,
          reason: 'and stamps the subject marker');
      await h.dispose();
    });

    testWidgets('without a sharing service the wrap-up Continue ends the '
        'flow directly — ending it *is* the skip', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-wrap-up-continue');

      expect(find.byKey(const ValueKey('first-run-invite-step')),
          findsNothing);
      expect(h.profiles.firstRunFlowActive, isFalse);
      expect(h.profiles.pickerVisible, isFalse);
      await h.dispose();
    });

    testWidgets('several created profiles land on the picker when the flow '
        'ends (the household surface; a single one lands on Today)',
        (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-add-another');
      await h.enterName('Aster');
      await h.tapKey('first-run-continue');
      await h.tapKey('cycle-create');
      await h.tapKey('first-run-wrap-up-continue');

      expect(h.profiles.activeProfiles.length, 2);
      expect(h.profiles.pickerVisible, isTrue,
          reason: 'issue #804 step 4: more than one profile lands on the '
              'household view (the picker, until #803\'s dedicated view '
              'exists)');
      await h.dispose();
    });
  });

  group('onboarding layout and copy (persona audit #994-#996)', () {
    testWidgets('issue #994: the who-chips clear the Name field at a narrow '
        'width and large text scale', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm(
        textScale: 2.0,
        physicalSize: const Size(320, 640),
      );

      final chips = find.byKey(const ValueKey('first-run-who-chips'));
      final name = find.byKey(const ValueKey('first-run-name-field'));
      expect(chips, findsOneWidget);
      expect(name, findsOneWidget);
      expect(
        tester.getBottomLeft(chips).dy,
        lessThan(tester.getTopLeft(name).dy),
        reason: 'issue #994: the compact, shrink-wrapped chips removed the '
            'Material minimum-height slack, so the Name field\'s floating '
            'label drew across their bottom edge — the chips must sit '
            'strictly above the field',
      );
      await h.dispose();
    });

    testWidgets('issue #995: the wrap-up question renders exactly once — in '
        'the app bar, never repeated as a body heading', (tester) async {
      final h = Harness(tester);
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');

      expect(find.text('Add another person?'), findsOneWidget,
          reason: 'issue #995: the title was rendered twice (app bar and '
              'body heading), so the user read it before the one sentence '
              'of body copy');
      await h.dispose();
    });

    testWidgets('issue #996: the invite step leads with the guardian outcome '
        'and names the sign-in as the way to send an invite', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final h = Harness(
        tester,
        sharing: _FakeSharing(),
        auth: AuthController(authService: auth),
      );
      await h.pumpToNameForm();

      await h.createCaredForProfile('Riley');
      await h.tapKey('first-run-wrap-up-continue');

      expect(find.text('Add another guardian?'), findsOneWidget);
      expect(find.text('Sign in to invite'), findsOneWidget,
          reason: 'issue #996: the primary button names the outcome the '
              'sign-in is for');
      expect(
        find.text(
          'A co-parent or caregiver can follow and log this profile from '
          'their own phone.',
        ),
        findsOneWidget,
        reason: 'issue #996: the body states the benefit, not the account '
            'plumbing',
      );
      await h.dispose();
    });
  });
}
