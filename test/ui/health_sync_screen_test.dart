/// Widget tests for [HealthSyncScreen] (Issue #153) — exercised directly,
/// bypassing `SettingsScreen`'s `AppConfig.hasHealthSync` gate, per that
/// flag's "ships dormant but testable" doc comment. Uses a real
/// [HealthSyncBinding] backed by [FakeSettingsStore] (the actual invariant
/// logic under test), a plain in-memory [FakeProfilesRepository], and a
/// bare async function for guardian rows — no database required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<HealthImportSummary> importNow() async {
    calls++;
    return summary;
  }
}

/// A runner that throws, for the unexpected-failure line.
class _ThrowingImporter implements HealthImportRunner {
  @override
  HealthImportPlatform get platform => HealthImportPlatform.appleHealth;

  @override
  Future<HealthImportSummary> importNow() async =>
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required HealthSyncBinding binding,
    String? signedInUserId = 'u1',
    ProfilesRepository? profilesRepository,
    HealthImportRunner? importer,
    bool writeEnabled = true,
  }) async {
    // Issue #186 added revocation/30-day-limit copy above the profile
    // picker, and #217 adds an import tile and its result block below it,
    // so give the lazy ListView a tall viewport to keep every profile tile
    // and the import/unbind actions inside the build window.
    tester.view.physicalSize = const Size(800, 1800);
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
      expect(
        find.textContaining('Updated 2 days from Apple Health.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Kept your own logged value on 1 day.'),
        findsOneWidget,
      );
    });

    testWidgets('a device-zone import is reported as placed, never skipped '
        '(Issue #902)', (tester) async {
      final importer = _FakeImporter(const HealthImportSummary(
        samplesRead: 3,
        daysWritten: 3,
        samplesFromDeviceZone: 3,
      ));
      final binding = await boundBinding(FakeSettingsStore());
      await pumpScreen(tester, binding: binding, importer: importer);

      await tester.tap(find.byKey(const ValueKey('health-sync-import-tile')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Placed 3 samples using the time zone of this phone.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Skipped'), findsNothing);
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
      expect(
        find.textContaining('Updated 2 days from Apple Health.'),
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
      expect(
        find.textContaining('Updated 2 days from Apple Health.'),
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
        find.textContaining("This profile can't import from Apple Health"),
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
}
