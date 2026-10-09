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

  setUp(() {
    calls = [];
    saveResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'saveWidgetData') return saveResult;
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

    final saves =
        calls.where((call) => call.method == 'saveWidgetData').toList();
    expect(saves, hasLength(1),
        reason: 'one atomic write, not one per field (issue #1731)');

    final args = saves.single.arguments as Map<Object?, Object?>;
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

  test('a write the plugin reports as failed throws, and no partial payload '
      'was written', () async {
    saveResult = false;
    final store = HomeWidgetDataStore();

    await expectLater(store.savePayload(payload()), throwsStateError);
    expect(
      calls.where((call) => call.method == 'saveWidgetData'),
      hasLength(1),
      reason: 'one attempted write, never a second field write',
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
