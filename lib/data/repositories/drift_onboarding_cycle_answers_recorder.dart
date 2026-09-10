/// Drift implementation of the onboarding-answers seam (Issue #216, U3):
/// persists exactly the two answers with landed storage (Issue #188's
/// `profile_modes`), preserving columns it does not own.
///
/// Preservation rules, all regression-tested:
/// * `health_sync_consent` is never clobbered with the default `false`
///   when re-recording over an existing row (#153's groundwork owns it).
/// * `mode_started_on` is kept when the life-stage mode is unchanged and
///   stamped with today only on an actual mode change, so an unrelated
///   edit (a rename) does not rewrite mode history.
/// * The birth-control effective dates ride `birthControlEffectiveDates`'s
///   shared rules (issue #183, in `drift_profile_modes_repository.dart`):
///   re-recording the same method keeps whatever anchor is stored, a
///   method change to a tracked one stamps today, and a non-tracked
///   answer clears both — so this write can never wipe the anchor
///   `DriftProfileModesRepository` wrote for the same answer.
/// * A no-op edit over identical values writes nothing at all — no
///   `local_rev` bump, no dirty flag, nothing for the sync engine to push.
library;

import 'package:lunarlog/data/db/db.dart' show ProfileModeData;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';

class DriftOnboardingCycleAnswersRecorder
    implements OnboardingCycleAnswersRecorder {
  DriftOnboardingCycleAnswersRecorder(this._storage,
      {LocalDate Function()? todayProvider})
      : _today = todayProvider ?? LocalDate.today;

  final LunarLogStorage _storage;
  final LocalDate Function() _today;

  @override
  Future<void> record(String profileId, OnboardingCycleAnswers answers) async {
    final existing = await _storage.getProfileMode(profileId);
    final mode = answers.lifecycleMode.toDb();
    if (!_needsWrite(existing, answers)) return;
    // The effective prior mode: an absent row already means `tracking`
    // (the lazy-default contract), so a birth-control-only answer over no
    // row is not a mode change and stamps nothing.
    final priorMode = existing?.mode ?? 'tracking';
    final (bcStartedOn, bcStoppedOn) = birthControlEffectiveDates(
      existing: existing,
      incomingMethod: answers.birthControlMethod,
      today: _today,
    );
    await _storage.upsertProfileMode(
      profileId: profileId,
      mode: mode,
      // Unchanged mode keeps the recorded start; a change (including a
      // change back to tracking) restarts the clock today.
      modeStartedOn: priorMode == mode ? existing?.modeStartedOn : _today().iso,
      birthControlMethod: answers.birthControlMethod,
      birthControlStartedOn: bcStartedOn,
      birthControlStoppedOn: bcStoppedOn,
      // Never clobbered with the default: the recorder does not own this
      // column (#153's health-sync consent owns it).
      healthSyncConsent: existing?.healthSyncConsent ?? false,
    );
  }

  /// Whether a write is needed at all: no row plus default answers is the
  /// server's lazy-default contract (nothing to store), and an existing
  /// row matching the answers exactly is a no-op edit.
  bool _needsWrite(ProfileModeData? existing, OnboardingCycleAnswers answers) {
    if (existing == null) return answers.hasPersistableAnswers;
    return existing.mode != answers.lifecycleMode.toDb() ||
        existing.birthControlMethod != answers.birthControlMethod;
  }
}
