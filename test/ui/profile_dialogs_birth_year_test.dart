/// Issue #923: the profile edit dialog refuses a birth year later than the
/// profile's earliest live day entry. Before this, such a typo saved fine and
/// then made every earlier entry fail autosave forever (the #848 date-bounds
/// policy rejects a year before the profile's `birth_year`). Mirrors
/// `profile_dialogs_minor_test.dart`'s harness.
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
  int? earliestEntryYear,
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
              final result = await showProfileEditDialog(
                context,
                existing: existing,
                earliestEntryYear: earliestEntryYear,
              );
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

const _birthYear = ValueKey('edit-birth-year-field');

void main() {
  group('validateBirthYearForProfile', () {
    test('no earliest entry year adds no extra rule', () {
      expect(validateBirthYearForProfile('2050'), isNull);
      expect(validateBirthYearForProfile('not a year'), isNotNull);
    });

    test('a year later than the earliest entry is refused, naming it', () {
      final message = validateBirthYearForProfile(
        '2025',
        earliestEntryYear: 2024,
      );
      expect(message, isNotNull);
      expect(message, contains('entries from 2024'));
    });

    test('a year equal to or earlier than the earliest entry passes', () {
      expect(validateBirthYearForProfile('2024', earliestEntryYear: 2024),
          isNull);
      expect(validateBirthYearForProfile('2015', earliestEntryYear: 2024),
          isNull);
      expect(validateBirthYearForProfile('', earliestEntryYear: 2024), isNull);
    });
  });

  testWidgets('a birth year later than the earliest entry is refused with the '
      'naming copy and the dialog stays open', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(birthYear: 2015),
      earliestEntryYear: 2024,
      onPopped: (result) => popped = result,
    );

    await tester.enterText(find.byKey(_birthYear), '2025');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, isNull, reason: 'the dialog must not save the bad year');
    expect(find.textContaining('entries from 2024'), findsOneWidget);
  });

  testWidgets('a birth year at or before the earliest entry still saves',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(birthYear: 2015),
      earliestEntryYear: 2024,
      onPopped: (result) => popped = result,
    );

    await tester.enterText(find.byKey(_birthYear), '2024');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.birthYear, 2024);
  });
}
