/// Unit tests for [feedbackFailureCopy] (Issue #545, moved out of
/// `lib/domain/feedback/feedback_service.dart`'s `userFacingMessage`
/// getters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/feedback_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
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

  test('every case has non-empty copy', () {
    for (final failure in failures) {
      expect(feedbackFailureCopy(_l10n, failure), isNotEmpty,
          reason: '${failure.runtimeType} has empty copy');
    }
  });

  test('network copy names the server, not a generic connection error', () {
    expect(feedbackFailureCopy(_l10n, const FeedbackFailure.network()),
        'Could not reach the server. Check your connection and try again.');
  });

  test(
      'FeedbackAttachmentUploadFailedFailure composes the nested failure copy '
      'and never echoes a raw error', () {
    final ticket = FeedbackTicket(
      id: 't1',
      category: FeedbackCategory.bug,
      status: FeedbackTicketStatus.newTicket,
      message: 'it broke',
      replyEmail: 'user@example.com',
      attachmentPaths: const [],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final failure = FeedbackAttachmentUploadFailedFailure(
      ticket,
      const FeedbackFailure.attachmentTooLarge(),
    );
    final copy = feedbackFailureCopy(_l10n, failure);
    expect(copy, contains('That image is too large. Choose one under 5 MB.'));
    expect(copy, contains('Support history'));
  });
}
