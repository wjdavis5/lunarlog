/// Widget tests for account deletion and export (Issue #17, Unit U6; R1-R3,
/// R6, R10-R12, KTD3, KTD7; AE1, AE4, AE5). Every collaborator is a fake
/// (KTD6): the device gate, the deletion service, the export collaborator,
/// and the Apple authorization-code fetch never touch a platform channel or
/// the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/data/export/account_export_writer.dart';
import 'package:lunarlog/ui/account/device_reset_callback.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../support/fake_auth_service.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

Finder key(String value) => find.byKey(ValueKey(value));

/// The `en` lookups behind [accountDeletionFailureCopy]'s expected copy —
/// the same arb values the widget tree resolves through the delegate
/// (issue #1004, tranche 5).
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

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

class FakeObservationsRepository implements ObservationsRepository {
  Map<String, List<Observation>> observationsByProfile = const {};

  @override
  Future<List<Observation>> listForProfile(String profileId) async =>
      observationsByProfile[profileId] ?? const [];

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
          String dayEntryId) async =>
      const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

class FakeCareContentRepository implements CareContentRepository {
  Map<String, List<CareNote>> careNotesByProfile = const {};
  Map<String, List<VisitPrepItem>> prepItemsByProfile = const {};

  @override
  Future<List<CareNote>> listCareNotes(String profileId) async =>
      careNotesByProfile[profileId] ?? const [];

  @override
  Stream<List<CareNote>> watchCareNotes(String profileId) =>
      Stream.value(careNotesByProfile[profileId] ?? const []);

  @override
  Future<CareNote> saveCareNote({
    String? id,
    required String profileId,
    required String body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteCareNote(String id) async {}

  @override
  Future<List<VisitPrepItem>> listPrepItems(String profileId) async =>
      prepItemsByProfile[profileId] ?? const [];

  @override
  Stream<List<VisitPrepItem>> watchPrepItems(String profileId) =>
      Stream.value(prepItemsByProfile[profileId] ?? const []);

  @override
  Future<List<VisitPrepItem>> listSupplyItems(String profileId) async =>
      const [];

  @override
  Stream<List<VisitPrepItem>> watchSupplyItems(String profileId) =>
      Stream.value(const []);

  @override
  Future<VisitPrepItem> addPrepItem({
    String? id,
    required String profileId,
    required String body,
    VisitPrepItemKind kind = VisitPrepItemKind.visitPrep,
  }) async =>
      throw UnimplementedError();

  @override
  Future<VisitPrepItem?> editPrepItem({
    required String id,
    required String body,
  }) async =>
      null;

  @override
  Future<VisitPrepItem?> setPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
  }) async =>
      null;

  @override
  Future<void> deletePrepItem(String id) async {}

  @override
  Future<int> clearCheckedPrepItems(
    String profileId, {
    VisitPrepItemKind kind = VisitPrepItemKind.visitPrep,
  }) async =>
      0;
}

class FakeAccountDeletionService implements AccountDeletionService {
  int deleteCalls = 0;
  final List<String?> appleCodesPassed = [];
  Object? nextError;
  Completer<void>? hold;

  /// Simulates the server's own Step 3 (Issue #605/LLA-052's server-informed
  /// flow): when true, a call with no Apple code fails closed with
  /// [AccountDeletionFailure.appleCodeRequired] - exactly `delete-account
  /// /index.ts`'s behavior for an Apple-linked account whose deletion-
  /// progress marker (#527/#605) does not already cover the current Apple
  /// identity. A call that supplies a code (or any call at all when this is
  /// false, e.g. a "code-free retry" or a non-Apple account) proceeds
  /// normally to [nextError]/[hold] below.
  bool requireAppleCode = false;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    deleteCalls++;
    appleCodesPassed.add(appleAuthorizationCode);
    if (requireAppleCode && appleAuthorizationCode == null) {
      throw const AccountDeletionFailure.appleCodeRequired();
    }
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

/// Issue #140 review, LLA-094: [AccountSection._runExport] reads entries/
/// observations through this one coherent seam now — delegates straight to
/// the harness's own fakes so every prior "what gets threaded through"
/// regression-guard still holds; profileMode/cycleOverrides are outside
/// this file's own test scope (LLA-084 coverage lives in
/// `account_importer_test.dart`/`account_export_test.dart`).
class _HarnessExportSnapshotRepository implements AccountExportSnapshotRepository {
  _HarnessExportSnapshotRepository(this._entries, this._observations);

