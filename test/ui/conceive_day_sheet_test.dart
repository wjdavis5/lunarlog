/// Issue #204 (Conceive mode): the day sheet's category prioritization —
/// Tests and Discharge come first while `profile_modes.mode = 'conceive'`,
/// and stay in their ordinary place otherwise (AC5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';

final LocalDate _today = LocalDate(2026, 8, 20);

class _SheetEntries implements DayEntriesRepository {
  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => null;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) =>
      Stream.value(const []);

  @override
  Future<DayEntry> save(DayEntry entry) async => entry;

  @override
  Future<List<DayEntryMergeEvent>> mergeEventsForDay(
          String profileId, LocalDate date) async =>
      const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> pumpSheet(WidgetTester tester, {LifecycleMode? lifecycleMode}) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DaySheet(
        repository: _SheetEntries(),
        profileId: 'p',
        date: _today,
        today: _today,
        lifecycleMode: lifecycleMode,
      ),
    ),
  ));
}

void main() {
  testWidgets('Conceive mode surfaces Tests, then Discharge, ahead of the '
      'rest of the day sheet', (tester) async {
    await pumpSheet(tester, lifecycleMode: LifecycleMode.conceive);
    await tester.pumpAndSettle();

    final testsY =
        tester.getTopLeft(find.byKey(const ValueKey('category-picker-header-tests'))).dy;
    final dischargeY = tester
        .getTopLeft(find.byKey(const ValueKey('category-picker-header-discharge')))
        .dy;
    final painY =
        tester.getTopLeft(find.byKey(const ValueKey('category-picker-header-pain'))).dy;

    expect(testsY, lessThan(dischargeY));
    expect(dischargeY, lessThan(painY),
        reason: 'both fertility-signal categories precede every other one');
  });

  testWidgets('outside Conceive mode the ordinary order is unchanged '
      '(Pain first, Tests/Discharge last)', (tester) async {
    await pumpSheet(tester, lifecycleMode: LifecycleMode.tracking);
    await tester.pumpAndSettle();

    final painY =
        tester.getTopLeft(find.byKey(const ValueKey('category-picker-header-pain'))).dy;
    final testsY =
        tester.getTopLeft(find.byKey(const ValueKey('category-picker-header-tests'))).dy;

    expect(painY, lessThan(testsY));
  });
}
