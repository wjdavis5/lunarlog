/// Repository interfaces (R14/R16): the UI consumes these and the domain
/// models only — storage types never cross this boundary. Concrete
/// drift-backed implementations live in `lib/data/repositories/`.
library;

import '../logging/tracking_preferences.dart';
import '../models/local_date.dart';
import '../models/measurement_unit.dart';
import '../models/profile.dart';
import '../models/profile_mode.dart';
import '../models/profile_relationship.dart';

abstract interface class ProfilesRepository {
  /// Creates a new profile (id assigned by storage). [birthYear] and
  /// [relationship] are optional, display/context-only subject metadata
  /// (Issue #4 R1, R2, R3); neither is validated beyond the closed set
  /// [ProfileRelationship] already enforces. [mode] (Issue #131) is the
  /// profile's care mode — presentation only, defaulting to
  /// [ProfileMode.standard]. The three cycle facts (Issue #218) are the
  /// onboarding-supplied answers stored on the profile and editable later
  /// through [update]; all individually optional (skipped questions are
  /// null), and never validated here — `CycleFacts.canSeed` in the
  /// prediction domain is the gate that decides which values can seed a
  /// provisional estimate. [bbtUnit]/[weightUnit] (Issue #255) are the
  /// per-profile display-unit preferences for numeric measurements,
  /// defaulting to metric (`BbtUnit.celsius`/`WeightUnit.kg`) — editable
  /// later through [update], and always a rendering preference only (each
  /// stored `observations` value keeps the unit it was entered in).
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder,
    ProfileMode mode,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit,
    WeightUnit weightUnit,
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

  /// Writes (or clears) the profile's tracking-preferences document
  /// (Issue #259): [preferences] is the curated set the day sheet reads,
  /// or null to clear back to "never customized". Touches only that
  /// column (plus the usual sync bookkeeping) — an ordinary metadata edit
  /// must never restamp or clobber a co-guardian's curated document, and
  /// this write marks the row dirty so the document syncs (AC1/AC6).
  /// Returns the updated profile, or null when [id] is unknown or
  /// tombstoned. [preferences.toJsonText]'s null (nothing to store) and
  /// an empty document are accepted as the same "clear" instruction.
  /// Throws [ArgumentError] when the document does not serialize to a
  /// JSON object (it always does from a well-formed
  /// [TrackingPreferences]; the check guards programmatic misuse).
  Future<Profile?> setTrackingPreferences(
    String id,
    TrackingPreferences? preferences,
  );
}
