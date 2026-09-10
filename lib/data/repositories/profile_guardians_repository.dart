/// Thin repository seam over guardian rows for a profile (R14/R16):
/// `lib/ui/` needs a live view of a profile's guardians (role gating for
/// U8, attribution badges), but Drift row types must not cross into it.
/// This wraps [LunarLogStorage]'s existing public watch query and maps
/// each row to the domain model at the boundary — no new storage API, no
/// schema knowledge, just the mapping [manage_guardians_screen.dart] and
/// [month_calendar.dart] used to do for themselves (finding #11).
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    as domain;

class ProfileGuardiansRepository
    implements domain.ProfileGuardiansRepository {
  const ProfileGuardiansRepository(this._storage);

  final LunarLogStorage _storage;

  /// Every guardian row for [profileId], any status, mapped to the domain
  /// model. Callers filter by [ProfileGuardian.status] themselves (e.g. to
  /// an "accepted" subset) — this seam only removes the Drift row type,
  /// not the caller's own view logic.
  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      _storage
          .watchGuardiansForProfile(profileId)
          .map((rows) => rows.map(profileGuardianToDomain).toList());

  /// One-shot variant of [watchForProfile] (Issue #153): callers that need
  /// a single read — e.g. resolving a profile's owner for the health-sync
  /// binding picker — rather than a live subscription.
  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async {
    final rows = await _storage.getGuardiansForProfile(profileId);
    return rows.map(profileGuardianToDomain).toList();
  }
}
