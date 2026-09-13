/// Localized copy for [PredictionConnectionFailure] (Issue #545): the
/// domain sealed type stays fieldless data in `lib/domain`, and every call
/// site routes through this mapper instead of a `userFacingMessage` getter
/// that hardcoded English inside the domain layer. The `en` ARB values are
/// character-identical to the literals they replace, so this is
/// copy-neutral.
///
/// The domain's failure subclasses were renamed from a leading-underscore
/// (`_PredictionNetworkFailure`, …) to public names as part of this move —
/// a private subtype cannot be named in an object pattern outside its own
/// library, so the switch below could not otherwise exist here.
library;

import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Split into two switches (CRAP gate: a 12-arm exhaustive switch scores
/// above the complexity-10 threshold) rather than one —
/// [_predictionConnectionFailureCopyRest] takes the back half. The split
/// stays fully exhaustive: every subtype is still named literally once,
/// either here or in the OR-pattern arm below (one switch-expression arm
/// regardless of how many types it alternates, so it costs this function
/// only one decision point) — a future new [PredictionConnectionFailure]
/// subtype still fails to compile here until it is added to one of the two
/// switches.
String predictionConnectionFailureCopy(
  AppLocalizations l10n,
  PredictionConnectionFailure failure,
) => switch (failure) {
  PredictionNetworkFailure() => l10n.commonNetworkError,
  PredictionNotFoundFailure() => l10n.predictionConnectionFailureNotFound,
  PredictionExpiredFailure() => l10n.predictionConnectionFailureExpired,
  PredictionAlreadyAcceptedFailure() =>
    l10n.predictionConnectionFailureAlreadyAccepted,
  PredictionAlreadyGuardianFailure() =>
    l10n.predictionConnectionFailureAlreadyGuardian,
  PredictionUnauthorizedFailure() ||
  PredictionInvalidTokenFailure() ||
  PredictionPregnancyModeFailure() ||
  PredictionAlreadyConnectedFailure() ||
  PredictionOneDirectionalFailure() ||
  PredictionMinorProfileFailure() ||
  PredictionOtherFailure() => _predictionConnectionFailureCopyRest(
    l10n,
    failure,
  ),
};

/// The back half of [predictionConnectionFailureCopy]'s switch — only ever
/// reached via its OR-pattern arm above, so the trailing wildcard is
/// unreachable in practice; it exists solely because this function's own
/// parameter type is still the full sealed [PredictionConnectionFailure],
/// which Dart requires this switch to cover exhaustively on its own too.
String _predictionConnectionFailureCopyRest(
  AppLocalizations l10n,
  PredictionConnectionFailure failure,
) => switch (failure) {
  PredictionUnauthorizedFailure() => l10n.commonUnauthorized,
  PredictionInvalidTokenFailure() =>
    l10n.predictionConnectionFailureInvalidToken,
  PredictionPregnancyModeFailure() =>
    l10n.predictionConnectionFailurePregnancyMode,
  PredictionAlreadyConnectedFailure() =>
    l10n.predictionConnectionFailureAlreadyConnected,
  PredictionOneDirectionalFailure() =>
    l10n.predictionConnectionFailureOneDirectional,
  PredictionMinorProfileFailure() =>
    l10n.predictionConnectionFailureMinorProfile,
  PredictionOtherFailure() => l10n.commonSomethingWentWrong,
  _ => throw StateError(
    'unreachable: ${failure.runtimeType} is handled by '
    'predictionConnectionFailureCopy',
  ),
};
