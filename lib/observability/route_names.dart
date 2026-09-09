/// Static route-name registry (U1/U2; KTD2, KTD3; R4). Every navigable
/// destination in the app — a pushed screen or a modal route worth
/// distinguishing in a crash's navigation trail — gets one bare identifier
/// here, applied at its push site via `RouteSettings(name: ...)` or
/// `routeSettings:`. Names are never derived from the data a screen
/// displays: `ProfileDetailScreen` is the name for every profile, never
/// `ProfileDetail_<id>`, because [scrub.dart]'s `scrubRouteName` trusts
/// registry membership as its real gate (KTD2) — a name built from data
/// would defeat that gate by construction, not just by omission.
///
/// This file lives under `lib/observability/`, not `lib/ui/` (KTD3): every
/// file in `lib/observability/` depends only on `lib/config.dart`, its own
/// siblings, and packages, and `scrub.dart` (used from the Sentry hub setup,
/// far from the UI layer) needs this registry. `lib/ui/` imports this file;
/// this file never imports `lib/ui/`.
library;

/// The initial route, named via `onGenerateRoute` since `MaterialApp.home`
/// cannot carry a [RouteSettings] (U2 Approach 3).
const String kRouteProfileHomeGate = 'ProfileHomeGate';

/// `lib/ui/settings/settings_screen.dart`.
const String kRouteSettingsScreen = 'SettingsScreen';

/// `lib/ui/settings/settings_screen.dart` (Send feedback).
const String kRouteFeedbackScreen = 'FeedbackScreen';

/// `lib/ui/settings/settings_screen.dart` (Support history).
const String kRouteSupportHistoryScreen = 'SupportHistoryScreen';

/// `lib/ui/account/account_section.dart`.
const String kRouteSignInScreen = 'SignInScreen';

/// `lib/ui/account/sync_status_tile.dart`.
const String kRouteUploadConsentScreen = 'UploadConsentScreen';

/// `lib/ui/profiles/profile_picker_screen.dart`.
const String kRouteProfileDetailScreen = 'ProfileDetailScreen';

/// `lib/ui/profiles/profile_picker_screen.dart`.
const String kRouteManageGuardiansScreen = 'ManageGuardiansScreen';

/// `lib/ui/sharing/activity_feed_screen.dart` (issue #124) — a real
/// destination with its own content, pushed from the profile screen and
/// from Manage Guardians.
const String kRouteActivityFeedScreen = 'ActivityFeedScreen';

/// The day-entry bottom sheet (`lib/ui/logging/month_calendar.dart` pushes
/// `DaySheet`) — a genuine destination with its own content, not a trivial
/// confirm dialog (U2 Approach 2b).
const String kRouteDaySheetScreen = 'DaySheetScreen';

/// `lib/ui/account/delete_account_dialog.dart` — the multi-step
/// delete-account flow, not a single confirm/cancel choice (U2 Approach 2b).
const String kRouteDeleteAccountDialog = 'DeleteAccountDialog';

/// `lib/ui/profiles/profile_dialogs.dart` (create/edit a profile).
const String kRouteProfileEditDialog = 'ProfileEditDialog';

/// `lib/ui/profiles/profile_dialogs.dart` (archive a profile).
const String kRouteProfileArchiveDialog = 'ProfileArchiveDialog';

/// The read-only future-day explainer (`lib/ui/logging/month_calendar.dart`
/// pushes it for a tapped future cell, issue #133 KTD8) — a genuine
/// destination explaining the predicted state, never the log sheet.
const String kRouteFutureDayExplainerScreen = 'FutureDayExplainerScreen';

/// `lib/ui/feedback/attachment_field.dart` — explains what a screenshot may
/// contain before the picker opens; worth distinguishing from a plain
/// confirm (U2 Approach 2b).
const String kRouteAttachmentConsentDialog = 'AttachmentConsentDialog';

/// `lib/ui/account/account_mismatch_screen.dart`.
const String kRouteAccountMismatchDialog = 'AccountMismatchDialog';

/// `lib/ui/settings/health_sync_screen.dart` (Issue #153). Dormant behind
/// `AppConfig.hasHealthSync` until a HealthKit/Health Connect adapter
/// exists — see that flag's doc comment.
const String kRouteHealthSyncScreen = 'HealthSyncScreen';

/// `lib/ui/settings/health_sync_screen.dart` (Issue #153) — the confirm
/// dialog naming what binding a profile means, not a trivial confirm/cancel
/// (U2 Approach 2b).
const String kRouteHealthSyncBindDialog = 'HealthSyncBindDialog';

/// Every registered route name (KTD2's real gate). A name in this set is
/// kept verbatim by `scrubRouteName`; anything else falls through to the
/// shape check and, failing that, becomes `unknown`.
const Set<String> kSentryRouteNames = {
  kRouteProfileHomeGate,
  kRouteSettingsScreen,
  kRouteFeedbackScreen,
  kRouteSupportHistoryScreen,
  kRouteSignInScreen,
  kRouteUploadConsentScreen,
  kRouteProfileDetailScreen,
  kRouteManageGuardiansScreen,
  kRouteActivityFeedScreen,
  kRouteDaySheetScreen,
  kRouteDeleteAccountDialog,
  kRouteProfileEditDialog,
  kRouteProfileArchiveDialog,
  kRouteFutureDayExplainerScreen,
  kRouteAttachmentConsentDialog,
  kRouteAccountMismatchDialog,
  kRouteHealthSyncScreen,
  kRouteHealthSyncBindDialog,
};
