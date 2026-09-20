/// Issue #820: the profile edit dialog's minor control. With no birth year
/// it stays the editable fallback checkbox; once a valid birth year is
/// present it becomes a read-only, derived display and the checkbox is no
/// longer offered as an independent control. Mirrors
/// `profile_dialogs_postpartum_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:provider/provider.dart';

class _FakeModesRepository implements ProfileModesRepository {
  @override
  Future<ProfileLifecycleMode?> find(String profileId) async => null;
  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) => Stream.value(null);
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

Profile _profile({bool isMinor = false, int? birthYear}) => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Nova',
      isMinor: isMinor,
      birthYear: birthYear,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _openDialog(
  WidgetTester tester, {
  Profile? existing,
  void Function(ProfileEditResult? result)? onPopped,
}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ProfileModesRepository?>.value(value: _FakeModesRepository()),
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

const _checkbox = ValueKey('edit-minor-checkbox');
const _derived = ValueKey('edit-minor-derived');
const _birthYear = ValueKey('edit-birth-year-field');

void main() {
  testWidgets('no birth year: the editable checkbox is offered', (tester) async {
    await _openDialog(tester, existing: _profile(isMinor: true));
    await tester.pumpAndSettle();

    expect(find.byKey(_checkbox), findsOneWidget);
    expect(find.byKey(_derived), findsNothing);
  });

  testWidgets('an existing birth year hides the checkbox and shows the '
      'derived status (adult or minor)', (tester) async {
    await _openDialog(tester, existing: _profile(isMinor: true, birthYear: 1980));
    await tester.pumpAndSettle();

    expect(find.byKey(_checkbox), findsNothing,
        reason: 'the flag is no longer independently editable');
    expect(find.byKey(_derived), findsOneWidget);
    expect(find.textContaining('adult'), findsOneWidget,
        reason: 'birth year 1980 is an adult in 2026, despite the stored flag');
  });

  testWidgets('typing a birth year flips the control to the derived '
      'display live', (tester) async {
    await _openDialog(tester, existing: _profile(isMinor: true));
    await tester.pumpAndSettle();
    expect(find.byKey(_checkbox), findsOneWidget);

    await tester.enterText(find.byKey(_birthYear), '2020');
    await tester.pumpAndSettle();

    expect(find.byKey(_checkbox), findsNothing);
    expect(find.byKey(_derived), findsOneWidget);
    expect(find.textContaining('minor'), findsOneWidget);
  });

  testWidgets('submit emits the derived flag when a birth year is present',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(isMinor: true),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(_birthYear), '1980');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.birthYear, 1980);
    expect(popped!.isMinor, isFalse,
        reason: 'the present birth year is authoritative over the flag');
  });

  testWidgets('submit preserves the stored flag when no birth year is given',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(isMinor: true),
      onPopped: (result) => popped = result,
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.birthYear, isNull);
    expect(popped!.isMinor, isTrue);
  });
}
