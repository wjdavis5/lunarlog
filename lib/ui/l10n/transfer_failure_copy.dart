/// Localized copy for [TransferFailure] (Issue #545): the domain sealed
/// type stays fieldless data in `lib/domain` (the diagnostic `message`
/// carried by [TransferOtherFailure] is never shown to the operator, only
/// logged via `toString`), and every call site routes through this mapper
/// instead of a `userFacingMessage` getter that hardcoded English inside
/// the domain layer. The `en` ARB values are character-identical to the
/// literals they replace, so this is copy-neutral.
library;

import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String transferFailureCopy(AppLocalizations l10n, TransferFailure failure) =>
    switch (failure) {
      TransferNetworkFailure() => l10n.commonNetworkError,
      TransferNotFoundFailure() => l10n.transferFailureNotFound,
      TransferExpiredFailure() => l10n.transferFailureExpired,
      TransferCancelledFailure() => l10n.transferFailureCancelled,
      TransferAlreadyAcceptedFailure() => l10n.transferFailureAlreadyAccepted,
      TransferSelfTransferFailure() => l10n.transferFailureSelfTransfer,
      TransferStaleOwnerFailure() => l10n.transferFailureStaleOwner,
      TransferAlreadyArmedFailure() => l10n.transferFailureAlreadyArmed,
      TransferUnauthorizedFailure() => l10n.commonUnauthorized,
      TransferInvalidTokenFailure() => l10n.transferFailureInvalidToken,
      TransferOtherFailure() => l10n.commonSomethingWentWrong,
    };
