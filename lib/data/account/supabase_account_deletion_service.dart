/// [AccountDeletionService] implementation over the `delete-account` Edge
/// Function (Issue #17, Unit U4). Mirrors the error-mapping shape of
/// `SupabaseSharingService._mapError` so the seam family stays consistent.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/account/account_deletion_service.dart';

/// Client-side ceiling for the `delete-account` Edge Function call (#17 P1
/// fix): `functions_client` 2.7.1's `invoke()` has no default deadline, so
/// an unresponsive network would otherwise hang the delete flow forever
/// with the busy spinner up and [AccountSection] never learning the call
/// failed. Generous enough to cover the RPC, Apple revocation, and
/// `auth.admin.deleteUser` run in sequence server-side (observed up to
/// ~20s in the worst case) with real headroom.
const Duration kAccountDeletionTimeout = Duration(seconds: 45);

class SupabaseAccountDeletionService implements AccountDeletionService {
  SupabaseAccountDeletionService({
    required this.client,
    this.timeout = kAccountDeletionTimeout,
  });

  final SupabaseClient client;

  /// Injectable so tests never wait out the real duration (#17 P1 fix).
  final Duration timeout;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    try {
      final response = await client.functions.invoke(
        'delete-account',
        body: <String, Object?>{
          'appleAuthorizationCode': ?appleAuthorizationCode,
        },
        abortSignal: Future.delayed(timeout),
      );
      _throwIfBodyReportsFailure(response.data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// A 2xx response can still report `{ ok: false, code: ... }` (the
  /// function's own convention, U2 step 6) - a thrown [FunctionException]
  /// only covers a non-2xx status. Fails *closed*: a malformed/unparseable
  /// 2xx body (anything that isn't the documented `Map` shape) is treated
  /// as a failure, not a success (#17 P1 fix) - the alternative silently
  /// triggers the caller's irreversible local wipe on a response this
  /// client cannot actually verify says `ok: true`.
  void _throwIfBodyReportsFailure(dynamic data) {
    if (data is! Map) throw const AccountDeletionFailure.unknown();
    if (data['ok'] == true) return;
    throw _mapResponseCode(data['code']);
  }

  AccountDeletionFailure _mapError(Object error) {
    if (error is AccountDeletionFailure) return error;
    if (error is RequestAbortedException) {
      // Our own client-side timeout fired (see [timeout] above) - unlike a
      // network failure, the request may already have reached the server
      // and be running to completion, so this must not be folded into
      // AccountDeletionFailure.network's "definitely didn't happen" story
      // (#17 P1 fix). RequestAbortedException extends http.ClientException,
      // so this check must stay before that one below.
      return const AccountDeletionFailure.timeout();
    }
    if (error is SocketException || error is http.ClientException) {
      return const AccountDeletionFailure.network();
    }
    if (error is FunctionException) {
      return _mapFunctionException(error);
    }
    return const AccountDeletionFailure.unknown();
  }

  AccountDeletionFailure _mapFunctionException(FunctionException error) {
    if (error.status == 401) {
      return const AccountDeletionFailure.unauthorized();
    }
    if (error is FunctionsFetchException) {
      // The request never reached the function (offline, DNS, timeout).
      return const AccountDeletionFailure.network();
    }
    final details = error.details;
    if (details is Map) {
      return _mapResponseCode(details['code']);
    }
    return const AccountDeletionFailure.unknown();
  }

  AccountDeletionFailure _mapResponseCode(Object? code) {
    if (code == 'apple_code_required') {
      return const AccountDeletionFailure.appleCodeRequired();
    }
    if (code == 'apple_revoke_failed') {
      return const AccountDeletionFailure.appleRevokeFailed();
    }
    if (code == 'unauthorized') {
      return const AccountDeletionFailure.unauthorized();
    }
    if (code == 'delete_user_failed') {
      return const AccountDeletionFailure.deleteUserFailed();
    }
    return const AccountDeletionFailure.unknown();
  }
}
