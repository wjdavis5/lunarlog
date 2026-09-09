/// Drift-backed [ProfileModesRepository] (Issue #218's persistence seam
/// over Issue #188's `profile_modes` storage): the one-call surface #216's
/// onboarding form and the profile-settings editor use to persist the
/// birth-control-method and goal/mode answers.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';

class DriftProfileModesRepository implements ProfileModesRepository {
  DriftProfileModesRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? birthControlMethod,
  }) =>
      _storage.upsertProfileMode(
        profileId: profileId,
        mode: mode.toDb(),
        modeStartedOn: modeStartedOn,
        birthControlMethod: birthControlMethod,
      );

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async {
    final row = await _storage.getProfileMode(profileId);
    if (row == null) return null;
    return (
      mode: LifecycleMode.fromDb(row.mode),
      birthControlMethod: row.birthControlMethod,
    );
  }
}
