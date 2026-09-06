import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

void main() {
  group('FeedbackCategory', () {
    test('fromDb round-trips every value', () {
      for (final category in FeedbackCategory.values) {
        expect(FeedbackCategory.fromDb(category.toDb()), category);
      }
    });

    test('fromDb throws on an unknown string', () {
      expect(() => FeedbackCategory.fromDb('praise'), throwsArgumentError);
    });
  });

  group('FeedbackTicketStatus', () {
    test('fromDb round-trips every value', () {
      for (final status in FeedbackTicketStatus.values) {
        expect(FeedbackTicketStatus.fromDb(status.toDb()), status);
      }
    });

    test('fromDb throws on an unknown string', () {
      expect(() => FeedbackTicketStatus.fromDb('closed'), throwsArgumentError);
    });
  });

  group('FeedbackReplyAuthor', () {
    test('fromDb round-trips every value', () {
      for (final author in FeedbackReplyAuthor.values) {
        expect(FeedbackReplyAuthor.fromDb(author.toDb()), author);
      }
    });

    test('fromDb throws on an unknown string', () {
      expect(() => FeedbackReplyAuthor.fromDb('bot'), throwsArgumentError);
    });
  });

  group('DeviceDiagnostics', () {
    const diagnostics = DeviceDiagnostics(
      os: 'iOS',
      osVersion: '18.0',
      model: 'iPhone15,2',
      appVersion: '1.0.0',
      buildNumber: '42',
      locale: 'en_US',
      breadcrumbs: ['nav:overview', 'nav:calendar'],
    );

    test('toJson emits exactly the seven allowlist keys and no others', () {
      final json = diagnostics.toJson();
      expect(
        json.keys.toSet(),
        {'os', 'os_version', 'model', 'app_version', 'build_number', 'locale', 'breadcrumbs'},
      );
    });

    test('toJson with an empty breadcrumb list still emits a breadcrumbs array', () {
      const empty = DeviceDiagnostics(
        os: 'Android',
        osVersion: '15',
        model: 'Pixel 9',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en_US',
        breadcrumbs: [],
      );
      final json = empty.toJson();
      expect(json['breadcrumbs'], isA<List<String>>());
      expect(json['breadcrumbs'], isEmpty);
    });

    test('previewLines renders every field', () {
      final lines = diagnostics.previewLines().join('\n');
      expect(lines, contains('iOS 18.0'));
      expect(lines, contains('iPhone15,2'));
      expect(lines, contains('1.0.0 (42)'));
      expect(lines, contains('en_US'));
      expect(lines, contains('nav:overview'));
    });

    test('equality and hashCode agree for equal and differing instances', () {
      const same = DeviceDiagnostics(
        os: 'iOS',
        osVersion: '18.0',
        model: 'iPhone15,2',
        appVersion: '1.0.0',
        buildNumber: '42',
        locale: 'en_US',
        breadcrumbs: ['nav:overview', 'nav:calendar'],
      );
      const different = DeviceDiagnostics(
        os: 'Android',
        osVersion: '18.0',
        model: 'iPhone15,2',
        appVersion: '1.0.0',
        buildNumber: '42',
        locale: 'en_US',
        breadcrumbs: ['nav:overview', 'nav:calendar'],
      );
      expect(diagnostics, same);
      expect(diagnostics.hashCode, same.hashCode);
      expect(diagnostics, isNot(different));
      expect(diagnostics, isNot('not a DeviceDiagnostics'));
    });

    test('breadcrumb-only differences are detected: different length and different content', () {
      const base = DeviceDiagnostics(
        os: 'iOS',
        osVersion: '18.0',
        model: 'iPhone15,2',
        appVersion: '1.0.0',
        buildNumber: '42',
        locale: 'en_US',
        breadcrumbs: ['nav:overview', 'nav:calendar'],
      );
      const differentLength = DeviceDiagnostics(
        os: 'iOS',
        osVersion: '18.0',
        model: 'iPhone15,2',
        appVersion: '1.0.0',
        buildNumber: '42',
        locale: 'en_US',
        breadcrumbs: ['nav:overview'],
      );
      const differentContent = DeviceDiagnostics(
        os: 'iOS',
        osVersion: '18.0',
        model: 'iPhone15,2',
        appVersion: '1.0.0',
        buildNumber: '42',
        locale: 'en_US',
        breadcrumbs: ['nav:overview', 'nav:settings'],
      );
      expect(base, isNot(differentLength));
      expect(base, isNot(differentContent));
    });
  });

  group('FeedbackAttachment', () {
    test('sizeBytes reflects the byte list length', () {
      final attachment = FeedbackAttachment(
        bytes: List<int>.filled(1024, 0),
        mimeType: 'image/png',
        filename: 'shot.png',
      );
      expect(attachment.sizeBytes, 1024);
    });
  });

  group('FeedbackTicket and FeedbackReply', () {
    final createdAt = DateTime.utc(2026, 9, 5);
    final updatedAt = DateTime.utc(2026, 9, 5, 1);

    FeedbackTicket makeTicket({FeedbackTicketStatus status = FeedbackTicketStatus.newTicket}) =>
        FeedbackTicket(
          id: 't1',
          category: FeedbackCategory.bug,
          message: 'It crashed',
          replyEmail: 'a@example.com',
          status: status,
          attachmentPaths: const ['uid/t1/a.png'],
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

    test('FeedbackTicket equality and hashCode agree for equal and differing instances', () {
      final a = makeTicket();
      final b = makeTicket();
      final differentStatus = makeTicket(status: FeedbackTicketStatus.replied);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(differentStatus));
      expect(a, isNot('not a ticket'));

      final differentPathsLength = FeedbackTicket(
        id: 't1',
        category: FeedbackCategory.bug,
        message: 'It crashed',
        replyEmail: 'a@example.com',
        status: FeedbackTicketStatus.newTicket,
        attachmentPaths: const [],
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      final differentPathsContent = FeedbackTicket(
        id: 't1',
        category: FeedbackCategory.bug,
        message: 'It crashed',
        replyEmail: 'a@example.com',
        status: FeedbackTicketStatus.newTicket,
        attachmentPaths: const ['uid/t1/b.png'],
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      expect(a, isNot(differentPathsLength));
      expect(a, isNot(differentPathsContent));
    });

    test('FeedbackReply equality and hashCode agree for equal and differing instances', () {
      final a = FeedbackReply(
        id: 'r1',
        ticketId: 't1',
        author: FeedbackReplyAuthor.user,
        message: 'still happening',
        createdAt: createdAt,
      );
      final b = FeedbackReply(
        id: 'r1',
        ticketId: 't1',
        author: FeedbackReplyAuthor.user,
        message: 'still happening',
        createdAt: createdAt,
      );
      final different = FeedbackReply(
        id: 'r1',
        ticketId: 't1',
        author: FeedbackReplyAuthor.admin,
        message: 'still happening',
        createdAt: createdAt,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
    });
  });

  group('FeedbackFailure', () {
    const failures = <FeedbackFailure>[
      FeedbackFailure.network(),
      FeedbackFailure.unauthorized(),
      FeedbackFailure.rateLimited(),
      FeedbackFailure.invalidInput(),
      FeedbackFailure.attachmentTooLarge(),
      FeedbackFailure.attachmentRejected(),
      FeedbackFailure.notFound(),
      FeedbackFailure.other(),
    ];

    test('every case has a non-empty userFacingMessage', () {
      for (final failure in failures) {
        expect(failure.userFacingMessage, isNotEmpty);
      }
    });

    test('no case echoes a provider string; toString carries only the case name', () {
      for (final failure in failures) {
        expect(failure.toString(), startsWith('FeedbackFailure.'));
        expect(failure.toString(), isNot(contains(' ')));
      }
    });

    test('equality is by runtime type', () {
      expect(const FeedbackFailure.network(), const FeedbackFailure.network());
      expect(const FeedbackFailure.network(), isNot(const FeedbackFailure.other()));
    });
  });
}
