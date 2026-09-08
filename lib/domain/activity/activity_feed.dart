/// The per-profile activity feed, derived (issue #124).
///
/// Everything here is computed at read time from what the schema already
/// holds — `day_entries.logged_by_user_id` / `last_modified_by_user_id` /
/// `updated_at`, `profile_guardians` rows, and the device-local
/// [MergeEvent]s — so there is no new attribution model and no new synced
/// state (issue #124's "no new attribution model" constraint).
///
/// Honest about what is knowable (same constraint): the schema records only
/// the latest modifier per row, so the feed is one row per day entry — its
/// latest state — never one row per historical edit. "Updated by X" is
/// asserted only where the stamps themselves say so (a modifier differing
/// from the logger); X editing X's own entry reads "Logged by X" because
/// nothing in the data can tell those apart, and no fake audit trail is
/// built to paper over it.
///
/// Pure Dart (R14/R16): no Flutter, no drift.
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/profile_guardian.dart';
import 'merge_events.dart';

/// What a feed row says happened. Entry rows come from a day entry's
/// attribution stamps (KTD4); the rest come from the device-local records.
enum ActivityKind {
  /// A day entry whose latest write is its own creation (logger and last
  /// modifier agree, or the row is unattributed).
  logged,

  /// A live day entry whose last modifier differs from its logger.
  updated,

  /// A tombstoned day entry.
  removed,

  /// A same-date/push-resolution collision that discarded a value
  /// (device-local [MergeEvent]).
  mergeOutcome,

  /// A guardian's access to the profile was revoked.
  accessRemoved,
}

/// One rendered feed row. Carries ids and facts, never names (names are
/// resolved at render time so a display-name change is reflected
/// everywhere) and never note text or tag codes (content discretion).
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.kind,
    required this.occurredAt,
    this.localDateIso,
    this.actorId,
    this.secondaryActorId,
    this.flow,
    this.tagCount = 0,
    this.hasNote = false,
    this.discardedNote = false,
    this.discardedFlow = false,
  });

  /// Stable row identity for keys and de-duplication:
  /// `entry:<row id>`, `merge:<event id>`, or `guardian:<row id>`.
  final String id;

  final ActivityKind kind;

  /// Ordering stamp: the entry's `updated_at` or the event's `occurredAt`.
  final DateTime occurredAt;

  /// The ISO date the entry is *for*; null only for [ActivityKind.accessRemoved].
  final String? localDateIso;

  /// Who the row is about: the change's author for entry rows, the kept
  /// writer for merges, the removed guardian for access rows. Null when the
  /// row carries no attribution — rendered without an actor phrase, never
  /// invented (issue #124 AC on legacy rows).
  final String? actorId;

  /// Secondary actor: the original logger on `updated` rows, the discarded
  /// writer on merge rows.
  final String? secondaryActorId;

  /// Current flow of a live entry (calendar-glance level). Null for removed
  /// rows — a deleted day must not restate health detail the calendar no
  /// longer shows.
  final FlowLevel? flow;

  /// Number of tags on a live entry. Count only, never the codes.
  final int tagCount;

  /// Whether a live entry carries a note. Boolean only, never the text.
  final bool hasNote;

  /// Merge rows: whether the discard dropped a note / flow value.
  final bool discardedNote;
  final bool discardedFlow;
}

/// The derived feed plus the sharing facts the UI branches on.
class ActivityFeedData {
  const ActivityFeedData({required this.items, required this.isShared});

  /// Newest first, capped at [limit].
  final List<ActivityItem> items;

  /// Whether at least two guardians hold *accepted* rows — the gate for the
  /// feed vs. the single-guardian quiet state (R6). Empty guardian input
  /// (local-only, or not yet synced) is not shared.
  final bool isShared;
}

/// Builds the whole feed from its sources. Pure; every input is data the
/// caller already holds. Sorts newest first (id as the deterministic
/// tiebreak) and caps at [limit] rows.
ActivityFeedData buildActivityFeed({
  required List<DayEntry> entries,
  required List<ProfileGuardian> guardians,
  required List<MergeEvent> mergeEvents,
  int limit = 200,
}) {
  final accepted = guardians
      .where((g) => g.status == GuardianStatus.accepted)
      .toList(growable: false);
  final items = <ActivityItem>[
    for (final entry in entries) _entryItem(entry),
    for (final event in mergeEvents) _mergeItem(event),
    for (final guardian in guardians)
      if (guardian.status == GuardianStatus.revoked) _guardianItem(guardian),
  ]..sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  return ActivityFeedData(
    items: items.length > limit ? items.sublist(0, limit) : items,
    isShared: accepted.length >= 2,
  );
}

