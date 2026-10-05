/// Issue #1489: the floating button's label — "Log today" until today has
/// something logged, "Edit today" from then on, by the same rule the Today
/// log card uses (`TodayLog.hasContent`), known before any tap and changed
/// the moment the entry does.
///
/// The button's placement, its viewer gate and the sheet it opens are
/// covered by `test/ui/app_shell_test.dart`.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/today_log_fab.dart';
import 'package:provider/provider.dart';

import '../../support/erroring_day_entries_repository.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

const Key kFab = ValueKey('today-log-fab');
const String kLog = 'Log today';
const String kEdit = 'Edit today';

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    profiles = DriftProfilesRepository(db.storage);
    entries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftDayEntriesRepository entries;
  late final DriftObservationsRepository observations;

  /// "Today" as the button sees it, read through one stable closure.
  LocalDate now = kToday;
  LocalDate _today() => now;

  /// The prediction service's date tickers, one per pipeline it opens. The
  /// app's is a minute poll that fires when the civil date changes
  /// (`dateRolloverTicker`); here the test fires it by hand, with no timer.
  final List<StreamController<void>> _dateTickers = [];
  Stream<void> _dateTicker() {
    late final StreamController<void> controller;
    controller = StreamController<void>(onListen: () => controller.add(null));
    _dateTickers.add(controller);
    return controller.stream;
  }

  /// What the app's ticker does once the date has rolled over.
  void tickDate() {
    for (final ticker in _dateTickers) {
      if (ticker.hasListener) ticker.add(null);
    }
  }

  late final CyclePredictionService predictions =
      CyclePredictionService(entries, dateTicker: _dateTicker);

  Future<String> createProfile([String name = 'Alice']) async =>
      (await profiles.create(displayName: name, isMinor: false)).id;

  Future<DayEntry> saveDay(
    String profileId,
    LocalDate date, {
    FlowLevel flow = FlowLevel.none,
    List<String> tags = const [],
    String? note,
    bool pms = false,
    List<Observation> attached = const [],
  }) =>
      entries.saveDayEntryWithObservations(
        entry: DayEntry(
          id: '',
          profileId: profileId,
          localDate: date,
          tz: 'America/Chicago',
          flow: flow,
          tags: tags,
          note: note,
          pms: pms,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        observationsToUpsert: attached,
      );

  /// A reading for today, to attach in [saveDay]. With a [dayEntryId] it
  /// is one to write on its own, through `observations.save`.
  Observation reading(
    String profileId,
    ObservationCategory category,
    double value,
    String unit, {
    String dayEntryId = '',
  }) =>
      Observation(
        id: '',
        dayEntryId: dayEntryId,
        profileId: profileId,
        localDate: kToday,
        tz: 'America/Chicago',
        category: category,
        valueNum: value,
        unit: unit,
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// A spotting record for today, to attach in [saveDay]. With a
  /// [dayEntryId] it is one to write on its own, through
  /// `observations.save`.
  Observation spotting(String profileId, {String dayEntryId = ''}) =>
      Observation(
        id: '',
        dayEntryId: dayEntryId,
        profileId: profileId,
        localDate: kToday,
        tz: 'America/Chicago',
        category: ObservationCategory.spotting,
        code: 'spotting',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// Pumps a bare [TodayLogFab]. Pumping again keeps its state, so a second
  /// call with another profile is a profile switch.
  Future<void> pump(
    String profileId, {
    DayEntriesRepository? entriesSeam,
    bool withEntries = true,
    bool withObservations = true,
    bool withPredictions = false,
    LocalDate Function()? todayProvider,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // A tree with no entries repository still needs one provider for
          // MultiProvider to be valid.
          Provider<String>.value(value: 'today-log-fab-test'),
          if (withEntries)
            Provider<DayEntriesRepository>.value(value: entriesSeam ?? entries),
          if (withObservations)
            Provider<ObservationsRepository>.value(value: observations),
          if (withPredictions)
            Provider<CyclePredictionService>.value(value: predictions),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            floatingActionButton: TodayLogFab(
              profileId: profileId,
              todayProvider: todayProvider ?? _today,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

/// The button's one label.
String fabLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(kFab), matching: find.byType(Text)),
    )
    .data!;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('"Log today" when today has no entry', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.pump(profileId);

    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('"Edit today" when today has something logged, before any tap',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId);

    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('the label flips as the entry is saved and deleted',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.pump(profileId);
    expect(fabLabel(tester), kLog);

    await h.saveDay(profileId, kToday, flow: FlowLevel.medium);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    await h.entries.delete(profileId, kToday);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('an entry left with nothing on it still reads "Log today", '
      'and one with only a note or only the PMS marker reads "Edit today"',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday);
    await h.pump(profileId);
    expect(fabLabel(tester), kLog);

    await h.saveDay(profileId, kToday, note: 'slept badly');
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    await h.saveDay(profileId, kToday);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);

    await h.saveDay(profileId, kToday, pms: true);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('a day holding only a temperature reads "Edit today"',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(
      profileId,
      kToday,
      attached: [
        h.reading(profileId, ObservationCategory.bbt, 36.7, 'celsius'),
      ],
    );
    await h.pump(profileId);

    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('a spotting-only day with no flow at all, as the health import '
      'stores it, reads "Edit today"', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday, attached: [h.spotting(profileId)]);
    await h.pump(profileId);

    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  // The reminder's "Spotting" action, the health import and a sync pull all
  // write an observation with no day-entry write beside it.
  testWidgets('spotting written on its own, with no entry write, flips the '
      'label, and taking it off flips it back', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    final entry = await h.saveDay(profileId, kToday);
    await h.pump(profileId);
    expect(fabLabel(tester), kLog);

    final spotting = await h.observations
        .save(h.spotting(profileId, dayEntryId: entry.id));
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    await h.observations.delete(spotting.id);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('an empty day, then the entry and the spotting in two writes, '
      'ends at "Edit today"', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.pump(profileId);
    expect(fabLabel(tester), kLog);

    // The health import's order: an entry with no flow, and only then the
    // spotting that makes it a logged day.
    final entry = await h.saveDay(profileId, kToday);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.observations.save(h.spotting(profileId, dayEntryId: entry.id));
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    // The reminder action's order, on the next day: its entry is already a
    // logged day ("not bleeding"), and stays one when the spotting lands.
    h.now = kToday.addDays(1);
    final next =
        await h.saveDay(profileId, h.now, flow: FlowLevel.notBleeding);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.observations.save(
      h.spotting(profileId, dayEntryId: next.id).copyWith(localDate: h.now),
    );
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('a temperature written on its own flips the label',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    final entry = await h.saveDay(profileId, kToday);
    await h.pump(profileId);
    expect(fabLabel(tester), kLog);

    await h.observations.save(
      h.reading(
        profileId,
        ObservationCategory.bbt,
        36.7,
        'celsius',
        dayEntryId: entry.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('a deleted entry is no longer followed: "Log today" again',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    final entry = await h.saveDay(profileId, kToday);
    await h.pump(profileId);
    await h.observations.save(h.spotting(profileId, dayEntryId: entry.id));
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    await h.entries.delete(profileId, kToday);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('with no observations seam the entry alone decides',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(
      profileId,
      kToday,
      attached: [
        h.reading(profileId, ObservationCategory.bbt, 36.7, 'celsius'),
      ],
    );
    await h.pump(profileId, withObservations: false);
    expect(fabLabel(tester), kLog);

    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('yesterday\'s entry does not make it "Edit today"',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday.addDays(-1), tags: const ['cramps']);
    await h.pump(profileId);

    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('switching profile reads the other profile\'s day',
      (tester) async {
    final h = Harness(tester);
    final alice = await h.createProfile();
    final bea = await h.createProfile('Bea');
    await h.saveDay(alice, kToday, tags: const ['cramps']);
    await h.pump(alice);
    expect(fabLabel(tester), kEdit);

    await h.pump(bea);
    expect(fabLabel(tester), kLog);

    await h.pump(alice);
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('a different "today" is a different day\'s log',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId, todayProvider: () => kToday);
    expect(fabLabel(tester), kEdit);

    await h.pump(profileId, todayProvider: () => kToday.addDays(1));
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('the first write after midnight is read against the new day',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId);
    expect(fabLabel(tester), kEdit);

    // Midnight passes; an empty entry for the new day is the first write.
    h.now = kToday.addDays(1);
    await h.saveDay(profileId, h.now);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);

    await h.saveDay(profileId, h.now, tags: const ['headache']);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);
    await h.dispose();
  });

  testWidgets('opened again the next morning, with nothing written: back to '
      '"Log today"', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId);
    expect(fabLabel(tester), kEdit);

    // Back in the foreground the same day: yesterday has not happened yet.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    h.now = kToday.addDays(1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('at the date rollover, with the app open, the estimate\'s own '
      'recompute is what tells the button', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    // Enough history for an estimate: it is the estimate moving on to the
    // new day that the button hears.
    for (final start in [
      LocalDate(2026, 5, 7),
      LocalDate(2026, 6, 6),
      LocalDate(2026, 7, 6),
      LocalDate(2026, 8, 5),
    ]) {
      for (var day = 0; day < 4; day++) {
        await h.saveDay(profileId, start.addDays(day), flow: FlowLevel.medium);
      }
    }
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId, withPredictions: true);
    expect(fabLabel(tester), kEdit);

    // The ticker firing on the same day changes nothing.
    h.tickDate();
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kEdit);

    h.now = kToday.addDays(1);
    h.tickDate();
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('a tree with no entries repository reads "Log today"',
      (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    await h.pump(profileId, withEntries: false);

    expect(tester.takeException(), isNull);
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });

  testWidgets('a failing entries stream leaves the label as it was, and the '
      'label follows again once the stream recovers', (tester) async {
    final h = Harness(tester);
    final profileId = await h.createProfile();
    final flaky = ErroringDayEntriesRepository(h.entries);
    await h.saveDay(profileId, kToday, tags: const ['cramps']);
    await h.pump(profileId, entriesSeam: flaky);
    expect(fabLabel(tester), kEdit);

    flaky.broken = true;
    await h.entries.delete(profileId, kToday);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the stream error is recorded and dropped, never thrown');
    expect(fabLabel(tester), kEdit, reason: 'the last known answer stands');

    flaky.broken = false;
    await h.saveDay(profileId, kToday);
    await tester.pumpAndSettle();
    expect(fabLabel(tester), kLog);
    await h.dispose();
  });
}
