/// Unit tests for [ProfileGuardiansRepository.getForProfile] (Issue #153) —
/// the one-shot variant of [ProfileGuardiansRepository.watchForProfile],
/// added for the health-sync binding picker.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

void main() {
  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late DriftProfileGuardiansRepository repository;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    repository = DriftProfileGuardiansRepository(storage);
  });

  tearDown(() => db.close());

  test('returns an empty list for a profile with no guardian rows', () async {
    final profile = await storage.upsertProfile(displayName: 'Solo', isMinor: false);
    expect(await repository.getForProfile(profile.id), isEmpty);
  });

  test('returns every guardian row for the profile, mapped to the domain '
      'model, regardless of status', () async {
    final profile = await storage.upsertProfile(displayName: 'Shared', isMinor: false);
    await storage.applyRemoteRows([
      RemoteProfileGuardianRow(
        id: 'g-owner',
        profileId: profile.id,
        userId: 'owner-1',
        role: 'primary_guardian',
        status: 'accepted',
        displayName: 'Mom',
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      RemoteProfileGuardianRow(
        id: 'g-pending',
        profileId: profile.id,
        userId: 'caregiver-1',
        role: 'caregiver',
        status: 'pending',
        displayName: null,
        invitedBy: 'owner-1',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    final guardians = await repository.getForProfile(profile.id);
    expect(guardians, hasLength(2));
    expect(
      guardians.map((g) => g.userId).toSet(),
      {'owner-1', 'caregiver-1'},
    );
    final owner = guardians.singleWhere((g) => g.userId == 'owner-1');
    expect(owner.role, GuardianRole.primaryGuardian);
    expect(owner.status, GuardianStatus.accepted);
  });

  test('does not return another profile\'s guardian rows', () async {
    final a = await storage.upsertProfile(displayName: 'A', isMinor: false);
    final b = await storage.upsertProfile(displayName: 'B', isMinor: false);
    await storage.applyRemoteRows([
      RemoteProfileGuardianRow(
        id: 'g-a',
        profileId: a.id,
        userId: 'owner-a',
        role: 'primary_guardian',
        status: 'accepted',
        displayName: null,
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);

    expect(await repository.getForProfile(b.id), isEmpty);
    expect((await repository.getForProfile(a.id)).single.userId, 'owner-a');
  });
}