/// Classifies one day entry from its attribution stamps (KTD4, mirroring
/// `sync_push`'s own stamping: insert stamps logger and modifier with the
/// writer; update re-stamps only the modifier).
ActivityItem _entryItem(DayEntry entry) {
  final tombstone = entry.deletedAt != null;
  final modifier = entry.lastModifiedByUserId;
  final logger = entry.loggedByUserId;
  final editedByOther = _editedByOther(
      tombstone: tombstone, modifier: modifier, logger: logger);
  return ActivityItem(
    id: 'entry:${entry.id}',
    kind: _entryKind(tombstone: tombstone, editedByOther: editedByOther),
    occurredAt: entry.updatedAt,
    localDateIso: entry.localDate.iso,
    // The modifier is the author of the latest write — the delete included,
    // since the server re-stamps it on the delete push. Falls back to the
    // logger for pre-attribution rows pulled with only that stamp, and to
    // null for legacy/offline rows (rendered actor-less).
    actorId: _entryActor(
        editedByOther: editedByOther, modifier: modifier, logger: logger),
    secondaryActorId: editedByOther ? logger : null,
    flow: tombstone ? null : entry.flow,
    tagCount: tombstone ? 0 : entry.tags.length,
    hasNote: !tombstone && entry.note != null && entry.note!.isNotEmpty,
  );
}

/// Whether the latest write was made by someone other than the original
/// logger — the only thing the stamps can prove about "updated".
bool _editedByOther({
  required bool tombstone,
  required String? modifier,
  required String? logger,
}) =>
    !tombstone && modifier != null && logger != null && modifier != logger;

ActivityKind _entryKind({
  required bool tombstone,
  required bool editedByOther,
}) =>
    tombstone
        ? ActivityKind.removed
        : editedByOther
            ? ActivityKind.updated
            : ActivityKind.logged;

String? _entryActor({
  required bool editedByOther,
  required String? modifier,
  required String? logger,
}) =>
    editedByOther ? modifier : (modifier ?? logger);

ActivityItem _mergeItem(MergeEvent event) => ActivityItem(
      id: 'merge:${event.id}',
      kind: ActivityKind.mergeOutcome,
      occurredAt: event.occurredAt,
      localDateIso: event.localDateIso,
      actorId: event.winnerActorId,
      secondaryActorId: event.loserActorId,
      discardedNote: event.discardedNote,
      discardedFlow: event.discardedFlow,
    );

ActivityItem _guardianItem(ProfileGuardian guardian) => ActivityItem(
      id: 'guardian:${guardian.id}',
      kind: ActivityKind.accessRemoved,
      occurredAt: guardian.updatedAt,
      actorId: guardian.userId,
    );

/// Resolves a user id for display, mirroring the attribution badge's ladder
/// (issue #124): `you` for the current user, then the guardian's display
/// name, then the role label, then the neutral "a guardian" — and null for
/// a null id, so an unattributed row renders without an actor phrase and a
/// raw uuid is never shown. Names come from guardian rows of any status: a
/// revoked guardian's own past entries still deserve their name.
String? activityActorLabel(
  String? userId,
  String? currentUserId,
  List<ProfileGuardian> guardians,
) {
  if (userId == null) return null;
  if (currentUserId != null && userId == currentUserId) return 'you';
  for (final guardian in guardians) {
    if (guardian.userId == userId) {
      final name = guardian.displayName;
      if (name != null && name.isNotEmpty) return name;
      return guardian.role.label;
    }
  }
  return 'a guardian';
}

/// Whether [item] is newer than the device-local [lastSeen] stamp (R8). A
/// null stamp — this device never opened the feed — marks nothing new: the
/// first visit baselines everything as already seen rather than painting
/// the entire history "New".
bool isActivityNew(ActivityItem item, DateTime? lastSeen) =>
    lastSeen != null && item.occurredAt.isAfter(lastSeen);

/// Compact relative age for a change stamp: "just now", "5m ago", "3h ago",
/// "2d ago", then an absolute local date once a week out. [now] is injected
/// so tests are deterministic.
String relativeActivityAge(DateTime at, DateTime Function() now) {
  final age = now().toUtc().difference(at.toUtc());
  if (age.isNegative || age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes}m ago';
  if (age.inDays < 1) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
