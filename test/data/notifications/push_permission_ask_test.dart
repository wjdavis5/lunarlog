/// Tests for [runPushPermissionAsk] (issue #1425): push registration's
/// launch-time permission ask, driven here with fakes in place of the two
/// `firebase_messaging` calls and of the gate's system-UI window.
///
/// The same ask against the real `GateController` is in
/// `test/ui/push_permission_window_test.dart`; through the real
/// `FirebasePushTokenSource` (queueing, the shared count, the scheduler's
/// "Turn on reminders" path) in `firebase_push_token_source_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/push_permission_ask.dart';
import 'package:lunarlog/domain/notifications/android_notification_denials.dart';
import 'package:lunarlog/domain/notifications/push_permission_plan.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _key = SettingsKeys.androidNotificationDeniedAttempts;

/// Stands in for `GateController.duringSystemUi`: records when the window
/// opens and closes, in one event log shared with the fake plugin calls.
class _Window {
  _Window(this.events);

  final List<String> events;
  int opened = 0;
  bool isOpen = false;

  Future<T> call<T>(Future<T> Function() action) async {
    opened++;
    isOpen = true;
    events.add('window opens');
    try {
      return await action();
    } finally {
      isOpen = false;
      events.add('window closes');
    }
  }
}

class _Harness {
  _Harness({
    required this.state,
    required this.answer,
    Map<String, String>? seed,
    this.probeError,
    this.requestError,
  }) : store = FakeSettingsStore(seed) {
    window = _Window(events);
  }

  /// What the probe reports before any ask.
  final PushPermissionState state;

  /// What the request leaves behind.
  final PushPermissionState answer;
  final Object? probeError;
  final Object? requestError;

  final FakeSettingsStore store;
  final events = <String>[];
  late final _Window window;
  int requests = 0;
  bool? windowOpenDuringRequest;

  Future<PushPermissionState> _probe() async {
    events.add('probe');
    if (probeError != null) throw probeError!;
    return state;
  }

  Future<PushPermissionState> _request() async {
    requests++;
    windowOpenDuringRequest = window.isOpen;
    events.add('request');
    if (requestError != null) throw requestError!;
    return answer;
  }

  Future<void> run({required bool isAndroid, bool withWindow = true}) =>
      runPushPermissionAsk(
        isAndroid: isAndroid,
        currentState: _probe,
        request: _request,
        androidDenials: AndroidNotificationDenials(store),
        duringSystemUi: withWindow ? window.call : null,
      );

  Future<String?> get count => store.get(_key);
}

