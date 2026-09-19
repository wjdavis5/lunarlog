/// Issue #856: the day sheet's delete is the only destructive action on the
/// logging path, and it used to have no undo -- the confirm dialog was the
/// whole guard. Deleting tombstones the day entry *and* cascades to every
/// live observation attached to it (spotting, graded pain intensity, BBT,
/// weight), so the undo has to capture the full pre-delete state and revive
/// the same rows, not just re-insert the entry.
///
/// These tests drive the real Drift repositories (not fakes) so they can
/// assert the restored entry and observation payloads end to end. The
/// shared repo pattern these mirror is `overview_panel.dart`'s
/// `today-card-logged-snackbar` Undo (issue #316) -- same content-plus-
/// action snackbar shape and default duration.
library;

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
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// A real-repository harness around one seeded day entry plus its child
/// observations, exposing the saved [entry] so the sheet opens on an
/// existing day (the only state that renders Delete).
class Harness {
  Harness(this.db);

  final LunarLogDatabase db;

  late DriftDayEntriesRepository entries;
  late DriftObservationsRepository observations;
  late String profileId;
  late String otherProfileId;
  late DayEntry entry;

  final ValueNotifier<String> activeProfile = ValueNotifier<String>('');

  Future<void> seed() async {
    final profiles = DriftProfilesRepository(db.storage);
    profileId = (await profiles.create(displayName: 'Alice', isMinor: false)).id;
    otherProfileId =
        (await profiles.create(displayName: 'Bob', isMinor: false)).id;
    activeProfile.value = profileId;

    entries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    entry = await entries.save(DayEntry(
      id: '',
      profileId: profileId,
      localDate: kToday,
      tz: 'UTC',
      flow: FlowLevel.medium,
      tags: const ['cramps'],
      note: 'tender',
      pms: true,
      updatedAt: DateTime.utc(2026, 1, 1),
    ));
    await _seedObservation(
      category: 'spotting',
      code: 'spotting',
    );
    await _seedObservation(
      category: 'pain',
      code: 'cramps',
      intensity: 4,
    );
    await _seedObservation(
      category: 'bbt',
      valueNum: 36.6,
      unit: 'celsius',
    );
    await _seedObservation(
      category: 'weight',
      valueNum: 61,
      unit: 'kg',
    );
  }

  Future<void> _seedObservation({
    required String category,
    String? code,
    double? valueNum,
    String? unit,
    int? intensity,
  }) async {
    await observations.save(Observation(
      id: '',
      dayEntryId: entry.id,
      profileId: profileId,
      localDate: kToday,
      tz: 'UTC',
      category: category,
      code: code,
      valueNum: valueNum,
      unit: unit,
      intensity: intensity,
      updatedAt: DateTime.utc(2026, 1, 1),
    ));
  }

  Future<void> dispose() async {
    activeProfile.dispose();
    await db.close();
  }
}

Future<Harness> pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final h = Harness(LunarLogDatabase(NativeDatabase.memory()));
  await h.seed();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ObservationsRepository>.value(value: h.observations),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: h.activeProfile,
                    builder: (_, id, _) => Text('active:$id'),
                  ),
                  FilledButton(
                    key: const ValueKey('open-day-sheet'),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => DaySheet(
                        repository: h.entries,
                        profileId: h.profileId,
                        date: kToday,
                        today: kToday,
                        existing: h.entry,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-day-sheet')));
  await tester.pumpAndSettle();
  return h;
}

/// The shared delete flow: confirm the dialog and settle the post-pop frame.
Future<void> deleteEntry(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Delete entry'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
      'delete shows an Undo snackbar; Undo restores the entry and every '
      'observation it carried', (tester) async {
    final h = await pumpSheet(tester);

    await deleteEntry(tester);

    expect(find.byKey(const ValueKey('day-sheet-delete-snackbar')),
        findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    expect(await h.entries.find(h.profileId, kToday), isNull,
        reason: 'the entry is tombstoned before Undo is tapped');
    expect(await h.observations.listForDayEntry(h.entry.id), isEmpty,
        reason: 'the delete cascade cleared the child observations too');

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();

    final restored = await h.entries.find(h.profileId, kToday);
    expect(restored, isNotNull, reason: 'Undo revives the tombstoned day');
    expect(restored!.id, h.entry.id,
        reason: 'the same row is revived -- not a fresh entry with a new id');
    expect(restored.flow, FlowLevel.medium);
    expect(restored.tags, const ['cramps']);
    expect(restored.note, 'tender');
    expect(restored.pms, isTrue);

    final restoredObs = await h.observations.listForDayEntry(h.entry.id);
    final byCategory = {
      for (final o in restoredObs) o.category: o,
    };
    expect(byCategory['spotting'], isNotNull,
        reason: 'spotting is an observation row, not the entry flow');
    expect(byCategory['pain']!.code, 'cramps');
    expect(byCategory['pain']!.intensity, 4,
        reason: 'graded tag intensity must survive the round trip');
    expect(byCategory['bbt']!.valueNum, 36.6);
    expect(byCategory['weight']!.valueNum, 61);

    await h.dispose();
  });

  testWidgets('letting the snackbar expire leaves the entry deleted',
      (tester) async {
    final h = await pumpSheet(tester);

    await deleteEntry(tester);
    expect(find.byKey(const ValueKey('day-sheet-delete-snackbar')),
        findsOneWidget);

    // No Undo tap: let the snackbar go away on its own. (Material's
    // action-bearing SnackBar is persistent in this Flutter version rather
    // than auto-timing out, so dismissal is explicit here -- the point is
    // that the undo only ever runs from an explicit tap.)
    final context = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('day-sheet-delete-snackbar')),
        findsNothing);
    expect(await h.entries.find(h.profileId, kToday), isNull,
        reason: 'an expired/ignored snackbar must never resurrect the entry');
    expect(await h.observations.listForDayEntry(h.entry.id), isEmpty);

    await h.dispose();
  });

  testWidgets(
      'Undo after the active profile has moved on restores to the entry\'s '
      'own profile, never the newly-active one', (tester) async {
    final h = await pumpSheet(tester);

    await deleteEntry(tester);
    expect(await h.entries.find(h.profileId, kToday), isNull);

    // The operator switches profiles while the snackbar is still up. The
    // restore is keyed to the captured entry's profileId, so it must land
    // back on Alice even though Bob is active now.
    h.activeProfile.value = h.otherProfileId;
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();

    expect(await h.entries.find(h.profileId, kToday), isNotNull,
        reason: 'Alice\'s deleted entry is restored under Alice');
    expect(await h.entries.find(h.otherProfileId, kToday), isNull,
        reason: 'Bob was never touched -- undo must not resurrect onto the '
            'newly-active profile');

    await h.dispose();
  });
}
