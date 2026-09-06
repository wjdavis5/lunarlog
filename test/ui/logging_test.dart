/// Widget tests for U5: month calendar, day sheet logging (flow/tags/note),
/// backfill, future-date lock, edit-without-duplicate, delete via tombstone,
/// symptom-only markers, save-failure retention, archived read-only view,
/// and caregiver attribution wiring (issue #79; R1-R7 of the attribution
/// wiring plan).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/mappers.dart' show flowFromDomain;
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart' show GuardianRole;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/fake_auth_service.dart';

/// Fixed "today" so month defaults and future locks are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

class Harness {
  Harness(
    this.db,
    this.profile,
    this.entries, {
    this.authService,
    this.authController,
  });

  final LunarLogDatabase db;
  final Profile profile;
  final DriftDayEntriesRepository entries;

  /// Present only when [pumpLogging] was called with `authService:` (U2;
  /// R1/R7). Exposed so a test can flip the signed-in user mid-flight.
  final FakeAuthService? authService;
  final AuthController? authController;
}

/// Materializes a server-authored guardian row locally, mirroring
/// `test/ui/sharing_flow_test.dart`'s `guardianRow` helper (KTD3) so
/// attribution fixtures stay honest about where `display_name` comes from.
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role, {
  String? displayName,
  String status = 'accepted',
  int serverVersion = 1,
}) =>
    RemoteProfileGuardianRow(
      id: id,
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      serverVersion: serverVersion,
    );