void main() {
  group('the system-UI window', () {
    test('an ask that can show the dialog runs inside the window, which '
        'opens only around the request itself', () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.granted,
      );

      await h.run(isAndroid: true);

      expect(h.events, ['probe', 'window opens', 'request', 'window closes'],
          reason: 'the probe (and the count read) happen before the window '
              'opens; the window is down again as soon as the request '
              'answers');
      expect(h.windowOpenDuringRequest, isTrue);
      expect(h.window.opened, 1);
    });

    test('no window opens, and no request is made, when Android already '
        'has the permission', () async {
      final h = _Harness(
        state: PushPermissionState.granted,
        answer: PushPermissionState.granted,
      );

      await h.run(isAndroid: true);

      expect(h.window.opened, 0,
          reason: 'a settled launch must show no cover');
      expect(h.requests, 0);
      expect(h.events, ['probe']);
    });

    test('no window opens, and no request is made, once Android has '
        'stopped showing the dialog', () async {
      for (final state in [
        PushPermissionState.refused,
        PushPermissionState.undetermined,
      ]) {
        final h = _Harness(
          state: state,
          answer: PushPermissionState.refused,
          seed: {_key: '2'},
        );

        await h.run(isAndroid: true);

        expect(h.window.opened, 0,
            reason: '$state: two refusals on record -- a request would be '
                'silently dropped, and a window for it would blank the '
                'launch');
        expect(h.requests, 0, reason: '$state');
      }
    });

    test('on Darwin the one request that shows the dialog gets the window',
        () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
      );

      await h.run(isAndroid: false);

      expect(h.events, ['probe', 'window opens', 'request', 'window closes']);
      expect(h.windowOpenDuringRequest, isTrue);
    });

    test('on Darwin a decided permission is still requested, with no '
        'window -- the call shows nothing', () async {
      for (final decided in [
        PushPermissionState.granted,
        PushPermissionState.refused,
      ]) {
        final h = _Harness(state: decided, answer: decided);

        await h.run(isAndroid: false);

        expect(h.requests, 1, reason: '$decided');
        expect(h.window.opened, 0, reason: '$decided');
      }
    });

    test('with no window to open (no gate in the tree) the request still '
        'runs, and its answer is still counted', () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
      );

      await h.run(isAndroid: true, withWindow: false);

      expect(h.requests, 1);
      expect(h.window.opened, 0);
      expect(await h.count, '1');
    });

    test('a failed permission read is treated as undetermined, not as a '
        'reason to fail push registration', () async {
      final h = _Harness(
        state: PushPermissionState.granted,
        answer: PushPermissionState.granted,
        probeError: StateError('plugin unavailable'),
      );

      await h.run(isAndroid: true);

      expect(h.requests, 1,
          reason: 'the request is what ran before the probe existed');
      expect(h.windowOpenDuringRequest, isTrue,
          reason: 'and it might show the dialog, so it gets the window');
    });

    test('a request that throws closes the window, counts nothing, and '
        'hands the failure back', () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
        seed: {_key: '1'},
        requestError: StateError('request in progress'),
      );

      await expectLater(h.run(isAndroid: true), throwsStateError);

      expect(h.window.isOpen, isFalse);
      expect(h.events.last, 'window closes');
      expect(await h.count, '1',
          reason: 'an answer the OS never gave is not a refusal');
    });
  });

  group('the Android refusal count', () {
    test('a refused ask adds one to the shared count', () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.refused,
      );

      await h.run(isAndroid: true);

      expect(await h.count, '1');
    });

    test('a second refused ask reaches the line, and nothing is asked '
        'after it', () async {
      final h = _Harness(
        state: PushPermissionState.refused,
        answer: PushPermissionState.refused,
        seed: {_key: '1'},
      );

      await h.run(isAndroid: true);

      expect(h.requests, 1,
          reason: 'one refusal on record still leaves a dialog to show');
      expect(await h.count, '2');

      await h.run(isAndroid: true);

      expect(h.requests, 1, reason: 'the next launch asks nothing');
      expect(h.window.opened, 1);
      expect(await h.count, '2');
    });

    test('a granted ask resets the shared count', () async {
      final h = _Harness(
        state: PushPermissionState.refused,
        answer: PushPermissionState.granted,
        seed: {_key: '1'},
      );

      await h.run(isAndroid: true);

      expect(await h.count, '0');
    });

    test('an ask the OS leaves undetermined is not a refusal -- the count '
        'is unchanged', () async {
      final h = _Harness(
        state: PushPermissionState.undetermined,
        answer: PushPermissionState.undetermined,
        seed: {_key: '1'},
      );

      await h.run(isAndroid: true);

      expect(h.requests, 1);
      expect(await h.count, '1');
    });

    test('a launch that finds the permission granted leaves the count '
        'alone -- only an answered ask writes it', () async {
      final h = _Harness(
        state: PushPermissionState.granted,
        answer: PushPermissionState.granted,
        seed: {_key: '2'},
      );

      await h.run(isAndroid: true);

      expect(await h.count, '2');
    });

    test('Darwin never reads or writes the Android count', () async {
      for (final state in PushPermissionState.values) {
        final h = _Harness(
          state: state,
          answer: PushPermissionState.refused,
          // Past the Android line: were it consulted, nothing would be
          // requested.
          seed: {_key: '2'},
        );

        await h.run(isAndroid: false);

        expect(h.requests, 1, reason: '$state');
        expect(await h.count, '2', reason: '$state');
      }
    });
  });
}
