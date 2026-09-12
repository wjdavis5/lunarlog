/// Localized copy for [SharingFailure] and [InviteCancellation] (Issue
/// #545): the domain sealed types stay fieldless data in `lib/domain`, and
/// every call site routes through these mappers instead of a
/// `userFacingMessage` getter that hardcoded English inside the domain
/// layer. The `en` ARB values are character-identical to the literals they
/// replace, so this is copy-neutral.
library;

import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String sharingFailureCopy(AppLocalizations l10n, SharingFailure failure) =>
    switch (failure) {
      SharingNetworkFailure() => l10n.commonNetworkError,
      SharingNotFoundFailure() => l10n.sharingFailureNotFound,
      SharingExpiredFailure() => l10n.sharingFailureExpired,
      SharingAlreadyAcceptedFailure() => l10n.sharingFailureAlreadyAccepted,
      SharingAlreadyGuardianFailure() => l10n.sharingFailureAlreadyGuardian,
      SharingUnauthorizedFailure() => l10n.commonUnauthorized,
      SharingInvalidTokenFailure() => l10n.sharingFailureInvalidToken,
      SharingOtherFailure() => l10n.sharingFailureOther,
    };

String inviteCancellationCopy(
  AppLocalizations l10n,
  InviteCancellation outcome,
) =>
    switch (outcome) {
      InviteCancellation.revoked => l10n.inviteCancellationRevoked,
      InviteCancellation.alreadyAccepted =>
        l10n.inviteCancellationAlreadyAccepted,
      InviteCancellation.alreadyRevoked =>
        l10n.inviteCancellationAlreadyRevoked,
      InviteCancellation.expired => l10n.inviteCancellationExpired,
    };
