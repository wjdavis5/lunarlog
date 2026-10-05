/// Issue #1503: the profile edit sheet's relationship control. The server
/// lets only a profile's primary guardian change who the profile is for
/// (issue #1499) and puts anyone else's value back, so a caller who cannot
/// change it sees the stored value as text with a line saying who can, and
/// the sheet's result carries the stored value. The default (a primary
/// guardian, a role that is not known yet, a new profile) keeps the
/// dropdown. The role wiring itself is covered through the picker in
/// `sharing_discoverability_test.dart`. Mirrors
/// `profile_dialogs_minor_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
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

Profile _profile({ProfileRelationship? relationship}) => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Nova',
      isMinor: false,
      relationship: relationship,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _openDialog(
  WidgetTester tester, {
  Profile? existing,
  bool? canChangeRelationship,
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
              // A null [canChangeRelationship] leaves the argument out, so
              // the sheet's own default is what is under test.
              final result = canChangeRelationship == null
                  ? await showProfileEditDialog(context, existing: existing)
                  : await showProfileEditDialog(
                      context,
                      existing: existing,
                      canChangeRelationship: canChangeRelationship,
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

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

const _dropdown = ValueKey('edit-relationship-dropdown');
const _readOnlyValue = ValueKey('edit-relationship-read-only');
const _lockedHint = ValueKey('edit-relationship-locked-hint');
const _lockedLine = 'Only the primary guardian can change this.';

void main() {
  testWidgets(
      'a caller who cannot change it sees the stored relationship as text '
      'and the line saying who can, with no dropdown', (tester) async {
    await _openDialog(
      tester,
      existing: _profile(relationship: ProfileRelationship.daughter),
      canChangeRelationship: false,
    );

    expect(find.byKey(_dropdown), findsNothing);
    expect(find.byType(DropdownButton<ProfileRelationship?>), findsNothing);
    expect(tester.widget<Text>(find.byKey(_readOnlyValue)).data, 'Daughter');
    expect(tester.widget<Text>(find.byKey(_lockedHint)).data, _lockedLine);
    // The field keeps its label, so the value is not a bare word.
    expect(find.text('Relationship'), findsOneWidget);
  });

  testWidgets('a profile with no relationship reads None when read-only',
      (tester) async {
    await _openDialog(
      tester,
      existing: _profile(),
      canChangeRelationship: false,
    );

    expect(tester.widget<Text>(find.byKey(_readOnlyValue)).data, 'None');
    expect(find.text(_lockedLine), findsOneWidget);
  });

  testWidgets(
      'her save carries the stored relationship and still saves the rest',
      (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(relationship: ProfileRelationship.daughter),
      canChangeRelationship: false,
      onPopped: (result) => popped = result,
    );

    await tester.enterText(find.byType(TextFormField).first, 'Nova B');
    await _save(tester);

    expect(popped, isNotNull);
    expect(popped!.displayName, 'Nova B');
    expect(popped!.relationship, ProfileRelationship.daughter);
  });

  testWidgets(
      'by default the dropdown is offered, with no line, and a change is '
      'saved', (tester) async {
    ProfileEditResult? popped;
    await _openDialog(
      tester,
      existing: _profile(relationship: ProfileRelationship.daughter),
      onPopped: (result) => popped = result,
    );

    expect(find.byKey(_dropdown), findsOneWidget);
    expect(find.byKey(_readOnlyValue), findsNothing);
    expect(find.text(_lockedLine), findsNothing);

    await tester.ensureVisible(find.byKey(_dropdown));
    await tester.tap(find.byKey(_dropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Son').last);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(popped!.relationship, ProfileRelationship.son);
  });

  testWidgets('a new profile is offered the dropdown', (tester) async {
    await _openDialog(tester);

    expect(find.byKey(_dropdown), findsOneWidget);
    expect(find.text(_lockedLine), findsNothing);
  });
}
