/// Domain interface for the server-side per-profile erasure RPC
/// (`delete_profile_data`, Issue #264/#472) — a full, permanent purge of
/// one profile, or a scoped purge of just the rows an external import left
/// behind. Deliberately its own seam, not folded into [ProfilesRepository]
/// (`../repositories/profiles_repository.dart`): that repository is
/// storage-only (R14/R16 — no network type crosses it, mirroring every
/// other repository in `lib/domain/repositories/`), while every other
/// network-calling RPC family in this app (account deletion, sharing,
/// ownership transfer, prediction connections) already lives in its own
/// service interface here in `lib/domain/`. `ProfilesRepository
/// .applyServerPurge` is the *local* half this service calls after its own
/// RPC succeeds — see that method's doc comment for why the wipe is reused
/// rather than reinvented.
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary, exactly
/// like [AccountDeletionService][account_deletion_service_link] and
/// [PredictionConnectionService][prediction_connection_service_link] beside
/// it. The implementation lives in `lib/data/profiles/`.
///
/// [account_deletion_service_link]: ../account/account_deletion_service.dart
/// [prediction_connection_service_link]: ../sharing/prediction_connection_service.dart
library;

import 'package:meta/meta.dart';

/// Typed failure thrown by [ProfileErasureService]'s methods. Deliberately
/// fieldless — no message, no code, no server response body — nothing that
/// could carry a raw Supabase error into a crash report, exactly like
/// [AccountDeletionFailure][account_deletion_failure_link] and
/// [PredictionConnectionFailure][prediction_connection_failure_link].
///
/// [account_deletion_failure_link]: ../account/account_deletion_service.dart
/// [prediction_connection_failure_link]: ../sharing/prediction_connection_service.dart
@immutable
sealed class ProfileErasureFailure implements Exception {
  const ProfileErasureFailure();

  /// The request never reached the server (offline, DNS, timeout) — never
  /// delete locally on this failure (see [ProfilesRepository
  /// .applyServerPurge]'s contract).
  const factory ProfileErasureFailure.network() = ProfileErasureNetworkFailure;

  /// The server's `delete_profile_data` RPC refused the call: the caller is
  /// not the named profile's accepted `primary_guardian` (or holds no
  /// session at all). The RPC deliberately raises the identical error for
  /// a nonexistent profile too (enumeration safety), so this case also
  /// covers "that profile id doesn't exist" from this account's point of
  /// view.
  const factory ProfileErasureFailure.unauthorized() =
      ProfileErasureUnauthorizedFailure;

  /// [ProfileErasureService.purgeImportedData]'s `source` was not one of
  /// the server's closed vocabulary — the RPC's own
  /// `invalid_parameter_value` guard.
  const factory ProfileErasureFailure.invalidSource() =
      ProfileErasureInvalidSourceFailure;

  const factory ProfileErasureFailure.other() = ProfileErasureOtherFailure;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ProfileErasureNetworkFailure extends ProfileErasureFailure {
  const ProfileErasureNetworkFailure();
  @override
  String toString() => 'ProfileErasureFailure.network';
}

final class ProfileErasureUnauthorizedFailure extends ProfileErasureFailure {
  const ProfileErasureUnauthorizedFailure();
  @override
  String toString() => 'ProfileErasureFailure.unauthorized';
}

final class ProfileErasureInvalidSourceFailure extends ProfileErasureFailure {
  const ProfileErasureInvalidSourceFailure();
  @override
  String toString() => 'ProfileErasureFailure.invalidSource';
}

final class ProfileErasureOtherFailure extends ProfileErasureFailure {
  const ProfileErasureOtherFailure();
  @override
  String toString() => 'ProfileErasureFailure.other';
}

/// The closed set of import `source` values `purgeImportedData` accepts —
/// the union the server's `delete_profile_data(p_source)` validates against
/// (`supabase/migrations/20260910110000_delete_profile_data.sql`'s header):
/// `day_entries`/`import_jobs` use manual/clue_import/healthkit/
/// health_connect/file_import, `observations` uses manual/apple_health/
/// health_connect/wearable/clue_import. `manual` is deliberately excluded
/// here — a "purge imported data" affordance offering to purge
/// hand-logged entries would contradict its own name, even though the
/// server itself would accept it.
enum PurgeableImportSource {
  clueImport('clue_import', 'Clue import'),
  fileImport('file_import', 'File import'),
  healthkit('healthkit', 'Apple Health (iOS)'),
  healthConnect('health_connect', 'Health Connect (Android)'),
  appleHealthObservations('apple_health', 'Apple Health (measurements)'),
  wearable('wearable', 'Wearable device');

  const PurgeableImportSource(this.wireValue, this.label);

  /// The exact string `delete_profile_data(p_source)` expects.
  final String wireValue;

  /// Display label for the source picker.
  final String label;
}

/// Contract for the server-side per-profile erasure RPC (Issue #264/#472).
abstract interface class ProfileErasureService {
  /// Permanently deletes [profileId] and every row attached to it —
  /// cycle history, care notes, guardian memberships (including
  /// co-guardians'), prediction connections, everything — server-side
  /// first, then (only once that succeeds) the equivalent local Drift
  /// cleanup. Callable only by the profile's accepted `primary_guardian`;
  /// the server enforces this again regardless of what the UI shows.
  ///
  /// Throws [ProfileErasureFailure] on any failure — including
  /// [ProfileErasureFailure.network] while offline — and touches nothing
  /// locally when it throws (the local wipe runs only after the server
  /// call has already succeeded).
  Future<void> deleteProfile({required String profileId});

  /// Purges only [profileId]'s rows whose `source` matches [source] —
  /// the profile itself and every guardian membership survive. Callable
  /// only by the profile's accepted `primary_guardian`, like
  /// [deleteProfile].
  ///
  /// Throws [ProfileErasureFailure] on any failure, including
  /// [ProfileErasureFailure.invalidSource] for a [source] the server does
  /// not recognize (never actually reachable through
  /// [PurgeableImportSource]'s closed enum, but kept typed rather than
  /// silently swallowed).
  Future<void> purgeImportedData({
    required String profileId,
    required PurgeableImportSource source,
  });
}
