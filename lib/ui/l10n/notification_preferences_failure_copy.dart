/// Localized copy for [NotificationPreferencesFailure] (Issue #545): the
/// domain sealed type stays fieldless data in `lib/domain`, and every call
/// site routes through this mapper instead of a `userFacingMessage` getter
/// that hardcoded English inside the domain layer. The `en` ARB values are
/// character-identical to the literals they replace, so this is
/// copy-neutral.
library;

import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String notificationPreferencesFailureCopy(
  AppLocalizations l10n,
  NotificationPreferencesFailure failure,
) =>
    switch (failure) {
      NotificationPreferencesUnauthorizedFailure() => l10n.commonUnauthorized,
      NotificationPreferencesNetworkFailure() => l10n.commonNetworkError,
      NotificationPreferencesInvalidTimeZoneFailure() =>
        l10n.notificationPreferencesFailureInvalidTimeZone,
      NotificationPreferencesOtherFailure() =>
        l10n.notificationPreferencesFailureOther,
    };