  final DayEntriesRepository _entries;
  final ObservationsRepository _observations;

  @override
  Future<AccountExportSnapshot> forProfile(String profileId) async => (
        entries: await _entries.listForProfile(profileId),
        observations: await _observations.listForProfile(profileId),
        profileMode: null,
        cycleOverrides: const <CycleOverride>[],
        mergeEvents: const <DayEntryMergeEvent>[],
        customTags: const <CustomTag>[],
        guardianNotes: const <GuardianNote>[],
      );
}

class DeletionHarness {
  DeletionHarness({
    List<String> providers = const ['email'],
    bool grantReauth = true,
    this.provideGate = true,
    bool provideDeletionService = true,
    FakeAccountDeletionService? deletionService,
    this.exportAccount,
    this.appleAuthorizationCodeRequest,
    this.showAddApple,
    this.mfaEnabled,
  })  : auth = FakeAuthService(),
        deletion = deletionService ??
            (provideDeletionService ? FakeAccountDeletionService() : null),
        gate = FakeGate(grantNext: grantReauth) {
    auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1', email: 'a@b.c'));
    auth.providers = providers;
    controller = AuthController(authService: auth, mfaEnabled: mfaEnabled);
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

  /// Issue #738: forwarded to the [AuthController] so the AAL2 step-up
  /// group can run the flag-on (`LUNARLOG_ENABLE_MFA=true`) build; null
  /// means the default-off build this test run compiles with.
  final bool? mfaEnabled;

  /// Forces [AccountSection]'s platform gate for the native Apple ceremony
  /// (Issue #605/LLA-052): `true` simulates an iOS-capable device, `false`
  /// simulates a platform with no native Sign in with Apple ceremony at all
  /// (e.g. Android); null (the default) uses the real platform check, which
  /// this test host does not satisfy.
  final bool? showAddApple;
  final bool provideGate;
  int resetCalls = 0;

  /// Exposed (rather than built fresh inside [pump]) so a test can populate
  /// them beforehand and assert what `_runExport` actually threads through
  /// to [exportAccount] (review finding: nothing pinned the
  /// `observationsByProfile[profile.id] = await observationsRepo.listForProfile(…)`
  /// line in `AccountSection._runExport` — deleting it would still pass
  /// every prior test).
  final FakeProfilesRepository profilesRepository = FakeProfilesRepository();
  final FakeDayEntriesRepository dayEntriesRepository = FakeDayEntriesRepository();
  final FakeObservationsRepository observationsRepository = FakeObservationsRepository();
  final FakeCareContentRepository careContentRepository =
      FakeCareContentRepository();

  /// Toggled by [unmountSection] (#17 P1 fix regression coverage): lets a
  /// test unmount just [AccountSection] - the way navigating away from the
  /// Settings screen would in the real app - while every provider above it
  /// (including the [DeviceResetCallback]) stays alive, mirroring how
  /// [DeviceResetCallback] is actually provided from the app root.
  final ValueNotifier<bool> _sectionVisible = ValueNotifier(true);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Issue #268: MfaSettingsSection renders unconditionally whenever
        // AccountSection is signed-in, and calls AppLocalizations.of
        // immediately — this harness needs the real delegates now, not
        // just the ones a screen-specific failure path used to reach.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: controller),
            if (provideGate)
              ChangeNotifierProvider<GateController>.value(value: gateController),
            Provider<SettingsStore>.value(value: _NoopSettings()),
            Provider<ProfilesRepository>.value(value: profilesRepository),
            Provider<DayEntriesRepository>.value(value: dayEntriesRepository),
            Provider<ObservationsRepository>.value(value: observationsRepository),
            Provider<CareContentRepository>.value(value: careContentRepository),
            // Issue #140 review, LLA-094: `_runExport` reads entries/
            // observations through this coherent snapshot seam now, not the
            // two repos above directly — still backed by the SAME fakes, so
            // this harness's "pins the observationsRepo.listForProfile call"
            // regression-guard (see the field doc comment above) still
            // holds.
            Provider<AccountExportSnapshotRepository>.value(
              value: _HarnessExportSnapshotRepository(
                dayEntriesRepository,
                observationsRepository,
              ),
            ),
            // The tree-provided export writer `_runExport` reads before
            // falling back to the injected collaborator (mirrors
            // `lib/app.dart`).
            Provider<AccountExportWriter>.value(
                value: const PlatformAccountExportWriter()),
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
            // Issue #268: MfaSettingsSection adds another tile group to
            // AccountSection's Column, which the real Settings screen
            // always hosts inside a scrolling ListView (see
            // settings_screen.dart) — this harness needs the same, or the
            // fixed test viewport overflows on a small screen size.
            body: SingleChildScrollView(
              child: ValueListenableBuilder<bool>(
                valueListenable: _sectionVisible,
                builder: (context, visible, _) => visible
                    ? AccountSection(
                        showExportAndDelete: true,
                        exportAccount: exportAccount,
                        appleAuthorizationCodeRequest: appleAuthorizationCodeRequest,
                        showAddApple: showAddApple,
                      )
                    : const SizedBox.shrink(),
              ),
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

  Future<void> dispose() async {
    controller.dispose();
    gateController.dispose();
    await auth.dispose();
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

  group('AAL2 step-up before deletion (issue #268 D-6)', () {
    // Issue #738: this group runs the flag-on build (`mfaEnabled: true`,
    // what `--dart-define=LUNARLOG_ENABLE_MFA=true` compiles to) — #714's
    // behavior exactly, nothing deleted. The flag-off default is pinned by
    // the closing test.
    testWidgets(
        'a verified MFA factor requires a correct step-up code, after the '
        'device credential and before the delete confirmation dialog',
        (tester) async {
      final h = DeletionHarness(mfaEnabled: true);
      addTearDown(h.dispose);
      h.auth
        ..mfaStepUpRequired = true
        ..mfaFactors = [
          MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026),
          ),
        ];
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();

      expect(h.gate.requests, 1,
          reason: 'the device credential still runs first, unchanged');
      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(find.text('Delete account?'), findsNothing,
          reason: 'the delete confirmation must wait for the step-up');
      expect(h.deletion!.deleteCalls, 0);

      await tester.enterText(
          find.byKey(const ValueKey('mfa-step-up-code-field')), '123456');
      await tester.tap(find.byKey(const ValueKey('mfa-step-up-confirm')));
      await tester.pumpAndSettle();

      expect(h.auth.verifyTotpCodeCalls.single,
          (factorId: 'factor-1', code: '123456'));
      expect(find.text('Delete account?'), findsOneWidget);

      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 1);
      expect(h.resetCalls, 1);
    });

    testWidgets('cancelling the step-up dialog never opens the confirmation '
        'or calls the deletion service', (tester) async {
      final h = DeletionHarness(mfaEnabled: true);
      addTearDown(h.dispose);
      h.auth
        ..mfaStepUpRequired = true
        ..mfaFactors = [
          MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026),
          ),
        ];
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account?'), findsNothing);
      expect(h.deletion!.deleteCalls, 0);
      expect(h.resetCalls, 0);
    });

