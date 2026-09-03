/// Pure conflict rules shared by every sync path (KTD5).
///
/// One rule, two implementations: the server's `sync_push` RPC applies the
/// same decisions in SQL. Timestamps are compared as absolute instants
/// (microsecond precision), never as ISO strings — Postgres renders
/// `.123+00:00` where Dart renders `.123000Z` for the same instant.
library;

/// Compares two instants by absolute time. Zone-insensitive.
int compareInstants(DateTime a, DateTime b) => a
    .toUtc()
    .microsecondsSinceEpoch
    .compareTo(b.toUtc().microsecondsSinceEpoch);

/// Whether [a] and [b] denote the same instant, regardless of rendering.
bool sameInstant(DateTime a, DateTime b) => compareInstants(a, b) == 0;

/// Per-id rule: the remote copy replaces the local one when its
/// `updated_at` is newer **or equal**. On the client the remote copy wins
/// ties so that both sides settle on the server's version (the server keeps
/// its stored copy on ties, and a tombstone pushed with an equal timestamp
/// is the one exception — delete wins that tie on the server).
bool remoteWinsById({
  required DateTime localUpdatedAt,
  required DateTime remoteUpdatedAt,
}) =>
    compareInstants(remoteUpdatedAt, localUpdatedAt) >= 0;

/// The minimum a day entry contributes to the same-date rule.
class DayEntryCandidate {
  const DayEntryCandidate({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;
}

/// Same-date rule among rows for one (profile, local_date): the newer
/// `updated_at` wins; on a tie the lexicographically smaller ULID wins.
/// Tombstones never compete — a live candidate always beats a tombstone,
/// and two tombstones have no winner (`null`). Symmetric in its arguments.
///
/// The loser is to be tombstoned with `deleted_at = updated_at =
/// winner.updated_at` by the caller.
DayEntryCandidate? sameDateWinner(DayEntryCandidate a, DayEntryCandidate b) {
  if (!a.isLive && !b.isLive) return null;
  if (!a.isLive) return b;
  if (!b.isLive) return a;
  final byTime = compareInstants(a.updatedAt, b.updatedAt);
  if (byTime > 0) return a;
  if (byTime < 0) return b;
  return a.id.compareTo(b.id) <= 0 ? a : b;
}
