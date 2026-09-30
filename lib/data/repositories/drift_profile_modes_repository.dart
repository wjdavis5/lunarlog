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
///   cadence — with two exceptions:
///   - Issue #1203: an operator-picked [incomingStartedOn] on a tracked
///     method replaces the stored start (and clears `stopped_on` — a
///     recorded start says the method is in effect from that day). This
///     is how the Edit profile sheet's "Started on" field writes the
///     *true* date instead of the workaround's assumed-today stamp.
///   - when a tracked method has *no* start date at all (a row written
///     before issue #183's anchoring existed) and no explicit date was
///     picked, a write stamps today, giving the adherence cadence an
///     anchor it could never otherwise acquire. "A write", not "a save":
///     the onboarding recorder's no-op gate (`_needsWrite`) performs no
///     write at all for an untouched Save, so through that writer the
///     stamp lands on the first save that actually changes something —
///     the doc comment previously promised "the first save through either
///     writer", which the no-op gate never let come true from the UI
///     (issue #1203's reconciliation of the two claims);
/// * a method that changes *to a tracked one* stamps `started_on` with
///   the picked [incomingStartedOn] when the writer supplies one, today
///   otherwise, and clears `stopped_on` — the new method is in effect
///   from that day, and the date is the anchor the patch/ring/shot due
///   dates count from;
/// * a method that changes *to a non-tracked answer* (or is cleared)
///   clears both — nothing is in effect, so there is nothing to anchor.
///
/// [incomingStartedOn] is ignored for a non-tracked answer: a start date
/// without a tracked method means nothing (the Edit profile sheet only
/// offers the field for tracked methods; a stray value from another
/// caller must not sneak an anchor into a non-tracked row).
(String?, String?) birthControlEffectiveDates({
  required ProfileModeData? existing,
  required String? incomingMethod,
  String? incomingStartedOn,
  required LocalDate Function() today,
}) {
  final newMethod = BirthControlMethod.fromDb(incomingMethod);
  final oldMethod = BirthControlMethod.fromDb(existing?.birthControlMethod);
  if (newMethod == oldMethod) {
    if (newMethod != null && newMethod.isTracked) {
      if (incomingStartedOn != null) {
        return (incomingStartedOn, null);
      }
      final startedOn = existing?.birthControlStartedOn;
      if (startedOn == null) {
        return (today().iso, null);
      }
    }
    return (
      existing?.birthControlStartedOn,
      existing?.birthControlStoppedOn,
    );
  }
  if (newMethod != null && newMethod.isTracked) {
    return (incomingStartedOn ?? today().iso, null);
  }
  return (null, null);
}

class DriftProfileModesRepository implements ProfileModesRepository {
  DriftProfileModesRepository(this._storage, {LocalDate Function()? todayProvider})
      : _today = todayProvider ?? LocalDate.today;

  final CycleStore _storage;
  final LocalDate Function() _today;

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
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
      estimatedDueDate: estimatedDueDate,
      postpartumBirthDate: postpartumBirthDate,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: startedOn,
      birthControlStoppedOn: stoppedOn,
    );
  }

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async {
    final row = await _storage.getProfileMode(profileId);
    return _toDomain(row);
  }

  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) =>
      _storage.watchProfileMode(profileId).map(_toDomain);

  ProfileLifecycleMode? _toDomain(ProfileModeData? row) => row == null
      ? null
      : (
          mode: LifecycleMode.fromDb(row.mode),
          modeStartedOn: row.modeStartedOn,
          estimatedDueDate: row.estimatedDueDate,
          postpartumBirthDate: row.postpartumBirthDate,
          birthControlMethod: row.birthControlMethod,
          birthControlStartedOn: row.birthControlStartedOn,
          birthControlStoppedOn: row.birthControlStoppedOn,
        );
}
