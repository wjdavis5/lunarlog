/// A [DayEntriesRepository] decorator (issue #543) that lets a test flip a
/// stream that has already been listened to from healthy emissions to a
/// thrown error and back — for asserting that `CyclePredictionService`,
/// `CycleHistoryService`, and `MonthCalendar`'s own entries subscription all
/// surface `StreamBuilder.hasError` as `InlineError` rather than a
/// permanent spinner.
library;

import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

class ErroringDayEntriesRepository implements DayEntriesRepository {
  ErroringDayEntriesRepository(this._inner);

  final DayEntriesRepository _inner;

  /// When true, every subsequent emission on every `watchForProfile` stream
  /// this repository has vended throws instead of delivering entries.
  bool broken = false;

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) => _inner.saveDayEntryWithObservations(
    entry: entry,
    observationsToUpsert: observationsToUpsert,
    observationIdsToDelete: observationIdsToDelete,
  );

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      _inner.find(profileId, localDate);

  @override
  Future<List<DayEntry>> listForProfile(String profileId) =>
      _inner.listForProfile(profileId);

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    return _inner.watchForProfile(profileId, from: from, to: to).map((entries) {
      if (broken) throw StateError('simulated watchForProfile failure');
      return entries;
    });
  }

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  @override
  Future<bool> hasAnyEntries(String profileId) =>
      _inner.hasAnyEntries(profileId);

  @override
  Stream<bool> watchHasAnyEntries(String profileId) =>
      _inner.watchHasAnyEntries(profileId);

  // Issue #130: no merge-notice surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
          String profileId, LocalDate date) async =>
      const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  // Issue #130: no per-profile export surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
          String profileId) async =>
      const [];
}

/// The same decorator for [ActivityFeedRepository] (issue #543's
/// `activity_feed_screen.dart` coverage) — flips a stream that has already
/// been listened to from healthy snapshots to a thrown error and back.
class ErroringActivityFeedRepository implements ActivityFeedRepository {
  ErroringActivityFeedRepository(this._inner);

  final ActivityFeedRepository _inner;

  /// When true, every subsequent emission on every `watch` stream this
  /// repository has vended throws instead of delivering a snapshot.
  bool broken = false;

  @override
  Stream<ActivityFeedSnapshot> watch(String profileId) {
    return _inner.watch(profileId).map((snapshot) {
      if (broken) throw StateError('simulated watch failure');
      return snapshot;
    });
  }

  @override
  Future<void> markSeen(String profileId) => _inner.markSeen(profileId);
}
