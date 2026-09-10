/// Drift-backed [ProfileModesRepository] (Issue #218's persistence seam
/// over Issue #188's `profile_modes` storage): the one-call surface #216's
/// onboarding form and the profile-settings editor use to persist the
/// birth-control-method and goal/mode answers.
///
/// Issue #183: this save also owns the birth-control effective dates the
/// adherence reminders anchor on (`birth_control_started_on`/
/// `birth_control_stopped_on`, issue #260's columns), via
/// [birthControlEffectiveDates] — the same rules the onboarding recorder
/// applies, so neither writer can wipe the other's anchor. The raw
/// columns stay writable only through `LunarLogStorage.upsertProfileMode`
/// for the callers that own them (the sync pull).
library;

import 'package:lunarlog/data/db/db.dart' show ProfileModeData;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';

/// The birth-control effective-date pair (`birth_control_started_on`/
/// `birth_control_stopped_on`) a save of [incomingMethod] writes given the
/// [existing] row — the one set of rules both answer writers (the
/// repository's [DriftProfileModesRepository.save] and the onboarding
/// recorder) share, so no writer can wipe the other's anchor:
///
/// * an unchanged recorded method (compared through
///   [BirthControlMethod.fromDb], so a legacy spelling equals its
///   canonical id) keeps both dates exactly as stored — an unrelated edit
///   never rewrites method history and never restarts the reminder
///   cadence — except when a tracked method has *no* start date at all (a
///   row written before issue #183's anchoring existed): the first save
///   through either writer stamps today, giving the adherence cadence an
///   anchor it could never otherwise acquire;
/// * a method that changes *to a tracked one* stamps `started_on` with
///   today and clears `stopped_on` — the new method is in effect from
///   today, and that date is the anchor the patch/ring/shot due dates
///   count from;
/// * a method that changes *to a non-tracked answer* (or is cleared)
///   clears both — nothing is in effect, so there is nothing to anchor.
(String?, String?) birthControlEffectiveDates({
  required ProfileModeData? existing,
  required String? incomingMethod,
  required LocalDate Function() today,
}) {
  final newMethod = BirthControlMethod.fromDb(incomingMethod);
  final oldMethod = BirthControlMethod.fromDb(existing?.birthControlMethod);
  if (newMethod == oldMethod) {
    final startedOn = existing?.birthControlStartedOn;
    if (newMethod != null && newMethod.isTracked && startedOn == null) {
      return (today().iso, null);
    }
    return (startedOn, existing?.birthControlStoppedOn);
  }
  if (newMethod != null && newMethod.isTracked) {
    return (today().iso, null);
  }
  return (null, null);
}

class DriftProfileModesRepository implements ProfileModesRepository {
  DriftProfileModesRepository(this._storage, {LocalDate Function()? todayProvider})
      : _today = todayProvider ?? LocalDate.today;

  final LunarLogStorage _storage;
  final LocalDate Function() _today;

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? birthControlMethod,
  }) async {
    final existing = await _storage.getProfileMode(profileId);
    final (startedOn, stoppedOn) = birthControlEffectiveDates(
      existing: existing,
      incomingMethod: birthControlMethod,
      today: _today,
    );
    await _storage.upsertProfileMode(
      profileId: profileId,
      mode: mode.toDb(),
      modeStartedOn: modeStartedOn,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: startedOn,
      birthControlStoppedOn: stoppedOn,
    );
  }

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async {
    final row = await _storage.getProfileMode(profileId);
    if (row == null) return null;
    return (
      mode: LifecycleMode.fromDb(row.mode),
      birthControlMethod: row.birthControlMethod,
      birthControlStartedOn: row.birthControlStartedOn,
      birthControlStoppedOn: row.birthControlStoppedOn,
    );
  }
}
