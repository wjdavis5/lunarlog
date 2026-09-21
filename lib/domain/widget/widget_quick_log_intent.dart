/// The widget's quick-log intent codec (issue #141): the `lunarlog://` URI
/// the widget's tap builds, and its parse back into a target profile.
///
/// The write itself never happens in the widget: a tap only *opens the app*
/// carrying this URI (the same after-the-gate shape the notification-action
/// work established in issue #136 — KTD4's "writes only after the gate is
/// unlocked"). `WidgetQuickLogExecutor` (`lib/data/widget/`) parses it and
/// latches the write until the device-credential gate is satisfied.
///
/// The URI carries only the profile id — never a name, a date, or health
/// detail. It sits on the app's own `lunarlog` scheme, where the auth link
/// classifier (`lib/data/auth/auth_link_classifier.dart`) already ignores
/// every host except `auth-callback`, so an intercepted or spoofed
/// `lunarlog://widget-quick-log` link is inert to sign-in flows and this
/// parser accepts only the exact host below.
library;

/// The URI scheme — the app's own, already registered in
/// `ios/Runner/Info.plist`'s `CFBundleURLTypes` and Android's
/// `AndroidManifest.xml` (the auth-callback/invite filter). Reused, not
/// re-registered: the widget's launch intents target the activity directly
/// on Android, and iOS's `widgetURL` resolves through the existing scheme.
const String kWidgetUriScheme = 'lunarlog';

/// The host of the quick-log intent. Only this exact host parses; anything
/// else on the scheme is not a widget intent (the auth observer ignores it
/// by its own rules).
const String kWidgetQuickLogHost = 'widget-quick-log';

/// The query parameter carrying the target profile id.
const String kWidgetProfileParam = 'profile';

/// The query parameter the `home_widget` plugin requires to recognize a
/// URL as widget-originated (its iOS `isWidgetUrl` checks for *any* query
/// item named this). Constant value; carries no information of its own.
const String kWidgetMarkerParam = 'homeWidget';
const String kWidgetMarkerValue = '1';

/// Builds the launch URI the widget's quick-log action opens the app with.
String widgetQuickLogUri(String profileId) => Uri(
      scheme: kWidgetUriScheme,
      host: kWidgetQuickLogHost,
      queryParameters: {
        kWidgetMarkerParam: kWidgetMarkerValue,
        kWidgetProfileParam: profileId,
      },
    ).toString();

/// The plain open intent (no action): a tap on a widget whose profile
/// cannot be quick-logged just opens the app. Same marker parameter so the
/// plugin recognizes it, but no [kWidgetQuickLogHost] — the executor's
/// parser returns null for it and nothing is latched.
String widgetOpenUri() => Uri(
      scheme: kWidgetUriScheme,
      host: 'widget-open',
      queryParameters: {kWidgetMarkerParam: kWidgetMarkerValue},
    ).toString();

/// The decoded quick-log intent, or null when [uri] is not one. Null for
/// every foreign scheme/host and for a quick-log URI missing its profile
/// id — a malformed intent must never fall through to "log for whatever
/// profile is active" (the wrong person's profile is worse than no write).
WidgetQuickLogIntent? parseWidgetQuickLogUri(Uri uri) {
  if (uri.scheme != kWidgetUriScheme) return null;
  if (uri.host != kWidgetQuickLogHost) return null;
  final profileId = uri.queryParameters[kWidgetProfileParam];
  if (profileId == null || profileId.isEmpty) return null;
  return WidgetQuickLogIntent(profileId: profileId);
}

/// A widget tap asking for a "period started today" write on [profileId].
/// The executor re-verifies the profile, the logging role, and the gate
/// before writing — this intent is a request, never an authorization.
class WidgetQuickLogIntent {
  const WidgetQuickLogIntent({required this.profileId});

  final String profileId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetQuickLogIntent && other.profileId == profileId;

  @override
  int get hashCode => profileId.hashCode;

  @override
  String toString() =>
      'WidgetQuickLogIntent(<${profileId.length}-char profile id>)';
}
