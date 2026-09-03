/// The transport seam between the sync engine and the server (U10; KTD2,
/// KTD3, KTD6): one push RPC and one paged, cursor-filtered pull per table.
/// Rows cross this boundary JSON-ready (see `row_codec.dart`) on the way
/// out and as parsed [RemoteRow]s on the way in, so the engine never sees
/// a `SupabaseClient` and `FakeSyncTransport` can stand in for one.
///
/// Every failure is a [SyncTransportError] *kind* — never the provider's
/// message, code or body (R18).
library;

import 'package:meta/meta.dart';

import 'remote_rows.dart';
import 'row_codec.dart' show JsonRow;

/// One `sync_push` call: profiles then day entries, each at most
/// [maxRows] rows (the RPC raises `22023` beyond that). Rows are the
/// codec's JSON objects, already validated.
@immutable
class PushBatch {
  PushBatch({
    List<JsonRow> profiles = const [],
    List<JsonRow> dayEntries = const [],
  })  : profiles = List.unmodifiable(profiles),
        dayEntries = List.unmodifiable(dayEntries) {
    if (profiles.length > maxRows) {
      throw ArgumentError.value(profiles.length, 'profiles',
          'a push batch carries at most $maxRows profiles');
    }
    if (dayEntries.length > maxRows) {
      throw ArgumentError.value(dayEntries.length, 'dayEntries',
          'a push batch carries at most $maxRows day entries');
    }
  }

  /// The RPC's per-array limit (KTD3).
  static const int maxRows = 500;

  final List<JsonRow> profiles;
  final List<JsonRow> dayEntries;

  int get rowCount => profiles.length + dayEntries.length;

  bool get isEmpty => rowCount == 0;

  @override
  String toString() =>
      'PushBatch(profiles: ${profiles.length}, dayEntries: ${dayEntries.length})';
}

/// What `sync_push` answered (KTD3).
@immutable
class PushResult {
  PushResult({
    required List<RemoteRow> resolved,
    required List<String> rejectedIds,
    required this.serverNow,
  })  : resolved = List.unmodifiable(resolved),
        rejectedIds = List.unmodifiable(rejectedIds);

  /// The server's current copy of every row it tombstoned by resolution
  /// and of every incoming row it declined — apply with `dirty = false`.
  final List<RemoteRow> resolved;

  /// Ids of rows the server rejected outright (validation, constraint or
  /// RLS failure, opaque by design). They stay dirty on the device.
  final List<String> rejectedIds;

  /// The server's clock at the call (UTC): `server_now - device_now` is
  /// the offset the storage clock applies (KTD4).
  final DateTime serverNow;

  @override
  String toString() =>
      'PushResult(resolved: ${resolved.length}, rejected: ${rejectedIds.length})';
}

/// Typed transport failure. Fieldless except [SyncTransportRejectedError],
/// which carries ids only.
@immutable
sealed class SyncTransportError implements Exception {
  const SyncTransportError();

  /// No usable session: the request was refused as unauthenticated or the
  /// token could not be refreshed. Sync needs a sign-in.
  const factory SyncTransportError.auth() = SyncTransportAuthError;

  /// The server could not be reached or was unavailable (offline, DNS,
  /// timeout, 5xx, rate-limited). Retry with backoff.
  const factory SyncTransportError.network() = SyncTransportNetworkError;

  /// A transport that cannot report partial results row-by-row rejected
  /// these ids. `SupabaseSyncTransport` never throws this — the RPC
  /// reports rejections in [PushResult.rejectedIds] — but fakes and future
  /// transports may.
  const factory SyncTransportError.rejected(List<String> ids) =
      SyncTransportRejectedError;

  /// Everything else: a malformed response, a client-side bug (batch too
  /// large), an unexpected status.
  const factory SyncTransportError.other() = SyncTransportOtherError;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class SyncTransportAuthError extends SyncTransportError {
  const SyncTransportAuthError();

  @override
  String toString() => 'SyncTransportError.auth';
}

final class SyncTransportNetworkError extends SyncTransportError {
  const SyncTransportNetworkError();

  @override
  String toString() => 'SyncTransportError.network';
}

final class SyncTransportRejectedError extends SyncTransportError {
  const SyncTransportRejectedError(this.ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is SyncTransportRejectedError && _sameIds(other.ids);

  bool _sameIds(List<String> other) {
    if (other.length != ids.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);

  @override
  String toString() => 'SyncTransportError.rejected(${ids.length} ids)';
}

final class SyncTransportOtherError extends SyncTransportError {
  const SyncTransportOtherError();

  @override
  String toString() => 'SyncTransportError.other';
}

/// The server as the engine sees it.
abstract interface class SyncTransport {
  /// Runs one `sync_push` with [batch]. Throws [SyncTransportError].
  Future<PushResult> push(PushBatch batch);

  /// One page of [table] with `server_version > afterVersion`, ascending by
  /// `server_version`, at most [limit] rows (KTD2). A page shorter than
  /// [limit] is the last one. Throws [SyncTransportError].
  Future<List<RemoteRow>> pullPage({
    required SyncTable table,
    required int afterVersion,
    required int limit,
  });
}
