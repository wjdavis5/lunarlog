/// Issue #1217: the Edit profile sheet must not run under the status bar /
/// Dynamic Island once its content is tall enough to fill the screen. A
/// modal bottom sheet removes the top view padding from its own MediaQuery,
/// so the body's own `SafeArea` (profile_dialogs.dart) sees a 0 top inset
/// and cannot help — `showProfileEditDialog` has to pass `useSafeArea:
/// true` so the *route* keeps the sheet below the inset. Mirrors
/// `profile_dialogs_birth_control_start_test.dart`'s harness.
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

ProfileLifecycleMode _pillRow() => (
      mode: LifecycleMode.tracking,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: 'pill',
      birthControlStartedOn: '2026-08-15',
      birthControlStoppedOn: null,
    );

Profile _profile() => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Maya',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  testWidgets('the Edit profile sheet for a Pill profile starts at or below '
      'the status-bar inset on a 402x874 surface (issue #1217)',
      (tester) async {
    // The QA surface from the issue (iPhone 17 Pro, logical points) with
    // its status-bar / Dynamic Island inset. dpr 1.0 keeps the FakeViewPadding
    // values logical, matching a11y_pass_test.dart's setup.
    const topInset = 59.0;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.padding = const FakeViewPadding(top: topInset);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    // The test font is more compact than a device font, so at the default
    // text scale the form can fit above the fold and never test the
    // full-height path. Accessibility text sizes are the issue's own second
    // trigger; at 2.0 the sheet is guaranteed to fill the screen.
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ProfileModesRepository?>.value(
            value: _FakeModesRepository(_pillRow())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProfileEditDialog(context, existing: _profile()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text('Edit profile')).dy;
    expect(titleTop, greaterThanOrEqualTo(topInset),
        reason: 'the sheet fills the screen (a tracked method\'s "Started on" '
            'field is showing), so its title must start below the status-bar '
            'inset — not under the clock and the Dynamic Island');

    // Guard the premise: the title sitting in the top half proves the sheet
    // really did grow to (near) full height, so the assertion above is
    // pinning the safe-area behavior and not a short, bottom-anchored card
    // that never approaches the inset anyway.
    expect(titleTop, lessThan(874 / 2),
        reason: 'the sheet is full height, so the title sits in its top '
            'portion — if this fails the form no longer fills the surface '
            'and this test has stopped exercising the #1217 scenario');
  });
}
