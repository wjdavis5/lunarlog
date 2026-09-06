/// Unit tests for [SupabaseAccountDeletionService] (Issue #17, Unit U4):
/// the body/Apple-code pass-through and the error-mapping shape mirrored
/// from `SupabaseSharingService._mapError`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_supabase_client.dart';

void main() {
  group('deleteAccount success', () {
    test('invokes delete-account and completes normally', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(data: {'ok': true}, status: 200),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await service.deleteAccount();

      expect(client.functions.invokedFunctionNames, ['delete-account']);
      expect(client.functions.invokedBodies.single, isA<Map<String, Object?>>());
      expect(
        (client.functions.invokedBodies.single as Map)
            .containsKey('appleAuthorizationCode'),
        isFalse,
        reason: 'omitted entirely when null, not sent as a null value',
      );
    });

    test('passes the Apple code through in the body when supplied', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(data: {'ok': true}, status: 200),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await service.deleteAccount(appleAuthorizationCode: 'a-fresh-code');

      final body = client.functions.invokedBodies.single as Map;
      expect(body['appleAuthorizationCode'], 'a-fresh-code');
    });
  });

  group('deleteAccount failure mapping', () {
    test('FunctionException with status 401 maps to unauthorized', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw const FunctionsHttpException(
          status: 401,
          details: {'ok': false, 'code': 'unauthorized'},
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.unauthorized()),
      );
    });

    test('a non-2xx response body carrying code apple_revoke_failed maps to '
        'appleRevokeFailed', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw const FunctionsHttpException(
          status: 409,
          details: {'ok': false, 'code': 'apple_revoke_failed'},
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(appleAuthorizationCode: 'a-fresh-code'),
        throwsA(const AccountDeletionFailure.appleRevokeFailed()),
      );
    });

    test('a 2xx response body reporting ok:false with code '
        'apple_revoke_failed also maps to appleRevokeFailed', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(
          data: {'ok': false, 'code': 'apple_revoke_failed'},
          status: 200,
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(appleAuthorizationCode: 'a-fresh-code'),
        throwsA(const AccountDeletionFailure.appleRevokeFailed()),
      );
    });

    test('SocketException maps to network', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw const SocketException('offline'),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.network()),
      );
    });

    test('http.ClientException maps to network', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw http.ClientException('connection reset'),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.network()),
      );
    });

    test('FunctionsFetchException (request never reached the function) maps '
        'to network', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw const FunctionsFetchException(details: 'timed out'),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.network()),
      );
    });

    test('an unrecognized error maps to unknown, and the failure object '
        'retains no error text', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw StateError('some internal detail that must not leak'),
      );
      final service = SupabaseAccountDeletionService(client: client);

      Object? failure;
      try {
        await service.deleteAccount();
      } catch (error) {
        failure = error;
      }

      expect(failure, const AccountDeletionFailure.unknown());
      expect(failure.toString(), 'AccountDeletionFailure.unknown');
      expect(failure.toString(), isNot(contains('internal detail')));
    });

    test('an unrecognized code string in an otherwise-ok-shaped body maps '
        'to unknown', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(
          data: {'ok': false, 'code': 'something_new'},
          status: 200,
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.unknown()),
      );
    });

    test('a 2xx response body carrying code delete_user_failed maps to '
        'deleteUserFailed (#17 P1 fix)', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(
          data: {'ok': false, 'code': 'delete_user_failed'},
          status: 200,
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.deleteUserFailed()),
      );
    });

    test('a non-2xx response body carrying code delete_user_failed also '
        'maps to deleteUserFailed', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            throw const FunctionsHttpException(
          status: 500,
          details: {'ok': false, 'code': 'delete_user_failed'},
        ),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.deleteUserFailed()),
      );
    });

    test('a non-Map 2xx response body fails closed as unknown, not success '
        '(#17 P1 fix)', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(data: 'not a map', status: 200),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.unknown()),
      );
    });

    test('a null 2xx response body also fails closed as unknown', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(data: null, status: 200),
      );
      final service = SupabaseAccountDeletionService(client: client);

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.unknown()),
      );
    });
  });

  group('client-side timeout (#17 P1 fix)', () {
    test('a call that never returns maps to timeout, not network or unknown, '
        'once the injected timeout elapses', () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) => Completer<FunctionResponse>().future,
      );
      final service = SupabaseAccountDeletionService(
        client: client,
        timeout: Duration.zero,
      );

      await expectLater(
        service.deleteAccount(),
        throwsA(const AccountDeletionFailure.timeout()),
      );
    });

    test('a response that arrives before the timeout still succeeds',
        () async {
      final client = FakeSupabaseClient(
        functionsInvoke: (name, {headers, body}) async =>
            const FunctionResponse(data: {'ok': true}, status: 200),
      );
      final service = SupabaseAccountDeletionService(
        client: client,
        timeout: const Duration(seconds: 30),
      );

      await service.deleteAccount();
    });
  });
}
