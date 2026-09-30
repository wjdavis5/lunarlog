/// Everything one render of the activity feed needs, derived at emission
/// time (issue #124). Pure Dart read model: it carries domain types only
/// ([ActivityItem], [ProfileGuardian]) and never a storage row type, so it
/// can cross into `lib/ui`.
library;

import '../models/profile_guardian.dart';
import 'activity_feed.dart';

class ActivityFeedSnapshot {
  const ActivityFeedSnapshot({
    required this.items,
    required this.guardians,
    required this.lastSeen,
    required this.isShared,
  });

  /// Newest first ([buildActivityFeed]).
  final List<ActivityItem> items;

  /// This profile's guardian rows, any status — the source for actor-name
  /// resolution and the viewer read-only gate.
  final List<ProfileGuardian> guardians;

  /// The device-local last-opened stamp, or null when never opened.
  final DateTime? lastSeen;

  /// Whether two or more accepted guardians exist (the feed vs. the
  /// single-guardian quiet state).
  final bool isShared;

  /// Whether any row is newer than [lastSeen] — drives the entry-point
  /// "new" dot. Null [lastSeen] (never opened) is never "new". Gated on
  /// [isShared] the same way the screen is (issue #1216): the
  /// single-guardian quiet state never lists these rows, so a dot earned
  /// on an unshared profile would always open to "Just you for now" —
  /// including after the operator's own every log and every Health
  /// import, teaching the person to ignore the dot for the day it
  /// actually means something.
  bool get hasNewItems => lastSeen != null &&
      isShared &&
      items.any((item) => isActivityNew(item, lastSeen));
}
