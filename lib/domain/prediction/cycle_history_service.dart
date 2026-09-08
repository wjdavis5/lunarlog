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
  /// or omission-list change.
  Stream<CycleHistoryView> watch(String profileId) {
    final entries = _dayEntries.watchForProfile(profileId);
    final exclusions = _exclusions;
    if (exclusions == null) {
      return entries.map(
        (list) => deriveCycleHistoryFromEntries(entries: list),
      );
    }
    return combineLatest2(entries, exclusions.watch(profileId)).map(
      (latest) => deriveCycleHistoryFromEntries(
        entries: latest.$1,
        omittedCycleStarts: latest.$2,
      ),
    );
  }

  /// One-shot computation from current stored entries.
  Future<CycleHistoryView> current(String profileId) async {
    final exclusions = _exclusions;
    final omissions = exclusions == null
        ? const <LocalDate>{}
        : await exclusions.load(profileId);
    return deriveCycleHistoryFromEntries(
      entries: await _dayEntries.listForProfile(profileId),
      omittedCycleStarts: omissions,
    );
  }
}
