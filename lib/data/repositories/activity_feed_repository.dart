/// Repository seam over the derived per-profile activity feed (issue #124).
///
/// Combines the four existing watches — day entries (tombstones included),
/// guardian rows, the device-local merge-event list, and the device-local
/// last-seen stamp — into one [ActivityFeedSnapshot] stream, and stamps
/// "seen" when the feed is opened. Read-only against every synced table;
/// the only writes are the two device-local `app_settings` keys from
/// `lib/domain/activity/merge_events.dart`. No Drift row type crosses the
/// boundary (R14/R16), matching [ProfileGuardiansRepository]'s shape.
library;

import 'dart:async';

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart' as domain;
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart'
    as contract;

class ActivityFeedRepository implements contract.ActivityFeedRepository {
  const ActivityFeedRepository(this._storage);

  final LunarLogStorage _storage;

  /// Emits a snapshot whenever any source changes. The first emission
  /// arrives once all four sources have reported (each `watch*`/`watchSetting`
  /// streams its current value on listen); until then the stream is silent
  /// and the UI shows its waiting state. Because the underlying Drift
  /// streams re-emit on every write, a change another guardian pushed and
  /// this device synced appears here without any restart (issue #124 AC3).
  @override
  Stream<ActivityFeedSnapshot> watch(String profileId) {
    late StreamController<ActivityFeedSnapshot> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    var entries = const <domain.DayEntry>[];
    var guardians = const <domain.ProfileGuardian>[];
    var mergeEvents = const <MergeEvent>[];
    DateTime? lastSeen;
    var entriesReady = false;
    var guardiansReady = false;
    var mergeEventsReady = false;
    var lastSeenReady = false;

    void emit() {
      if (!entriesReady || !guardiansReady || !mergeEventsReady || !lastSeenReady) {
        return;
      }
      final data = buildActivityFeed(
        entries: entries,
        guardians: guardians,
        mergeEvents: mergeEvents,
      );
      controller.add(ActivityFeedSnapshot(
        items: data.items,
        guardians: guardians,
        lastSeen: lastSeen,
        isShared: data.isShared,
      ));
    }

    controller = StreamController<ActivityFeedSnapshot>(
      onListen: () {
        subscriptions.add(
          _storage
              .watchDayEntries(profileId: profileId, includeTombstones: true)
              .listen((rows) {
            entries = [for (final row in rows) dayEntryToDomain(row)];
            entriesReady = true;
            emit();
          }),
        );
        subscriptions.add(
          _storage.watchGuardiansForProfile(profileId).listen((rows) {
            guardians = [for (final row in rows) profileGuardianToDomain(row)];
            guardiansReady = true;
            emit();
          }),
        );
        subscriptions.add(
          _storage
              .watchSetting(activityMergeEventsKey(profileId))
              .listen((stored) {
            mergeEvents = decodeMergeEvents(stored);
            mergeEventsReady = true;
            emit();
          }),
        );
        subscriptions.add(
          _storage.watchSetting(activityLastSeenKey(profileId)).listen((stored) {
            lastSeen = stored == null ? null : DateTime.tryParse(stored);
            lastSeenReady = true;
            emit();
          }),
        );
      },
      onCancel: () => Future.wait(
        [for (final subscription in subscriptions) subscription.cancel()],
      ),
    );
    return controller.stream;
  }

  /// Stamps this device's "feed opened" instant for [profileId] (R8). The
  /// caller snapshots the *previous* value for its in-visit "New" chips
  /// before this overwrites it.
  @override
  Future<void> markSeen(String profileId) => _storage.setSetting(
        key: activityLastSeenKey(profileId),
        value: DateTime.now().toUtc().toIso8601String(),
      );
}
