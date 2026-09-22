/// Widget tests for [HealthSyncScreen] (Issue #153) — exercised directly,
/// bypassing `SettingsScreen`'s `AppConfig.hasHealthSync` gate, per that
/// flag's "ships dormant but testable" doc comment. Uses a real
/// [HealthSyncBinding] backed by [FakeSettingsStore] (the actual invariant
/// logic under test), a plain in-memory [FakeProfilesRepository], and a
/// bare async function for guardian rows — no database required.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/ui/settings/health_sync_screen.dart';

import '../support/fake_settings_store.dart';

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository(this.profiles);

  final List<Profile> profiles;

  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    bool? irregularFraming,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Profile?> setTrackingPreferences(
          String id, TrackingPreferences? preferences) =>
      throw UnimplementedError();

  @override
  Future<Profile?> findById(String id) async {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError();

  @override
  Future<Profile> update(Profile profile) => throw UnimplementedError();

  @override
  Stream<List<Profile>> watch() => Stream.value(profiles);

  @override
  Future<void> applyServerPurge(String id) => throw UnimplementedError();
}

/// A repository whose `list()` always throws — exercises `_load()`'s
/// `catchError` handling (review fix): the loading spinner must resolve
/// instead of spinning forever.
class ThrowingProfilesRepository implements ProfilesRepository {
  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    bool? irregularFraming,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Profile?> setTrackingPreferences(
          String id, TrackingPreferences? preferences) =>
      throw UnimplementedError();

  @override
  Future<Profile?> findById(String id) => throw UnimplementedError();

  @override
  Future<List<Profile>> list() async =>
      throw StateError('boom: repository unavailable');

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError();

  @override
  Future<Profile> update(Profile profile) => throw UnimplementedError();

  @override
  Stream<List<Profile>> watch() => throw UnimplementedError();

  @override
  Future<void> applyServerPurge(String id) => throw UnimplementedError();
}

/// A binding whose `canBind` always allows but whose `bind` always denies
/// — simulates eligibility changing out from under the operator between
/// this screen's last load and the confirm dialog closing (e.g. another
/// device changed the binding or this profile's ownership mid-flow), so
/// the "surface bind()'s deny reason" code path (review fix) can be
/// exercised deterministically.
class _AlwaysAllowThenDenyBinding extends HealthSyncBinding {
  _AlwaysAllowThenDenyBinding(super.settings);

  @override
  HealthSyncCheck canBind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) =>
      HealthSyncCheck.allowed;

  @override
  Future<HealthSyncCheck> bind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) async =>
      HealthSyncCheck.notOwner;
}

Profile _profile({
  required String id,
  required String name,
  bool isMinor = false,
  DateTime? archivedAt,
}) =>
    Profile(
      id: id,
      displayName: name,
      isMinor: isMinor,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProfileGuardian _owner(String profileId, String userId) => ProfileGuardian(
      id: 'g-$profileId',
      profileId: profileId,
      userId: userId,
      role: GuardianRole.primaryGuardian,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A programmable [HealthImportRunner] for the #217/#458 UI states.
class _FakeImporter implements HealthImportRunner {
  _FakeImporter(this.summary, {this.platform = HealthImportPlatform.appleHealth});

  HealthImportSummary summary;

  @override
  final HealthImportPlatform platform;
  int calls = 0;

  @override
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  }) async {
    calls++;
    return summary;
  }
}

/// A runner that throws, for the unexpected-failure line.
class _ThrowingImporter implements HealthImportRunner {
  @override
  HealthImportPlatform get platform => HealthImportPlatform.appleHealth;

  @override
  Future<HealthImportSummary> importNow({
    void Function(HealthImportProgress progress)? onProgress,
  }) async =>
      throw StateError('boom');
}

