/// The one place a [SnackBar] with an action is built ("Undo", the sync
/// glyph's shortcut to Settings).
///
/// On the pinned Flutter (3.47.2) `SnackBar` defaults `persist` to
/// `action != null`, and `ScaffoldMessengerState`'s timeout does nothing
/// for a persistent snackbar. Built directly, every snackbar with an action
/// therefore stayed on screen until someone swiped it away, and each later
/// snackbar queued unseen behind it — "Recorded a medium-flow period start
/// for today. / Undo" sat there for as long as the Today tab was open.
///
/// [actionSnackBar] gives such a snackbar a duration long enough to use the
/// action and then lets it leave. Someone navigating with assistive
/// technology keeps Flutter's intended behaviour — the snackbar persists
/// until they dismiss it — because a timeout they cannot see coming would
/// take the action away mid-reach.
///
/// `test/architecture/action_snack_bar_test.dart` fails if any other file
/// under `lib/` constructs a `SnackBarAction` itself.
library;

import 'package:flutter/material.dart';

/// How long a snackbar with an action stays up before it leaves on its own:
/// twice [SnackBar]'s 4-second default for a plain message, so there is time
/// to read the line and still reach the action.
const Duration kActionSnackBarDuration = Duration(seconds: 8);

/// Builds a [SnackBar] showing [content] with one action labelled
/// [actionLabel] that calls [onAction].
///
/// [accessibleNavigation] is `MediaQuery.accessibleNavigationOf(context)` at
/// the call site (a builder with no context of its own takes it as a
/// parameter the same way): true keeps the snackbar up until it is
/// dismissed, false lets it time out after [kActionSnackBarDuration].
///
/// [key] keys the snackbar itself; a caller that keys the message instead
/// puts that key on [content].
SnackBar actionSnackBar({
  Key? key,
  required Widget content,
  required String actionLabel,
  required VoidCallback onAction,
  required bool accessibleNavigation,
  VoidCallback? onVisible,
}) {
  return SnackBar(
    key: key,
    content: content,
    duration: kActionSnackBarDuration,
    persist: accessibleNavigation,
    onVisible: onVisible,
    action: SnackBarAction(label: actionLabel, onPressed: onAction),
  );
}
