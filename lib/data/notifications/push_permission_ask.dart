/// Runs push registration's in-context permission ask (issues #1425,
/// #1444): the probe, the decision, the system-UI window around a request
/// that can show a dialog, and — on Android — the refusal count.
///
/// The two plugin calls it drives arrive as closures, so this file has no
/// plugin import and every branch runs under `flutter test`
/// (`test/data/notifications/push_permission_ask_test.dart`); the closures
/// themselves live in the plugin-bound, coverage-excluded
/// `firebase_push_token_source.dart`.
library;

import 'package:lunarlog/domain/notifications/android_notification_denials.dart';
import 'package:lunarlog/domain/notifications/push_permission_plan.dart';

/// Runs [action] inside the app gate's system-UI window — in production,
/// `GateController.duringSystemUi`, handed down from the composition root
/// as a plain function so `lib/data` never imports the gate. While the
/// window is open the gate covers the content but does not re-lock on the
/// lifecycle events a system dialog produces.
typedef SystemUiWindow = Future<T> Function<T>(Future<T> Function() action);

/// Makes the in-context ask, or decides not to.
///
/// [currentState] reads the permission without asking; [request] asks and
/// reports the state it left behind. A failed read is treated as
/// undetermined rather than failing push registration: the request that
/// follows is what would have run before this probe existed.
///
/// [duringSystemUi] is opened only around a [request] that can present the
/// system dialog (see [planPushPermissionAsk]), and only for as long as
/// that request takes — so an ask whose permission is already settled
/// opens no window and covers nothing. `null` (no gate in the tree) runs
/// the request bare.
///
/// On Android the answer to an ask is recorded in [androidDenials], the
/// same count the "Turn on reminders" tap reads, so that tap opens
/// settings once Android has stopped showing its dialog instead of
/// requesting into silence. A request that throws records nothing.
Future<void> runPushPermissionAsk({
  required bool isAndroid,
  required Future<PushPermissionState> Function() currentState,
  required Future<PushPermissionState> Function() request,
  required AndroidNotificationDenials androidDenials,
  SystemUiWindow? duringSystemUi,
}) async {
  final state = await _stateOrUndetermined(currentState);
  // The refusal count is Android's alone; off Android it is neither read
  // nor written.
  final denials = isAndroid ? androidDenials : null;
  final plan = planPushPermissionAsk(
    isAndroid: isAndroid,
    state: state,
    androidDeniedAttempts: await denials?.load() ?? 0,
  );
  switch (plan) {
    case PushPermissionAskPlan.skip:
      return;
    case PushPermissionAskPlan.askWithoutWindow:
      await request();
    case PushPermissionAskPlan.askInWindow:
      final answer = await _inWindow(duringSystemUi, request);
      await denials?.record(pushPermissionAnswer(answer));
  }
}

Future<PushPermissionState> _stateOrUndetermined(
  Future<PushPermissionState> Function() currentState,
) async {
  try {
    return await currentState();
  } catch (_) {
    return PushPermissionState.undetermined;
  }
}

Future<PushPermissionState> _inWindow(
  SystemUiWindow? duringSystemUi,
  Future<PushPermissionState> Function() request,
) =>
    duringSystemUi == null ? request() : duringSystemUi(request);
