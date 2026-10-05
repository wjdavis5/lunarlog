/// Localized copy for [SharingFailure] and [InviteCancellation] (Issue
/// #545): the domain sealed types stay fieldless data in `lib/domain`, and
/// every call site routes through these mappers instead of a
/// `userFacingMessage` getter that hardcoded English inside the domain
/// layer. The `en` ARB values are character-identical to the literals they
/// replace, so this is copy-neutral.
library;

import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// The line shown for [failure].
///
/// Split into two switches since issue #1504 added [SharingRevokedFailure]
/// (CRAP gate: a ten-arm exhaustive switch scores above the complexity-10
/// threshold) — [_sharingFailureCopyRest] takes the back half, the way
/// `transfer_failure_copy.dart` does it. The split stays fully exhaustive:
/// every subtype is still named literally once, either here or in the
/// OR-pattern arm below (one switch-expression arm however many types it
/// alternates), so a new [SharingFailure] subtype still fails to compile
/// here until it is added to one of the two switches.
String sharingFailureCopy(AppLocalizations l10n, SharingFailure failure) =>
    switch (failure) {
      SharingNetworkFailure() => l10n.commonNetworkError,
      SharingNotFoundFailure() => l10n.sharingFailureNotFound,
      SharingExpiredFailure() => l10n.sharingFailureExpired,
      SharingRevokedFailure() => l10n.sharingFailureRevoked,
      SharingAlreadyAcceptedFailure() => l10n.sharingFailureAlreadyAccepted,
      SharingAlreadyGuardianFailure() ||
      SharingUnauthorizedFailure() ||
      SharingNotSignedInFailure() ||
      SharingInvalidTokenFailure() ||
      SharingOtherFailure() => _sharingFailureCopyRest(l10n, failure),
    };

/// The back half of [sharingFailureCopy]'s switch — only ever reached via
/// its OR-pattern arm above, so the trailing wildcard is unreachable in
/// practice; it exists solely because this function's own parameter type
/// is still the full sealed [SharingFailure], which Dart requires this
/// switch to cover exhaustively on its own too.
String _sharingFailureCopyRest(
  AppLocalizations l10n,
  SharingFailure failure,
) => switch (failure) {
  SharingAlreadyGuardianFailure() => l10n.sharingFailureAlreadyGuardian,
  SharingUnauthorizedFailure() => l10n.commonUnauthorized,
  SharingNotSignedInFailure() => l10n.sharingFailureNotSignedIn,
  SharingInvalidTokenFailure() => l10n.sharingFailureInvalidToken,
  SharingOtherFailure() => l10n.sharingFailureOther,
  _ => throw StateError(
    'unreachable: ${failure.runtimeType} is handled by sharingFailureCopy',
  ),
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
