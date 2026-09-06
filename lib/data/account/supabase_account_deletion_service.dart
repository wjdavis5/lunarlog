/// [AccountDeletionService] implementation over the `delete-account` Edge
/// Function (Issue #17, Unit U4). Mirrors the error-mapping shape of
/// `SupabaseSharingService._mapError` so the seam family stays consistent.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/account/account_deletion_service.dart';

class SupabaseAccountDeletionService implements AccountDeletionService {
  SupabaseAccountDeletionService({required this.client});

  final SupabaseClient client;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    try {
      final response = await client.functions.invoke(
        'delete-account',
        body: <String, Object?>{
          'appleAuthorizationCode': ?appleAuthorizationCode,
        },
      );
      _throwIfBodyReportsFailure(response.data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// A 2xx response can still report `{ ok: false, code: ... }` (the
  /// function's own convention, U2 step 6) - a thrown [FunctionException]
  /// only covers a non-2xx status.
  void _throwIfBodyReportsFailure(dynamic data) {
    if (data is! Map) return;
    if (data['ok'] == true) return;
    throw _mapResponseCode(data['code']);
  }

  AccountDeletionFailure _mapError(Object error) {
    if (error is AccountDeletionFailure) return error;
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
    if (code == 'apple_revoke_failed') {
      return const AccountDeletionFailure.appleRevokeFailed();
    }
    if (code == 'unauthorized') {
      return const AccountDeletionFailure.unauthorized();
    }
    return const AccountDeletionFailure.unknown();
  }
}
