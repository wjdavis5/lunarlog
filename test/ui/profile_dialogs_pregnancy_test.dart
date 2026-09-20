/// Issue #192 (Pregnancy mode): the profile edit dialog's due-date
/// collection — the field appears only for Pregnancy mode, is pre-filled
/// with the derived estimate (last recorded period start + 280 days),
/// takes a manual override through the date picker, and pre-fills the
/// stored due date of an already-pregnant profile (AC1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:provider/provider.dart';

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

Profile _profile({String? lastPeriodStart}) => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Nova',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      lastPeriodStart: lastPeriodStart == null
          ? null
          : LocalDate.fromIso(lastPeriodStart),
    );

Future<void> _openDialog(
  WidgetTester tester, {
  required _FakeModesRepository modes,
  Profile? existing,
  void Function(ProfileEditResult? result)? onPopped,
}) async {
  final entries = _StubDayEntriesRepository();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ProfileModesRepository?>.value(value: modes),
      Provider<CyclePredictionService?>.value(
        value: CyclePredictionService(entries),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result =
                  await showProfileEditDialog(context, existing: existing);
              onPopped?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _switchToPregnancy(WidgetTester tester) async {
  await tester.ensureVisible(
      find.byKey(const ValueKey('edit-lifecycle-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-lifecycle-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pregnancy').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('switching to Pregnancy reveals a derived due date '
      '(last period start + 280 days) and carries it into the result',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(lastPeriodStart: '2026-09-14'),
      onPopped: (result) => popped = result,
    );

    expect(find.byKey(const ValueKey('edit-due-date-field')), findsNothing);
    await _switchToPregnancy(tester);
    expect(find.byKey(const ValueKey('edit-due-date-field')), findsOneWidget);
    // Derived hint names the 280-day rule; 2026-09-14 + 280 = 2027-06-21.
    expect(find.byKey(const ValueKey('edit-due-date-hint')), findsOneWidget);
    expect(find.textContaining('June 21, 2027'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(popped, isNotNull);
    expect(popped!.lifecycleMode, LifecycleMode.pregnancy);
    expect(popped!.estimatedDueDate, '2027-06-21');
  });

  testWidgets('an unknown last period start leaves the field empty with the '
      'manual-pick hint (the manual override case)', (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(),
    );
    await _switchToPregnancy(tester);
    expect(find.byKey(const ValueKey('edit-due-date-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-due-date-hint')), findsOneWidget);
    // The 280-day derivation hint is absent — nothing was derivable.
    expect(find.byKey(const ValueKey('edit-due-date-value')), findsOneWidget);
    expect(find.textContaining('280 days'), findsNothing);
  });

  testWidgets('an already-pregnant profile pre-fills its STORED due date '
      '(not a fresh derivation)', (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository((
        mode: LifecycleMode.pregnancy,
        modeStartedOn: '2026-09-10',
        estimatedDueDate: '2027-06-17',
        postpartumBirthDate: null,
        birthControlMethod: null,
        birthControlStartedOn: null,
        birthControlStoppedOn: null,
      )),
      existing: _profile(lastPeriodStart: '2026-09-14'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-due-date-field')), findsOneWidget);
    // The stored 2027-06-17 wins over the freshly derived 2027-06-21.
    expect(find.textContaining('June 17, 2027'), findsOneWidget);
    expect(find.textContaining('June 21, 2027'), findsNothing);
  });

  testWidgets('switching AWAY from Pregnancy hides the field again',
      (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository((
        mode: LifecycleMode.pregnancy,
        modeStartedOn: '2026-09-10',
        estimatedDueDate: '2027-06-17',
        postpartumBirthDate: null,
        birthControlMethod: null,
        birthControlStartedOn: null,
        birthControlStoppedOn: null,
      )),
      existing: _profile(),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-due-date-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-lifecycle-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Period Tracking').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-due-date-field')), findsNothing);
  });

  testWidgets('tapping the field opens the date picker and a picked date '
      'replaces the derived value (the manual override path)',
      (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(lastPeriodStart: '2026-09-14'),
    );
    await _switchToPregnancy(tester);
    expect(find.textContaining('June 21, 2027'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit-due-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-due-date-field')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // Pick the 15th of the shown month and confirm.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The value no longer reads as the derived June 21 2027 estimate.
    expect(find.textContaining('June 21, 2027'), findsNothing);
    expect(find.byKey(const ValueKey('edit-due-date-value')), findsOneWidget);
  });
}
