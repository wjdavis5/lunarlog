/// The concrete [HealthSyncDeletionService] (Issue #186, AC6): when a
/// bound-profile day entry is tombstoned, its ULID — the recorded external
/// id on both platforms (Health Connect `clientRecordId` / HealthKit
/// `HKMetadataKeyExternalUUID`) — is handed to the platform port's
/// `deleteRecords`, so a deleted lunarlog entry never leaves an orphaned
/// sample in the health store.
///
/// Resolution of the guard facts mirrors `health_flow_write_service.dart`'s
/// `_resolveBound` (the port re-checks per call, natively mirrored, so this
/// pre-flight is purely to avoid issuing a delete the guard would refuse).
/// A deletion is a health-API touch, so it is gated identically to a write.
///
/// Pure Dart (R14/R16); driven by the tombstone coordinator in the same
/// directory, wired in `app.dart` like the write coordinator.
library;

import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';

// The service takes its collaborators as constructor parameters that are not
// initializing formals, the write service's declared pattern.
// ignore_for_file: prefer_initializing_formals

/// Resolves the guardian rows for one profile (the write service's typedef).
typedef GuardiansForProfile = Future<List<ProfileGuardian>> Function(
    String profileId);

class LocalHealthSyncDeletionService implements HealthSyncDeletionService {
  LocalHealthSyncDeletionService({
    required HealthPlatformStore platform,
    required HealthSyncBinding binding,
    required ProfilesRepository profiles,
    required GuardiansForProfile guardiansForProfile,
    required String? Function() signedInUserId,
  })  : _platform = platform,
        _binding = binding,
        _profiles = profiles,
        _guardiansForProfile = guardiansForProfile,
        _signedInUserId = signedInUserId;

  final HealthPlatformStore _platform;
  final HealthSyncBinding _binding;
  final ProfilesRepository _profiles;
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;

  @override
  Future<HealthSyncDeletionReport> deleteSamples(List<String> recordIds) async {
    if (recordIds.isEmpty) {
      return const HealthSyncDeletionReport(attempted: 0, blocked: null);
    }
    final facts = await _resolveBoundFacts();
    if (facts == null) {
      // No bound profile on this device: nothing is deletable (the native
      // guard would refuse every call anyway). Not attempted, not blocked.
      return const HealthSyncDeletionReport(attempted: 0, blocked: null);
    }
    final result = await _platform.deleteRecords(facts, recordIds);
    return HealthSyncDeletionReport(
      attempted: recordIds.length,
      blocked: result is HealthPlatformAllowed ? null : result,
    );
  }

  /// The bound profile plus its guard facts, or null when health sync is
  /// off for this device or the bound profile no longer resolves.
  Future<HealthGuardFacts?> _resolveBoundFacts() async {
    final profileId = await _binding.boundProfileId();
    if (profileId == null) return null;
    final profile = await _profiles.findById(profileId);
    if (profile == null) return null;
    return HealthGuardFacts(
      profile: profile,
      signedInUserId: _signedInUserId(),
      ownerUserId: ownerUserIdFor(await _guardiansForProfile(profileId)),
    );
  }
}
