/// Issue #1203: the profile edit dialog's birth-control "Started on"
/// field — shown only while the selected method is a tracked one,
/// pre-filled with the stored anchor for an unchanged method, defaulted
/// to today for a newly picked tracked method, blank ("—") when nothing
/// is known, past-bounded in the picker, and never submitted for a
/// non-tracked method. Mirrors `profile_dialogs_postpartum_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
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

ProfileLifecycleMode _row({
  String? birthControlMethod,
  String? birthControlStartedOn,
}) =>
    (
      mode: LifecycleMode.tracking,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: birthControlStartedOn,
      birthControlStoppedOn: null,
    );

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
                  await showProfileEditDialog(context, existing: _profile());
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

Future<void> _switchBirthControl(
  WidgetTester tester,
  String label,
) async {
  await tester
      .ensureVisible(find.byKey(const ValueKey('edit-birth-control-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-birth-control-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

String? _fieldValue(WidgetTester tester) => tester.widget<Text>(
      find.byKey(const ValueKey('edit-birth-control-start-date-value')),
    ).data;

void main() {
  testWidgets('the field is hidden for a non-tracked method and appears '
      'with a today default when a tracked method is newly picked',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(birthControlMethod: 'none')),
      onPopped: (result) => popped = result,
    );

    expect(
        find.byKey(const ValueKey('edit-birth-control-start-date-field')),
        findsNothing,
        reason: 'nothing is in effect to anchor for "None"');

    await _switchBirthControl(tester, 'Pill');

    expect(
        find.byKey(const ValueKey('edit-birth-control-start-date-field')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('edit-birth-control-start-date-hint')),
        findsOneWidget);

    await _save(tester);
    expect(popped!.birthControlChoice, BirthControlChoice.pill);
    expect(popped!.birthControlStartedOn, LocalDate.today().iso,
        reason: 'a new tracked method defaults to today — the same day '
            'the recorder\'s #183 rule would have stamped invisibly');
  });

  testWidgets('an unchanged tracked method pre-fills its stored anchor and '
      'carries it into the result', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(
        birthControlMethod: 'pill',
        birthControlStartedOn: '2026-08-15',
      )),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('edit-birth-control-start-date-field')),
        findsOneWidget);
    expect(find.textContaining('August 15, 2026'), findsOneWidget);

    await _save(tester);
    expect(popped!.birthControlChoice, BirthControlChoice.pill);
    expect(popped!.birthControlStartedOn, '2026-08-15',
        reason: 'the untouched field re-submits the stored anchor '
            'verbatim, so an unchanged Save stays a no-op');
  });

  testWidgets('a tracked method with no stored anchor shows "—" and '
      'submits null when left blank (nothing is assumed)',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(birthControlMethod: 'pill')),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    expect(_fieldValue(tester), '—',
        reason: 'the issue\'s exact scenario: a pill with no recorded '
            'start date must not silently pre-fill an assumed today');

    await _save(tester);
    expect(popped!.birthControlStartedOn, isNull,
        reason: 'a blank submit leaves the recorder\'s #183 fallback in '
            'charge');
  });

  testWidgets('switching to a non-tracked method hides the field and never '
      'submits a date', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(
        birthControlMethod: 'pill',
        birthControlStartedOn: '2026-08-15',
      )),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    await _switchBirthControl(tester, 'Condom');
    expect(
        find.byKey(const ValueKey('edit-birth-control-start-date-field')),
        findsNothing);

    await _save(tester);
    expect(popped!.birthControlChoice, BirthControlChoice.condom);
    expect(popped!.birthControlStartedOn, isNull,
        reason: 'a date alongside a non-tracked answer means nothing');
  });

  testWidgets('switching between two tracked methods defaults the field to '
      'today (the new method is in effect from today)',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(
        birthControlMethod: 'pill',
        birthControlStartedOn: '2026-08-15',
      )),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    await _switchBirthControl(tester, 'Patch');
    expect(_fieldValue(tester), isNot('August 15, 2026'),
        reason: 'the pill\'s anchor is not the patch\'s');

    await _save(tester);
    expect(popped!.birthControlChoice, BirthControlChoice.patch);
    expect(popped!.birthControlStartedOn, LocalDate.today().iso,
        reason: 'a newly picked tracked method defaults to today');
  });

  testWidgets('the picker is past-bounded: nothing after today, and the '
      'far past is unreachable too', (tester) async {
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(birthControlMethod: 'pill')),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('edit-birth-control-start-date-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();

    final today = LocalDate.today();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.lastDate, today.toDateTime(),
        reason: 'a method cannot have started in the future');
    expect(dialog.firstDate, today.addMonths(-60).toDateTime(),
        reason: 'five years back covers the longest tracked regimen '
            '(the hormonal IUD\'s label life); beyond that is unreachable');

    // Dismissing the picker leaves the blank field blank.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_fieldValue(tester), '—');
  });

  testWidgets('picking a date carries it into the result', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      modes: _FakeModesRepository(_row(birthControlMethod: 'pill')),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('edit-birth-control-start-date-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    // The picker opens on the current month; pick its first day (always
    // selectable — day 1 is never after today, so it sits inside the
    // past-bounded window) and confirm.
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _save(tester);
    final today = LocalDate.today();
    expect(popped!.birthControlStartedOn,
        LocalDate(today.year, today.month, 1).iso);
  });
}
