/// Cycle-history service (issue #132): [CycleHistoryView]s as a map over
/// the same combined stream shape the prediction service uses — day
/// entries plus the device-local omission list. Pure recompute per
/// emission; nothing derived is persisted (KTD5's shape, extended).
library;

import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';
import '../repositories/settings_store.dart';
import '../util/combine_latest.dart';
import 'cycle_history.dart';

class CycleHistoryService {
  CycleHistoryService(this._dayEntries, {SettingsStore? settings})
    : _exclusions = settings == null ? null : CycleExclusionList(settings);

  final DayEntriesRepository _dayEntries;
  final CycleExclusionList? _exclusions;

  /// Emits the profile's history view now and again on every entry write
  /// or omission-list change. [today] is evaluated per emission, matching
  /// [CyclePredictionService.watch] — issue #213's confidence tier needs a
  /// "today" the same way the estimate itself always has, so the history
  /// badge stays derived from the same engine; it defaults to the local
  /// civil date.
  Stream<CycleHistoryView> watch(
    String profileId, {
    LocalDate Function()? today,
  }) {
    final todayOf = today ?? LocalDate.today;
    final entries = _dayEntries.watchForProfile(profileId);
    final exclusions = _exclusions;
    if (exclusions == null) {
      return entries.map(
        (list) => deriveCycleHistoryFromEntries(
          entries: list,
          today: todayOf(),
        ),
      );
    }
    return combineLatest2(entries, exclusions.watch(profileId)).map(
      (latest) => deriveCycleHistoryFromEntries(
        entries: latest.$1,
        today: todayOf(),
        omittedCycleStarts: latest.$2,
      ),
    );
  }

  /// One-shot computation from current stored entries.
  Future<CycleHistoryView> current(
    String profileId, {
    LocalDate Function()? today,
  }) async {
    final todayOf = today ?? LocalDate.today;
    final exclusions = _exclusions;
    final omissions = exclusions == null
        ? const <LocalDate>{}
        : await exclusions.load(profileId);
    return deriveCycleHistoryFromEntries(
      entries: await _dayEntries.listForProfile(profileId),
      today: todayOf(),
      omittedCycleStarts: omissions,
    );
  }
}
