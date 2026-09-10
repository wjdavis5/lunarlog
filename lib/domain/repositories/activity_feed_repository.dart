/// Repository contract for a profile's derived activity feed (issue #124).
///
/// Combines day entries, guardian rows, device-local merge events, and the
/// device-local last-seen stamp into one [ActivityFeedSnapshot] stream, and
/// stamps "seen" when the feed is opened. The Drift-backed implementation
/// lives in `lib/data/repositories/`.
library;

import '../activity/activity_feed_snapshot.dart';

abstract interface class ActivityFeedRepository {
  /// Emits a snapshot whenever any source changes. The first emission
  /// arrives once all sources have reported; until then the stream is
  /// silent and the UI shows its waiting state.
  Stream<ActivityFeedSnapshot> watch(String profileId);

  /// Stamps this device's "feed opened" instant for [profileId]. The caller
  /// snapshots the *previous* value for its in-visit "New" chips before
  /// this overwrites it.
  Future<void> markSeen(String profileId);
}
