import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restore_error_screen.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/settings/privacy_policy_screen.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import 'account_test.dart';

class _StubSharingService implements SharingService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RestoreErrorScreen escape actions (Issue #250)', () {
    testWidgets('renders Retry, Continue without syncing, and Sign out buttons',
        (tester) async {
      var retried = false;
      var continued = false;
      var signedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light(),
          home: RestoreErrorScreen(
            onRetry: () => retried = true,
            onContinueWithoutSyncing: () => continued = true,
            onSignOut: () => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('restore-error')), findsOneWidget);
      expect(find.text('Unable to restore data'), findsOneWidget);

      final retryBtn = find.byKey(const ValueKey('restore-retry-button'));
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      expect(retried, isTrue);

      final continueBtn =
          find.byKey(const ValueKey('restore-continue-button'));
      expect(continueBtn, findsOneWidget);
      await tester.tap(continueBtn);
      expect(continued, isTrue);

      final signOutBtn =
          find.byKey(const ValueKey('restore-sign-out-button'));
      expect(signOutBtn, findsOneWidget);
      await tester.tap(signOutBtn);
      expect(signedOut, isTrue);
    });

    testWidgets('omits Continue button when onContinueWithoutSyncing is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RestoreErrorScreen(
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('restore-continue-button')), findsNothing);
    });

    testWidgets('fallback signs out through AuthController when onSignOut is null',
        (tester) async {
      final fakeAuth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(
          id: 'user-1',
          email: 'test@example.com',
          providers: ['email'],
        ),
      );
      final authController = AuthController(authService: fakeAuth);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthController>.value(
          value: authController,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RestoreErrorScreen(
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final signOutBtn =
          find.byKey(const ValueKey('restore-sign-out-button'));
      expect(signOutBtn, findsOneWidget);

      await tester.tap(signOutBtn);
      await tester.pumpAndSettle();

      expect(fakeAuth.signOutCalls, contains(AuthSignOutScope.local));
    });

    testWidgets('scrolls safely under 2.5x text scale without overflow',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RestoreErrorScreen(
            onRetry: () {},
            onContinueWithoutSyncing: () {},
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('restore-error')), findsOneWidget);
    });

    testWidgets('ProfileHomeGate: tapping Continue without syncing bypasses restore error to FirstRunScreen',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-sign-in'));
      await pumpFew(tester);

      h.engine.emitPhase(
        SyncPhase.error,
        boundUserId: 'user-a@b.c',
        lastError: SyncErrorKind.network,
      );
      await h.settle();

      expect(key('restore-error'), findsOneWidget);
      expect(find.text('Create a profile'), findsNothing);

      // Tap "Continue without syncing"
      await tester.tap(key('restore-continue-button'));
      await h.settle();

      // Should now show FirstRunScreen ("Create a profile")
      expect(key('restore-error'), findsNothing);
      expect(find.text('Create a profile'), findsOneWidget);

      await h.dispose();
    });

    testWidgets('ProfileHomeGate: tapping Sign out clears session and returns to unauthenticated first run',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-sign-in'));
      await pumpFew(tester);

      h.engine.emitPhase(
        SyncPhase.error,
        boundUserId: 'user-a@b.c',
        lastError: SyncErrorKind.network,
      );
      await h.settle();

      expect(key('restore-error'), findsOneWidget);

      // Tap "Sign out"
      await tester.tap(key('restore-sign-out-button'));
      await h.settle();

      // Sign out was called on auth service
      expect(h.auth.signOutCalls, contains(AuthSignOutScope.local));

      await h.dispose();
    });
  });

  group('Modal Bottom Sheets under 2.5x text scale (Issue #250)', () {
    testWidgets('showProfileEditDialog renders in modal sheet without overflow at 2.5x scale',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());

      final profile = Profile(
        id: 'p1',
        displayName: 'Alex',
        isMinor: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showProfileEditDialog(
                    context,
                    existing: profile,
                  ),
                  child: const Text('Edit Profile'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('InviteGuardianDialog renders in modal sheet without overflow at 2.5x scale',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheetContext) => InviteGuardianDialog(
                      profileId: 'p1',
                      profileName: 'Alex',
                      sharingService: _StubSharingService(),
                    ),
                  ),
                  child: const Text('Invite Guardian'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite Guardian'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Invite guardian to Alex'), findsOneWidget);
      expect(find.text('Create Link'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('PrivacyPolicyScreen (Issue #250)', () {
    testWidgets('renders full-screen scaffold and pops on close',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routes: {
            kRoutePrivacyPolicyScreen: (_) => const PrivacyPolicyScreen(),
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => pushNamedScreen<void>(context, kRoutePrivacyPolicyScreen),
                  child: const Text('Open Privacy'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Privacy'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.text('lunarlog Privacy Policy'), findsOneWidget);
      expect(find.textContaining('Sync & Family Sharing'), findsOneWidget);

      // Close button
      final closeBtn = find.text('Close');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsNothing);
    });
  });
}