/// Materializes a server-authored day entry carrying attribution stamps
/// (`logged_by_user_id`/`last_modified_by_user_id`). These two columns are
/// only ever written by the `applyRemoteRows` path (KTD3) — the local
/// `DayEntriesRepository.save()` upsert has no parameters for them.
RemoteDayEntryRow dayEntryRow(
  String profileId,
  String id,
  LocalDate date, {
  String? loggedByUserId,
  String? lastModifiedByUserId,
  FlowLevel flow = FlowLevel.medium,
}) =>
    RemoteDayEntryRow(
      id: id,
      profileId: profileId,
      localDate: date.iso,
      tz: 'America/Chicago',
      flow: flowFromDomain(flow),
      tags: const [],
      note: null,
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: null,
      serverVersion: 1,
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

DayEntry entryFor(
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.medium,
  List<String> tags = const [],
  String? note,
}) {
  return DayEntry(
    id: '',
    profileId: profileId,
    localDate: date,
    tz: 'America/Chicago',
    flow: flow,
    tags: tags,
    note: note,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

/// The provider set `pumpLogging` builds (mirrors `lib/app.dart`'s
/// ordering, KTD2), factored out so the profile-switch test (R6) can
/// rebuild the same tree shape at a second `pumpWidget` call without its
/// own copy silently drifting from this one.
List<SingleChildWidget> loggingProviders({
  required ProfilesRepository profiles,
  required DayEntriesRepository dayEntries,
  required SettingsStore settings,
  AuthController? authController,
  LunarLogStorage? storage,
}) =>
    [
      Provider<ProfilesRepository>.value(value: profiles),
      Provider<DayEntriesRepository>.value(value: dayEntries),
      Provider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider(
        create: (_) => ProfileController(
          profilesRepository: profiles,
          settingsStore: settings,
        )..load(),
      ),
      if (authController != null)
        ChangeNotifierProvider<AuthController>.value(value: authController),
      if (storage != null) Provider<LunarLogStorage>.value(value: storage),
    ];

Future<Harness> pumpLogging(
  WidgetTester tester, {
  bool readOnly = false,
  DayEntriesRepository? entryRepositoryOverride,
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
  String Function()? timezoneProvider,
  // Attribution seam (U2; R1/R5/R7). Both default off so every pre-existing
  // test keeps exercising the local-only fallback unchanged (R4).
  FakeAuthService? authService,
  bool withStorage = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) {
    await seed(db, profile.id);
  }
  final entries = DriftDayEntriesRepository(db.storage);

  final authController = authService == null
      ? null
      : AuthController(authService: authService);

  await tester.pumpWidget(
    MultiProvider(
      providers: loggingProviders(
        profiles: profiles,
        dayEntries: entryRepositoryOverride ?? entries,
        settings: settings,
        authController: authController,
        // Matches lib/app.dart's provider set (KTD2): LunarLogStorage is
        // what ProfileDetailScreen reads to decide whether MonthCalendar
        // gets a ProfileGuardiansRepository (R5) at all.
        storage: withStorage ? db.storage : null,
      ),
      child: MaterialApp(
        home: ProfileDetailScreen(
          profile: profile,
          readOnly: readOnly,
          todayProvider: () => kToday,
          timezoneProvider: timezoneProvider,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(
    db,
    profile,
    entries,
    authService: authService,
    authController: authController,
  );
}

/// Must run as the last statement of every test that used [pumpLogging]
/// (same drift-stream teardown discipline as U4's profiles_test).
Future<void> disposeLogging(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  h.authController?.dispose();
  await h.authService?.dispose();
  await h.db.close();
}

Future<void> showMonth(WidgetTester tester, int year, int month) async {
  final label = '${kMonthNames[month - 1]} $year';
  var guard = 0;
  while (find.text(label).evaluate().isEmpty) {
    expect(guard++, lessThan(1200), reason: 'month never reached: $label');
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
  }
  expect(find.text(label), findsOneWidget);
}

/// Repository whose save always fails (F2 failure-state path).
class ThrowingDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<DayEntry> save(DayEntry entry) async {
    throw Exception('simulated write failure');
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => null;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId) =>
      Stream.value(const []);

  @override
  Future<void> delete(String profileId, LocalDate localDate) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('F2 day logging', () {
    testWidgets('logging today (flow + 2 tags + note) persists via the '
        'repository and re-renders from the stream after reopening the sheet',
        (tester) async {
      final h = await pumpLogging(tester);

      expect(find.text('August 2026'), findsOneWidget,
          reason: "today's month is the default");

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Cramps'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Fatigue'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('note-field')), 'rough day');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsNothing);
      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.flow, FlowLevel.medium);
      expect(saved.tags, unorderedEquals(['cramps', 'fatigue']));
      expect(saved.note, 'rough day');
      expect(isValidIanaTimeZone(saved.tz), isTrue,
          reason: 'persists canonical IANA timezone identifier');
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsOneWidget,
          reason: 'stream recompute re-rendered the calendar marker');

      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Medium'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Cramps'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Fatigue'))
            .selected,
        isTrue,
      );
      expect(find.text('rough day'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('backfilling a past date stores against that civil date and '
        'the calendar marker appears', (tester) async {
      final h = await pumpLogging(tester);

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-05')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, LocalDate(2026, 3, 5));
      expect(saved!.localDate, LocalDate(2026, 3, 5));
      expect(saved.flow, FlowLevel.heavy);
      expect(find.byKey(const ValueKey('bleed-2026-03-05')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('future dates cannot be selected and month navigation stops '
        'at the current month', (tester) async {
      final h = await pumpLogging(tester);

      expect(find.byKey(const ValueKey('day-cell-2026-08-31')), findsOneWidget,
          reason: 'future days render but are disabled');
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-31')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);

      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next month'),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull,
          reason: 'cannot navigate forward of the current month');
      await disposeLogging(tester, h);
    });

    testWidgets('the sheet itself refuses future dates even when opened '
        'directly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DaySheet(
              repository: ThrowingDayEntriesRepository(),
              profileId: 'p',
              date: kToday.addDays(1),
              today: kToday,
            ),
          ),
        ),
      );
      expect(find.textContaining("Future dates"), findsOneWidget);
      expect(find.byKey(const ValueKey('save-button')), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('editing flow updates the same record (no duplicate row)',
        (tester) async {
      final h = await pumpLogging(tester);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();
      final first = await h.entries.find(h.profile.id, kToday);
      expect(first!.flow, FlowLevel.light);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final second = await h.entries.find(h.profile.id, kToday);
      expect(second!.flow, FlowLevel.heavy);
      expect(second.id, first.id, reason: 'upsert keyed on profile+date');

      final fullFidelity = await h.db.storage
          .getDayEntries(profileId: h.profile.id, includeTombstones: true);
      final rowsForDate =
          fullFidelity.where((row) => row.localDate == '2026-08-30').toList();
      expect(rowsForDate, hasLength(1));
      await disposeLogging(tester, h);
    });

    testWidgets('saving day entry populates canonical IANA timezone and '
        'respects injected timezoneProvider seam', (tester) async {
      final h = await pumpLogging(
        tester,
        timezoneProvider: () => 'America/New_York',
      );

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.tz, 'America/New_York');
      expect(isValidIanaTimeZone(saved.tz), isTrue);

      await disposeLogging(tester, h);
    });

    testWidgets('editing existing entry updates legacy abbreviation to canonical IANA timezone',
        (tester) async {
      final h = await pumpLogging(
        tester,
        timezoneProvider: () => 'America/Chicago',
        seed: (db, profileId) async {
          // Simulate an existing entry previously written with platform abbreviation 'EDT'.
          await DriftDayEntriesRepository(db.storage).save(
            DayEntry(
              id: '',
              profileId: profileId,
              localDate: kToday,
              tz: 'EDT',
              flow: FlowLevel.medium,
              tags: const [],
              updatedAt: DateTime.utc(2026, 8, 30),
            ),
          );
        },
      );

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      // Change flow to heavy and save
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.flow, FlowLevel.heavy);
      expect(saved.tz, 'America/Chicago');
      expect(isValidIanaTimeZone(saved.tz), isTrue);

      await disposeLogging(tester, h);
    });

    testWidgets('delete confirms and the entry disappears from the calendar '
        'via the stream (AE2 linkage)', (tester) async {
      final h = await pumpLogging(
        tester,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage)
              .save(entryFor(profileId, kToday));
        },
      );

      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsNothing);
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsNothing,
          reason: 'hidden from calendar after tombstone delete');
      expect(await h.entries.find(h.profile.id, kToday), isNull);

      final rows = await h.db.storage
          .getDayEntries(profileId: h.profile.id, includeTombstones: true);
      expect(rows.single.deletedAt, isNotNull,
          reason: 'tombstone persists in storage, invisible in UI');
      await disposeLogging(tester, h);
    });

    testWidgets('tag chips render exactly the curated 17 in 4 categories; '
        'toggling two tags persists both codes', (tester) async {
      final h = await pumpLogging(tester);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsNWidgets(17));
      for (final header in ['Pain', 'Body', 'Mood', 'Other']) {
        expect(find.text(header), findsOneWidget);
      }
      for (final tag in kTagTaxonomy) {
        expect(find.text(tag.display), findsOneWidget);
      }

      await tester.tap(find.text('Headache'));
      await tester.pump();
      await tester.tap(find.text('Cramps'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.tags, unorderedEquals(['cramps', 'headache']));
      await disposeLogging(tester, h);
    });

    testWidgets('symptom-only day (flow none + tags) renders the secondary '
        'marker, not the bleed marker', (tester) async {
      final h = await pumpLogging(
        tester,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage).save(entryFor(
            profileId,
            kToday,
            flow: FlowLevel.none,
            tags: const ['cramps'],
            note: 'meh',
          ));
        },
      );

      expect(find.byKey(const ValueKey('symptom-dot-2026-08-30')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsNothing);
      await disposeLogging(tester, h);
    });

    testWidgets('save failure keeps the sheet open with values intact and '
        'shows the retry error', (tester) async {
      final h =
          await pumpLogging(tester, entryRepositoryOverride: ThrowingDayEntriesRepository());

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('note-field')), 'kept input');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget,
          reason: 'never auto-dismiss on failure');
      expect(find.byKey(const ValueKey('save-error')), findsOneWidget);
      expect(find.text("Couldn't save — try again"), findsOneWidget);
      expect(find.text('kept input'), findsOneWidget,
          reason: 'entered values are never dropped');
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy'))
            .selected,
        isTrue,
      );
      await disposeLogging(tester, h);
    });

    testWidgets('archived profile calendar is read-only: day sheet shows '
        'entry details with no save/delete affordances', (tester) async {
      final h = await pumpLogging(
        tester,
        readOnly: true,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage).save(entryFor(
            profileId,
            LocalDate(2026, 3, 1),
            tags: const ['cramps'],
            note: 'spotty',
          ));
        },
      );

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.text('2026-03-01'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('spotty'), findsOneWidget);
      expect(find.byKey(const ValueKey('save-button')), findsNothing);
      expect(find.byTooltip('Delete entry'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-02')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing,
          reason: 'no entry-creation affordance in read-only mode');
      await disposeLogging(tester, h);
    });
  });

  group('caregiver attribution', () {
    testWidgets('entry logged by the signed-in user shows "Logged by you" '
        '(R1)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-mom'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by you'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('entry logged by another guardian shows their display name '
        '(R2)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent',
                displayName: 'Dad'),
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-dad'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by Dad'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'entry logged by a guardian with no display name shows the role '
        'label (R2)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent'),
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-dad'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by Co-Parent'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'entry logged by a user id with no guardian row shows the generic '
        'fallback, distinct from a real caregiver-role guardian match (R3)',
        (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final matchedDate = kToday.addDays(-1);
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            // A real guardian whose role happens to be "caregiver" — whose
            // label is the literal string 'Caregiver', identical to the
            // no-match fallback text. Giving it a display name and
            // attributing a *separate* entry to it proves the wiring
            // actually looked the guardian up (real name shown) rather
            // than the generic-fallback and matched-caregiver-role cases
            // coincidentally rendering the same text: if the guardian list
            // were ever dropped, this second entry would also read
            // "Logged by Caregiver" instead of "Logged by Nanny".
            guardianRow(profileId, 'g-nanny', 'user-nanny', 'caregiver',
                displayName: 'Nanny'),
            dayEntryRow(profileId, 'e-1', kToday,
                loggedByUserId: 'user-ghost'),
            dayEntryRow(profileId, 'e-2', matchedDate,
                loggedByUserId: 'user-nanny'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Caregiver'), findsOneWidget,
          reason: 'a user id absent from the guardian list falls back to '
              'the generic label');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('day-cell-${matchedDate.iso}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Nanny'), findsOneWidget,
          reason: 'a real guardian whose role label is the same string as '
              'the generic fallback must still resolve to its own display '
              'name, proving the match — not the fallback — produced it');
      expect(find.textContaining('Logged by Caregiver'), findsNothing);

      await disposeLogging(tester, h);
    });

    testWidgets(
        'entry logged by one guardian and last-modified by another shows '
        'both segments', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-someone'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-mom', 'user-mom', 'primary_guardian',
                displayName: 'Mom'),
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent',
                displayName: 'Dad'),
            dayEntryRow(
              profileId,
              'e-1',
              kToday,
              loggedByUserId: 'user-mom',
              lastModifiedByUserId: 'user-dad',
            ),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by Mom • Modified by Dad'),
          findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'signed-out (no AuthController, storage still wired as it always '
        'is per app.dart) resolves a matching guardian\'s display name but '
        'never "you" (R4)', (tester) async {
      // `lib/app.dart` provides `LunarLogStorage` unconditionally (it does
      // not gate on auth), while `AuthController` is only provided `if
      // (authController != null)`. So the real signed-out configuration is
      // `withStorage: true` with no `authService:` — NOT a tree with no
      // storage at all, which can never occur in the shipped app. In that
      // real configuration, `ProfileDetailScreen` still constructs a
      // `ProfileGuardiansRepository` from storage (R5), so `MonthCalendar`
      // still resolves guardians — only `currentUserId` is unavailable
      // (no `AuthController` to read it from).
      final h = await pumpLogging(
        tester,
        // Deliberately no `authService:` — signed out. `withStorage: true`
        // matches app.dart's unconditional storage provider.
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-mom', 'user-mom', 'primary_guardian',
                displayName: 'Mom'),
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-mom'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      // No AuthController means currentUserId is always null, so "you"
      // attribution is impossible while signed out — but the guardians
      // repository is still live (storage is unconditional), so a real
      // guardian match still resolves to its own display name.
      expect(find.textContaining('Logged by Mom'), findsOneWidget,
          reason: 'guardians resolve even while signed out because '
              'ProfileDetailScreen wires the guardians repository from the '
              'unconditional LunarLogStorage provider, independent of auth');
      expect(find.textContaining('you'), findsNothing,
          reason: 'with no AuthController, currentUserId is always null, '
              'so the badge can never render "you" while signed out');
      await disposeLogging(tester, h);
    });

    testWidgets(
        'archived (read-only) day sheet renders the same attribution as '
        'the editable body (R1/R2, second call site)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        readOnly: true,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent',
                displayName: 'Dad'),
            dayEntryRow(profileId, 'e-1', LocalDate(2026, 3, 1),
                loggedByUserId: 'user-dad'),
          ]);
        },
      );

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.textContaining('Logged by Dad'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'switching profiles does not leak the previous profile\'s '
        'guardians (R6)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent',
                displayName: 'Dad'),
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-dad'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Dad'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final profiles = DriftProfilesRepository(h.db.storage);
      final settings = DriftSettingsStore(h.db.storage);
      final profileB =
          await profiles.create(displayName: 'Bob', isMinor: false);
      final dadLeakDate = kToday.addDays(-1);
      await h.db.storage.applyRemoteRows([
        guardianRow(profileB.id, 'g-aunt', 'user-aunt', 'viewer',
            displayName: 'Aunt'),
        dayEntryRow(profileB.id, 'e-2', kToday, loggedByUserId: 'user-aunt'),
        // Attributed to profile A's guardian's *user id*, but profile B
        // registers no guardian for that id. If profile A's guardian list
        // (["Dad"]) ever leaked into profile B's attribution context, this
        // entry would incorrectly resolve to "Logged by Dad" instead of the
        // generic fallback — the real regression this test guards against,
        // as distinct from merely not seeing "Dad" text anywhere by
        // coincidence.
        dayEntryRow(profileB.id, 'e-3', dadLeakDate,
            loggedByUserId: 'user-dad'),
      ]);

      // Rebuild ProfileDetailScreen at the same tree position with the new
      // profile, mirroring how the home gate swaps the active profile
      // in-place (see ProfileDetailScreen's own didUpdateWidget doc). Reuses
      // loggingProviders so this tree shape can never silently drift from
      // pumpLogging's — a like-for-like update, not a remount.
      await tester.pumpWidget(
        MultiProvider(
          providers: loggingProviders(
            profiles: profiles,
            dayEntries: h.entries,
            settings: settings,
            authController: h.authController,
            storage: h.db.storage,
          ),
          child: MaterialApp(
            home: ProfileDetailScreen(
              profile: profileB,
              todayProvider: () => kToday,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Aunt'), findsOneWidget,
          reason: "profile B's own real guardian still resolves correctly "
              'after the switch');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // The load-bearing assertion: an entry attributed to profile A's
      // guardian's user id must resolve to the generic fallback in profile
      // B, not to "Dad" — proving the guardian list actually reset on
      // switch rather than merely never containing an entry that would
      // render "Dad" by coincidence.
      await tester.tap(find.byKey(ValueKey('day-cell-${dadLeakDate.iso}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Caregiver'), findsOneWidget,
          reason: "profile A's guardian must not resolve in profile B's "
              'attribution context');
      expect(find.textContaining('Dad'), findsNothing,
          reason: "profile B must never render profile A's guardian names");

      await disposeLogging(tester, h);
    });

    testWidgets(
        'signing in while the calendar is mounted attributes the next '
        'opened sheet (R7)', (tester) async {
      final auth = FakeAuthService();
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-mom'),
          ]);
        },
      );

      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-mom'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by you'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        "a revoked guardian's past entry still resolves to their display "
        'name (KTD4)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-dad', 'user-dad', 'co_parent',
                displayName: 'Dad', status: 'revoked'),
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-dad'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged by Dad'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'a guardian-list update on the already-open stream is still applied '
        '(guardian-subscription liveness)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          // No guardian row for user-nanny yet — the entry can only
          // resolve to the generic fallback on the first render.
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-nanny'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Caregiver'), findsOneWidget,
          reason: 'no guardian row exists yet for user-nanny');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Write a guardian row onto the SAME db the calendar's guardians
      // stream is already subscribed to (no rebuild, no remount) — this is
      // the only thing that can prove the subscription is still live
      // rather than a one-shot snapshot taken at mount time.
      await h.db.storage.applyRemoteRows([
        guardianRow(h.profile.id, 'g-nanny', 'user-nanny', 'caregiver',
            displayName: 'Nanny'),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by Nanny'), findsOneWidget,
          reason: 'a guardian-list update emitted after the first snapshot '
              'must still reach the badge; a subscription that only ever '
              'consumes the first emission (e.g. `.take(1)`) would keep '
              'showing the stale generic fallback forever');
      await disposeLogging(tester, h);
    });

    testWidgets(
        'the read-only day sheet badge renders "Logged by you" when '
        'currentUserId matches the entry, proving the read-only call site '
        'forwards it', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        readOnly: true,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', LocalDate(2026, 3, 1),
                loggedByUserId: 'user-mom'),
          ]);
        },
      );

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      // The entry is logged by the signed-in user, so the badge's content
      // depends on `currentUserId` reaching the read-only body's
      // CaregiverAttributionBadge: if that path dropped or nulled it,
      // `_formatUser` could never take the "you" branch and this would
      // instead read the generic "Logged by Caregiver" fallback (no
      // guardian row exists for user-mom here).
      expect(find.textContaining('Logged by you'), findsOneWidget,
          reason: 'the read-only badge must receive the real currentUserId');
      await disposeLogging(tester, h);
    });

    testWidgets(
        'signing out while the calendar is mounted clears attribution for '
        'the next opened sheet (sign-out leg of _onAuthChanged)',
        (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', kToday, loggedByUserId: 'user-mom'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by you'), findsOneWidget,
          reason: 'sanity check: starts signed in with attribution showing');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      auth.emit(AuthSessionState.signedOut);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Logged by you'), findsNothing,
          reason: 'signing out must clear currentUserId so the same entry '
              'can no longer render as attributed to "you"');
      expect(find.textContaining('Logged by Caregiver'), findsOneWidget,
          reason: 'with currentUserId cleared and no guardian row for '
              'user-mom, the badge falls back to the generic label — this '
              'fails if the sign-out leg of _onAuthChanged is ignored');
      await disposeLogging(tester, h);
    });
  });

  group('viewer role read-only (U6)', () {
    testWidgets(
        'caller is an accepted viewer: tapping a day opens the read-only '
        'sheet, with no flow selector, tag chips, or note field (R13)',
        (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-doc'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
          ]);
          await db.storage.applyRemoteRows([
            dayEntryRow(profileId, 'e-1', kToday),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byKey(const ValueKey('note-field')), findsNothing);
      expect(find.byKey(const ValueKey('save-button')), findsNothing);
      expect(find.text(GuardianRole.viewer.readOnlyReason!), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('caller is an accepted caregiver: the day sheet is writable',
        (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-sitter'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-sitter', 'user-sitter', 'caregiver'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'caller is an accepted co_parent or primary_guardian: writable',
        (tester) async {
      for (final role in ['co_parent', 'primary_guardian']) {
        final auth = FakeAuthService()
          ..emit(AuthSessionState.signedIn,
              user: const AuthUser(id: 'user-parent'));
        final h = await pumpLogging(
          tester,
          authService: auth,
          withStorage: true,
          seed: (db, profileId) async {
            await db.storage.applyRemoteRows([
              guardianRow(profileId, 'g-parent', 'user-parent', role),
            ]);
          },
        );

        await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('save-button')), findsOneWidget,
            reason: '$role must be writable');
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        await disposeLogging(tester, h);
      }
    });

    testWidgets(
        'caller is a viewer on an archived profile: read-only, and the copy '
        'names the view-only reason rather than only the archive reason '
        '(R14)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-doc'));
      final h = await pumpLogging(
        tester,
        readOnly: true,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
            dayEntryRow(profileId, 'e-1', LocalDate(2026, 3, 1)),
          ]);
        },
      );

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.text(GuardianRole.viewer.readOnlyReason!), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'guardian rows have not synced (empty list): writable, not '
        'read-only (R15)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'currentUserId is null (no account, local-only operator): writable '
        '(R15)', (tester) async {
      final h = await pumpLogging(tester, withStorage: true);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        'guardian rows exist but none match the current user: writable '
        '(R15)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-mom'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets(
        "the caller's row exists with status revoked: this path does not "
        'additionally crash on a missing accepted role', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-doc'));
      final h = await pumpLogging(
        tester,
        authService: auth,
        withStorage: true,
        seed: (db, profileId) async {
          await db.storage.applyRemoteRows([
            guardianRow(profileId, 'g-doc', 'user-doc', 'viewer',
                status: 'revoked'),
          ]);
        },
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.byKey(const ValueKey('save-button')), findsOneWidget,
          reason: 'a non-accepted row is not a viewer - fails open (R15)');
      await disposeLogging(tester, h);
    });

    test('the read-only copy for the viewer case is asserted from '
        'GuardianRole, not from a literal in the widget', () {
      expect(GuardianRole.viewer.readOnlyReason,
          'You have view-only access to this profile.');
      for (final role
          in GuardianRole.values.where((r) => r != GuardianRole.viewer)) {
        expect(role.readOnlyReason, isNull,
            reason: '$role can log, so it has no read-only reason to show');
      }
    });
  });
}
