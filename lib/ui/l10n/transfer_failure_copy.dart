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

///
/// Split into two switches (CRAP gate: an 11-arm exhaustive switch scores
/// above the complexity-10 threshold) rather than one — [_transferFailureCopyRest]
/// takes the back half. The split stays fully exhaustive: every subtype is
/// still named literally once, either here or in the OR-pattern arm below
/// (one switch-expression arm regardless of how many types it alternates,
/// so it costs this function only one decision point) — a future new
/// [TransferFailure] subtype still fails to compile here until it is added
/// to one of the two switches.
String transferFailureCopy(AppLocalizations l10n, TransferFailure failure) =>
    switch (failure) {
      TransferNetworkFailure() => l10n.commonNetworkError,
      TransferNotFoundFailure() => l10n.transferFailureNotFound,
      TransferExpiredFailure() => l10n.transferFailureExpired,
      TransferCancelledFailure() => l10n.transferFailureCancelled,
      TransferAlreadyAcceptedFailure() => l10n.transferFailureAlreadyAccepted,
      TransferSelfTransferFailure() ||
      TransferStaleOwnerFailure() ||
      TransferAlreadyArmedFailure() ||
      TransferUnauthorizedFailure() ||
      TransferInvalidTokenFailure() ||
      TransferOtherFailure() => _transferFailureCopyRest(l10n, failure),
    };

/// The back half of [transferFailureCopy]'s switch — only ever reached via
/// its OR-pattern arm above, so the trailing wildcard is unreachable in
/// practice; it exists solely because this function's own parameter type
/// is still the full sealed [TransferFailure], which Dart requires this
/// switch to cover exhaustively on its own too.
String _transferFailureCopyRest(
  AppLocalizations l10n,
  TransferFailure failure,
) => switch (failure) {
  TransferSelfTransferFailure() => l10n.transferFailureSelfTransfer,
  TransferStaleOwnerFailure() => l10n.transferFailureStaleOwner,
  TransferAlreadyArmedFailure() => l10n.transferFailureAlreadyArmed,
  TransferUnauthorizedFailure() => l10n.commonUnauthorized,
  TransferInvalidTokenFailure() => l10n.transferFailureInvalidToken,
  TransferOtherFailure() => l10n.commonSomethingWentWrong,
  _ => throw StateError(
    'unreachable: ${failure.runtimeType} is handled by transferFailureCopy',
  ),
};
