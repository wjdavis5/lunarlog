/// Issue #1489: the Today log card mounted in [OverviewPanel] — where it
/// sits, that it is there in every estimate state, that it follows today's
/// entry live, who gets its Edit action, and that the guardian lens never
/// gets it.
///
/// The card's own rendering (lines, the six-tag rule, the screen-reader
/// sentence) is covered by `test/ui/components/today_log_card_test.dart`;
/// the rule for "is anything logged today" by
/// `test/domain/logging/today_log_test.dart`.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/app_shell_scope.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../support/fake_auth_service.dart';

/// Fixed "today" so the seeded estimates are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

const Key kCard = ValueKey('today-log-card');
const Key kEdit = ValueKey('today-log-edit');
const Key kDisclaimer = ValueKey('overview-disclaimer');

const String kEmptyLine = 'Nothing logged today yet';

/// A note's text in these tests, and the words in it that appear nowhere
/// else on the panel. Nothing Today renders or announces may contain them.
const String kNoteText = 'zebra crossing after the dentist';
const List<String> kNoteWords = ['zebra', 'crossing', 'dentist'];

/// Six 30-day episodes ending 2026-08-05: an active estimate on [kToday],
/// cycle day 26, nothing late.
final List<LocalDate> kActiveStarts = [
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

RemoteProfileGuardianRow guardianRow(
  String profileId,
  String userId,
  String role, {
  bool isSubject = false,
}) =>
    RemoteProfileGuardianRow(
      id: 'g-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      status: 'accepted',
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      serverVersion: 1,
      isSubject: isSubject,
    );

/// A tag registry whose one stream the test feeds by hand.
class _HandFedTagRegistry implements TagRegistryRepository {
  final StreamController<List<CustomTag>> controller =
      StreamController<List<CustomTag>>();

  @override
  Stream<List<CustomTag>> watchForProfile(String profileId) =>
      controller.stream;

  Future<void> close() => controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// An observations seam whose every read fails.
class _FailingObservations implements ObservationsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('observations read failed');
}

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    profiles = DriftProfilesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    entries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    tagRegistry = DriftTagRegistryRepository(db.storage);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftSettingsStore settings;
  late final DriftDayEntriesRepository entries;
  late final DriftObservationsRepository observations;
  late final DriftTagRegistryRepository tagRegistry;

  /// "Today" as the panel sees it. One stable closure reads this, so a
  /// test can move the clock without the panel being told.
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

  late final NotificationPermissionState _permission =
      NotificationPermissionState(NotificationAvailability.available);
  late final CyclePredictionService _predictions = CyclePredictionService(
    entries,
    settings: settings,
    profiles: profiles,
    dateTicker: _dateTicker,
    birthControlStateFor: (profileId) =>
        db.storage.watchProfileMode(profileId).map(
              (row) => row == null
                  ? null
                  : (
                      method: row.birthControlMethod,
                      startedOn: row.birthControlStartedOn,
                      stoppedOn: row.birthControlStoppedOn,
                    ),
            ),
  );
  late final CycleHistoryService _history =
      CycleHistoryService(entries, settings: settings);

  Future<Profile> createProfile({
    String name = 'Alice',
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      profiles.create(
        displayName: name,
        isMinor: false,
        bbtUnit: bbtUnit,
        weightUnit: weightUnit,
      );

  /// Logs a four-day period starting on each of [starts].
  Future<void> logPeriods(String profileId, List<LocalDate> starts) async {
    for (final start in starts) {
      for (var i = 0; i < 4; i++) {
        await saveDay(profileId, start.addDays(i), flow: FlowLevel.medium);
      }
    }
  }

  /// Saves the entry for [date], with [attached] written in the same
  /// transaction the way the day sheet's autosave writes them.
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

  /// An observation to attach to [date]'s entry in [saveDay].
  Observation attachment(
    String profileId,
    LocalDate date,
    ObservationCategory category, {
    double? valueNum,
    String? unit,
  }) =>
      Observation(
        id: '',
        dayEntryId: '',
        profileId: profileId,
        localDate: date,
        tz: 'America/Chicago',
        category: category,
        code: category == ObservationCategory.spotting ? 'spotting' : null,
        valueNum: valueNum,
        unit: unit,
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// Signs [userId] in. The controller and the fake are torn down with the
  /// test.
  AuthController signIn(String userId) {
    final auth = FakeAuthService()
      ..emit(AuthSessionState.signedIn, user: AuthUser(id: userId));
    final controller = AuthController(authService: auth);
    addTearDown(() async {
      controller.dispose();
      await auth.dispose();
    });
    return controller;
  }

  /// Pumps a bare [OverviewPanel] for [profile] over the real repositories.
  /// Pumping again keeps the panel's state, so a second call with another
  /// profile is a profile switch.
  Future<void> pump(
    Profile profile, {
    bool readOnly = false,
    AuthController? auth,
    bool withGuardians = false,
    bool inShell = false,
    DayEntriesRepository? entriesSeam,
    ObservationsRepository? observationsSeam,
    bool withObservations = true,
    bool withTagRegistry = true,
    TagRegistryRepository? tagRegistrySeam,
    LocalDate Function()? todayProvider,
    double textScale = 1.0,
    Size physicalSize = const Size(800, 1400),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Widget panel = Scaffold(
      body: OverviewPanel(
        profileId: profile.id,
        profile: profile,
        todayProvider: todayProvider ?? _today,
        readOnly: readOnly,
        timezoneProvider: () => 'America/Chicago',
        guardiansRepository: withGuardians
            ? DriftProfileGuardiansRepository(db.storage)
            : null,
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entriesSeam ?? entries),
          if (withObservations)
            Provider<ObservationsRepository>.value(
              value: observationsSeam ?? observations,
            ),
          if (withTagRegistry)
            Provider<TagRegistryRepository>.value(
              value: tagRegistrySeam ?? tagRegistry,
            ),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(value: _predictions),
          Provider<CycleHistoryService>.value(value: _history),
          Provider<CycleExclusionList>.value(
            value: CycleExclusionList(settings),
          ),
          ChangeNotifierProvider<NotificationPermissionState>.value(
            value: _permission,
          ),
          if (auth != null)
            ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: inShell
              ? AppShellScope(
                  current: AppTab.today,
                  select: (_) {},
                  child: panel,
                )
              : panel,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Same drift-stream teardown discipline as the other overview suites.
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

/// Everything the log card's own text widgets show.
List<String> cardTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(kCard), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? '')
    .toList();

/// Everything a screen reader would be given anywhere on screen.
String spokenText(WidgetTester tester) {
  final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
  final spoken = <String>[];
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    spoken.addAll([data.label, data.value, data.hint, data.tooltip]);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(owner.rootSemanticsNode!);
  return spoken.join(' | ');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the card is there in every estimate state', () {
    // Each state's own card key, and how to put the profile in that state.
    final states = <String,
        ({Key estimate, Future<void> Function(Harness h, Profile p) arrange})>{
      'an active estimate': (
        estimate: const ValueKey('overview-active'),
        arrange: (h, p) => h.logPeriods(p.id, kActiveStarts),
      ),
      'not enough history': (
        estimate: const ValueKey('overview-not-enough'),
        arrange: (h, p) async {},
      ),
      'a suppressed estimate': (
        estimate: const ValueKey('predictions-suppressed'),
        arrange: (h, p) => h.db.storage.upsertProfileMode(
              profileId: p.id,
              mode: 'tracking',
              birthControlMethod: BirthControlMethod.implant.toDb(),
              birthControlStartedOn: '2026-01-01',
            ),
      ),
      'estimates turned off': (
        estimate: const ValueKey('predictions-disabled'),
        arrange: (h, p) =>
            h.settings.set(predictionsEnabledSettingKey(p.id), 'false'),
      ),
    };

    for (final MapEntry(key: name, value: state) in states.entries) {
      testWidgets('$name, nothing logged today: the quiet line, under the '
          'estimate and above the disclaimer', (tester) async {
        final h = Harness(tester);
        final profile = await h.createProfile();
        await state.arrange(h, profile);
        await h.pump(profile);

        expect(find.byKey(state.estimate), findsOneWidget);
        expect(find.byKey(kCard), findsOneWidget);
        expect(cardTexts(tester), [kEmptyLine]);
        expect(find.byKey(kEdit), findsNothing);
        expect(
          tester.getTopLeft(find.byKey(kCard)).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.byKey(state.estimate)).dy,
          ),
        );
        expect(
          tester.getBottomLeft(find.byKey(kCard)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byKey(kDisclaimer)).dy),
        );
        await h.dispose();
      });

      testWidgets('$name, something logged today: the summary and Edit',
          (tester) async {
        final h = Harness(tester);
        final profile = await h.createProfile();
        await state.arrange(h, profile);
        await h.saveDay(profile.id, kToday, tags: const ['cramps']);
        await h.pump(profile);

        expect(find.byKey(state.estimate), findsOneWidget);
        expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);
        expect(
          tester.getTopLeft(find.byKey(kCard)).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.byKey(state.estimate)).dy,
          ),
        );
        await h.dispose();
      });
    }

    testWidgets('inside a shell the card sits above "See cycle history"',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.logPeriods(profile.id, kActiveStarts);
      await h.pump(profile, inShell: true);

      const link = ValueKey('overview-see-history-link');
      expect(find.byKey(link), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(kCard)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(link)).dy),
      );
      await h.dispose();
    });
  });

  group('what the card says', () {
    testWidgets('flow, tags and a note; never the note\'s text',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(
        profile.id,
        kToday,
        flow: FlowLevel.medium,
        tags: const ['cramps', 'headache'],
        note: kNoteText,
      );
      await h.pump(profile);

      expect(cardTexts(tester), [
        'Logged today',
        'Edit',
        'Medium flow',
        'Cramps, Headache',
        'Note added',
      ]);
      final spoken = spokenText(tester);
      expect(
        spoken,
        contains('Logged today: Medium flow. Cramps, Headache. Note added.'),
      );
      for (final word in kNoteWords) {
        expect(
          find.textContaining(word, findRichText: true),
          findsNothing,
          reason: '"$word" is from the note',
        );
        expect(spoken, isNot(contains(word)), reason: '"$word" is from the note');
      }
      handle.dispose();
      await h.dispose();
    });

    testWidgets('an entry left with nothing on it is nothing logged',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday);
      await h.pump(profile);

      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });

    testWidgets('yesterday\'s entry is not today\'s', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday.addDays(-1), tags: const ['cramps']);
      await h.pump(profile);

      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });

    testWidgets('a spotting day reads "Spotting"', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(
        profile.id,
        kToday,
        // What the day sheet writes for a spotting-only day (#247).
        flow: FlowLevel.notBleeding,
        attached: [
          h.attachment(profile.id, kToday, ObservationCategory.spotting),
        ],
      );
      await h.pump(profile);

      expect(cardTexts(tester), ['Logged today', 'Edit', 'Spotting']);
      await h.dispose();
    });

    testWidgets('a custom tag reads by the name it was given, and follows a '
        'rename', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      final custom = await h.tagRegistry
          .create(profileId: profile.id, label: 'Back cracking');
      await h.saveDay(profile.id, kToday, tags: [custom.code, 'cramps']);
      await h.pump(profile);

      expect(find.text('Back cracking, Cramps'), findsOneWidget);
      expect(find.textContaining(custom.code), findsNothing);

      await h.tagRegistry.rename(tagId: custom.id, label: 'Spine pops');
      await tester.pumpAndSettle();
      expect(find.text('Spine pops, Cramps'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('with no tag registry in the tree a custom tag is shown by '
        'its code, not dropped', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, tags: const ['back_cracking']);
      await h.pump(profile, withTagRegistry: false);

      expect(cardTexts(tester), ['Logged today', 'Edit', 'back_cracking']);
      await h.dispose();
    });

    testWidgets('a failing tag registry stream leaves the card standing, '
        'and the names arrive once it recovers', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      final registry = _HandFedTagRegistry();
      await h.saveDay(profile.id, kToday, tags: const ['back_cracking']);
      await h.pump(profile, tagRegistrySeam: registry);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'back_cracking']);

      registry.controller.addError(StateError('simulated'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'back_cracking']);

      registry.controller.add([
        CustomTag(
          id: 't1',
          profileId: profile.id,
          code: 'back_cracking',
          displayName: 'Back cracking',
          category: kCustomTagCategory,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Back cracking']);
      await h.dispose();
      // Not awaited: under the widget test's fake clock an await on this
      // already-finished future never resumes, and the test hangs.
      unawaited(registry.close());
    });

    testWidgets('a temperature-only day is a logged day, in the profile\'s '
        'unit', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile(bbtUnit: BbtUnit.fahrenheit);
      await h.saveDay(
        profile.id,
        kToday,
        attached: [
          h.attachment(
            profile.id,
            kToday,
            ObservationCategory.bbt,
            valueNum: 37,
            unit: 'celsius',
          ),
        ],
      );
      await h.pump(profile);

      expect(cardTexts(tester), ['Logged today', 'Edit', 'BBT (°F): 98.6']);
      await h.dispose();
    });

    testWidgets('with no observations seam the card still says what the '
        'entry holds', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(
        profile.id,
        kToday,
        flow: FlowLevel.notBleeding,
        tags: const ['cramps'],
        attached: [
          h.attachment(profile.id, kToday, ObservationCategory.spotting),
        ],
      );
      await h.pump(profile, withObservations: false);

      expect(
        cardTexts(tester),
        ['Logged today', 'Edit', 'Not bleeding', 'Cramps'],
      );
      await h.dispose();
    });

    testWidgets('a failing observations read costs the readings, not the '
        'card', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, flow: FlowLevel.light);
      await h.pump(profile, observationsSeam: _FailingObservations());

      expect(tester.takeException(), isNull);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Light flow']);
      await h.dispose();
    });
  });

  group('the card follows today\'s entry', () {
    testWidgets('a save, a change and a delete each show at once',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.logPeriods(profile.id, kActiveStarts);
      await h.pump(profile);
      expect(cardTexts(tester), [kEmptyLine]);

      await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await tester.pumpAndSettle();
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      await h.saveDay(
        profile.id,
        kToday,
        flow: FlowLevel.light,
        tags: const ['cramps', 'fatigue'],
        note: kNoteText,
      );
      await tester.pumpAndSettle();
      expect(cardTexts(tester), [
        'Logged today',
        'Edit',
        'Light flow',
        'Cramps, Fatigue',
        'Note added',
      ]);

      await h.entries.delete(profile.id, kToday);
      await tester.pumpAndSettle();
      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });

    testWidgets('switching profile shows the other profile\'s day',
        (tester) async {
      final h = Harness(tester);
      final alice = await h.createProfile();
      final bea = await h.createProfile(name: 'Bea');
      await h.saveDay(alice.id, kToday, tags: const ['cramps']);
      await h.saveDay(bea.id, kToday, tags: const ['headache']);
      await h.pump(alice);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      await h.pump(bea);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Headache']);
      expect(find.textContaining('Cramps'), findsNothing);
      await h.dispose();
    });

    testWidgets('a different "today" is a different day\'s log',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await h.pump(profile, todayProvider: () => kToday);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      await h.pump(profile, todayProvider: () => kToday.addDays(1));
      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });

    testWidgets('the first write after midnight is read against the new '
        'day', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await h.pump(profile);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      h.now = kToday.addDays(1);
      await h.saveDay(profile.id, h.now, tags: const ['headache']);
      await tester.pumpAndSettle();
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Headache']);
      await h.dispose();
    });

    testWidgets('at the date rollover, with nothing written, yesterday\'s '
        'log stops being shown as today\'s', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.logPeriods(profile.id, kActiveStarts);
      await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await h.pump(profile);
      expect(find.text('Cycle day 26'), findsOneWidget);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      // Midnight: the app's date ticker fires and the estimate moves on.
      h.now = kToday.addDays(1);
      h.tickDate();
      await tester.pumpAndSettle();
      expect(find.text('Cycle day 27'), findsOneWidget);
      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });

    testWidgets('opened again the next morning with estimates turned off: '
        'coming back to the foreground is enough', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.settings.set(predictionsEnabledSettingKey(profile.id), 'false');
      await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await h.pump(profile);
      expect(find.byKey(const ValueKey('predictions-disabled')), findsOneWidget);
      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps']);

      // No estimate to recompute here, so the rollover tick says nothing;
      // the return to the foreground is what the card goes on.
      h.now = kToday.addDays(1);
      h.tickDate();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(cardTexts(tester), [kEmptyLine]);
      await h.dispose();
    });
  });

  group('who may edit', () {
    testWidgets('Edit opens today\'s day sheet on today\'s entry, in the '
        'profile\'s own units', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile(
        bbtUnit: BbtUnit.fahrenheit,
        weightUnit: WeightUnit.lb,
      );
      final saved = await h.saveDay(profile.id, kToday, tags: const ['cramps']);
      await h.pump(profile);

      await tester.tap(find.byKey(kEdit));
      await tester.pumpAndSettle();

      final sheet = tester.widget<DaySheet>(find.byType(DaySheet));
      expect(sheet.date, kToday);
      expect(sheet.existing?.id, saved.id);
      expect(sheet.readOnly, isFalse);
      expect(sheet.bbtUnit, BbtUnit.fahrenheit);
      expect(sheet.weightUnit, WeightUnit.lb);
      await h.dispose();
    });

    testWidgets('an archived profile gets the summary without Edit',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, flow: FlowLevel.medium);
      await h.pump(profile, readOnly: true);

      expect(cardTexts(tester), ['Logged today', 'Medium flow']);
      expect(find.byKey(kEdit), findsNothing);
      await h.dispose();
    });

    testWidgets('a subject who may only view gets the summary without Edit',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, flow: FlowLevel.medium);
      await h.db.storage.applyRemoteRows([
        guardianRow(profile.id, 'user-self', 'viewer', isSubject: true),
      ]);
      await h.pump(
        profile,
        auth: h.signIn('user-self'),
        withGuardians: true,
      );

      expect(cardTexts(tester), ['Logged today', 'Medium flow']);
      expect(find.byKey(kEdit), findsNothing);
      await h.dispose();
    });

    testWidgets('a subject who may log gets Edit', (tester) async {
      final h = Harness(tester);
      final profile = await h.createProfile();
      await h.saveDay(profile.id, kToday, flow: FlowLevel.medium);
      await h.db.storage.applyRemoteRows([
        guardianRow(profile.id, 'user-self', 'caregiver', isSubject: true),
      ]);
      await h.pump(
        profile,
        auth: h.signIn('user-self'),
        withGuardians: true,
      );

      expect(cardTexts(tester), ['Logged today', 'Edit', 'Medium flow']);
      await h.dispose();
    });
  });

  group('the guardian lens (#850) does not get the card', () {
    for (final role in ['co_parent', 'caregiver', 'viewer']) {
      testWidgets('a $role sees the guardian card and none of today\'s '
          'content', (tester) async {
        final h = Harness(tester);
        final profile = await h.createProfile();
        await h.logPeriods(profile.id, kActiveStarts);
        await h.saveDay(
          profile.id,
          kToday,
          tags: const ['cramps', 'headache'],
          note: kNoteText,
        );
        await h.db.storage.applyRemoteRows([
          guardianRow(profile.id, 'user-parent', role),
        ]);
        await h.pump(
          profile,
          auth: h.signIn('user-parent'),
          withGuardians: true,
        );

        expect(
          find.byKey(const ValueKey('guardian-overview-card')),
          findsOneWidget,
        );
        expect(find.byKey(kCard), findsNothing);
        expect(find.text('Logged today'), findsNothing);
        expect(find.textContaining('Cramps'), findsNothing);
        expect(find.textContaining('Headache'), findsNothing);
        expect(find.text('Note added'), findsNothing);
        await h.dispose();
      });
    }
  });

  group('text scale', () {
    for (final scale in [1.0, 2.0, 3.1]) {
      testWidgets('the panel with a full day logged does not overflow at '
          '${scale}x on a phone-class viewport', (tester) async {
        final h = Harness(tester);
        final profile = await h.createProfile();
        await h.logPeriods(profile.id, kActiveStarts);
        await h.saveDay(
          profile.id,
          kToday,
          flow: FlowLevel.notBleeding,
          tags: const [
            'breast_tenderness',
            'migraine_with_aura',
            'back_pain',
            'bloating',
            'nausea',
            'acne',
            'fatigue',
          ],
          note: kNoteText,
          pms: true,
          attached: [
            h.attachment(
              profile.id,
              kToday,
              ObservationCategory.bbt,
              valueNum: 36.75,
              unit: 'celsius',
            ),
          ],
        );
        await h.pump(
          profile,
          textScale: scale,
          physicalSize: const Size(390, 844),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('overview-active')),
          findsOneWidget,
        );
        // At the largest sizes the estimate card alone fills the screen,
        // so the log card is built only once it is scrolled to.
        await tester.scrollUntilVisible(
          find.byKey(kCard),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Logged today'), findsOneWidget);
        await h.dispose();
      });
    }
  });
}
