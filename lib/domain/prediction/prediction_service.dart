/// Prediction service: computes [CyclePrediction]s as a map over day-entry
/// repository streams. Nothing is persisted and no write path triggers
/// computation (KTD5) — consumers subscribe, writes re-derive.
///
/// Issue #132: when a [SettingsStore] is injected, the device-local
/// omission list (`omittedCycles.<profileId>`, KTD2) joins the combine —
/// every estimate is re-derived when the operator omits or restores a
/// cycle, and the reminder coordinator and reminder-window publisher
/// (which consume [watch]) replan with it for free.
library;

import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';
import '../repositories/settings_store.dart';
import '../util/combine_latest.dart';
import 'cycle_history.dart';
import 'prediction.dart';

class CyclePredictionService {
  CyclePredictionService(this._dayEntries, {SettingsStore? settings})
      : _exclusions = settings == null ? null : CycleExclusionList(settings);

  final DayEntriesRepository _dayEntries;
  final CycleExclusionList? _exclusions;

  /// Recomputed on every emission of the profile's day-entry stream and,
  /// when a settings store is wired, of the profile's omission-list key.
  /// [today] is evaluated per emission so long-lived subscriptions stay
  /// correct across midnight; it defaults to the local civil date.
  Stream<CyclePrediction> watch(String profileId,
      {LocalDate Function()? today}) {
    final todayOf = today ?? LocalDate.today;
    final entries = _dayEntries.watchForProfile(profileId);
    final exclusions = _exclusions;
    if (exclusions == null) {
      return entries.map(
        (list) => computePredictionFromEntries(
          entries: list,
          today: todayOf(),
        ),
      );
    }
    return combineLatest2(entries, exclusions.watch(profileId)).map(
      (latest) => computePredictionFromEntries(
        entries: latest.$1,
        today: todayOf(),
        omittedCycleStarts: latest.$2,
      ),
    );
  }

  /// One-shot computation from current stored entries (and the current
  /// omission list, when settings are wired).
  Future<CyclePrediction> current(String profileId,
      {LocalDate Function()? today}) async {
    final todayOf = today ?? LocalDate.today;
    final exclusions = _exclusions;
    final omissions = exclusions == null
        ? const <LocalDate>{}
        : await exclusions.load(profileId);
    return computePredictionFromEntries(
      entries: await _dayEntries.listForProfile(profileId),
      today: todayOf(),
      omittedCycleStarts: omissions,
    );
  }
}
