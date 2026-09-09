/// Central named-route construction (issue #182 AC6, restored to full
/// coverage by issue #313). This app never calls `Navigator.pushNamed` (see
/// `app.dart`'s note on `onGenerateRoute`) -- every push is a direct
/// `Navigator.of(context).push(...)`, and every full-screen push builds its
/// route through one of these two: [buildNamedRoute] directly, or the
/// handful of parameterless destinations reused across more than one push
/// site, collected in [kAppRoutes] and keyed by the `kRoute*` constants in
/// `lib/observability/route_names.dart`. Pairing a route name with the
/// widget it names lives in exactly this one file, rather than being
/// re-typed as `MaterialPageRoute(settings: RouteSettings(name: ...))`
/// boilerplate at each call site.
///
/// A destination that needs data only known at its push site (a profile, a
/// repository, a callback -- e.g. `ManageGuardiansScreen`, `HealthSyncScreen`,
/// the archived-profile `ProfileDetailScreen` push) still names its route
/// through [buildNamedRoute] directly at that call site; it just can't live
/// in the parameterless [kAppRoutes] map. A modal sheet or dialog names
/// itself through its own `routeSettings`/`RouteSettings` argument instead of
/// either of these -- see `lib/app.dart`'s invite/claim sheets or
/// `lib/ui/logging/day_sheet.dart`'s push site for that shape.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart';
import 'package:lunarlog/ui/feedback/support_history_screen.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';

/// Builds the screen for a named [Route] from a [BuildContext] alone.
typedef LunarLogWidgetBuilder = Widget Function(BuildContext context);

/// The one place a [RouteSettings] name is paired with a [MaterialPageRoute]
/// -- every push site in the app builds its route through this.
Route<T> buildNamedRoute<T>({
  required String name,
  required LunarLogWidgetBuilder builder,
}) =>
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name),
      builder: builder,
    );

/// Parameterless destinations reachable from more than one place (or simply
/// needing nothing but a `BuildContext`) -- pushed via [pushNamedScreen]
/// rather than re-declared at each call site.
final Map<String, LunarLogWidgetBuilder> kAppRoutes = {
  kRouteSettingsScreen: (_) => const SettingsScreen(),
  kRouteFeedbackScreen: (_) => const FeedbackScreen(),
  kRouteSupportHistoryScreen: (_) => const SupportHistoryScreen(),
  kRouteSignInScreen: (_) => const SignInScreen(),
};

/// Pushes a [kAppRoutes] entry by name. Every call site passes one of the
/// map's own keys (a compile-time-known `kRoute*` constant), so a missing
/// entry is a coding error caught the first time the call site runs, not a
/// runtime state a caller needs to handle.
Future<T?> pushNamedScreen<T>(BuildContext context, String name) =>
    Navigator.of(context).push<T>(
      buildNamedRoute<T>(name: name, builder: kAppRoutes[name]!),
    );
