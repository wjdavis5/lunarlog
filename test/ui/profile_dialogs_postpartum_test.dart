/// Issue #861 (Postpartum mode): the profile edit dialog's birth-date
/// collection — the field appears only for Postpartum mode, is optional
/// (blank keeps the mode-start surrogate), pre-fills the stored birth date
/// of an already-postpartum profile, and opens a picker bounded so a future
/// date can never be selected. Mirrors `profile_dialogs_pregnancy_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
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

Profile _profile() => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Nova',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _openDialog(
  WidgetTester tester, {
  required _FakeModesRepository modes,
  Profile? existing,
  void Function(ProfileEditResult? result)? onPopped,
}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ProfileModesRepository?>.value(value: modes),
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

Future<void> _switchToPostpartum(WidgetTester tester) async {
  await tester
      .ensureVisible(find.byKey(const ValueKey('edit-lifecycle-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-lifecycle-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Postpartum').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('switching to Postpartum reveals an optional birth-date field '
      'and leaving it blank keeps the mode-start surrogate', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(),
      onPopped: (result) => popped = result,
    );

    expect(
        find.byKey(const ValueKey('edit-postpartum-birth-date-field')),
        findsNothing);
    await _switchToPostpartum(tester);
    expect(
        find.byKey(const ValueKey('edit-postpartum-birth-date-field')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('edit-postpartum-birth-date-hint')),
        findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(popped, isNotNull);
    expect(popped!.lifecycleMode, LifecycleMode.postpartum);
    expect(popped!.postpartumBirthDate, isNull,
        reason: 'the field is optional; blank is a valid answer');
  });

  testWidgets('an already-postpartum profile pre-fills its stored birth date '
      'and carries it into the result', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository((
        mode: LifecycleMode.postpartum,
        modeStartedOn: '2026-09-10',
        estimatedDueDate: null,
        postpartumBirthDate: '2026-09-01',
        birthControlMethod: null,
        birthControlStartedOn: null,
        birthControlStoppedOn: null,
      )),
      existing: _profile(),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('edit-postpartum-birth-date-field')),
        findsOneWidget);
    expect(find.textContaining('September 1, 2026'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(popped!.postpartumBirthDate, '2026-09-01');
  });

  testWidgets('the birth-date picker is bounded so a future date cannot be '
      'selected (rejection at entry)', (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(),
    );
    await _switchToPostpartum(tester);

    await tester.tap(
        find.byKey(const ValueKey('edit-postpartum-birth-date-field')));
    await tester.pumpAndSettle();

    final today = LocalDate.today();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.lastDate, today.toDateTime(),
        reason: 'no date after today is selectable');
    expect(dialog.firstDate, today.addMonths(-24).toDateTime(),
        reason: 'the absurdly far past is unreachable too');

    // Dismissing the picker (its barrier) leaves the optional field blank
    // (still the surrogate).
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final value = tester.widget<Text>(
      find.byKey(const ValueKey('edit-postpartum-birth-date-value')),
    );
    expect(value.data, '—');
  });

  testWidgets('picking a date carries it into the result', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(null),
      existing: _profile(),
      onPopped: (result) => popped = result,
    );
    await _switchToPostpartum(tester);
    await tester.tap(
        find.byKey(const ValueKey('edit-postpartum-birth-date-field')));
    await tester.pumpAndSettle();

    // The picker opens on the current month; pick its first day (always
    // within the last-24-months bound) and confirm.
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final today = LocalDate.today();
    final expected = LocalDate(today.year, today.month, 1).iso;
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(popped!.postpartumBirthDate, expected);
  });

  group('acceptedPostpartumBirthDate (shared DayEntryPolicy bounds)', () {
    final today = LocalDate(2026, 9, 19);

    test('accepts an ordinary past date', () {
      expect(
        acceptedPostpartumBirthDate(LocalDate(2026, 9, 1), today: today),
        '2026-09-01',
      );
    });

    test('rejects a future date', () {
      expect(
        acceptedPostpartumBirthDate(LocalDate(2026, 9, 22), today: today),
        isNull,
      );
    });

    test('rejects a date before the profile birth year', () {
      expect(
        acceptedPostpartumBirthDate(
          LocalDate(2010, 1, 1),
          today: today,
          birthYear: 2015,
        ),
        isNull,
      );
    });
  });
}
