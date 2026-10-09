/// Issue #1712: a spotting read that started for one profile (or an older
/// window) must never paint its markers on the next profile's calendar, and
/// a failed read must not surface as an unhandled async error or leave an
/// older set up.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

final LocalDate _today = LocalDate(2026, 8, 30);

/// A spotting observation hangs off a day entry (the day sheet's own
/// `notBleeding` + observation shape), and the calendar's ring renders only
/// for a day that has an entry — so both are seeded together.
DayEntry _entryFor(String profileId, LocalDate date) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: date,
  tz: 'America/Chicago',
  flow: FlowLevel.notBleeding,
  tags: const [],
  updatedAt: DateTime.utc(2026, 1, 1),
);

List<Observation> _spottingObservations(String profileId, Set<String> isos) => [
  for (final iso in isos)
    Observation(
      id: 'obs-$iso',
      dayEntryId: 'entry-$iso',
      profileId: profileId,
      localDate: LocalDate.fromIso(iso),
      tz: 'America/Chicago',
      category: ObservationCategory.spotting,
      code: 'spotting',
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
];

/// A [SpottingObservationsRangeRepository] whose reads resolve from
/// [spotting] per profile, or from a test-completed [pending] future when
/// one is registered; a profile in [failing] throws instead.
class _FakeSpotting implements SpottingObservationsRangeRepository {
  final spotting = <String, Set<String>>{};
  final pending = <String, Completer<List<Observation>>>{};
  final failing = <String>{};

  @override
  Future<List<Observation>> listSpottingObservationsInRange({
    required String profileId,
    required LocalDate from,
    required LocalDate to,
  }) {
    final completer = pending[profileId];
    if (completer != null) return completer.future;
    if (failing.contains(profileId)) {
      throw StateError('simulated spotting read failure');
    }
    return Future.value(
      _spottingObservations(profileId, spotting[profileId] ?? const {}),
    );
  }

  @override
  Future<List<Observation>> listForProfile(String profileId) async =>
      _spottingObservations(profileId, spotting[profileId] ?? const {});

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
    String dayEntryId,
  ) async => const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

/// The calendar over [entries]/[observations]; pumping it again with another
/// [profileId] updates it in place, exactly as the shell does on a switch
/// (no key).
Widget _host(
  DayEntriesRepository entries,
  ObservationsRepository observations, {
  required String profileId,
}) {
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<ObservationsRepository>.value(value: observations),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MonthCalendar(
          profileId: profileId,
          todayProvider: () => _today,
          observationsRepository: observations,
        ),
      ),
    ),
  );
}

Future<void> _tearDown(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a spotting read in flight for the previous profile is dropped '
      'after the switch', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    final p2 = await profiles.create(displayName: 'Bea', isMinor: false);
    final observations = _FakeSpotting();
    observations.spotting[p2.id] = {'2026-08-12'};
    observations.pending[p1.id] = Completer<List<Observation>>();
    await entries.save(_entryFor(p2.id, LocalDate(2026, 8, 12)));
    // The stale read's own day: it must have an entry for its marker to be
    // visible at all, which is what makes the pre-fix failure observable.
    await entries.save(_entryFor(p1.id, LocalDate(2026, 8, 10)));

    await tester.pumpWidget(_host(entries, observations, profileId: p1.id));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-12')),
      findsNothing,
      reason: 'sanity: the first profile\'s read has not landed yet',
    );

    await tester.pumpWidget(_host(entries, observations, profileId: p2.id));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-12')),
      findsOneWidget,
      reason: 'sanity: the new profile\'s own spotting marker renders',
    );

    observations.pending[p1.id]!.complete(
      _spottingObservations(p1.id, {'2026-08-10'}),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-10')),
      findsNothing,
      reason: 'issue #1712: the previous profile\'s read must not paint',
    );
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-12')),
      findsOneWidget,
      reason: 'the new profile\'s own markers stay',
    );

    await _tearDown(tester, db);
  });

  testWidgets('a failed spotting read clears the markers without an '
      'unhandled error', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    final observations = _FakeSpotting();
    observations.spotting[p1.id] = {'2026-08-12'};
    await entries.save(_entryFor(p1.id, LocalDate(2026, 8, 12)));

    await tester.pumpWidget(_host(entries, observations, profileId: p1.id));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-12')),
      findsOneWidget,
    );

    // The next entries tick re-reads; make that read fail.
    observations.failing.add(p1.id);
    await entries.save(_entryFor(p1.id, LocalDate(2026, 8, 13)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('flow-spotting-dot-2026-08-12')),
      findsNothing,
      reason: 'issue #1712: a failed read must not leave stale markers up',
    );

    await _tearDown(tester, db);
  });
}
