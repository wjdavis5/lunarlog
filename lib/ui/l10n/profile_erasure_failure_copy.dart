/// Localized copy for [ProfileErasureFailure] (Issues #545/#883): the
/// domain sealed type stays fieldless data in `lib/domain`, and the purge
/// surfaces route through this mapper instead of hardcoding English.
/// Mirrors `sharing_failure_copy.dart`.
library;

import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Purge-context copy for [failure]. [ProfileErasureNotSignedInFailure] is
/// deliberately distinct from [ProfileErasureUnauthorizedFailure]: only a
/// session fixes the former, so it must say "sign in", never "not primary
/// guardian" (Issue #883).
String profileErasureFailureCopy(
  AppLocalizations l10n,
  ProfileErasureFailure failure,
) =>
    switch (failure) {
      ProfileErasureNetworkFailure() => l10n.profileErasureFailureNetwork,
      ProfileErasureUnauthorizedFailure() =>
        l10n.profileErasureFailureUnauthorized,
      ProfileErasureNotSignedInFailure() =>
        l10n.profileErasureFailureNotSignedIn,
      ProfileErasureInvalidSourceFailure() =>
        l10n.profileErasureFailureInvalidSource,
      ProfileErasureOtherFailure() => l10n.profileErasureFailureOther,
    };
