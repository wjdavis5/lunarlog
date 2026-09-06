import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/feedback/supabase_feedback_service.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _uid = '01JABCDEF01234567890123456';

/// Puts [client] into a signed-in state without any network round trip:
/// `recoverSession` saves the session directly whenever it decodes as
/// unexpired, and a token that fails to decode as a JWT is treated as
/// having no expiry (see `gotrue`'s `Session.isExpired`).
Future<void> _signIn(SupabaseClient client) async {
  await client.auth.recoverSession(jsonEncode({
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'user': {
      'id': _uid,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-05T00:00:00.000Z',
    },
  }));
}

void main() {
  SupabaseClient makeClient(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        final res = await handler(request);
        return http.Response(
          res.body,
          res.statusCode,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            ...res.headers,
          },
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
  }

  Map<String, dynamic> ticketRow({
    String id = 't1',
    String category = 'bug',
    String message = 'crashed',
    String replyEmail = 'a@example.com',
    String status = 'new',
    List<String> attachmentPaths = const [],
  }) =>
      {
        'id': id,
        'user_id': _uid,
        'reply_email': replyEmail,
        'category': category,
        'message': message,
        'device_info': <String, dynamic>{},
        'attachment_paths': attachmentPaths,
        'status': status,
        'created_at': '2026-09-05T00:00:00.000Z',
        'updated_at': '2026-09-05T00:00:00.000Z',
      };

  group('submitTicket', () {
    test('posts to /rest/v1/feedback_tickets with exactly the granted columns and returns the ticket', () async {
      final client = makeClient((req) async {
        if (req.url.path == '/rest/v1/feedback_tickets') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body.keys.toSet(), {'user_id', 'reply_email', 'category', 'message', 'device_info'});
          expect(body['user_id'], _uid);
          expect(body['category'], 'bug');
          return http.Response(jsonEncode(ticketRow()), 200);
        }
        if (req.url.path == '/functions/v1/feedback-notify') {
          return http.Response('', 204);
        }
        fail('unexpected request: ${req.method} ${req.url}');
      });
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      final ticket = await service.submitTicket(
        category: FeedbackCategory.bug,
        message: 'crashed',
        replyEmail: 'a@example.com',
        diagnostics: const DeviceDiagnostics(
          os: 'iOS',
          osVersion: '18.0',
          model: 'iPhone',
          appVersion: '1.0.0',
          buildNumber: '1',
          locale: 'en_US',
          breadcrumbs: [],
        ),
      );

      expect(ticket.id, 't1');
      expect(ticket.category, FeedbackCategory.bug);
      expect(ticket.status, FeedbackTicketStatus.newTicket);
      await pumpEventQueue();
    });

    test('with an attachment, uploads to the expected object path then PATCHes attachment_paths', () async {
      var uploaded = false;
      final client = makeClient((req) async {
        if (req.url.path == '/rest/v1/feedback_tickets' && req.method == 'POST') {
          return http.Response(jsonEncode(ticketRow(id: 't2')), 200);
        }
        if (req.url.path.startsWith('/storage/v1/object/feedback-attachments/$_uid/t2/')) {
          uploaded = true;
          return http.Response(jsonEncode({'Key': req.url.path}), 200);
        }
        if (req.url.path == '/rest/v1/feedback_tickets' && req.method == 'PATCH') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['attachment_paths'], hasLength(1));
          return http.Response(
            jsonEncode(ticketRow(id: 't2', attachmentPaths: [body['attachment_paths'][0] as String])),
            200,
          );
        }
        if (req.url.path == '/functions/v1/feedback-notify') {
          return http.Response('', 204);
        }
        fail('unexpected request: ${req.method} ${req.url}');
      });
      await _signIn(client);

      final service = SupabaseFeedbackService(
        client: client,
        idGenerator: const Uuid(),
      );

      final ticket = await service.submitTicket(
        category: FeedbackCategory.bug,
        message: 'crashed with a screenshot',
        replyEmail: 'a@example.com',
        attachment: FeedbackAttachment(
          bytes: List<int>.filled(10, 1),
          mimeType: 'image/png',
          filename: 'shot.png',
        ),
      );

      expect(uploaded, isTrue);
      expect(ticket.attachmentPaths, hasLength(1));
      expect(ticket.attachmentPaths.single, startsWith('$_uid/t2/'));
      expect(ticket.attachmentPaths.single, endsWith('.png'));
      await pumpEventQueue();
    });

    test('after a successful insert, the notify function is invoked with the ticket id', () async {
      String? notifiedTicketId;
      final client = makeClient((req) async {
        if (req.url.path == '/rest/v1/feedback_tickets') {
          return http.Response(jsonEncode(ticketRow(id: 't3')), 200);
        }
        if (req.url.path == '/functions/v1/feedback-notify') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          notifiedTicketId = body['ticket_id'] as String;
          return http.Response('', 204);
        }
        fail('unexpected request: ${req.method} ${req.url}');
      });
      await _signIn(client);

      final service = SupabaseFeedbackService(client: client);
      await service.submitTicket(
        category: FeedbackCategory.other,
        message: 'hello',
        replyEmail: 'a@example.com',
      );

      // The notify call is fire-and-forget; flush the microtask/event queue.
      await pumpEventQueue();
      expect(notifiedTicketId, 't3');
    });

    test('a notify invocation failure (500) does not make submitTicket throw', () async {
      final client = makeClient((req) async {
        if (req.url.path == '/rest/v1/feedback_tickets') {
          return http.Response(jsonEncode(ticketRow(id: 't4')), 200);
        }
        if (req.url.path == '/functions/v1/feedback-notify') {
          return http.Response(jsonEncode({'message': 'boom'}), 500);
        }
        fail('unexpected request: ${req.method} ${req.url}');
      });
      await _signIn(client);

      final service = SupabaseFeedbackService(client: client);
      final ticket = await service.submitTicket(
        category: FeedbackCategory.other,
        message: 'hello',
        replyEmail: 'a@example.com',
      );

      expect(ticket.id, 't4');
      await pumpEventQueue();
    });

    test('insert returning 42501 maps to FeedbackFailure.unauthorized', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'message': 'nope', 'code': '42501'}), 400);
      });
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      expect(
        () => service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com'),
        throwsA(isA<FeedbackUnauthorizedFailure>()),
      );
    });

    test('insert returning 55000 maps to FeedbackFailure.rateLimited', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'message': 'rate limit', 'code': '55000'}), 400);
      });
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      expect(
        () => service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com'),
        throwsA(isA<FeedbackRateLimitedFailure>()),
      );
    });

    test('insert returning 23514 maps to FeedbackFailure.invalidInput', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'message': 'check failed', 'code': '23514'}), 400);
      });
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      expect(
        () => service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com'),
        throwsA(isA<FeedbackInvalidInputFailure>()),
      );
    });

    test('a SocketException yields FeedbackFailure.network', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async => throw const SocketException('offline')),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      expect(
        () => service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com'),
        throwsA(isA<FeedbackNetworkFailure>()),
      );
    });

    test('a Storage 413 yields attachmentTooLarge; a 415 yields attachmentRejected', () async {
      Future<void> expectStorageFailure(String statusCode, Type expected) async {
        final client = makeClient((req) async {
          if (req.url.path == '/rest/v1/feedback_tickets') {
            return http.Response(jsonEncode(ticketRow(id: 't5')), 200);
          }
          if (req.url.path.startsWith('/storage/v1/object/feedback-attachments/')) {
            return http.Response(
              jsonEncode({'message': 'rejected', 'statusCode': statusCode}),
              int.parse(statusCode),
            );
          }
          fail('unexpected request: ${req.method} ${req.url}');
        });
        await _signIn(client);
        final service = SupabaseFeedbackService(client: client);

        await expectLater(
          service.submitTicket(
            category: FeedbackCategory.bug,
            message: 'x',
            replyEmail: 'a@example.com',
            attachment: FeedbackAttachment(
              bytes: List<int>.filled(10, 1),
              mimeType: 'image/png',
              filename: 'shot.png',
            ),
          ),
          throwsA(isA<FeedbackFailure>().having((f) => f.runtimeType, 'type', expected)),
        );
      }

      await expectStorageFailure('413', FeedbackAttachmentTooLargeFailure);
      await expectStorageFailure('415', FeedbackAttachmentRejectedFailure);
    });

    test('a signed-out client rejects locally with FeedbackFailure.unauthorized', () async {
      final client = makeClient((req) async {
        fail('a signed-out submit must never reach the network: ${req.method} ${req.url}');
      });
      final service = SupabaseFeedbackService(client: client);

      expect(
        () => service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com'),
        throwsA(isA<FeedbackUnauthorizedFailure>()),
      );
    });
  });

  group('listReplies', () {
    test('a ticket with no replies returns an empty list, not null', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/feedback_replies');
        return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
      });
      final service = SupabaseFeedbackService(client: client);

      final replies = await service.listReplies('t1');
      expect(replies, isEmpty);
    });
  });

  group('privacy', () {
    test('a raised failure toString carries only the case name, never a provider message', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'message': 'super secret detail', 'code': 'XXXXX'}), 400);
      });
      await _signIn(client);
      final service = SupabaseFeedbackService(client: client);

      try {
        await service.submitTicket(category: FeedbackCategory.bug, message: 'x', replyEmail: 'a@example.com');
        fail('expected a FeedbackFailure');
      } on FeedbackFailure catch (failure) {
        expect(failure.toString(), isNot(contains('super secret detail')));
        expect(failure.userFacingMessage, isNot(contains('super secret detail')));
      }
    });
  });
}
