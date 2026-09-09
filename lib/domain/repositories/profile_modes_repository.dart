/// Repository interface for a profile's life-stage mode row (Issue #188's
/// `profile_modes` storage), surfaced as the persistence seam for Issue
/// #218's onboarding questions: the birth-control-method and goal/mode
/// answers are captured and persisted here — never thrown away — even
/// though their downstream consumers (#233 (PI-10)/#260 birth-control
/// vocabulary and prediction, #192/#196/#204 mode-aware prediction) are
/// separate issues. This interface deliberately defines no new enum: the
/// mode axis is [LifecycleMode] exactly as #188 shipped it, and the birth
/// control method stays free text (bounded by
/// `kMaxBirthControlMethodLength`) until #233/#260 own the vocabulary.
///
/// Concrete drift-backed implementation lives in
/// `lib/data/repositories/drift_profile_modes_repository.dart`.
library;

import '../models/lifecycle_mode.dart';

/// The read shape of a profile's mode row: the life-stage mode (never
/// null — an absent row means [LifecycleMode.tracking], the server's
/// lazy-default contract) plus the optional free-text birth-control
/// method answer.
typedef ProfileLifecycleMode = ({LifecycleMode mode, String? birthControlMethod});

abstract interface class ProfileModesRepository {
  /// Creates or updates the profile's single mode row. Null parameters on
  /// an *update* clear that column (this is a full-row upsert, matching
  /// `LunarLogStorage.upsertProfileMode`'s shape); callers that only want
  /// to change one field read the current row first via [find].
  ///
  /// [modeStartedOn] is the date the mode took effect (today for an
  /// onboarding answer that named a non-default mode; null keeps the
  /// column unset).
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? birthControlMethod,
  });

  /// The profile's mode row, or null when none was ever written (meaning
  /// [LifecycleMode.tracking] with no birth-control answer).
  Future<ProfileLifecycleMode?> find(String profileId);
}
