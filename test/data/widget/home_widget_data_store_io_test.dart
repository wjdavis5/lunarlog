/// Issue #1731: the IO store writes the whole payload as one JSON value
/// under the single envelope key, so a failed or interrupted write can
/// never pair one profile's id with another profile's day count. The
/// `home_widget` plugin's method channel is mocked, so these run against
/// the store's real plugin calls.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/home_widget_data_store.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('home_widget');
  late List<MethodCall> calls;
  var saveResult = true;
  var removalFailuresRemaining = 0;

  setUp(() {
    calls = [];
    saveResult = true;
    removalFailuresRemaining = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map<Object?, Object?>;
        // Issue #1787 coverage: lets a test fail the first legacy-key
        // removal (a null value is a removal) without failing the payload
        // write.
        if (args['data'] == null && removalFailuresRemaining > 0) {
          removalFailuresRemaining--;
          return false;
        }
        return saveResult;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<String, String> payload() => WidgetCycleStatePayload.encode(
        state: const WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: 14,
          daysUntilNext: 7,
          canQuickLog: true,
        ),
        profileId: '01JTESTPROFILE',
        asOf: LocalDate(2026, 10, 9),
      );

  test('savePayload writes the whole payload as one JSON value under the '
      'envelope key', () async {
    final store = HomeWidgetDataStore();
    await store.savePayload(payload());

    final envelopeSaves = calls
        .where((call) =>
            call.method == 'saveWidgetData' &&
            (call.arguments as Map<Object?, Object?>)['data'] != null)
        .toList();
    expect(envelopeSaves, hasLength(1),
        reason: 'one atomic payload write, not one per field (issue #1731)');

    final args = envelopeSaves.single.arguments as Map<Object?, Object?>;
    expect(args['id'], WidgetCycleStatePayload.keyPayload);
    expect(
      jsonDecode(args['data']! as String),
      {
        WidgetCycleStatePayload.keyState: 'day',
        WidgetCycleStatePayload.keyCycleDay: '14',
        WidgetCycleStatePayload.keyDaysUntilNext: '7',
        WidgetCycleStatePayload.keyCanQuickLog: '1',
        WidgetCycleStatePayload.keyProfileId: '01JTESTPROFILE',
        WidgetCycleStatePayload.keyAsOf: '2026-10-09',
      },
      reason: 'the JSON carries exactly the documented fields',
    );
  });

  test('the six pre-envelope keys are removed once, on the first save '
      '(issue #1787)', () async {
    final store = HomeWidgetDataStore();
    await store.savePayload(payload());
    await store.savePayload(payload());

    final removals = calls
        .where((call) =>
            call.method == 'saveWidgetData' &&
            (call.arguments as Map<Object?, Object?>)['data'] == null)
        .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
        .toList();
    expect(
      removals,
      [
        WidgetCycleStatePayload.keyState,
        WidgetCycleStatePayload.keyCycleDay,
        WidgetCycleStatePayload.keyDaysUntilNext,
        WidgetCycleStatePayload.keyCanQuickLog,
        WidgetCycleStatePayload.keyProfileId,
        WidgetCycleStatePayload.keyAsOf,
      ],
      reason: 'each legacy key removed exactly once, on the first save',
    );
  });

  test('a failed legacy-key removal is retried on the next save '
      '(issue #1787)', () async {
    removalFailuresRemaining = 1;
    final store = HomeWidgetDataStore();
    await store.savePayload(payload());
    await store.savePayload(payload());

    final removals = calls
        .where((call) =>
            call.method == 'saveWidgetData' &&
            (call.arguments as Map<Object?, Object?>)['data'] == null)
        .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
        .toList();
    expect(
      removals,
      [
        WidgetCycleStatePayload.keyState, // failed, retried below
        WidgetCycleStatePayload.keyState,
        WidgetCycleStatePayload.keyCycleDay,
        WidgetCycleStatePayload.keyDaysUntilNext,
        WidgetCycleStatePayload.keyCanQuickLog,
        WidgetCycleStatePayload.keyProfileId,
        WidgetCycleStatePayload.keyAsOf,
      ],
      reason: 'the failed removal is retried, and the rest follow once',
    );
  });

  test('a write the plugin reports as failed throws, and no partial payload '
      'was written', () async {
    saveResult = false;
    final store = HomeWidgetDataStore();

    await expectLater(store.savePayload(payload()), throwsStateError);
    expect(
      calls.where((call) =>
          call.method == 'saveWidgetData' &&
          (call.arguments as Map<Object?, Object?>)['data'] != null),
      hasLength(1),
      reason: 'one attempted payload write, never a second field write',
    );
  });

  test('refresh asks the plugin to redraw the widget', () async {
    final store = HomeWidgetDataStore();
    await store.refresh();

    final refreshes =
        calls.where((call) => call.method == 'updateWidget').toList();
    expect(refreshes, hasLength(1));
    final args = refreshes.single.arguments as Map<Object?, Object?>;
    expect(args['name'], kLunarLogWidgetName);
    expect(args['android'], kLunarLogWidgetAndroidName);
    expect(args['ios'], kLunarLogWidgetName);
  });
}
