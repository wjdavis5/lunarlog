/// Issue #196 (Perimenopause mode): the day sheet's category
/// prioritization — Hot flashes (and the sleep/energy/mind/feelings
/// cluster) come first while `profile_modes.mode = 'perimenopause'`, and
/// `hot_flashes` stays a top-level category in every other mode (AC3/AC4).
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

double _headerY(WidgetTester tester, String wireName) => tester
    .getTopLeft(
      find.byKey(ValueKey('category-picker-header-$wireName')),
    )
    .dy;

void main() {
  testWidgets('Perimenopause mode surfaces the symptom cluster first (AC3)',
      (tester) async {
    await pumpSheet(tester, lifecycleMode: LifecycleMode.perimenopause);
    await tester.pumpAndSettle();

    final hotFlashesY = _headerY(tester, 'hot_flashes');
    final sleepY = _headerY(tester, 'sleep');
    final painY = _headerY(tester, 'pain');

    expect(hotFlashesY, lessThan(sleepY));
    expect(sleepY, lessThan(painY),
        reason: 'the perimenopause cluster precedes every other category');
  });

  testWidgets('hot_flashes stays a top-level category outside the mode (AC4)',
      (tester) async {
    await pumpSheet(tester, lifecycleMode: LifecycleMode.tracking);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('category-picker-header-hot_flashes')),
      findsOneWidget,
    );
  });

  testWidgets('Conceive mode is unchanged — Pain still precedes Hot flashes',
      (tester) async {
    await pumpSheet(tester, lifecycleMode: LifecycleMode.conceive);
    await tester.pumpAndSettle();

    expect(_headerY(tester, 'pain'), lessThan(_headerY(tester, 'hot_flashes')));
  });
}
