/// Repository contract for a profile's guardian rows (R14/R16).
///
/// `lib/ui` needs a live view of a profile's guardians (role gating,
/// attribution badges), but storage row types must not cross into it. This
/// contract speaks only in [ProfileGuardian] models; the Drift-backed
/// implementation lives in `lib/data/repositories/`.
library;

import '../models/profile_guardian.dart';

abstract interface class ProfileGuardiansRepository {
  /// Every guardian row for [profileId], any status, mapped to the domain
  /// model. Callers filter by [ProfileGuardian.status] themselves (e.g. to
  /// an "accepted" subset) — this seam only removes the storage row type,
  /// not the caller's own view logic.
  Stream<List<ProfileGuardian>> watchForProfile(String profileId);

  /// One-shot variant of [watchForProfile] (Issue #153): callers that need
  /// a single read — e.g. resolving a profile's owner for the health-sync
  /// binding picker — rather than a live subscription.
  Future<List<ProfileGuardian>> getForProfile(String profileId);
}
