/// How long a pending invitation or prediction-sharing link has left, as the
/// fragment its row shows: "expires in 6 days".
library;

import 'package:lunarlog/l10n/app_localizations.dart';

/// From this many hours up the label counts days (issue #1465). Below it,
/// hours still say something a day count would round away: "expires in 30h"
/// is not "expires in 1 day".
const int kExpiryDaysFromHours = 48;

/// The expiry fragment for [remaining].
///
/// Minutes below an hour, hours below two days, whole days after that. Every
/// step rounds down, so the label never promises more time than is left. A
/// negative [remaining] reads "expired" rather than as a negative duration,
/// for a row loaded just before its invitation lapsed.
String invitationExpiryLabel(AppLocalizations l10n, Duration remaining) {
  if (remaining.isNegative) return l10n.sharingManageGuardiansExpiryExpired;
  if (remaining.inHours >= kExpiryDaysFromHours) {
    return l10n.sharingManageGuardiansExpiryDays(remaining.inDays);
  }
  if (remaining.inHours >= 1) {
    return l10n.sharingManageGuardiansExpiryHours(remaining.inHours);
  }
  final minutes = remaining.inMinutes;
  return l10n.sharingManageGuardiansExpiryMinutes(minutes < 1 ? 1 : minutes);
}
