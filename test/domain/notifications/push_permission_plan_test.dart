/// Unit tests for the pure decisions behind push registration's
/// in-context permission ask (issues #1425, #1444).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/notification_permission_action.dart';
import 'package:lunarlog/domain/notifications/push_permission_plan.dart';

void main() {
  group('planPushPermissionAsk on Android', () {
    PushPermissionAskPlan plan(PushPermissionState state, int attempts) =>
        planPushPermissionAsk(
          isAndroid: true,
          state: state,
          androidDeniedAttempts: attempts,
        );

    test('a never-asked permission is requested inside the window -- the '
        'system dialog will appear', () {
      expect(plan(PushPermissionState.undetermined, 0),
          PushPermissionAskPlan.askInWindow);
    });

    test('one refusal still leaves Android a dialog to show, so the '
        'request is made, inside the window', () {
      expect(plan(PushPermissionState.refused, 1),
          PushPermissionAskPlan.askInWindow);
      expect(plan(PushPermissionState.undetermined, 1),
          PushPermissionAskPlan.askInWindow);
    });

    test('a granted permission makes no request and opens no window, '
        'whatever is on record', () {
      for (final attempts in [0, 1, 2]) {
        expect(plan(PushPermissionState.granted, attempts),
            PushPermissionAskPlan.skip,
            reason: '$attempts on record');
      }
    });

    test('two refusals on record make no request -- it would be silently '
        'dropped, and a window for it would cover the app for no dialog',
        () {
      for (final state in [
        PushPermissionState.undetermined,
        PushPermissionState.refused,
      ]) {
        expect(plan(state, 2), PushPermissionAskPlan.skip,
            reason: '$state');
        expect(plan(state, 3), PushPermissionAskPlan.skip,
            reason: '$state');
      }
    });

    test('it stops asking at exactly the count where the "Turn on '
        'reminders" tap starts opening settings -- one rule for both', () {
      for (var attempts = 0; attempts <= 4; attempts++) {
        final tapOpensSettings = nextNotificationPermissionAction(attempts) ==
            NotificationPermissionAction.openSettings;

        expect(
          plan(PushPermissionState.refused, attempts) ==
              PushPermissionAskPlan.skip,
          tapOpensSettings,
          reason: '$attempts on record',
        );
      }
    });
  });

  group('planPushPermissionAsk on Darwin', () {
    PushPermissionAskPlan plan(PushPermissionState state) =>
        planPushPermissionAsk(
          isAndroid: false,
          state: state,
          // The Android count has no say off Android.
          androidDeniedAttempts: 5,
        );

    test('an undetermined permission is requested inside the window -- '
        'the one time the dialog appears', () {
      expect(plan(PushPermissionState.undetermined),
          PushPermissionAskPlan.askInWindow);
    });

    test('a decided permission is still requested, as it always was, but '
        'with no window: the call shows nothing', () {
      for (final state in [
        PushPermissionState.granted,
        PushPermissionState.refused,
      ]) {
        expect(plan(state), PushPermissionAskPlan.askWithoutWindow,
            reason: '$state');
      }
    });
  });

  group('pushPermissionAnswer', () {
    test('granted is a grant', () {
      expect(pushPermissionAnswer(PushPermissionState.granted), isTrue);
    });

    test('refused is a refusal', () {
      expect(pushPermissionAnswer(PushPermissionState.refused), isFalse);
    });

    test('still undetermined is no answer at all, not a refusal', () {
      expect(pushPermissionAnswer(PushPermissionState.undetermined), isNull);
    });
  });
}
