/// Repository interfaces (R14/R16): the UI consumes these and the domain
/// models only — storage types never cross this boundary. Concrete
/// drift-backed implementations live in `lib/data/repositories/`.
library;

import '../models/profile.dart';
import '../models/profile_relationship.dart';

abstract interface class ProfilesRepository {
  /// Creates a new profile (id assigned by storage). [birthYear] and
  /// [relationship] are optional, display/context-only subject metadata
  /// (Issue #4 R1, R2, R3); neither is validated beyond the closed set
  /// [ProfileRelationship] already enforces.
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder,
    int? birthYear,
    ProfileRelationship? relationship,
  });

  /// Persists edits to an existing profile (matched by id). Throws
  /// [ArgumentError] when the model carries no id.
  Future<Profile> update(Profile profile);

  /// The live (non-tombstoned) profile by id, or null.
  Future<Profile?> findById(String id);

  /// Live profiles ordered by sortOrder then id. Archived profiles are
  /// included (filter on `archivedAt` in the UI); tombstoned are not.
  Future<List<Profile>> list();

  /// Reactive variant of [list].
  Stream<List<Profile>> watch();

  /// Sets or clears the archive flag. Throws [StateError] for unknown or
  /// tombstoned profiles.
  Future<void> setArchived(String id, bool archived);

  /// Tombstones the profile (soft delete; never row removal).
  Future<void> delete(String id);
}