    testWidgets('no verified MFA factor: the delete confirmation opens '
        'immediately with no step-up dialog (unaffected pre-#268 path)',
        (tester) async {
      final h = DeletionHarness(mfaEnabled: true);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();

      expect(find.text("Confirm it's you"), findsNothing);
      expect(find.text('Delete account?'), findsOneWidget);
    });

    testWidgets(
        'feature flag off (issue #738, the default build): even a '
        'step-up-required account deletes with no step-up dialog — '
        'ensureAal2 auto-passes', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      h.auth
        ..mfaStepUpRequired = true
        ..mfaFactors = [
          MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026),
          ),
        ];
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();

      expect(find.text("Confirm it's you"), findsNothing,
          reason: 'a flag-off build never demands an AAL2 step-up');
      expect(find.text('Delete account?'), findsOneWidget);
      expect(h.auth.requiresMfaStepUpCalls, 0,
          reason: 'the gate short-circuits before consulting the service');
      expect(h.auth.listMfaFactorsCalls, 0,
          reason: 'the MFA settings tile group never rendered either');

      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.deletion!.deleteCalls, 1);
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
          Map<String, List<Observation>>? observationsByProfile = const {},
          Map<String, List<CareNote>>? careNotesByProfile = const {},
          Map<String, List<VisitPrepItem>>? visitPrepByProfile = const {},
          Map<String, ProfileLifecycleMode?>? profileModesByProfile = const {},
          Map<String, List<CycleOverride>>? cycleOverridesByProfile = const {},
          Map<String, List<DayEntryMergeEvent>>? mergeEventsByProfile = const {},
          Map<String, List<CustomTag>>? customTagsByProfile = const {},
          Map<String, List<GuardianNote>>? guardianNotesByProfile = const {},
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

    testWidgets('threads this profile\'s observations through to the export '
        'collaborator (pins the observationsRepo.listForProfile call in '
        '_runExport)', (tester) async {
      Map<String, List<Observation>>? captured;
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          Map<String, List<Observation>>? observationsByProfile = const {},
          Map<String, List<CareNote>>? careNotesByProfile = const {},
          Map<String, List<VisitPrepItem>>? visitPrepByProfile = const {},
          Map<String, ProfileLifecycleMode?>? profileModesByProfile = const {},
          Map<String, List<CycleOverride>>? cycleOverridesByProfile = const {},
          Map<String, List<DayEntryMergeEvent>>? mergeEventsByProfile = const {},
          Map<String, List<CustomTag>>? customTagsByProfile = const {},
          Map<String, List<GuardianNote>>? guardianNotesByProfile = const {},
          required appVersion,
        }) async {
          captured = observationsByProfile;
        },
      );
      addTearDown(h.dispose);
      final now = DateTime.utc(2026, 9, 1);
      h.profilesRepository.profiles = [
        Profile(
          id: 'p1',
          displayName: 'Riley',
          isMinor: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      h.observationsRepository.observationsByProfile = {
        'p1': [
          Observation(
            id: 'o1',
            dayEntryId: 'de1',
            profileId: 'p1',
            localDate: LocalDate(2026, 9, 1),
            tz: 'UTC',
            category: ObservationCategory.pain,
            updatedAt: now,
          ),
        ],
      };
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-export-first'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['p1'], isNotEmpty);
    });

    testWidgets('a failed export shows an inline dialog error and does not '
        'close it', (tester) async {
      final h = DeletionHarness(
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          Map<String, List<Observation>>? observationsByProfile = const {},
          Map<String, List<CareNote>>? careNotesByProfile = const {},
          Map<String, List<VisitPrepItem>>? visitPrepByProfile = const {},
          Map<String, ProfileLifecycleMode?>? profileModesByProfile = const {},
          Map<String, List<CycleOverride>>? cycleOverridesByProfile = const {},
          Map<String, List<DayEntryMergeEvent>>? mergeEventsByProfile = const {},
          Map<String, List<CustomTag>>? customTagsByProfile = const {},
          Map<String, List<GuardianNote>>? guardianNotesByProfile = const {},
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
          Map<String, List<Observation>>? observationsByProfile = const {},
          Map<String, List<CareNote>>? careNotesByProfile = const {},
          Map<String, List<VisitPrepItem>>? visitPrepByProfile = const {},
          Map<String, ProfileLifecycleMode?>? profileModesByProfile = const {},
          Map<String, List<CycleOverride>>? cycleOverridesByProfile = const {},
          Map<String, List<DayEntryMergeEvent>>? mergeEventsByProfile = const {},
          Map<String, List<CustomTag>>? customTagsByProfile = const {},
          Map<String, List<GuardianNote>>? guardianNotesByProfile = const {},
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

  group('Apple identity ceremony (KTD3) - server-informed flow '
      '(Issue #605/LLA-052)', () {
    testWidgets('the normal iOS first attempt: the server asks for a code, '
        'then the ceremony runs, then a second call carries the code',
        (tester) async {
      var appleCalls = 0;
      final service = FakeAccountDeletionService()..requireAppleCode = true;
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        showAddApple: true, // this device has the native ceremony available
        deletionService: service,
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
      expect(service.deleteCalls, 2,
          reason: 'the first, code-free call must run before the ceremony '
              'is ever invoked');
      expect(service.appleCodesPassed, [null, 'fresh-code-123']);
      expect(h.resetCalls, 1);
    });

    testWidgets('code-free retry on iOS: the server accepts the first, '
        'code-free call, and the ceremony is never invoked even though '
        'this device has one', (tester) async {
      var appleCalls = 0;
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        showAddApple: true, // this device has the native ceremony available
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

      expect(appleCalls, 0,
          reason:
              'the server never asked for a code, so the ceremony must not run');
      expect(h.deletion!.deleteCalls, 1);
      expect(h.deletion!.appleCodesPassed.single, isNull);
      expect(h.resetCalls, 1);
    });

    testWidgets('a non-Apple account needs no code either: the first, '
        'code-free call succeeds and no ceremony runs', (tester) async {
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

    testWidgets('a cancelled Apple dialog aborts deletion silently after '
        'the server asks for a code: exactly one (code-free) service call, '
        'no reset, no error copy', (tester) async {
      final service = FakeAccountDeletionService()..requireAppleCode = true;
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        showAddApple: true, // this device has the native ceremony available
        deletionService: service,
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

      expect(service.deleteCalls, 1,
          reason: 'only the first, code-free call ran - the cancelled '
              'ceremony aborted before a second call could happen');
      expect(h.resetCalls, 0);
      expect(key('account-delete-error'), findsNothing);
    });

    testWidgets('a non-cancellation Apple error surfaces unknown copy, not '
        'silence', (tester) async {
      final service = FakeAccountDeletionService()..requireAppleCode = true;
      final h = DeletionHarness(
        providers: ['email', 'apple'],
        showAddApple: true, // this device has the native ceremony available
        deletionService: service,
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

      expect(service.deleteCalls, 1);
      expect(h.resetCalls, 0);
      expect(key('account-delete-error'), findsOneWidget);
      expect(
        find.descendant(
          of: key('account-delete-error'),
          matching: find.text(
            accountDeletionFailureCopy(_en, const AccountDeletionFailure.unknown()),
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });

    group('no native ceremony on a platform that lacks it (mixed-provider '
        'Android)', () {
      testWidgets('a code-free retry succeeds: the native ceremony never '
          'runs, the service is called with a null code, and deletion '
          'still succeeds', (tester) async {
        var appleCalls = 0;
        final h = DeletionHarness(
          providers: ['email', 'apple'],
          showAddApple: false, // simulates Android: no native ceremony
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

        expect(appleCalls, 0,
            reason: 'the unavailable native ceremony must never be invoked');
        expect(h.deletion!.deleteCalls, 1);
        expect(h.deletion!.appleCodesPassed.single, isNull);
        expect(h.resetCalls, 1);
      });

      testWidgets('when the server still needs a fresh code: surfaces the '
          'distinct, honest appleNativeCeremonyUnavailable copy rather than '
          'either the native ceremony throwing '
          'SignInWithAppleNotSupportedException or the misleading plain '
          'apple_code_required "please try again" copy', (tester) async {
        var appleCalls = 0;
        final service = FakeAccountDeletionService()..requireAppleCode = true;
        final h = DeletionHarness(
          providers: ['email', 'apple'],
          showAddApple: false, // simulates Android: no native ceremony
          deletionService: service,
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

        expect(appleCalls, 0,
            reason: 'the unavailable native ceremony must never be invoked');
        expect(service.deleteCalls, 1,
            reason: 'only the first, code-free call ran - no second call '
                'was ever attempted on a platform with no ceremony');
        expect(service.appleCodesPassed.single, isNull);
        expect(h.resetCalls, 0);
        expect(
          find.descendant(
            of: key('account-delete-error'),
            matching: find.text(accountDeletionFailureCopy(_en,
                const AccountDeletionFailure.appleNativeCeremonyUnavailable())),
            matchRoot: true,
          ),
          findsOneWidget,
        );
      });
    });
  });

  group('each AccountDeletionFailure variant renders its own copy (R12)', () {
    for (final failure in const <AccountDeletionFailure>[
      AccountDeletionFailure.network(),
      AccountDeletionFailure.unauthorized(),
      AccountDeletionFailure.appleCodeRequired(),
      AccountDeletionFailure.appleNativeCeremonyUnavailable(),
      AccountDeletionFailure.appleRevokeFailed(),
      AccountDeletionFailure.appleRevocationMarkerFailed(),
      AccountDeletionFailure.attachmentCleanupFailed(),
      AccountDeletionFailure.attachmentCleanupUnbounded(),
      AccountDeletionFailure.timeout(),
      AccountDeletionFailure.deleteUserFailed(),
      AccountDeletionFailure.unknown(),
      AccountDeletionFailure.mfaRequired(),
    ]) {
      testWidgets('$failure', (tester) async {
        final service = FakeAccountDeletionService()..nextError = failure;
        // showAddApple: true (Issue #605/LLA-052) so a persistent
        // appleCodeRequired (set unconditionally as nextError above, so it
        // also fires on the ceremony's own follow-up call) still surfaces
        // its own copy via _performDeletion's generic catch, rather than
        // this loop accidentally exercising the
        // appleNativeCeremonyUnavailable path on a test host with no
        // native ceremony of its own.
        final h = DeletionHarness(
          deletionService: service,
          showAddApple: true,
          appleAuthorizationCodeRequest: () async =>
              _appleCredential('generic-loop-code'),
        );
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
            matching: find.text(accountDeletionFailureCopy(_en, failure)),
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

      final copy = accountDeletionFailureCopy(_en, failure);
      // Unlike appleRevokeFailed, nothing was touched on this path (the
      // Edge Function fails closed before Step 4's destructive RPC even
      // runs) - the copy must say so, not the appleRevokeFailed line's
      // "your account data was deleted, but...".
      expect(copy, isNot(contains('your account data was deleted')));
      expect(copy.toLowerCase(), contains('nothing was deleted'));
      expect(copy.toLowerCase(), contains('try again'));
    });

    testWidgets('appleNativeCeremonyUnavailable explains nothing was '
        'deleted and points to another device or support, not a bare retry '
        '(Issue #605/LLA-052)', (tester) async {
      const failure = AccountDeletionFailure.appleNativeCeremonyUnavailable();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(_en, failure);
      // Unlike appleCodeRequired, a bare retry can never succeed here - the
      // ceremony will never become available on this platform - so the
      // copy must not read as a plain "please try again" and must instead
      // point somewhere that can actually finish the job.
      expect(copy.toLowerCase(), contains('nothing was deleted'));
      expect(copy.toLowerCase(), contains('device'));
      expect(copy.toLowerCase(), contains('support'));
    });

    testWidgets('attachmentCleanupFailed explains nothing was deleted and '
        'the operator should retry (Issue #243 round 2 fix)', (tester) async {
      const failure = AccountDeletionFailure.attachmentCleanupFailed();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(_en, failure);
      // The attachment-cleanup step now runs before the destructive RPC
      // (Issue #243 round 2 fix), so a failure here leaves everything
      // untouched, exactly like appleCodeRequired - the copy must say so,
      // not the appleRevokeFailed line's "your account data was deleted,
      // but...".
      expect(copy, isNot(contains('your account data was deleted')));
      expect(copy.toLowerCase(), contains('nothing was deleted'));
      expect(copy.toLowerCase(), contains('try again'));
    });

    testWidgets('appleRevocationMarkerFailed explains the data WAS deleted and '
        'Apple DID confirm the revocation, unlike appleRevokeFailed (Issue '
        '#599)', (tester) async {
      const failure = AccountDeletionFailure.appleRevocationMarkerFailed();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(_en, failure);
      expect(copy, isNot(contains('could not confirm')));
      expect(copy.toLowerCase(), contains('deleted'));
      expect(copy.toLowerCase(), contains('confirmed the sign-in'));
      expect(copy.toLowerCase(), contains('try again'));
      expect(copy.toLowerCase(), contains('support'));
    });

    testWidgets('attachmentCleanupUnbounded explains nothing was deleted and '
        'directs to support rather than inviting a bare retry (Issue #605/'
        'LLA-053)', (tester) async {
      const failure = AccountDeletionFailure.attachmentCleanupUnbounded();
      final service = FakeAccountDeletionService()..nextError = failure;
      final h = DeletionHarness(deletionService: service);
      addTearDown(h.dispose);
      await h.pump(tester);

      await tester.tap(key('account-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-delete-confirm'));
      await tester.pumpAndSettle();

      final copy = accountDeletionFailureCopy(_en, failure);
      // Unlike attachmentCleanupFailed, this is a bound on the account's own
      // data - a bare retry can never clear it, so the copy must say so and
      // point to support instead of "please try again".
      expect(copy, isNot(contains('your account data was deleted')));
      expect(copy.toLowerCase(), contains('nothing was deleted'));
      expect(copy.toLowerCase(), contains('support'));
      expect(copy.toLowerCase(), isNot(contains('please try again')));
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

      final copy = accountDeletionFailureCopy(_en, failure);
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

      final copy = accountDeletionFailureCopy(_en, failure);
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

      final copy = accountDeletionFailureCopy(_en, failure);
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

  group('Issue #222: "Export my data" is no longer a tile in this section',
      () {
    testWidgets(
        'account-export never renders here, signed in or out, regardless '
        'of showExportAndDelete - it moved to YourDataSection', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      await h.pump(tester);
      expect(key('account-export'), findsNothing);

      h.auth.emit(AuthSessionState.signedOut);
      await tester.pumpAndSettle();
      expect(key('account-export'), findsNothing);
    });
  });

  group('R11: signed out / unconfigured / web absence (delete tile only - '
      '"Export my data" moved out of this section, Issue #222)', () {
    testWidgets('signed out: the delete tile does not render', (tester) async {
      final h = DeletionHarness();
      addTearDown(h.dispose);
      h.auth.emit(AuthSessionState.signedOut);
      await h.pump(tester);

      expect(key('account-delete'), findsNothing);
    });

    testWidgets('showExportAndDelete: false (simulated web) hides the '
        'delete tile', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      final deletion = FakeAccountDeletionService();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

      expect(key('account-delete'), findsNothing);
    });
  });
}
