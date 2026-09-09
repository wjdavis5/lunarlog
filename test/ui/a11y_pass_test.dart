/// Widget/unit tests for issue #138, the screen-reader and large-text
/// accessibility pass over the calendar, day sheet, overview, and Manage
/// Guardians:
///
/// * **Calendar** — day-cell semantics (date with weekday, flow state,
///   symptom presence, loggability, today/read-only status, predicted vs
///   logged), `button`/`selected` flags, full-name weekday headers,
///   excluded blank cells, text-scale-aware circle sizing, 48dp row
///   minimum, and the 1.0x/1.5x/2.0x overflow sweep.
/// * **Day sheet** — chips announcing their group and selected state
///   through `groupedChipSemantics`, header flags on the section headings,
///   the labelled note field, the read-only variant's reason, and the
///   overflow sweep.
/// * **Overview** — the wheel's semantic label, the confidence chip's
///   announced phrase, status/estimate/disclaimer reading order, and the
///   overflow sweep (TodayCard directly and [OverviewPanel] mounted).
/// * **Manage Guardians** — role announcement and the overflow sweep.
///
/// Pure halves (`dayCellMetricsFor`, `dayCellSemanticLabel`,
/// `cycleWheelSemanticsLabel`) are pinned directly where they live
/// (`forecast_calendar_test.dart`/`today_card_test.dart`) plus the metrics
/// here; this file walks the assembled widgets, the way a screen reader
/// meets them.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/cycle_wheel.dart';
import 'package:lunarlog/ui/components/today_card.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Same fixed "today" as `test/ui/calendar_navigation_test.dart` (a
/// Sunday), so weekday names in the expected labels are stable.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Steady 30-day cycles with 4-day bleeds — enough history for an active
/// estimate, matching `forecast_calendar_test.dart`'s kSteadyStarts (the
/// open cycle starts Aug 5 → the next estimate lands Sep 4).
const List<(int, int, int)> kSteadyStarts = [
  (2026, 3, 8),
  (2026, 4, 7),
  (2026, 5, 7),
  (2026, 6, 6),
  (2026, 7, 6),
  (2026, 8, 5),
];

Future<void> _seedCalendar(
  DriftDayEntriesRepository entries,
  String profileId,
) async {
  for (final (year, month, day) in kSteadyStarts) {
    for (var i = 0; i < 4; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: LocalDate(year, month, day).addDays(i),
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }
  // A symptom-only day (no bleed, one tag) in the displayed month.
  await entries.save(
    DayEntry(
      id: '',
      profileId: profileId,
      localDate: LocalDate(2026, 8, 12),
      tz: 'America/Chicago',
      flow: FlowLevel.none,
      tags: const ['cramps'],
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

/// Pumps [MonthCalendar] directly against a minimal provider set (same
/// shape as `calendar_navigation_test.dart`'s harness) on a phone-class
/// viewport, with the text scale and read-only flag this pass varies.
Future<LunarLogDatabase> pumpCalendar(
  WidgetTester tester, {
  double textScale = 1.0,
  Size physicalSize = const Size(390, 844),
  bool readOnly = false,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(db.storage)
      .create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);
  await _seedCalendar(entries, profile.id);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries),
        ),
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
        home: Scaffold(
          body: MonthCalendar(
            profileId: profile.id,
            todayProvider: () => kToday,
            readOnly: readOnly,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Pumps [DaySheet] as a real `showModalBottomSheet` over a host page
/// (the shape every production push site uses), with the text scale and
/// entry state this pass varies.
Future<LunarLogDatabase> pumpDaySheet(
  WidgetTester tester, {
  double textScale = 1.0,
  Size physicalSize = const Size(390, 844),
  bool readOnly = false,
  List<ProfileGuardian> guardians = const [],
  String? currentUserId,
  DayEntry? existing,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(db.storage)
      .create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);
  final sheetDate = LocalDate(2026, 8, 29);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ObservationsRepository>.value(value: observations),
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-day-sheet'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DaySheet(
                    repository: entries,
                    profileId: profile.id,
                    date: sheetDate,
                    today: kToday,
                    existing: existing ??
                        DayEntry(
                          id: 'seeded',
                          profileId: profile.id,
                          localDate: sheetDate,
                          tz: 'America/Chicago',
                          flow: FlowLevel.none,
                          tags: const ['cramps'],
                          note: 'existing note',
                          updatedAt: DateTime.utc(2026, 1, 1),
                        ),
                    readOnly: readOnly,
                    guardians: guardians,
                    currentUserId: currentUserId,
                  ),
                ),
                child: const Text('Open'),
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
  return db;
}

/// The smallest [SharingService] fake Manage Guardians needs: the pending
/// list is the only call this suite's screens make.
class _NoInvitesSharingService implements SharingService {
  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) => throw UnimplementedError();

  @override
  Future<InviteCancellation> cancelInvite(String invitationId) =>
      throw UnimplementedError();

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) => throw UnimplementedError();

  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) => throw UnimplementedError();

  @override
  Future<void> updateGuardianRole({
    required String profileId,
    required String targetUserId,
    required GuardianRole newRole,
  }) => throw UnimplementedError();
}

