/// Pure decisions for push registration's in-context permission ask
/// (issues #1425, #1444). Split out of
/// `lib/data/notifications/firebase_push_token_source.dart` (plugin-bound,
/// excluded from the coverage gate) so every branch here is unit-tested
/// directly; `lib/data/notifications/push_permission_ask.dart` runs them.
library;

import 'package:lunarlog/domain/notifications/notification_permission_action.dart';

/// What the platform reports about notification permission, reduced to
/// what the ask needs to tell apart.
enum PushPermissionState {
  /// Notifications are allowed.
  granted,

  /// Never asked: the system dialog has not been shown yet.
  undetermined,

  /// Refused. On Darwin, whose dialog is one-shot, that is final. On
  /// Android it does not say whether the OS would still show its dialog —
  /// the refusal count answers that (see [planPushPermissionAsk]).
  refused,
}

/// What the in-context ask should do.
enum PushPermissionAskPlan {
  /// Make no request: none could show a dialog or change anything.
  skip,

  /// Make the request with no system-UI window around it: it will show no
  /// dialog, so there is nothing on screen for the gate to cover.
  askWithoutWindow,

  /// Make the request inside the gate's system-UI window: the system
  /// dialog can appear, and the window is what keeps the gate from
  /// re-locking the app behind it.
  askInWindow,
}

/// Decides the in-context ask from the current [state].
///
/// **Android:** a request is made only while the dialog can still appear —
/// not granted, and fewer than two refusals on record
/// ([androidDeniedAttempts]). That is the same count, and the same line
/// ([nextNotificationPermissionAction]), the "Turn on reminders" tap
/// decides on, so the two can never disagree about whether Android has
/// stopped showing its dialog. Otherwise nothing is requested at all: a
/// request the OS would silently drop buys nothing, and opening a window
/// for it would cover the app for no dialog.
///
/// The count only knows the refusals that were recorded. Where the dialog
/// is unavailable for a reason it never saw — a build before issue #1425
/// that spent a dialog uncounted, or Android 12 and below, which has no
/// dialog and where "refused" just means notifications are switched off —
/// the request is still made, shows nothing, and is counted as refused;
/// that happens on at most two asks before the count stops it.
///
/// **Darwin:** the dialog appears exactly once, while the permission is
/// still undetermined, so only that request gets a window. A decided
/// permission is still requested, as it always has been — the call shows
/// nothing — so the behavior is unchanged apart from the window.
PushPermissionAskPlan planPushPermissionAsk({
  required bool isAndroid,
  required PushPermissionState state,
  required int androidDeniedAttempts,
}) {
  if (!isAndroid) {
    return state == PushPermissionState.undetermined
        ? PushPermissionAskPlan.askInWindow
        : PushPermissionAskPlan.askWithoutWindow;
  }
  if (state == PushPermissionState.granted) return PushPermissionAskPlan.skip;
  return nextNotificationPermissionAction(androidDeniedAttempts) ==
          NotificationPermissionAction.request
      ? PushPermissionAskPlan.askInWindow
      : PushPermissionAskPlan.skip;
}

/// The answer a finished ask gave, in the terms the Android refusal count
/// records: `true` granted, `false` refused, and `null` when the OS left
/// it undetermined — an answer that was never given is not a refusal.
bool? pushPermissionAnswer(PushPermissionState after) => switch (after) {
      PushPermissionState.granted => true,
      PushPermissionState.refused => false,
      PushPermissionState.undetermined => null,
    };
