/// Widget tests for issue #165's form-accessibility pass: autofill hints,
/// `textInputAction` per position with `onSubmitted` focus advancement,
/// password reveal toggles, and the recovery confirm-password field.
///
/// Every assertion here is widget-level (the `TextField`/`TextFormField`
/// configurations and the focus nodes they drive); the on-device halves —
/// iOS Keychain / Android Autofill actually offering to save and fill —
/// are manual checklist items (#22/#29) and cannot be asserted under
/// `flutter test`.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/password_recovery_screen.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart';
import 'package:lunarlog/ui/feedback/support_history_screen.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';
import 'package:lunarlog/ui/sharing/invite_guardian_dialog.dart';
import 'package:lunarlog/ui/sharing/prediction_connections_screen.dart';
import 'package:lunarlog/ui/sharing/share_predictions_dialog.dart';
import 'package:lunarlog/ui/sharing/transfer_ownership_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_attachment_source.dart';
import '../support/fake_auth_service.dart';
import '../support/fake_feedback_service.dart';
import '../support/fake_settings_store.dart';
import '../support/pump_helpers.dart';
import 'claim_profile_test.dart' as claim_test;
import 'first_run_test.dart' show Harness;
import 'sharing_flow_test.dart' show FakeSharingService;
import 'transfer_ownership_test.dart' as transfer_test;

TextField textFieldOf(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key));

/// The [TextField] a `TextFormField` builds internally. `TextFormField`
/// only forwards `focusNode`/`textInputAction`/`onFieldSubmitted`/hints
/// through its constructor — the built [TextField] is where they live as
/// readable fields (with the submit callback spelled `onSubmitted`).
TextField innerTextFieldOf(WidgetTester tester, Finder formField) =>
    tester.widget<TextField>(
      find.descendant(of: formField, matching: find.byType(TextField)),
    );

TextField formFieldOf(WidgetTester tester, Key key) =>
    innerTextFieldOf(tester, find.byKey(key));

/// A no-platform-channel diagnostics collector: the feedback screen's
/// tree-provided seam must exist, but these tests never look at its output.
class _NullDiagnosticsCollector implements DeviceDiagnosticsCollector {
  @override
  Future<DeviceDiagnostics> collect() async => const DeviceDiagnostics(
        os: 'test',
        osVersion: '0',
        model: 'test',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en-US',
        breadcrumbs: <String>[],
      );
}

/// Minimal [PredictionConnectionService] fake for the two #165 assertions
/// that drive a create and an accept; every other member is out of scope.
class _FakePredictionService implements PredictionConnectionService {
  int createCalls = 0;
  int acceptCalls = 0;
  String? lastRecipientLabel;

  @override
  Future<AcceptedPredictionConnection> acceptConnection(
          {required String rawToken}) async {
    acceptCalls++;
    return const AcceptedPredictionConnection(
      connectionId: 'conn-1',
      profileId: 'p2',
      profileName: 'Avery',
    );
  }

