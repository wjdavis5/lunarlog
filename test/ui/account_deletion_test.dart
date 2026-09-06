/// Widget tests for account deletion and export (Issue #17, Unit U6; R1-R3,
/// R6, R10-R12, KTD3, KTD7; AE1, AE4, AE5). Every collaborator is a fake
/// (KTD6): the device gate, the deletion service, the export collaborator,
/// and the Apple authorization-code fetch never touch a platform channel or
/// the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart' show DeviceResetCallback, GateController;
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../support/fake_auth_service.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

Finder key(String value) => find.byKey(ValueKey(value));

/// A few plain pumps for screens with a busy spinner, where `pumpAndSettle`
/// would time out waiting on its indefinite animation (mirrors
/// `test/ui/account_test.dart`'s `pumpFew`).
Future<void> pumpFew(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class FakeProfilesRepository implements ProfilesRepository {
  List<Profile> profiles = const [];

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDayEntriesRepository implements DayEntriesRepository {
  Map<String, List<DayEntry>> entriesByProfile = const {};

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      entriesByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAccountDeletionService implements AccountDeletionService {
  int deleteCalls = 0;
  final List<String?> appleCodesPassed = [];
  Object? nextError;
  Completer<void>? hold;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    deleteCalls++;
    appleCodesPassed.add(appleAuthorizationCode);
    final holdFuture = hold?.future;
    if (holdFuture != null) await holdFuture;
    final error = nextError;
    if (error != null) throw error;
  }
}

class _NoopSettings implements SettingsStore {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Stream<String?> watch(String key) => Stream.value(null);
}

AuthorizationCredentialAppleID _appleCredential(String code) =>
    AuthorizationCredentialAppleID(
      userIdentifier: null,
      givenName: null,
      familyName: null,
      authorizationCode: code,
      email: null,
      identityToken: null,
      state: null,
    );

class DeletionHarness {
  DeletionHarness({
    List<String> providers = const ['email'],
    bool grantReauth = true,
    this.provideGate = true,
    bool provideDeletionService = true,
    FakeAccountDeletionService? deletionService,
    this.exportAccount,
    this.appleAuthorizationCodeRequest,
  })  : auth = FakeAuthService(),
        deletion = deletionService ??
            (provideDeletionService ? FakeAccountDeletionService() : null),
        gate = FakeGate(grantNext: grantReauth) {
    auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1', email: 'a@b.c'));
    auth.providers = providers;
    controller = AuthController(authService: auth);
    // A real Timer factory would leave the inactivity/system-UI timers
    // pending past the end of each test (the same reason
    // test/ui/account_test.dart's pumpSection uses this fake).
    gateController = GateController(
        gate: gate, inactivityTimerFactory: FakeInactivityTimers().factory);
  }

  final FakeAuthService auth;
  late final AuthController controller;
  final FakeGate gate;
  late final GateController gateController;
  final FakeAccountDeletionService? deletion;
  final ExportAccountCollaborator? exportAccount;
  final AppleAuthorizationCodeRequest? appleAuthorizationCodeRequest;
  final bool provideGate;
  int resetCalls = 0;

  /// Toggled by [unmountSection] (#17 P1 fix regression coverage): lets a
  /// test unmount just [AccountSection] - the way navigating away from the
  /// Settings screen would in the real app - while every provider above it
  /// (including the [DeviceResetCallback]) stays alive, mirroring how
  /// [DeviceResetCallback] is actually provided from the app root.
  final ValueNotifier<bool> _sectionVisible = ValueNotifier(true);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: controller),
            if (provideGate)
              ChangeNotifierProvider<GateController>.value(value: gateController),
            Provider<SettingsStore>.value(value: _NoopSettings()),
            Provider<ProfilesRepository>.value(value: FakeProfilesRepository()),
            Provider<DayEntriesRepository>.value(value: FakeDayEntriesRepository()),
            if (deletion != null)
              Provider<AccountDeletionService>.value(value: deletion!),
            Provider<DeviceResetCallback>.value(
              value: () async {
                resetCalls++;
              },
              updateShouldNotify: (_, _) => false,
            ),
          ],
          child: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: _sectionVisible,
              builder: (context, visible, _) => visible
                  ? AccountSection(
                      showExportAndDelete: true,
                      exportAccount: exportAccount,
                      appleAuthorizationCodeRequest: appleAuthorizationCodeRequest,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts [AccountSection] without touching the providers above it.
  Future<void> unmountSection(WidgetTester tester) async {
    _sectionVisible.value = false;
    await tester.pump();
  }

  void dispose() {
    controller.dispose();
    gateController.dispose();
    auth.dispose();
    _sectionVisible.dispose();
  }
}

void main() {
  group('AE1: delete flow, credential granted and confirmed', () {
    testWidgets('calls the service exactly once, then resetDevice exactly '
        'once, in that order', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 1);
      expect(h.resetCalls, 1);
      expect(h.gate.requests, 1, reason: 'the device credential came first');
    });
  });

  group('AE5: a declined credential cancels silently', () {
    testWidgets('no dialog, no service call, no reset, no error copy', (
      tester,
    ) async {
      final h = DeletionHarness(grantReauth: false);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account?'), findsNothing);
      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);
      expect(key('account-delete-error'), findsNothing);
      expect(h.gate.requests, 1);
    });
  });

  group('cancelling the confirmation dialog', () {
    testWidgets('no service call, no reset', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);
    });
  });

  group('Export first', () {
    testWidgets('runs the export, leaves the decision unmade, makes no '
        'service call', (tester) async {
      var exportCalls = 0;
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          exportCalls++;
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-export-first'));
      await tester.pumpAndSettle();

      expect(exportCalls, 1);
      expect(find.text('Delete account?'), findsOneWidget,
          reason: 'the dialog stays open after Export first');
      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);

      // The operator can still decide afterwards.
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();
      expect(h.deletion!.deleteCalls, 1);
    });

    testWidgets('a failed export shows an inline dialog error and does not '
        'close it', (tester) async {
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          throw StateError('disk full');
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-export-first'));
      await tester.pumpAndSettle();

      expect(key('account-delete-export-error'), findsOneWidget);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(h.deletion!.deleteCalls, 0);
    });
  });

  group('Export/Delete race guard (#17 P1 fix)', () {
    testWidgets('Delete and Cancel are disabled while an export is running, '
        'a tap on either does nothing, and a failure that completes '
        'afterward still surfaces (the dialog cannot have unmounted in the '
        'meantime)', (tester) async {
      final exportHold = Completer<void>();
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          await exportHold.future;
          throw StateError('disk full');
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-export-first'));
      await tester.pump(); // export is now in flight, still held open

      expect(
        tester
            .widget<TextButton>(find.ancestor(
              of: find.text('Cancel'),
              matching: find.byType(TextButton),
            ))
            .onPressed,
        isNull,
        reason: 'Cancel is disabled mid-export',
      );
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNull,
        reason: 'Delete is disabled mid-export (the race this guards against)',
      );

      // Tapping the guarded Delete button does nothing while exporting.
      await tester.tap(key('account-delete-confirm'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Delete account?'), findsOneWidget,
          reason: 'the dialog is still open: the tap was a no-op');
      expect(h.deletion!.deleteCalls, 0);

      // The export finishes (with a failure) only now - the dialog could
      // not have unmounted underneath it, so the error still reaches the
      // screen instead of being silently swallowed.
      exportHold.complete();
      await tester.pumpAndSettle();

      expect(key('account-delete-export-error'), findsOneWidget);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(h.deletion!.deleteCalls, 0);

      // The guard lifts once the export has actually finished.
      expect(
        tester.widget<FilledButton>(key('account-delete-confirm')).onPressed,
        isNotNull,
      );
    });
  });

  group('resetDevice reliability regardless of widget lifecycle '
      '(#17 P1 fix)', () {
    testWidgets('a confirmed deletion still wipes the device even if '
        'AccountSection is unmounted before the service call resolves', (
      tester,
    ) async {
      final service = FakeAccountDeletionService()..hold = Completer<void>();
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await pumpFew(tester); // the service call is now in flight, held open

      // Navigate away: AccountSection unmounts, but the DeviceResetCallback
      // provider above it (mirroring the app root in production) does not.
      await h.unmountSection(tester);
      expect(find.byType(AccountSection), findsNothing);

      service.hold!.complete();
      await tester.pump();
      await tester.pump();

      expect(h.resetCalls, 1,
          reason: 'the data wipe must run for a confirmed deletion even '
              'though the widget that started it is already gone');
    });
  });

  group('Apple identity ceremony (KTD3)', () {
    testWidgets('with apple in providers, the code is fetched and forwarded '
        'to the service', (tester) async {
      var appleCalls = 0;
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        appleAuthorizationCodeRequest: () async {
          appleCalls++;
          return _appleCredential('fresh-code-123');
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(appleCalls, 1);
      expect(h.deletion!.deleteCalls, 1);
      expect(h.deletion!.appleCodesPassed.single, 'fresh-code-123');
      expect(h.resetCalls, 1);
    });

    testWidgets('without apple in providers, the service is called with a '
        'null code and no Apple ceremony runs', (tester) async {
      var appleCalls = 0;
      final h = DeletionHarness(
        providers: ['email'],
        appleAuthorizationCodeRequest: () async {
          appleCalls++;
          return _appleCredential('should-not-be-used');
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(appleCalls, 0);
      expect(h.deletion!.deleteCalls, 1);
      expect(h.deletion!.appleCodesPassed.single, isNull);
    });

    testWidgets('a cancelled Apple dialog aborts deletion silently: no '
        'service call, no reset', (tester) async {
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        appleAuthorizationCodeRequest: () async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'cancelled',
          );
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);
      expect(key('account-delete-error'), findsNothing);
    });

    testWidgets('a non-cancellation Apple error surfaces unknown copy, not '
        'silence', (tester) async {
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        appleAuthorizationCodeRequest: () async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'boom',
          );
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);
      expect(key('account-delete-error'), findsOneWidget);
      expect(
        find.descendant(
          of: key('account-delete-error'),
          matching: find.text(
            accountDeletionFailureCopy(const AccountDeletionFailure.unknown()),
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });
  });

  group('each AccountDeletionFailure variant renders its own copy (R12)', () {
    for (final failure in const <AccountDeletionFailure>[
      AccountDeletionFailure.network(),
      AccountDeletionFailure.unauthorized(),
      AccountDeletionFailure.appleCodeRequired(),
      AccountDeletionFailure.appleRevokeFailed(),
      AccountDeletionFailure.timeout(),
      AccountDeletionFailure.deleteUserFailed(),
      AccountDeletionFailure.unknown(),
    ]) {
      testWidgets('$failure', (tester) async {
        final service = FakeAccountDeletionService()..nextError = failure;
        final h = DeletionHarness(deletionService: service);
        addTearDown(h.dispose);
        await h.pump(tester);

        await tester.tap(key('account-delete'));
        await tester.pumpAndSettle();
        await tester.tap(key('account-delete-confirm'));
        await tester.pumpAndSettle();

        expect(h.resetCalls, 0, reason: 'no reset on any failure (R12)');
        expect(key('account-delete-error'), findsOneWidget);
        expect(
          find.descendant(
            of: key('account-delete-error'),
            matching: find.text(accountDeletionFailureCopy(failure)),
            matchRoot: true,
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('appleCodeRequired explains nothing was deleted and the '
        'operator should retry (#17 P1 round 2 fix)', (tester) async {
      const failure = AccountDeletionFailure.appleCodeRequired();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(failure);
      // Unlike appleRevokeFailed, nothing was touched on this path (the
      // Edge Function fails closed before Step 4's destructive RPC even
      // runs) - the copy must say so, not the appleRevokeFailed line's
      // "your account data was deleted, but...".
      expect(copy, isNot(contains('your account data was deleted')));
      expect(copy.toLowerCase(), contains('nothing was deleted'));
      expect(copy.toLowerCase(), contains('try again'));
    });

    testWidgets('appleRevokeFailed explains the data WAS deleted, only Apple '
        'revocation failed, and the action can be retried', (tester) async {
      const failure = AccountDeletionFailure.appleRevokeFailed();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(failure);
      // By this point the server rows are already gone (KTD4) - the copy
      // must say so truthfully, not claim "nothing was removed".
      expect(copy, isNot(contains('Nothing was removed')));
      expect(copy, isNot(contains('not deleted')));
      expect(copy.toLowerCase(), contains('deleted'));
      expect(copy.toLowerCase(), contains('sign-in'));
      expect(copy.toLowerCase(), contains('try again'));
      expect(copy.toLowerCase(), contains('support'));
    });

    testWidgets('deleteUserFailed explains the data WAS deleted and never '
        'tells the operator to sign in again (#17 P1 fix)', (tester) async {
      const failure = AccountDeletionFailure.deleteUserFailed();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(failure);
      // The data really is already gone by the time this code is possible
      // (#17 P1 fix) - the copy must not claim otherwise, and must not send
      // the operator to sign back into an account that may no longer be
      // reachable that way.
      expect(copy, isNot(contains('not deleted')));
      expect(copy.toLowerCase(), isNot(contains('sign in again')));
      expect(copy.toLowerCase(), contains('already been deleted'));
      expect(copy.toLowerCase(), contains('try again'));
    });

    testWidgets('timeout copy does not claim the account was not deleted '
        '(#17 P1 fix)', (tester) async {
      const failure = AccountDeletionFailure.timeout();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(failure);
      expect(copy, isNot(contains('not deleted')));
      expect(copy.toLowerCase(), isNot(contains('sign in again')));
    });
  });

  group('one action at a time', () {
    testWidgets('the delete tile is disabled while the call is in flight; a '
        'second tap does nothing', (tester) async {
      final service = FakeAccountDeletionService()..hold = Completer<void>();
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      // Enough pumps for the dialog's own exit route animation to finish
      // (the service call itself never resolves - `hold` is still open, so
      // pumpAndSettle would hang on the indefinite spinner).
      await pumpFew(tester);

      expect(find.text('Delete account?'), findsNothing,
          reason: 'the confirmation dialog itself has closed');
      expect(
        find.descendant(
          of: key('account-delete'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(key('account-delete')).enabled, isFalse);

      // A second tap while busy does nothing (no dialog re-opens).
      await tester.tap(key('account-delete'));
      await tester.pump();
      expect(find.text('Delete account?'), findsNothing);

      service.hold!.complete();
      await tester.pumpAndSettle();
      expect(service.deleteCalls, 1);
      expect(h.resetCalls, 1);
    });
  });

  group('AE4: export', () {
    testWidgets('tapping export invokes the injected collaborator once', (
      tester,
    ) async {
      var exportCalls = 0;
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          exportCalls++;
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-export'));
      await tester.pumpAndSettle();

      expect(exportCalls, 1);
      expect(key('account-export-error'), findsNothing);
    });

    testWidgets('a failed export surfaces copy, not an exception', (
      tester,
    ) async {
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          throw StateError('disk full');
        },
      );
      addTearDown(h.dispose);
      await h.pump(tester);

      // Must not throw out of the tap handler.
      await tester.tap(key('account-export'));
      await tester.pumpAndSettle();

      expect(key('account-export-error'), findsOneWidget);
      expect(
        tester.widget<Text>(key('account-export-error')).data,
        kAccountExportFailureCopy,
      );
    });
  });

  group('R11: signed out / unconfigured / web absence', () {
    testWidgets('signed out: neither tile renders', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      h.auth.emit(AuthSessionState.signedOut);
      await h.pump(tester);

      expect(key('account-export'), findsNothing);
      expect(key('account-delete'), findsNothing);
    });

    testWidgets('showExportAndDelete: false (simulated web) hides both '
        'tiles', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      final deletion = FakeAccountDeletionService();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<AccountDeletionService>.value(value: deletion),
            ],
            child: const Scaffold(
              body: AccountSection(showExportAndDelete: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(key('account-export'), findsNothing);
      expect(key('account-delete'), findsNothing);
    });
  });
}
