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

String predictionConnectionFailureCopy(
  AppLocalizations l10n,
  PredictionConnectionFailure failure,
) =>
    switch (failure) {
      PredictionNetworkFailure() => l10n.commonNetworkError,
      PredictionNotFoundFailure() => l10n.predictionConnectionFailureNotFound,
      PredictionExpiredFailure() => l10n.predictionConnectionFailureExpired,
      PredictionAlreadyAcceptedFailure() =>
        l10n.predictionConnectionFailureAlreadyAccepted,
      PredictionAlreadyGuardianFailure() =>
        l10n.predictionConnectionFailureAlreadyGuardian,
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
    };