  @override
  Future<GeneratedPredictionInvite> createConnection({
    required String profileId,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) async {
    createCalls++;
    lastRecipientLabel = recipientLabel;
    return GeneratedPredictionInvite(
      connectionId: 'conn-new',
      profileId: profileId,
      rawToken: 'raw-token',
      tokenHash: 'hash-token',
      inviteUri: Uri.parse('lunarlog://invite?code=raw-token&kind=prediction'),
      expiresAt: DateTime.utc(2026, 9, 20),
    );
  }

  @override
  Future<ActivePredictionConnection?> getActiveConnection(
          {required String profileId}) async =>
      throw UnimplementedError();

  @override
  Future<List<IncomingPredictionConnection>> listIncomingConnections() async =>
      const [];

  @override
  Future<void> leaveConnection({required String connectionId}) async =>
      throw UnimplementedError();

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async =>
      throw UnimplementedError();

  @override
  Future<PredictionProjection?> fetchProjection({required String profileId}) =>
      throw UnimplementedError();

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> retractProjection({required String profileId}) =>
      throw UnimplementedError();

  @override
  Future<void> revokeConnection({required String connectionId}) async =>
      throw UnimplementedError();
}

FeedbackTicket _ticket() => FeedbackTicket(
      id: 't1',
      category: FeedbackCategory.bug,
      message: 'It crashed',
      replyEmail: 'a@example.com',
      status: FeedbackTicketStatus.newTicket,
      attachmentPaths: const [],
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  group('sign-in screen (#165)', () {
    Future<(FakeAuthService, AuthController)> pumpSignIn(
      WidgetTester tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      final settings = FakeSettingsStore();
      addTearDown(settings.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<SettingsStore>.value(value: settings),
            ],
            child: const SignInScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (auth, controller);
    }

    testWidgets(
      'credential pair sits in one AutofillGroup with honest hints and '
      'per-position input actions',
      (tester) async {
        await pumpSignIn(tester);
        final group = find.byType(AutofillGroup);
        expect(group, findsOneWidget);
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const ValueKey('auth-email')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const ValueKey('auth-password')),
          ),
          findsOneWidget,
        );

        final email = textFieldOf(tester, const ValueKey('auth-email'));
        expect(email.autofillHints, const [AutofillHints.email]);
        expect(email.textInputAction, TextInputAction.next);

        final password = textFieldOf(tester, const ValueKey('auth-password'));
        expect(password.autofillHints, const [AutofillHints.password]);
        expect(password.textInputAction, TextInputAction.done);
      },
    );

    testWidgets('create mode swaps the password hint to newPassword',
        (tester) async {
      await pumpSignIn(tester);
      await tester.tap(find.byKey(const ValueKey('auth-mode-toggle')));
      await tester.pumpAndSettle();
      expect(
        textFieldOf(tester, const ValueKey('auth-password')).autofillHints,
        const [AutofillHints.newPassword],
        reason: 'password managers offer generation on the create path',
      );
    });

