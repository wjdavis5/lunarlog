/// Widget tests for [HealthSyncScreen] (Issue #153) — exercised directly,
/// bypassing `SettingsScreen`'s `AppConfig.hasHealthSync` gate, per that
/// flag's "ships dormant but testable" doc comment. Uses a real
/// [HealthSyncBinding] backed by [FakeSettingsStore] (the actual invariant
/// logic under test), a plain in-memory [FakeProfilesRepository], and a
/// bare async function for guardian rows — no database required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HealthSyncScreen(
          profilesRepository:
              profilesRepository ?? FakeProfilesRepository(profiles),
          guardiansForProfile: guardiansForProfile,
          binding: binding,
          signedInUserId: signedInUserId,
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

    // The minor profile explains the transfer requirement.
    expect(
      find.textContaining('after ownership transfer'),
      findsOneWidget,
    );
    final minorTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('health-sync-profile-minor')),
    );
    expect(minorTile.enabled, isFalse);

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

  testWidgets('tapping a minor profile does nothing (disabled tile has no '
      'tap handler)', (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await pumpScreen(tester, binding: binding);

    await tester.tap(find.byKey(const ValueKey('health-sync-profile-minor')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await binding.boundProfileId(), isNull);
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

  testWidgets('the unbind action clears the binding and hides itself',
      (tester) async {
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

  testWidgets('an unresolved owner (guardians not yet synced) gets the '
      'same actionable "sign in and sync" prompt even while signed in',
      (tester) async {
    final binding = HealthSyncBinding(FakeSettingsStore());
    await tester.pumpWidget(
      MaterialApp(
        home: HealthSyncScreen(
          profilesRepository:
              FakeProfilesRepository([_profile(id: 'unsynced', name: 'Eve')]),
          guardiansForProfile: (_) async => const [],
          binding: binding,
          signedInUserId: 'u1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign in and sync once'), findsOneWidget);
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
}
