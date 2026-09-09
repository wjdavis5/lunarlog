/// Drift-backed [ObservationsRepository] over U2's storage layer (Issue
/// #240). Every storage call is scoped to exactly one profile id (R3),
/// mirroring [DriftDayEntriesRepository].
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/repositories/observations_repository.dart';

import 'mappers.dart';

class DriftObservationsRepository implements ObservationsRepository {
  DriftObservationsRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<List<domain.Observation>> listForProfile(String profileId) async => [
        for (final row in await _storage.getObservationsForProfile(profileId))
          observationToDomain(row),
      ];
}