    testWidgets(
      '"next" on the email field advances focus to the password field, and '
      'tab order runs email → password with nothing decorative between',
      (tester) async {
        await pumpSignIn(tester);
        final email = textFieldOf(tester, const ValueKey('auth-email'));
        final password = textFieldOf(tester, const ValueKey('auth-password'));

        email.focusNode!.requestFocus();
        await tester.pump();
        email.onSubmitted!('a@example.com');
        await tester.pump();
        expect(password.focusNode!.hasFocus, isTrue);

        email.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(password.focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets(
      'the reveal toggle flips only the password field\'s obscureText',
      (tester) async {
        await pumpSignIn(tester);
        expect(
          textFieldOf(tester, const ValueKey('auth-password')).obscureText,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('auth-password-reveal')));
        await tester.pump();
        expect(
          textFieldOf(tester, const ValueKey('auth-password')).obscureText,
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('auth-password-reveal')));
        await tester.pump();
        expect(
          textFieldOf(tester, const ValueKey('auth-password')).obscureText,
          isTrue,
        );
      },
    );

    testWidgets('"done" on the password field submits the sign-in',
        (tester) async {
      final (auth, _) = await pumpSignIn(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'hunter2hunter2',
      );
      textFieldOf(tester, const ValueKey('auth-password'))
          .onSubmitted!('hunter2hunter2');
      await tester.pumpAndSettle();
      expect(auth.signInCalls, hasLength(1));
      expect(auth.signInCalls.single.email, 'a@example.com');
    });

    testWidgets(
      'the emailed-code field carries oneTimeCode, "done", and verifies only '
      'a plausible code on submit',
      (tester) async {
        final (auth, _) = await pumpSignIn(tester);
        await tester.enterText(
          find.byKey(const ValueKey('auth-email')),
          'a@example.com',
        );
        await tester.tap(find.byKey(const ValueKey('auth-magic-link')));
        await tester.pumpAndSettle();

        final code = textFieldOf(tester, const ValueKey('auth-code'));
        expect(code.autofillHints, const [AutofillHints.oneTimeCode]);
        expect(code.textInputAction, TextInputAction.done);

        code.onSubmitted!('12');
        await tester.pumpAndSettle();
        expect(auth.codeCalls, isEmpty, reason: 'not a plausible code');

        await tester.enterText(
          find.byKey(const ValueKey('auth-code')),
          '123456',
        );
        textFieldOf(tester, const ValueKey('auth-code')).onSubmitted!('123456');
        await tester.pumpAndSettle();
        expect(auth.codeCalls, hasLength(1));
        expect(auth.codeCalls.single.code, '123456');
      },
    );
  });

  group('password recovery screen (#165)', () {
    Future<(FakeAuthService, AuthController)> pumpRecovery(
      WidgetTester tester,
    ) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      // Arm the recovery latch: AuthController.consumeRecovery() is a
      // no-op without one, and the match-saves test asserts consumption.
      auth.latchRecovery();
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider<AuthController>.value(
            value: controller,
            child: const PasswordRecoveryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (auth, controller);
    }

    testWidgets(
      'new-password + confirm pair: one AutofillGroup, newPassword hint and '
      '"next" on new-password, "done" on an unhinted confirm field',
      (tester) async {
        await pumpRecovery(tester);
        final group = find.byType(AutofillGroup);
        expect(group, findsOneWidget);
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const ValueKey('recovery-new-password')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const ValueKey('recovery-confirm-password')),
          ),
          findsOneWidget,
        );

        final password = textFieldOf(
          tester,
          const ValueKey('recovery-new-password'),
        );
        expect(password.autofillHints, const [AutofillHints.newPassword]);
        expect(password.textInputAction, TextInputAction.next);

        final confirm = textFieldOf(
          tester,
          const ValueKey('recovery-confirm-password'),
        );
        // Unhinted: TextField normalizes an absent hint list to empty, so
        // assert emptiness (never a password hint on a confirm field —
        // password managers would double-fill it).
        expect(confirm.autofillHints ?? const <String>[], isEmpty);
        expect(confirm.textInputAction, TextInputAction.done);
        expect(confirm.obscureText, isTrue);
      },
    );

    testWidgets(
      '"next" advances to the confirm field, and each reveal toggle flips '
      'its own field only',
      (tester) async {
        await pumpRecovery(tester);
        final password = textFieldOf(
          tester,
          const ValueKey('recovery-new-password'),
        );
        final confirm = textFieldOf(
          tester,
          const ValueKey('recovery-confirm-password'),
        );

        password.onSubmitted!('a brand new pass');
        await tester.pump();
        expect(confirm.focusNode!.hasFocus, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('recovery-new-password-reveal')),
        );
        await tester.pump();
        expect(
          textFieldOf(
            tester,
            const ValueKey('recovery-new-password'),
          ).obscureText,
          isFalse,
        );
        expect(
          textFieldOf(
            tester,
            const ValueKey('recovery-confirm-password'),
          ).obscureText,
          isTrue,
          reason: 'the new-password toggle never reveals the confirm field',
        );

        await tester.tap(
          find.byKey(const ValueKey('recovery-confirm-password-reveal')),
        );
        await tester.pump();
        expect(
          textFieldOf(
            tester,
            const ValueKey('recovery-confirm-password'),
          ).obscureText,
          isFalse,
        );
        await tester.tap(
          find.byKey(const ValueKey('recovery-new-password-reveal')),
        );
        await tester.pump();
        expect(
          textFieldOf(
            tester,
            const ValueKey('recovery-new-password'),
          ).obscureText,
          isTrue,
        );
        expect(
          textFieldOf(
            tester,
            const ValueKey('recovery-confirm-password'),
          ).obscureText,
          isFalse,
          reason: 'the confirm toggle never reveals the new-password field',
        );
      },
    );

    testWidgets(
      'a confirm mismatch blocks the save with the form\'s inline error; a '
      'match saves via "done" and consumes the recovery latch',
      (tester) async {
        final (auth, _) = await pumpRecovery(tester);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-new-password')),
          'a brand new pass',
        );
        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirm-password')),
          'something else',
        );
        await tester.tap(find.byKey(const ValueKey('recovery-save')));
        await tester.pumpAndSettle();

        expect(find.text('Passwords do not match.'), findsOneWidget);
        expect(auth.updatePasswordCalls, isEmpty);
        expect(find.byKey(const ValueKey('recovery-save')), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirm-password')),
          'a brand new pass',
        );
        textFieldOf(tester, const ValueKey('recovery-confirm-password'))
            .onSubmitted!('a brand new pass');
        await tester.pumpAndSettle();
        // The controller's updatePassword round-trips microtasks past what
        // a plain pumpAndSettle drains (the account_test.dart recovery
        // tests use the same helper).
        await drainIsolateTraffic(tester);

        expect(auth.updatePasswordCalls, ['a brand new pass']);
        expect(auth.recoveryConsumed, 1);
      },
    );
  });

  group('profile edit dialog (#165)', () {
    testWidgets(
      'name field: name hint and "next" advancing to birth year; birth year: '
      '"done" submits the dialog',
      (tester) async {
        ProfileEditResult? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await showProfileEditDialog(context);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final name = innerTextFieldOf(
          tester,
          find.widgetWithText(TextFormField, 'Name'),
        );
        expect(name.autofillHints, const [AutofillHints.name]);
        expect(name.textInputAction, TextInputAction.next);

        name.focusNode!.requestFocus();
        await tester.pump();
        name.onSubmitted!('Luna');
        await tester.pump();

        final birthYear = innerTextFieldOf(
          tester,
          find.widgetWithText(TextFormField, 'Birth year (optional)'),
        );
        expect(birthYear.focusNode!.hasFocus, isTrue);
        expect(birthYear.textInputAction, TextInputAction.done);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Luna',
        );
        birthYear.onSubmitted!('');
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.displayName, 'Luna');
      },
    );
  });

  group('first-run forms (#165)', () {
    testWidgets(
      'name form: name hint and "done" continuing to the cycle questions; '
      'cycle fields chain focus and "done" creates the profile',
      (tester) async {
        final harness = Harness(tester);
        // Skip the introduction cards and the age acknowledgment exactly
        // like first_run_test.dart's pumpedToCycle helper — these tests
        // target the fields, not the cards.
        await harness.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
        await harness.settings
            .set(SettingsKeys.minimumAgeAcknowledged, 'true');
        await harness.pump();

        final name = innerTextFieldOf(tester, find.byType(TextFormField));
        expect(name.autofillHints, const [AutofillHints.name]);
        expect(name.textInputAction, TextInputAction.done);

        await tester.enterText(find.byType(TextFormField), 'Luna');
        name.onSubmitted!('Luna');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cycle-typical-cycle')),
          findsOneWidget,
          reason: '"done" on the name form is the Continue action',
        );

        final cycle = formFieldOf(tester, const ValueKey('cycle-typical-cycle'));
        final period = formFieldOf(
          tester,
          const ValueKey('cycle-typical-period'),
        );
        expect(cycle.textInputAction, TextInputAction.next);
        expect(period.textInputAction, TextInputAction.done);

        cycle.focusNode!.requestFocus();
        await tester.pump();
        cycle.onSubmitted!('28');
        await tester.pump();
        expect(period.focusNode!.hasFocus, isTrue);

        period.onSubmitted!('5');
        await tester.pumpAndSettle();
        expect(
          harness.profiles.activeProfiles,
          isNotEmpty,
          reason: '"done" on the last cycle field is the Create profile action',
        );

        await harness.dispose();
      },
    );
  });

  group('day sheet (#165)', () {
    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    testWidgets(
      'BBT "next" advances to weight, weight "next" advances to the note '
      'field; the multiline note field is "newline" and the search field is '
      '"search"',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final today = LocalDate(2026, 9, 10);
        final db = LunarLogDatabase(NativeDatabase.memory());
        final profile = await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        final entries = DriftDayEntriesRepository(db.storage);
        final observations = DriftObservationsRepository(db.storage);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<ObservationsRepository>.value(value: observations),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => DaySheet(
                          repository: entries,
                          profileId: profile.id,
                          date: today,
                          today: today,
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          textFieldOf(
            tester,
            const ValueKey('category-picker-search'),
          ).textInputAction,
          TextInputAction.search,
        );

        final bbt = formFieldOf(tester, const ValueKey('bbt-field'));
        expect(bbt.textInputAction, TextInputAction.next);
        bbt.onSubmitted!('36.5');
        await tester.pump();
        expect(
          formFieldOf(tester, const ValueKey('weight-field'))
              .focusNode!
              .hasFocus,
          isTrue,
        );

        final weight = formFieldOf(tester, const ValueKey('weight-field'));
        expect(weight.textInputAction, TextInputAction.next);
        weight.onSubmitted!('61');
        await tester.pump();
        expect(
          formFieldOf(tester, const ValueKey('note-field')).focusNode!.hasFocus,
          isTrue,
        );

        final note = formFieldOf(tester, const ValueKey('note-field'));
        expect(
          note.textInputAction,
          TextInputAction.newline,
          reason: 'a multiline note field must keep enter as a line break',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      },
    );
  });

  group('feedback (#165)', () {
    testWidgets(
      'reply email: email hint and "done" submitting; the multiline message '
      'field stays "newline"',
      (tester) async {
        final service = FakeFeedbackService();
        final settings = FakeSettingsStore();
        addTearDown(settings.close);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MultiProvider(
              providers: [
                // The screen reads the interface types, so register the
                // fakes under those (a Provider<FakeFeedbackService> is
                // invisible to context.read<FeedbackService>()).
                Provider<FeedbackService>.value(value: service),
                Provider<DeviceDiagnosticsCollector>.value(
                  value: _NullDiagnosticsCollector(),
                ),
                Provider<SettingsStore>.value(value: settings),
                Provider<AttachmentSource>.value(
                  value: FakeAttachmentSource(),
                ),
              ],
              child: const FeedbackScreen(
                diagnosticsCollector: null,
                attachmentSource: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          textFieldOf(tester, const ValueKey('feedback-message'))
              .textInputAction,
          TextInputAction.newline,
        );

        await tester.enterText(
          find.byKey(const ValueKey('feedback-message')),
          'It crashed',
        );
        await tester.enterText(
          find.byKey(const ValueKey('feedback-reply-email')),
          'a@example.com',
        );
        final email = textFieldOf(
          tester,
          const ValueKey('feedback-reply-email'),
        );
        expect(email.autofillHints, const [AutofillHints.email]);
        expect(email.textInputAction, TextInputAction.done);
        email.onSubmitted!('a@example.com');
        await tester.pumpAndSettle();

        expect(service.submitCalls, 1);
        expect(service.lastReplyEmail, 'a@example.com');
      },
    );
  });

  group('support history reply (#165)', () {
    testWidgets(
      'the reply field is "send" and its onSubmitted sends the reply',
      (tester) async {
        final service = FakeFeedbackService()
          ..ticketsToReturn = [_ticket()];
        final settings = FakeSettingsStore();
        addTearDown(settings.close);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MultiProvider(
              providers: [
                Provider<FeedbackService>.value(value: service),
                Provider<SettingsStore>.value(value: settings),
              ],
              child: const SupportHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(ListTile));
        await tester.pumpAndSettle();

        final field = textFieldOf(
          tester,
          const ValueKey('support-history-reply-field-t1'),
        );
        expect(field.textInputAction, TextInputAction.send);
        await tester.enterText(
          find.byKey(const ValueKey('support-history-reply-field-t1')),
          'thanks',
        );
        field.onSubmitted!('thanks');
        await tester.pumpAndSettle();

        expect(service.addReplyCalls, 1);
        expect(service.lastReplyMessage, 'thanks');
      },
    );
  });

  group('sharing forms (#165)', () {
    testWidgets(
      'invite dialog: the label field is "done" and submits the invite',
      (tester) async {
        final service = FakeSharingService();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: InviteGuardianDialog(
                profileId: 'p1',
                profileName: 'Luna',
                sharingService: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textInputAction, TextInputAction.done);
        field.onSubmitted!('Dad');
        await tester.pumpAndSettle();

        expect(service.lastCreatedRole, isNotNull);
        expect(find.text('Invitation Created'), findsOneWidget);
      },
    );

    testWidgets(
      'accept-invite sheet: the display-name field carries the name hint and '
      '"done" accepts',
      (tester) async {
        final service = FakeSharingService();
        AcceptedInviteResult? accepted;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AcceptInviteSheet(
                rawToken: 'tok',
                sharingService: service,
                onAccepted: (result) => accepted = result,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.autofillHints, const [AutofillHints.name]);
        expect(field.textInputAction, TextInputAction.done);
        field.onSubmitted!('Dad');
        await tester.pumpAndSettle();

        expect(accepted, isNotNull);
        expect(find.byType(AcceptInviteSheet), findsNothing);
      },
    );

    testWidgets(
      'claim sheet: child name "next" advances to the parent label, whose '
      '"done" claims',
      (tester) async {
        final service = claim_test.FakeOwnershipTransferService();
        ClaimedProfileResult? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ClaimProfileSheet(
                rawToken: 'tok',
                service: service,
                onClaimed: (r) => result = r,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final child =
            tester.widget<TextField>(find.byType(TextField).at(0));
        expect(child.textInputAction, TextInputAction.next);
        await tester.enterText(find.byType(TextField).at(0), 'Luna');
        child.onSubmitted!('Luna');
        await tester.pump();

        final parent =
            tester.widget<TextField>(find.byType(TextField).at(1));
        expect(parent.focusNode!.hasFocus, isTrue);
        expect(parent.textInputAction, TextInputAction.done);
        await tester.enterText(find.byType(TextField).at(1), 'Dad');
        parent.onSubmitted!('Dad');
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(service.claimCalls.single.childDisplayName, 'Luna');
        expect(service.claimCalls.single.parentDisplayName, 'Dad');
      },
    );

    testWidgets(
      'transfer screen: the label field is "done" and arms only once a role '
      'is chosen (the button\'s own guard)',
      (tester) async {
        final service = transfer_test.FakeOwnershipTransferService();
        final profile = Profile(
          id: 'p1',
          displayName: 'Luna',
          isMinor: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TransferOwnershipScreen(profile: profile, service: service),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textInputAction, TextInputAction.done);
        field.onSubmitted!('Sam');
        await tester.pumpAndSettle();
        expect(
          find.text('Transfer ownership?'),
          findsNothing,
          reason: 'no role chosen — the confirm dialog must not open',
        );
        expect(service.lastCreatedProfileId, isNull);

        await tester.tap(find.text(ParentPostTransferRole.coManager.label));
        await tester.pumpAndSettle();
        tester.widget<TextField>(find.byType(TextField)).onSubmitted!('Sam');
        await tester.pumpAndSettle();
        expect(find.text('Transfer ownership?'), findsOneWidget);
      },
    );

    testWidgets(
      'share-predictions dialog: the label field is "done" and creates the '
      'connection',
      (tester) async {
        final service = _FakePredictionService();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SharePredictionsDialog(
                profileId: 'p1',
                profileName: 'Luna',
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textInputAction, TextInputAction.done);
        await tester.enterText(find.byType(TextField), 'Partner');
        field.onSubmitted!('Partner');
        await tester.pumpAndSettle();

        expect(service.createCalls, 1);
        expect(service.lastRecipientLabel, 'Partner');
      },
    );

    testWidgets(
      'prediction code dialog: the field is "done" and submits the trimmed '
      'code like the Connect button',
      (tester) async {
        final service = _FakePredictionService();
        AcceptedPredictionConnection? connected;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PredictionConnectionsScreen(
              service: service,
              onConnected: (result) => connected = result,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('enter-prediction-code')));
        await tester.pumpAndSettle();

        final field = textFieldOf(
          tester,
          const ValueKey('prediction-code-field'),
        );
        expect(field.textInputAction, TextInputAction.done);
        await tester.enterText(
          find.byKey(const ValueKey('prediction-code-field')),
          'the-code',
        );
        textFieldOf(tester, const ValueKey('prediction-code-field'))
            .onSubmitted!('the-code');
        await tester.pumpAndSettle();

        expect(service.acceptCalls, 1);
        expect(connected?.profileId, 'p2');
      },
    );
  });
}
