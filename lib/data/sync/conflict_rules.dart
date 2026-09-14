/// Pure conflict rules shared by every sync path (KTD5).
///
/// One rule, two implementations: the server's `sync_push` RPC applies the
/// same decisions in SQL. Timestamps are compared as absolute instants
/// (microsecond precision), never as ISO strings — Postgres renders
/// `.123+00:00` where Dart renders `.123000Z` for the same instant. The
/// same-date tag merge (Issue #3 gap-closure plan, Unit U4/U5) is a third
/// such rule: [mergeTags] here must compute the identical set union as the
/// server's `public.merge_tag_arrays` SQL function.
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

/// Per-id rule for `profile_guardians` (LLA-035, issue #635): membership
/// status transitions (accept/revoke) are ordered by the server-owned,
/// monotonic `server_version` sequence rather than `updated_at`.
/// `profile_guardians.updated_at` is directly client-writable (a guardian
/// may edit its own `display_name` alongside it), so [remoteWinsById]
/// against it lets an accepted guardian stamp a far-future `updated_at`
/// that permanently outranks a later, authoritative revocation —
/// `server_version` is stamped exclusively by the server's
/// `set_server_version` trigger and always advances forward on every
/// state transition, revocation included, regardless of what any client
/// wrote into `updated_at`. Remote wins ties, same convention as
/// [remoteWinsById].
bool remoteWinsByVersion({
  required int localServerVersion,
  required int remoteServerVersion,
}) =>
    remoteServerVersion >= localServerVersion;

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

/// R7/R9: the set union of two tag lists for the same-date collision path,
/// deduplicated and sorted for a deterministic, order-independent,
/// idempotent result - mirrors the server's `public.merge_tag_arrays` SQL
/// function exactly (KTD4/KTD6). This is the tag rule; it is never applied
/// on the same-id convergence path (R10), where an empty `tags` legitimately
/// means "the user removed these tags". Capped at 32 tags matching
/// `day_entries_tags_check`.
List<String> mergeTags(List<String> a, List<String> b) {
  final merged = {...a, ...b}.toList()..sort();
  if (merged.length > 32) {
    return merged.sublist(0, 32);
  }
  return merged;
}
