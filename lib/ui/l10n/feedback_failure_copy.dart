/// Localized copy for [FeedbackFailure] (Issue #545): the domain sealed
/// type stays fieldless (aside from [FeedbackAttachmentUploadFailedFailure]
/// and [FeedbackNotFoundFailure], neither of which carry copy) in
/// `lib/domain`, and every call site routes through this mapper instead of
/// a `userFacingMessage` getter that hardcoded English inside the domain
/// layer. The `en` ARB values are character-identical to the literals they
/// replace, so this is copy-neutral.
library;

import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String feedbackFailureCopy(AppLocalizations l10n, FeedbackFailure failure) =>
    switch (failure) {
      FeedbackNetworkFailure() => l10n.commonServerUnreachable,
      FeedbackUnauthorizedFailure() => l10n.commonUnauthorized,
      FeedbackRateLimitedFailure() => l10n.feedbackFailureRateLimited,
      FeedbackInvalidInputFailure() => l10n.feedbackFailureInvalidInput,
      FeedbackAttachmentTooLargeFailure() =>
        l10n.feedbackFailureAttachmentTooLarge,
      FeedbackAttachmentRejectedFailure() =>
        l10n.feedbackFailureAttachmentRejected,
      FeedbackNotFoundFailure() => l10n.feedbackFailureNotFound,
      FeedbackOtherFailure() => l10n.commonSomethingWentWrong,
      // Recurses through this same mapper for the nested attachment
      // failure (mirrors the domain getter this replaces, which composed
      // `attachmentFailure.userFacingMessage` the same way).
      FeedbackAttachmentUploadFailedFailure(:final attachmentFailure) =>
        l10n.feedbackFailureAttachmentUploadFailed(
          feedbackFailureCopy(l10n, attachmentFailure),
        ),
    };