void main() {
  // Fixture: 'eligible' owned by the signed-in user (u1), 'minor' also
  // owned by u1 but is a minor, 'other' owned by a different account,
  // 'archived-profile' owned by u1 but archived (excluded from the
  // picker entirely — review fix).
  final profiles = [
    _profile(id: 'eligible', name: 'Alice'),
    _profile(id: 'minor', name: 'Baby', isMinor: true),
    _profile(id: 'other', name: 'Charlie'),
    _profile(
      id: 'archived-profile',
      name: 'Dana',
      archivedAt: DateTime.utc(2026, 1, 2),
    ),
  ];
  final guardiansByProfile = <String, List<ProfileGuardian>>{
    'eligible': [_owner('eligible', 'u1')],
    'minor': [_owner('minor', 'u1')],
    'other': [_owner('other', 'someone-else')],
    'archived-profile': [_owner('archived-profile', 'u1')],
  };

  Future<List<ProfileGuardian>> guardiansForProfile(String profileId) async =>
      guardiansByProfile[profileId] ?? const [];

  // Issue #959: the OS-permission status is driven through the real
  // `lunarlog/health` channel via a mock handler — the "channel fake" the
  // issue asks for — so these tests also pin the method name the native
  // halves must answer, not merely a hand-rolled Dart stand-in.
  const healthChannel = MethodChannel('lunarlog/health');
  final permissionCalls = <MethodCall>[];
  Object? permissionResult;
  setUp(() {
    permissionCalls.clear();
    permissionResult = 'granted';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(healthChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'permissionStatus') return permissionResult;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(healthChannel, null);
  });

  HealthPermissionProbe buildPermissionProbe() => MethodChannelHealthPlatform(
        binding: HealthSyncBinding(FakeSettingsStore()),
        minorBindingAllowed: true,
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required HealthSyncBinding binding,
    String? signedInUserId = 'u1',
    ProfilesRepository? profilesRepository,
    HealthImportRunner? importer,
    HealthPermissionProbe? permissionProbe,
    bool writeEnabled = true,
    Size viewport = const Size(800, 1800),
  }) async {
    // Issue #186 added revocation/30-day-limit copy above the profile
    // picker, and #217 adds an import tile and its result block below it,
    // so give the lazy ListView a tall viewport to keep every profile tile
    // and the import/unbind actions inside the build window. Issue #1017
    // overrides this with a short viewport to prove the result is scrolled
    // into view after a pass.
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // Issue #238: the screen reads copy (including the Android
        // symptom-limitation line) through AppLocalizations, so the harness
        // registers the delegates and locales the real app wires.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HealthSyncScreen(
          profilesRepository:
              profilesRepository ?? FakeProfilesRepository(profiles),
          guardiansForProfile: guardiansForProfile,
          binding: binding,
          signedInUserId: signedInUserId,
          importer: importer,
          permissionProbe: permissionProbe,
          writeEnabled: writeEnabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every non-archived profile, showing a deny reason '
      'only for ineligible ones, and excludes archived profiles entirely',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    expect(find.byKey(const ValueKey('health-sync-profile-eligible')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-sync-profile-minor')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-sync-profile-other')), findsOneWidget);

    // Archived profiles never appear in the picker (review fix).
    expect(
      find.byKey(const ValueKey('health-sync-profile-archived-profile')),
      findsNothing,
    );

    // The eligible profile shows no deny-reason subtitle.
    final eligibleTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-eligible')),
    );
    expect(eligibleTile.subtitle, isNull);
    expect(eligibleTile.enabled, isTrue);

    // Issue #882: a minor profile owned by the signed-in account is
    // eligible on the same terms as an adult, so it shows no deny reason
    // and its tile is enabled.
    final minorTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-minor')),
    );
    expect(minorTile.subtitle, isNull);
    expect(minorTile.enabled, isTrue);
    expect(find.textContaining('after ownership transfer'), findsNothing);

    // The non-owner profile (a real, resolved different owner) explains
    // the ownership requirement plainly.
    expect(
      find.textContaining("not this profile's owner"),
      findsOneWidget,
    );
    final otherTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-other')),
    );
    expect(otherTile.enabled, isFalse);

    // No unbind action while nothing is bound.
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('documents the forward-only write surface, the flow collapse '
      '(issue #193, mirroring Clue\'s own disclosure) and the user-initiated '
      'import (issue #217)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    // Issue #217 rewrote the old "nothing is ever read back" claim: import
    // exists, but only when the operator starts it.
    expect(
      find.textContaining('nothing is read unless you start that import '
          'yourself'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Only days logged after sync is turned on'),
      findsOneWidget,
    );
    // The one lossy mapping in the #193 table: superHeavy -> Apple's
    // `heavy`, plus the A3-4 spotting rule, spelled out.
    expect(
      find.textContaining('Super heavy days are written to the Health app '
          'as Heavy'),
      findsOneWidget,
    );
    expect(
      find.textContaining('spotting between periods is written as '
          'intermenstrual bleeding'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-sync-symptoms-copy')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'Symptoms you tag — cramps, headache, bloating, and mood'),
      findsOneWidget,
    );
  });

  testWidgets('an import-only platform (Android, Issue #458) shows the '
      'import explanation and hides the write-only copy', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      writeEnabled: false,
    );

    expect(
      find.byKey(const ValueKey('health-sync-import-only-copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-sync-forward-only-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-flow-collapse-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-symptoms-copy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-sync-revocation-copy')),
      findsNothing,
    );
  });

  testWidgets('an import-only platform (Android) documents the permanent '
      'symptom limitation (Issue #238)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding, writeEnabled: false);

    expect(
      find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
      findsOneWidget,
    );
    expect(
      find.textContaining("Symptoms (cramps, headaches, mood, and more) "
          "can't be written to Health Connect"),
      findsOneWidget,
    );
  });

  testWidgets('a write-enabled platform (iOS) does not show the Android '
      'symptom limitation (Issue #238)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    expect(
      find.byKey(const ValueKey('health-sync-symptoms-android-limitation')),
      findsNothing,
    );
  });

  testWidgets('tapping an eligible profile opens a confirm dialog naming '
      'what binding means; confirming binds it', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();

    expect(find.text('Sync Alice to this phone?'), findsOneWidget);
    expect(
      find.textContaining("Only Alice's data will ever be written"),
      findsOneWidget,
    );
    final dialogRoute = ModalRoute.of(
      tester.element(find.text('Sync Alice to this phone?')),
    );
    expect(dialogRoute?.settings.name, kRouteHealthSyncBindDialog);

    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'eligible');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('health-sync-profile-eligible')),
        matching: find.byKey(const ValueKey('health-sync-bound-check')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);
  });

  testWidgets('canceling the confirm dialog leaves the profile unbound',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('tapping the minor profile opens the confirm dialog and '
      'binds it on confirmation (Issue #882: minors bind on the same terms '
      'as adults, so the tile is no longer disabled)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-minor')));
    await tester.pumpAndSettle();

    expect(find.text('Sync Baby to this phone?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'minor');
  });

  testWidgets('confirming a bind that the binding then denies surfaces the '
      'deny reason instead of discarding it (review fix)', (tester) async {
    final binding = _AlwaysAllowThenDenyBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-bind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(
      find.textContaining("You are not this profile's owner"),
      findsOneWidget,
    );

    // Let the SnackBar retire before the test ends, matching
    // `test/ui/gate_test.dart`'s convention for avoiding a pending-timer
    // failure.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the unbind action (confirmed) clears the binding and hides '
      'itself', (tester) async {
    final settings = FakeSettingsStore();
    final binding = HealthSyncBinding(settings);
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );

    await pumpScreen(tester, binding: binding);

    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('tapping the unbind tile opens a confirm dialog naming the '
      'profile and does NOT unbind on cancel (Issue #893)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Stop syncing Alice to this phone?'), findsOneWidget);
    expect(
      find.textContaining("Nothing already logged in lunarlog"),
      findsOneWidget,
    );
    final dialogRoute = ModalRoute.of(
      tester.element(find.text('Stop syncing Alice to this phone?')),
    );
    expect(dialogRoute?.settings.name, kRouteHealthSyncUnbindDialog);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), 'eligible');
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsOneWidget);
  });

  testWidgets('confirming the unbind dialog unbinds the profile (Issue #893)',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await binding.bind(
      profile: profiles.firstWhere((p) => p.id == 'eligible'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
    );
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
    await tester.pumpAndSettle();
    // The dialog must not have already torn the binding down on its own.
    expect(await binding.boundProfileId(), 'eligible');

    await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
    await tester.pumpAndSettle();

    expect(await binding.boundProfileId(), isNull);
    expect(find.byKey(const ValueKey('health-sync-unbind-tile')), findsNothing);
  });

  testWidgets('a signed-out session denies every non-minor profile with an '
      'actionable "sign in and sync" prompt, not the plain not-owner '
      'message (review fix — distinct copy for a never-synced local-only '
      'user)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding, signedInUserId: null);

    final eligibleTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-eligible')),
    );
    expect(eligibleTile.enabled, isFalse);
    expect(
      find.textContaining('Sign in and sync once'),
      findsWidgets,
    );
    expect(find.textContaining("not this profile's owner"), findsNothing);
  });

  testWidgets('a signed-in profile with no resolved owner (guardians not '
      'yet synced) is allowed — no one else claims it (Issue #882 review '
      'round 2)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      profilesRepository:
          FakeProfilesRepository([_profile(id: 'unsynced', name: 'Eve')]),
      signedInUserId: 'u1',
    );

    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-unsynced')),
    );
    expect(tile.subtitle, isNull);
    expect(tile.enabled, isTrue);
    expect(find.textContaining('Sign in and sync once'), findsNothing);
  });

  testWidgets('a throwing repository resolves the spinner into an error '
      'state instead of spinning forever (review fix)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(
      tester,
      binding: binding,
      profilesRepository: ThrowingProfilesRepository(),
    );

    expect(find.byKey(const ValueKey('health-sync-loading')), findsNothing);
    expect(find.byKey(const ValueKey('health-sync-load-error')), findsOneWidget);
  });

  group('Issue #217 import', () {
    Future<HealthSyncBinding> boundBinding(FakeSettingsStore settings) async {
      final binding = HealthSyncBinding(settings);
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    testWidgets('after an import completes on a short screen the result is '
        'scrolled into view and announced in a SnackBar (Issue #1017)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 3,
        samplesFromDeviceZone: 3,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        // Short enough that the import tile and its result cannot both be
        // on screen at once, so the pass must scroll the result into view.
        viewport: const Size(400, 300),
      );

      final tile = find.byKey(const ValueKey('health-sync-import-tile'));
      await tester.scrollUntilVisible(tile, 120);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      final result = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(result, findsOneWidget);
      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final rect = tester.getRect(result);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
        rect.bottom,
        lessThanOrEqualTo(screenHeight),
        reason: 'the result must be scrolled fully into view after the pass',
      );
      // The completion headline is also announced in a SnackBar so the tap
      // cannot look like it did nothing.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Imported 3 days'),
        ),
        findsOneWidget,
      );

      // Retire the SnackBar so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a finished import states its outcome exactly once — the '
        'headline, without the pre-#992 duplicate lines (Issue #1017)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 3,
        daysUnchanged: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Imported 3 days, skipped 1 already logged.'),
        ),
        findsOneWidget,
      );
      // The headline already carries the imported and skipped counts, so the
      // summary must not restate them with "Updated N days" / "N days
      // already matched".
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('Updated 3 days'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('already matched'),
        ),
        findsNothing,
      );
      // Exactly one line: the outcome is stated once.
      expect(
        find.descendant(of: summary, matching: find.byType(Text)),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the import tile is hidden when no runner is provided or '
        'nothing is bound', (tester) async {
      final settings = FakeSettingsStore();
      final binding = HealthSyncBinding(settings);
      await pumpScreen(tester, binding: binding);
      // Not bound: no tile even with a runner.
      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsNothing,
      );

      await pumpScreen(
        tester,
        binding: await boundBinding(FakeSettingsStore()),
      );
      // Bound but no runner (an unconfigured/test build): still hidden.
      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsNothing,
      );
    });

    testWidgets('tapping Import runs the runner once and renders the '
        'positive summary', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 2,
        daysKeptManual: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      expect(
        find.byKey(const ValueKey('health-sync-import-tile')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(importer.calls, 1);
      // importedDays = 2, skippedAlreadyLoggedDays = 1.
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Imported 2 days, skipped 1 already logged.'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Kept your own logged value on 1 day.'),
        findsOneWidget,
      );
      // Issue #1017: the pre-#992 "Updated N days" line restated the
      // headline's imported count and is gone.
      expect(find.textContaining('Updated 2 days'), findsNothing);
    });

    testWidgets('the completion summary headline reports imported days and '
        'days skipped because a value was already there (Issue #992)',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 2,
        daysUnchanged: 4,
        daysKeptManual: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      // importedDays = 2, skippedAlreadyLoggedDays = 4 + 1 = 5. Scoped to the
      // result block: the completion SnackBar (Issue #1017) announces the
      // same headline.
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('Imported 2 days, skipped 5 already '
              'logged.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pass stopped by the page cap says so rather than '
        'pretending it finished (Issue #992)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 1,
        pageLimitReached: true,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The import stopped early'),
        findsOneWidget,
      );
    });

    testWidgets('a device-zone import is reported as dated alongside the '
        'unplaceable skips, never labelled skipped itself (Issue #902, #1001, '
        'reshaped by #1017)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 4,
        daysWritten: 3,
        samplesFromDeviceZone: 2,
        samplesWithoutZone: 1,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Dated 2 entries using the time zone of this phone.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Skipped 1 entry with no recorded time zone.'),
        findsOneWidget,
      );
      // The two inferred placements are reported as dated, never folded
      // into the skip count.
      expect(find.textContaining('Skipped 2 entries'), findsNothing);
    });

    testWidgets('a confirmed unbind clears the previous import summary from '
        'the screen (Issue #893)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 2,
        daysWritten: 2,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('health-sync-import-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Imported 2 days, skipped 0 already logged.'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('health-sync-confirm-unbind')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('health-sync-import-summary')),
        findsNothing,
      );
    });

    testWidgets('an empty result renders the neutral ambiguity copy, never '
        '"nothing tracked" or "permission denied"', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary());
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          healthImportEmptyCopy(HealthImportPlatform.appleHealth),
        ),
        findsOneWidget,
      );
      // The neutral copy itself states both possibilities; it must not
      // assert either as fact, and no denial line is rendered.
      expect(find.textContaining('permission denied'), findsNothing);
    });

    testWidgets('a denied read renders the same neutral copy as an empty '
        'one (HealthKit opacity)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformPermissionDenied(),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          healthImportEmptyCopy(HealthImportPlatform.appleHealth),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('permission denied'), findsNothing);
    });

    testWidgets('a guard refusal renders the cannot-import line', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformRefused(HealthSyncCheck.notOwner),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("This profile can't import from the Health app"),
        findsOneWidget,
      );
    });

    testWidgets('a platform unavailable outcome renders platform-specific copy',
        (tester) async {
      final iosImporter = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformUnavailable(),
      ), platform: HealthImportPlatform.appleHealth);
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: iosImporter);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("The Health app isn't available on this device."),
        findsOneWidget,
      );

      final androidImporter = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformUnavailable(),
      ), platform: HealthImportPlatform.healthConnect);
      final androidBinding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: androidBinding,
        importer: androidImporter,
        writeEnabled: false,
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("Health Connect isn't available on this device."),
        findsOneWidget,
      );
    });

    testWidgets('a platform failed outcome renders generic retry copy',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformFailed('disk error'),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't finish the import. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets('a platform allowed with empty summary renders neutral copy',
        (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        blocked: HealthPlatformAllowed(),
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text(healthImportEmptyCopy(HealthImportPlatform.appleHealth)),
        findsOneWidget,
      );
    });

    testWidgets('an Android runner names Health Connect and renders the '
        'spotting line (Issue #458)', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(spottingDaysWritten: 2),
        platform: HealthImportPlatform.healthConnect,
      );
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      expect(
        find.text('Import from Health Connect'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Added spotting to 2 days from Health Connect.'),
        findsOneWidget,
      );
    });

    testWidgets('a throwing runner renders the generic failure line',
        (tester) async {
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: _ThrowingImporter(),
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't finish the import. Please try again."),
        findsOneWidget,
      );
    });
  });

  // Issue #959: the OS permission state is shown per platform, with the
  // settings deep link offered only when it is denied.
  group('Issue #959 OS permission status', () {
    Future<HealthSyncBinding> boundBinding(FakeSettingsStore settings) async {
      final binding = HealthSyncBinding(settings);
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      return binding;
    }

    testWidgets('renders granted / not-yet-asked / denied from the channel '
        'fake, and offers the settings link only when denied', (tester) async {
      final probe = buildPermissionProbe();
      final binding = HealthSyncBinding(FakeSettingsStore());

      for (final (wire, expected) in [
        ('granted', 'Health app access: granted'),
        ('notAsked', 'Health app access: not yet asked'),
        ('denied', 'Health app access: denied — open Settings to change'),
      ]) {
        permissionResult = wire;
        // Tear the previous tree down so the screen's State is recreated
        // and re-runs its permission load for the new wire value.
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpScreen(tester, binding: binding, permissionProbe: probe);

        expect(
          find.byKey(const ValueKey('health-sync-permission-status')),
          findsOneWidget,
        );
        expect(find.text(expected), findsOneWidget);
        expect(
          find.byKey(const ValueKey('health-sync-open-settings')),
          wire == 'denied' ? findsOneWidget : findsNothing,
        );
      }
    });

    testWidgets('the permission line is sentence-initial on both platforms — '
        'iOS never reads a lowercase "the" (Issue #1053)', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());

      // iOS: Apple Health's mid-sentence form is 'the Health app', but the
      // status line opens with the store name, so it must use the
      // sentence-initial title form 'Health app'.
      permissionResult = 'notAsked';
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
      );
      expect(find.text('Health app access: not yet asked'), findsOneWidget);
      final line = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('health-sync-permission-status')),
          matching: find.byType(Text),
        ),
      );
      expect(line.data, startsWith('Health app'));
      expect(line.data, isNot(startsWith('the ')));

      // Android: Health Connect is the same name in both positions, and the
      // line still reads as expected (writeEnabled: false selects it when no
      // importer is wired).
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
        writeEnabled: false,
      );
      expect(find.text('Health Connect access: not yet asked'), findsOneWidget);
    });

    testWidgets('read status is never rendered as denied on iOS — a granted '
        'or not-yet-asked write permission is never a refusal', (tester) async {
      final probe = buildPermissionProbe();
      final binding = HealthSyncBinding(FakeSettingsStore());

      for (final wire in ['granted', 'notAsked']) {
        permissionResult = wire;
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpScreen(tester, binding: binding, permissionProbe: probe);

        const statusKey = ValueKey('health-sync-permission-status');
        expect(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.textContaining('denied'),
          ),
          findsNothing,
        );
        // The line reports the write/access state only — Apple's opaque read
        // authorization must never surface as a status.
        expect(
          find.descendant(
            of: find.byKey(statusKey),
            matching: find.textContaining('read'),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('tapping the settings link opens the platform settings deep '
        'link', (tester) async {
      permissionResult = 'denied';
      final binding = HealthSyncBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        permissionProbe: buildPermissionProbe(),
      );

      await tester.tap(find.byKey(const ValueKey('health-sync-open-settings')));
      await tester.pumpAndSettle();

      expect(
        permissionCalls.map((call) => call.method),
        contains('openPermissionSettings'),
      );
    });

    testWidgets('a revoked write permission updates the line after an import '
        '(Issue #959)', (tester) async {
      final importer = _FakeImporter(
        const HealthImportSummary(samplesRead: 1, daysWritten: 1),
      );
      permissionResult = 'granted';
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        permissionProbe: buildPermissionProbe(),
      );

      expect(find.text('Health app access: granted'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsNothing,
      );

      // The OS permission is revoked while the screen is open; the import
      // pass re-reads the status and the line follows.
      permissionResult = 'denied';
      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.text('Health app access: denied — open Settings to change'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsOneWidget,
      );
    });

    testWidgets('no probe means no status line or settings link (an '
        'unconfigured build)', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding);

      expect(
        find.byKey(const ValueKey('health-sync-permission-status')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('health-sync-open-settings')),
        findsNothing,
      );
    });
  });

  group('Issue #1001 platform-specific health store copy', () {
    testWidgets(
        'iOS renders Health app sync in app bar and the Health app in import tile',
        (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      final importer = _FakeImporter(
        const HealthImportSummary(),
        platform: HealthImportPlatform.appleHealth,
      );
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        writeEnabled: true,
      );

      expect(find.text('Health app sync'), findsOneWidget);
      expect(find.text('Import from the Health app'), findsOneWidget);
      expect(
        find.text(
          "Choose the one profile whose data this phone may ever write to its "
          "Health app. Every other profile stays out of this phone's Health app "
          'entirely.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Android renders Health Connect sync in app bar, intro, and import tile',
        (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      final importer = _FakeImporter(
        const HealthImportSummary(),
        platform: HealthImportPlatform.healthConnect,
      );
      await pumpScreen(
        tester,
        binding: binding,
        importer: importer,
        writeEnabled: false,
      );

      expect(find.text('Health Connect sync'), findsOneWidget);
      expect(find.text('Import from Health Connect'), findsOneWidget);
      expect(
        find.text(
          'Choose the one profile this phone may import health data into. Every '
          'other profile stays out of Health Connect entirely.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('bind dialog references platform health store', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      // iOS bind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: true);
      await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Only Alice's data will ever be written to the Health app. This phone "
          'can sync one profile at a time — choosing a different profile later '
          'replaces this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Android bind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: false);
      await tester.tap(find.byKey(const ValueKey('health-sync-profile-eligible')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Only Alice's data will ever be imported from Health Connect. This "
          'phone can sync one profile at a time — choosing a different profile '
          'later replaces this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('unbind dialog references platform health store', (tester) async {
      final binding = HealthSyncBinding(FakeSettingsStore());
      await binding.bind(
        profile: profiles.firstWhere((p) => p.id == 'eligible'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );

      // iOS unbind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: true);
      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This phone will stop writing data for Alice to the Health app and '
          'stop importing from it. Nothing already logged in lunarlog, or '
          'already written to the Health app, is deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Android unbind dialog
      await pumpScreen(tester, binding: binding, writeEnabled: false);
      await tester.tap(find.byKey(const ValueKey('health-sync-unbind-tile')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This phone will stop importing data for Alice from Health Connect. '
          'Nothing already logged is deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
