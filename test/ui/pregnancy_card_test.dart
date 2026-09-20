/// Issue #192 (Pregnancy mode): the Pregnancy-mode Cycle View surfaces —
/// the week-of-pregnancy card itself, and its mount in [OverviewPanel]
/// while the profile's life-stage mode is `pregnancy` (with the
/// prediction-suppression explanation still rendered beneath it, #528).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/pregnancy_card.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:provider/provider.dart';

/// The minimal day-entry stub the prediction service needs (empty
/// history: pregnancy suppresses before history is ever consulted).
/// `watchForProfile` yields exactly one event per subscriber — all
/// `combineLatest` needs to build its first combined value.
class _StubDayEntriesRepository implements DayEntriesRepository {
  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) async* {
    yield const [];
  }
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeModesRepository implements ProfileModesRepository {
  _FakeModesRepository(this.row);

  ProfileLifecycleMode? row;

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async => row;

  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) => Stream.value(row);

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
  }) async {}
}

class _StubSettingsStore implements SettingsStore {
  @override
  Stream<String?> watch(String key) => Stream.value(null);
  @override
  Future<String?> get(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _app({
  required Widget child,
  required _FakeModesRepository modes,
}) {
  final entries = _StubDayEntriesRepository();
  final settings = _StubSettingsStore();
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<SettingsStore>.value(value: settings),
      Provider<CyclePredictionService>.value(
        value: CyclePredictionService(
          entries,
          settings: settings,
          lifecycleModeFor: (_) =>
              Stream.value(modes.row?.mode ?? LifecycleMode.tracking),
        ),
      ),
      Provider<CycleExclusionList>.value(
        value: CycleExclusionList(settings),
      ),
      Provider<ProfileModesRepository>.value(value: modes),
      ChangeNotifierProvider(
        create: (_) => NotificationPermissionState(
          NotificationAvailability.available,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('PregnancyCard renders the week counter and due date',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: PregnancyCard(week: 12, dueDateText: 'June 17, 2027'),
      ),
    ));
    expect(find.byKey(const ValueKey('pregnancy-week')), findsOneWidget);
    expect(find.text('Week 12 of pregnancy'), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-due-date')), findsOneWidget);
    expect(find.text('Estimated due date: June 17, 2027'), findsOneWidget);
  });

  testWidgets('PregnancyCard with no due date renders the honest '
      'not-recorded line, never a fabricated week', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PregnancyCard()),
    ));
    expect(find.byKey(const ValueKey('pregnancy-due-date-missing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-week')), findsNothing);
  });

  testWidgets('OverviewPanel mounts the week card above the suppression '
      'explanation while in Pregnancy mode (Issue #192 AC2/AC3)',
      (tester) async {
    final modes = _FakeModesRepository((
      mode: LifecycleMode.pregnancy,
      modeStartedOn: '2026-09-14',
      estimatedDueDate: '2027-06-21',
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    ));
    await tester.pumpWidget(_app(
      modes: modes,
      child: OverviewPanel(
        profileId: 'p',
        // 2026-09-28 is gestational day 14 → week 2.
        todayProvider: () => LocalDate(2026, 9, 28),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('pregnancy-card')), findsOneWidget);
    expect(find.text('Week 2 of pregnancy'), findsOneWidget);
    // #528's suppression explanation stays visible beneath the counter.
    expect(find.byKey(const ValueKey('predictions-suppressed')),
        findsOneWidget);
  });

  testWidgets('OverviewPanel in Pregnancy mode without a due date shows '
      'the not-recorded line (no fabricated week)', (tester) async {
    final modes = _FakeModesRepository((
      mode: LifecycleMode.pregnancy,
      modeStartedOn: '2026-09-14',
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    ));
    await tester.pumpWidget(_app(
      modes: modes,
      child: OverviewPanel(
        profileId: 'p',
        todayProvider: () => LocalDate(2026, 9, 28),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('pregnancy-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-due-date-missing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-week')), findsNothing);
  });

  testWidgets('OverviewPanel outside Pregnancy mode renders no week card',
      (tester) async {
    final modes = _FakeModesRepository((
      mode: LifecycleMode.tracking,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    ));
    await tester.pumpWidget(_app(
      modes: modes,
      child: OverviewPanel(
        profileId: 'p',
        todayProvider: () => LocalDate(2026, 9, 28),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('pregnancy-card')), findsNothing);
  });
}
