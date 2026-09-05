/// The privileged server cascade behind [AccountDeletionService] (U1; R14):
/// the `request_account_deletion` RPC over an injected `SupabaseClient`
/// (the app passes `Supabase.instance.client` from the account UI; tests
/// pass one built over a mock `http.Client`), so nothing here touches
/// `Supabase.instance`.
///
/// Every failure is mapped to an [AccountDeletionError] kind by
/// [mapAccountDeletionError]; the provider's message, code and body stop
/// here (R18). Offline refuses before anything is removed: the service runs
/// this cascade before revocation and the device reset, so an offline throw
/// here removes nothing anywhere.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_deletion.dart';

class SupabaseAccountDeletion {
  SupabaseAccountDeletion(this._client);

  final SupabaseClient _client;

  static const String _rpc = 'request_account_deletion';

  /// Runs the cascade. Throws [AccountDeletionError].
  Future<void> deleteServerData() async {
    try {
      await _client.rpc<void>(_rpc);
    } catch (error) {
      throw mapAccountDeletionError(error);
    }
  }
}

/// HTTP statuses PostgREST answers with when the request is fine but the
/// service is not: retry later (offline for a deletion, which refuses).
const Set<int> _transientStatuses = {408, 425, 429};

/// Classifies [error] as an [AccountDeletionError] kind. Already-typed
/// errors pass through unchanged.
///
/// * `SocketException`, any other `IOException`, `http.ClientException`,
///   `TimeoutException`, and HTTP 5xx / 408 / 425 / 429 → offline.
/// * `AuthException` (no refreshable session) and a `PostgrestException`
///   whose code is HTTP 401/403, a `PGRST3xx` JWT error, or SQLSTATE `42501`
///   (insufficient privilege — the RPC needs a session) → notSignedIn.
/// * Everything else → server.
AccountDeletionError mapAccountDeletionError(Object error) {
  if (error is AccountDeletionError) return error;
  if (error is AuthRetryableFetchException) {
    return const AccountDeletionError.offline();
  }
  if (error is AuthException) {
    return const AccountDeletionError.notSignedIn();
  }
  if (error is PostgrestException) return _mapPostgrest(error);
  if (error is IOException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return const AccountDeletionError.offline();
  }
  return const AccountDeletionError.server();
}

AccountDeletionError _mapPostgrest(PostgrestException error) {
  final code = error.code ?? '';
  if (code.startsWith('PGRST3') || code == '42501') {
    return const AccountDeletionError.notSignedIn();
  }
  // postgrest stores the HTTP status as the code when the body carries no
  // SQLSTATE; a SQLSTATE is five characters, a status three.
  final status = code.length == 3 ? int.tryParse(code) : null;
  if (status != null) {
    if (status == 401 || status == 403) {
      return const AccountDeletionError.notSignedIn();
    }
    if (status >= 500 || _transientStatuses.contains(status)) {
      return const AccountDeletionError.offline();
    }
  }
  return const AccountDeletionError.server();
}
