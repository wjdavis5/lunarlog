/// Unit tests for [ProfileGuardiansRepository.getForProfile] (Issue #153) —
/// the one-shot variant of [ProfileGuardiansRepository.watchForProfile],
/// added for the health-sync binding picker.
///
/// Issue #551 problem 1: this test used to open a real drift database solely
/// to feed [DriftProfileGuardiansRepository]. It now drives a hand-written
/// fake of the repository's narrow [ProfileGuardianStore] role, so the
/// repository's own mapping and scoping logic is tested in isolation with no
/// database at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

/// Hand-written fake of the [ProfileGuardianStore] role — the only storage
/// surface [DriftProfileGuardiansRepository] touches. Holds guardian rows
/// keyed by profile id and records every profile id asked for, so the test
/// can assert the repository's per-profile scoping without a database.
class _FakeProfileGuardianStore implements ProfileGuardianStore {
  _FakeProfileGuardianStore([Map<String, List<ProfileGuardianData>>? rows])
      : _rowsByProfile = rows ?? const {};

  final Map<String, List<ProfileGuardianData>> _rowsByProfile;
  final List<String> requestedProfileIds = <String>[];

  @override
  Future<List<ProfileGuardianData>> getGuardiansForProfile(
      String profileId) async {
    requestedProfileIds.add(profileId);
    return _rowsByProfile[profileId] ?? const [];
  }

  @override
  Stream<List<ProfileGuardianData>> watchGuardiansForProfile(
          String profileId) =>
      Stream.value(_rowsByProfile[profileId] ?? const []);
}

ProfileGuardianData _guardian({
  required String id,
  required String profileId,
  required String userId,
  required String role,
  required String status,
  String? displayName,
  String? invitedBy,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    ProfileGuardianData(
      id: id,
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      invitedBy: invitedBy,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
      serverVersion: 1,
      isSubject: false,
    );

void main() {
  test('returns an empty list for a profile with no guardian rows', () async {
    final repository =
        DriftProfileGuardiansRepository(_FakeProfileGuardianStore());
    expect(await repository.getForProfile('solo'), isEmpty);
  });

  test('returns every guardian row for the profile, mapped to the domain '
      'model, regardless of status', () async {
    final store = _FakeProfileGuardianStore({
      'shared': [
        _guardian(
          id: 'g-owner',
          profileId: 'shared',
          userId: 'owner-1',
          role: 'primary_guardian',
          status: 'accepted',
          displayName: 'Mom',
        ),
        _guardian(
          id: 'g-pending',
          profileId: 'shared',
          userId: 'caregiver-1',
          role: 'caregiver',
          status: 'pending',
          invitedBy: 'owner-1',
        ),
      ],
    });
    final repository = DriftProfileGuardiansRepository(store);

    final guardians = await repository.getForProfile('shared');
    expect(guardians, hasLength(2));
    expect(
      guardians.map((g) => g.userId).toSet(),
      {'owner-1', 'caregiver-1'},
    );
    final owner = guardians.singleWhere((g) => g.userId == 'owner-1');
    expect(owner.role, GuardianRole.primaryGuardian);
    expect(owner.status, GuardianStatus.accepted);
    expect(owner.displayName, 'Mom');
  });

  test('scopes every read to exactly the requested profile id', () async {
    final store = _FakeProfileGuardianStore({
      'a': [
        _guardian(
          id: 'g-a',
          profileId: 'a',
          userId: 'owner-a',
          role: 'primary_guardian',
          status: 'accepted',
        ),
      ],
      'b': const [],
    });
    final repository = DriftProfileGuardiansRepository(store);

    expect(await repository.getForProfile('b'), isEmpty);
    final a = await repository.getForProfile('a');
    expect(a.single.userId, 'owner-a');
    expect(store.requestedProfileIds, ['b', 'a'],
        reason: 'the repository must pass the caller\'s profile id through '
            'untouched (per-profile isolation, R3)');
  });
}