ProfileGuardian _guardian(
  String id,
  String userId,
  GuardianRole role,
  String? displayName,
) =>
    ProfileGuardian(
      id: id,
      profileId: 'p-1',
      userId: userId,
      role: role,
      status: GuardianStatus.accepted,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('calendar semantics (#138)', () {
    testWidgets('every weekday header column announces the full day name, '
        'not the ambiguous single initial', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpCalendar(tester);

      for (final name in [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ]) {
        expect(
          find.bySemanticsLabel(name),
          findsOneWidget,
          reason: 'weekday header column must announce "$name" '
              '(exact match — day-cell labels are longer)',
        );
      }
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the leading blank cells are excluded from semantics',
        (tester) async {
      final db = await pumpCalendar(tester);
      // August 2026 starts on a Saturday: six leading blanks.
      final grid = find.byKey(const ValueKey('calendar-grid-2026-8'));
      for (var i = 0; i < 6; i++) {
        expect(
          find.descendant(
            of: grid,
            matching: find.byKey(ValueKey('calendar-leading-blank-2026-8-$i')),
          ),
          findsOneWidget,
          reason: 'blank filler cell $i must exist and be excluded',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('a logged bleed cell announces date, flow state, and '
        'symptom presence', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpCalendar(tester);

      expect(
        find.bySemanticsLabel('Wednesday, August 5, Medium flow, no symptoms'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Wednesday, August 12, logged symptoms'),
        findsOneWidget,
        reason: 'a symptom-only day announces symptoms, not a flow level',
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets("today's cell carries the label's today fragment, the "
        'selected flag, and the button flag', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpCalendar(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Sunday, August 30, not logged, today'),
      );
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('a read-only calendar announces read-only on past cells and '
        'drops the button flag from unloggable ones', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpCalendar(tester, readOnly: true);

      // August 13 has no entry and the calendar is read-only: announced
      // as read-only, and inert (no sheet to open).
      final unlogged = tester.getSemantics(
        find.bySemanticsLabel('Thursday, August 13, not logged, read-only'),
      );
      expect(unlogged.flagsCollection.isButton, isFalse);
      // A day with an entry still opens the (read-only) sheet: a button.
      final logged = tester.getSemantics(
        find.bySemanticsLabel(
          'Wednesday, August 5, Medium flow, no symptoms, read-only',
        ),
      );
      expect(logged.flagsCollection.isButton, isTrue);
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('a predicted day stays semantically distinct from a logged '
        'one and announces not-yet-loggable', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpCalendar(tester);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Friday, September 4, predicted period day, cycle day 1, '
            '.*future date, not yet loggable',
          ),
        ),
        findsOneWidget,
        reason: 'no predicted-day label may read like a logged one',
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });

  group('calendar geometry and touch targets (#138)', () {
    test('dayCellMetricsFor keeps the historic square cells at 1.0x', () {
      const scaler = TextScaler.linear(1.0);
      final metrics = dayCellMetricsFor(390, scaler);
      expect(metrics.circleSize, 34);
      expect(metrics.markersHeight, 14);
      expect(metrics.aspectRatio, closeTo(1.0, 1e-9));
    });

    test('dayCellMetricsFor grows the circle and row at 2.0x', () {
      const scaler = TextScaler.linear(2.0);
      final cellWidth = (390 - 8) / 7;
      final metrics = dayCellMetricsFor(390, scaler);
      expect(metrics.circleSize, 40,
          reason: 'scale(20) = 40 past the 34px floor');
      expect(metrics.markersHeight, 24,
          reason: 'scale(12) = 24 past the 14px floor');
      expect(
        cellWidth / metrics.aspectRatio,
        closeTo(66, 1e-9),
        reason: 'the row grows to fit circle + gap + markers (40 + 2 + 24)',
      );
    });

    test('dayCellMetricsFor keeps a 48dp row minimum on narrow screens',
        () {
      const scaler = TextScaler.linear(1.0);
      final cellWidth = (320 - 8) / 7; // ~44.6dp: narrower than 48.
      final metrics = dayCellMetricsFor(320, scaler);
      expect(cellWidth / metrics.aspectRatio, greaterThanOrEqualTo(48));
    });

    test('dayCellMetricsFor caps the circle at the column width at extreme '
        'scales', () {
      const scaler = TextScaler.linear(3.0);
      final cellWidth = (390 - 8) / 7;
      final metrics = dayCellMetricsFor(390, scaler);
      expect(metrics.circleSize, closeTo(cellWidth, 1e-9));
    });

    testWidgets('day cells meet the 48dp minimum at 1.0x on a phone-class '
        'viewport', (tester) async {
      final db = await pumpCalendar(tester);

      final size = tester.getSize(
        find.byKey(const ValueKey('day-cell-2026-08-30')),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the bleed circle grows with the text scale instead of '
        'clipping its scaled numeral', (tester) async {
      final db = await pumpCalendar(tester, textScale: 2.0);

      final circle = tester.getSize(
        find.byKey(const ValueKey('bleed-2026-08-05')),
      );
      expect(circle.width, 40);
      expect(circle.height, 40);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the calendar renders with no overflow at ${scale}x text '
          'scale on a phone-class viewport', (tester) async {
        final db = await pumpCalendar(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('calendar-page-view')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      });
    }
  });

  group('day sheet semantics (#138)', () {
    testWidgets('flow chips announce their group, label, and selected state',
        (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(tester);

      // The seeded entry carries no flow, so "None" is the selected chip.
      final medium = tester.getSemantics(find.bySemanticsLabel('Flow, Medium'));
      expect(medium.flagsCollection.isSelected, isNot(Tristate.isTrue));
      final none = tester.getSemantics(find.bySemanticsLabel('Flow, None'));
      expect(none.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        find.bySemanticsLabel('Flow, Spotting'),
        findsOneWidget,
        reason: 'the standalone spotting toggle shares the flow group',
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('tapping a flow chip moves the selected flag (the semantics '
        'tap and the visible chip share one write path)', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(tester);

      await tester.tap(find.bySemanticsLabel('Flow, Medium'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Flow, Medium'))
            .flagsCollection.isSelected,
        Tristate.isTrue,
        reason: 'the accessibility tap toggles the same selection the '
            'visible chip does',
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('tag chips announce their category group', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(tester);

      final cramps = tester.getSemantics(find.bySemanticsLabel('Pain, Cramps'));
      expect(cramps.flagsCollection.isSelected, Tristate.isTrue,
          reason: 'the seeded entry already carries the cramps tag');
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the sheet headings are flagged as semantic headers',
        (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(tester);

      expect(
        tester.getSemantics(find.text('Flow')).flagsCollection.isHeader,
        isTrue,
      );
      expect(
        tester.getSemantics(find.text('Pain')).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the note field is labelled for screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(tester);

      expect(find.bySemanticsLabel('Note'), findsOneWidget);
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the read-only variant announces why it is read-only '
        '(reusing the existing readOnlyReason strings)', (tester) async {
      final handle = tester.ensureSemantics();
      final db = await pumpDaySheet(
        tester,
        readOnly: true,
        currentUserId: 'user-viewer',
        guardians: [
          _guardian('g-1', 'user-viewer', GuardianRole.viewer, 'Grandma'),
        ],
      );

      expect(
        find.bySemanticsLabel('You have view-only access to this profile.'),
        findsOneWidget,
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the day sheet renders with no overflow at ${scale}x text '
          'scale on a phone-class viewport', (tester) async {
        final db = await pumpDaySheet(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.byType(DaySheet), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      });
    }
  });

  group('overview semantics (#138)', () {
    Future<void> pumpTodayCard(
      WidgetTester tester, {
      double textScale = 1.0,
      Size physicalSize = const Size(390, 844),
    }) async {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayCard(
                cycleDay: 14,
                duringEpisode: false,
                cycleLengthDays: 30,
                periodLengthDays: 4,
                estimateText: 'Next period estimate: September 4, 2026',
                tier: CycleConfidence.learning,
                showConfidenceChip: true,
                canLog: true,
                onLogToday: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the wheel, estimate, and disclaimer read in that order, '
        'and the confidence chip announces its phrase', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTodayCard(tester);

      expect(
        tester.getSemantics(find.byType(CycleWheel)).label,
        'Cycle day 14 of about 30 days. Period usually runs about 4 days.',
      );
      expect(
        find.bySemanticsLabel('Estimate confidence: learning.'),
        findsOneWidget,
        reason: 'the bare tier word alone is ambiguous to a screen reader',
      );
      final wheel = tester.getTopLeft(find.byType(CycleWheel)).dy;
      final estimate = tester
          .getTopLeft(find.byKey(const ValueKey('overview-next-period')))
          .dy;
      final disclaimer = tester
          .getTopLeft(find.byKey(const ValueKey('overview-disclaimer')))
          .dy;
      expect(wheel, lessThan(estimate));
      expect(estimate, lessThan(disclaimer));
      handle.dispose();
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the overview renders with no overflow at ${scale}x text '
          'scale on a phone-class viewport', (tester) async {
        await pumpTodayCard(tester, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }

    // The mounted [OverviewPanel] (the AC names the panel, not just its
    // TodayCard) over the same steady history, across the same sweep.
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the mounted OverviewPanel renders with no overflow at '
          '${scale}x text scale', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = LunarLogDatabase(NativeDatabase.memory());
        final profile = await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        final settings = DriftSettingsStore(db.storage);
        final entries = DriftDayEntriesRepository(db.storage);
        await _seedCalendar(entries, profile.id);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<DayEntriesRepository>.value(value: entries),
              Provider<SettingsStore>.value(value: settings),
              Provider<CyclePredictionService>.value(
                value: CyclePredictionService(entries, settings: settings),
              ),
              Provider<CycleExclusionList>.value(
                value: CycleExclusionList(settings),
              ),
              ChangeNotifierProvider<NotificationPermissionState>.value(
                value: NotificationPermissionState(
                  NotificationAvailability.available,
                ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: OverviewPanel(
                  profileId: profile.id,
                  todayProvider: () => kToday,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('overview-active')),
          findsOneWidget,
          reason: 'the steady history yields an active estimate card',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      });
    }
  });

  group('Manage Guardians semantics and text scale (#138)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the screen renders with no overflow at ${scale}x text '
          'scale, and the role stays announced '
          '(long name + "(you" suffix stress the tile)', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = LunarLogDatabase(NativeDatabase.memory());
        final storage = db.storage;
        final profile = await DriftProfilesRepository(storage)
            .create(displayName: 'Luna', isMinor: true);
        await storage.applyRemoteRows([
          RemoteProfileGuardianRow(
            id: 'g-0',
            profileId: profile.id,
            userId: 'user-mom',
            role: 'primary_guardian',
            status: 'accepted',
            displayName: 'Alexandra Penelope the Third',
            invitedBy: null,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
            serverVersion: 1,
          ),
          RemoteProfileGuardianRow(
            id: 'g-1',
            profileId: profile.id,
            userId: 'user-dad',
            role: 'co_parent',
            status: 'accepted',
            displayName: 'Dad',
            invitedBy: null,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
            serverVersion: 1,
          ),
        ]);
        final guardiansRepo = ProfileGuardiansRepository(storage);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ManageGuardiansScreen(
              profile: profile,
              guardiansRepository: guardiansRepo,
              sharingService: _NoInvitesSharingService(),
              currentUserId: 'user-mom',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(RegExp('Co-Parent')),
          findsOneWidget,
          reason: 'the role badge stays announced — the tile subtitle, or '
              'the merged tile node that contains it',
        );
        expect(find.byTooltip('Remove caregiver'), findsOneWidget,
            reason: 'the revoke action stays unambiguously labelled');
        handle.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      });
    }
  });
}
