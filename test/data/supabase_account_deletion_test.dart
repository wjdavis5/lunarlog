/// U1 (R14): [SupabaseAccountDeletion] runs the `request_account_deletion`
/// RPC over a real `SupabaseClient` whose HTTP layer is a `MockClient`, and
/// maps every failure class to a kinds-only [AccountDeletionError].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/account/account_deletion.dart';
import 'package:lunarlog/data/account/supabase_account_deletion.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const baseUrl = 'https://example.supabase.co';

http.Response json(Object? body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

typedef Handler = Future<http.Response> Function(http.Request request);

void main() {
  late List<http.Request> requests;
  SupabaseClient? client;

  SupabaseClient makeClient(Handler handler) => SupabaseClient(
        baseUrl,
        'anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final response = await handler(request);
          return http.Response(
            response.body,
            response.statusCode,
            headers: response.headers,
            reasonPhrase: response.reasonPhrase,
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

  setUp(() {
    requests = [];
  });

  tearDown(() async {
    await client?.dispose();
    client = null;
  });

  test('posts the deletion RPC and completes', () async {
    client = makeClient((_) async => json(null));
    final deletion = SupabaseAccountDeletion(client!);
    await deletion.deleteServerData();
    expect(requests.length, 1);
    expect(requests.single.url.path, '/rest/v1/rpc/request_account_deletion');
    expect(requests.single.method, 'POST');
  });

  test('a refused connection maps to offline', () async {
    client = makeClient((_) async {
      throw const SocketException('unreachable');
    });
    final deletion = SupabaseAccountDeletion(client!);
    await expectLater(
      deletion.deleteServerData(),
      throwsA(const AccountDeletionError.offline()),
    );
  });

  test('an unauthenticated RPC maps to notSignedIn', () async {
    client =
        makeClient((_) async => http.Response('{"message":"x"}', 401));
    final deletion = SupabaseAccountDeletion(client!);
    await expectLater(
      deletion.deleteServerData(),
      throwsA(const AccountDeletionError.notSignedIn()),
    );
  });

  test('a server outage maps to offline', () async {
    client = makeClient((_) async => http.Response('boom', 500));
    final deletion = SupabaseAccountDeletion(client!);
    await expectLater(
      deletion.deleteServerData(),
      throwsA(const AccountDeletionError.offline()),
    );
  });

  test('anything else maps to server', () async {
    client = makeClient((_) async => http.Response('nope', 400));
    final deletion = SupabaseAccountDeletion(client!);
    await expectLater(
      deletion.deleteServerData(),
      throwsA(const AccountDeletionError.server()),
    );
  });
}
