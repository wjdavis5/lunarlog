/// `GuardianOverviewCard` (Issue #850 U5, issue #1710): the per-profile
/// logistics facts — "last logged", tag count, note-present — must follow
/// the profile the card is showing, refresh after a save, and never apply a
/// read that was started for a previous profile.
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
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/guardian_overview_card.dart';
import 'package:provider/provider.dart';

final LocalDate _today = LocalDate(2026, 8, 30);

DayEntry _entry({
  required String profileId,
  required LocalDate date,
  List<String> tags = const [],
  String? loggedByUserId,
}) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: date,
  tz: 'America/Chicago',
  flow: FlowLevel.medium,
  tags: tags,
  note: null,
  updatedAt: DateTime.utc(2026, 1, 1),
  deletedAt: null,
  loggedByUserId: loggedByUserId,
);

/// A [DriftDayEntriesRepository] whose `latestEntryFor` for a profile the
/// test names resolves only when the test completes its completer.
class _PendingLatestReader extends DriftDayEntriesRepository {
  _PendingLatestReader(super.storage);

  final pending = <String, Completer<DayEntry?>>{};

  @override
  Future<DayEntry?> latestEntryFor(String profileId) {
    final completer = pending[profileId];
    if (completer != null) return completer.future;
    return super.latestEntryFor(profileId);
  }
}

/// The card over [entries], with everything else the guardian lens does not
/// need here kept minimal. Pumping it again with another [profileId] updates
/// the card in place, exactly as the shell does on a profile switch (no key).
Widget _host(
  DayEntriesRepository entries, {
  required String profileId,
  required String subjectName,
}) {
  return Provider<DayEntriesRepository>.value(
    value: entries,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GuardianOverviewCard(
          profileId: profileId,
          subjectName: subjectName,
          prediction: const NotEnoughHistory(
            episodeCount: 0,
            completedCycleCount: 0,
            validCycleCount: 0,
            usableCycleCount: 0,
          ),
          today: _today,
          guardians: const [],
          currentUserId: 'me',
          canAct: true,
          onAddNote: () {},
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

  testWidgets('a profile switch replaces the previous subject\'s facts',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    final p2 = await profiles.create(displayName: 'Bea', isMinor: false);
    await entries.save(
      _entry(
        profileId: p1.id,
        date: _today.addDays(-3),
        tags: const ['cramps'],
        loggedByUserId: 'me',
      ),
    );
    await entries.save(
      _entry(
        profileId: p2.id,
        date: _today.addDays(-1),
        loggedByUserId: 'me',
      ),
    );

    await tester.pumpWidget(
      _host(entries, profileId: p1.id, subjectName: 'Ada'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Last logged 3 days ago'), findsOneWidget);
    expect(find.text('1 tag logged'), findsOneWidget);

    await tester.pumpWidget(
      _host(entries, profileId: p2.id, subjectName: 'Bea'),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Last logged 1 day ago'),
      findsOneWidget,
      reason: 'issue #1710: the new subject\'s own facts must render',
    );
    expect(find.text('No tags or note recorded for that day.'), findsOneWidget);
    expect(
      find.textContaining('Last logged 3 days ago'),
      findsNothing,
      reason: 'the previous subject\'s facts must not linger',
    );

    await _tearDown(tester, db);
  });

  testWidgets('a never-logged subject stops reading "No days logged yet" '
      'once another subject with entries is selected', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    final p2 = await profiles.create(displayName: 'Bea', isMinor: false);
    await entries.save(
      _entry(
        profileId: p2.id,
        date: _today.addDays(-1),
        loggedByUserId: 'me',
      ),
    );

    await tester.pumpWidget(
      _host(entries, profileId: p1.id, subjectName: 'Ada'),
    );
    await tester.pumpAndSettle();
    expect(find.text('No days logged yet.'), findsOneWidget);

    await tester.pumpWidget(
      _host(entries, profileId: p2.id, subjectName: 'Bea'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Last logged 1 day ago'), findsOneWidget);
    expect(find.text('No days logged yet.'), findsNothing);

    await _tearDown(tester, db);
  });

  testWidgets('the facts refresh when the parent rebuilds after a save',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    await entries.save(
      _entry(
        profileId: p1.id,
        date: _today.addDays(-3),
        loggedByUserId: 'me',
      ),
    );

    await tester.pumpWidget(
      _host(entries, profileId: p1.id, subjectName: 'Ada'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Last logged 3 days ago'), findsOneWidget);
    expect(find.text('No tags or note recorded for that day.'), findsOneWidget);

    await entries.save(
      _entry(
        profileId: p1.id,
        date: _today.addDays(-1),
        tags: const ['cramps'],
        loggedByUserId: 'me',
      ),
    );
    // The same profile, rebuilt as the panel does after an entry write.
    await tester.pumpWidget(
      _host(entries, profileId: p1.id, subjectName: 'Ada'),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Last logged 1 day ago'),
      findsOneWidget,
      reason: 'issue #1710: a save must refresh the card\'s own facts',
    );
    expect(find.text('1 tag logged'), findsOneWidget);

    await _tearDown(tester, db);
  });

  testWidgets('a read in flight for the previous profile is dropped after '
      'the switch', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = _PendingLatestReader(db.storage);
    final p1 = await profiles.create(displayName: 'Ada', isMinor: false);
    final p2 = await profiles.create(displayName: 'Bea', isMinor: false);
    await entries.save(
      _entry(
        profileId: p2.id,
        date: _today.addDays(-1),
        loggedByUserId: 'me',
      ),
    );
    entries.pending[p1.id] = Completer<DayEntry?>();

    await tester.pumpWidget(
      _host(entries, profileId: p1.id, subjectName: 'Ada'),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guardian-overview-last-logged')),
      findsNothing,
      reason: 'sanity: the first subject\'s read has not landed yet',
    );

    await tester.pumpWidget(
      _host(entries, profileId: p2.id, subjectName: 'Bea'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Last logged 1 day ago'), findsOneWidget);

    entries.pending[p1.id]!.complete(
      _entry(profileId: p1.id, date: _today, loggedByUserId: 'me'),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Last logged 1 day ago'),
      findsOneWidget,
      reason: 'issue #1710: the previous profile\'s read must not repaint '
          'the card',
    );
    expect(find.textContaining('Last logged 0 days ago'), findsNothing);

    await _tearDown(tester, db);
  });
}
