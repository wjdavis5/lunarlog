/// Widget tests for the Settings screen's "Home-screen widget" section
/// (issue #141): the picker persists the profile selection, viewer-role
/// profiles are not offered (the coordinator's role rule for widget
/// configuration), and the section self-hides where no widget surface
/// exists.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/settings/home_widget_section.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_settings_store.dart';

class _FakeProfilesRepository implements ProfilesRepository {
  _FakeProfilesRepository(this.profiles);

  final List<Profile> profiles;

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  Stream<List<Profile>> watch() => Stream.value(profiles);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGuardiansRepository implements ProfileGuardiansRepository {
  _FakeGuardiansRepository(this.byProfile);

  final Map<String, List<ProfileGuardian>> byProfile;

  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async =>
      byProfile[profileId] ?? const [];

  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      Stream.value(byProfile[profileId] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(String id, String name) => Profile(
      id: id,
      displayName: name,
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProfileGuardian _guardian(String profileId, String userId, GuardianRole role) =>
    ProfileGuardian(
      id: 'g-$profileId-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

AuthController _signedInAuth(String userId) {
  final service = FakeAuthService()
    ..emit(
      AuthSessionState.signedIn,
      user: AuthUser(id: userId, email: 'a@b.c'),
    );
  addTearDown(service.dispose);
  final controller = AuthController(authService: service);
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required FakeSettingsStore settings,
  required _FakeProfilesRepository profiles,
  required _FakeGuardiansRepository guardians,
  required AuthController auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          Provider<SettingsStore>.value(value: settings),
          Provider<ProfilesRepository>.value(value: profiles),
          Provider<ProfileGuardiansRepository>.value(value: guardians),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: Scaffold(
          body: ListView(children: const [HomeWidgetSection()]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the picker tile and the privacy disclosure',
      (tester) async {
    final settings = FakeSettingsStore();
    await _pumpSection(
      tester,
      settings: settings,
      profiles: _FakeProfilesRepository([_profile('p1', 'Alice')]),
      guardians: _FakeGuardiansRepository(const {}),
      auth: _signedInAuth('u1'),
    );

    expect(find.byKey(const ValueKey('home-widget-profile-tile')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-widget-privacy-note')),
        findsOneWidget);
    // The default subtitle: follow the app's active profile.
    expect(find.text("Follow the app's current profile"), findsOneWidget);
  });

  group('the note says what a tap on the widget does on this phone', () {
    Future<String> noteOn(WidgetTester tester, TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpSection(
          tester,
          settings: FakeSettingsStore(),
          profiles: _FakeProfilesRepository([_profile('p1', 'Alice')]),
          guardians: _FakeGuardiansRepository(const {}),
          auth: _signedInAuth('u1'),
        );
        return tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('home-widget-privacy-note')),
                matching: find.byType(Text),
              ),
            )
            .data!;
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('Android: the Log button records a period, and the rest of '
        'the widget opens the app', (tester) async {
      final note = await noteOn(tester, TargetPlatform.android);
      // It used to say "tapping it records a period started today", which
      // is what the iPhone widget does. On Android only the button does.
      expect(note, contains('it has a Log button'));
      expect(note, contains('tapping that records a period started today'));
      expect(
        note,
        contains('Tapping anywhere else on the widget opens the app.'),
      );
      expect(note, isNot(contains('tapping it records')));
    });

    testWidgets('iPhone: the whole widget is the tap target, and the note '
        'says so', (tester) async {
      final note = await noteOn(tester, TargetPlatform.iOS);
      expect(note, contains('tapping it records a period started today'));
      expect(note, isNot(contains('Log button')));
      expect(note, isNot(contains('anywhere else')));
    });

    testWidgets('both say what the two notes share', (tester) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final note = await noteOn(tester, platform);
        expect(note, startsWith('The widget shows only a discreet state:'));
        expect(note, contains('only after you unlock the app'));
        expect(note, contains('logging it twice changes nothing'));
        expect(
          note,
          endsWith('Profiles you can only view are not offered here.'),
        );
      }
    });
  });

  testWidgets('the picker offers loggable profiles and persists a pin',
      (tester) async {
    final settings = FakeSettingsStore();
    await _pumpSection(
      tester,
      settings: settings,
      profiles: _FakeProfilesRepository([
        _profile('p1', 'Alice'),
        _profile('p2', 'Beth'),
      ]),
      // Beth's profile is the viewer's: offered nowhere for a pin.
      guardians: _FakeGuardiansRepository({
        'p2': [_guardian('p2', 'u1', GuardianRole.viewer)],
      }),
      auth: _signedInAuth('u1'),
    );

    await tester.tap(find.byKey(const ValueKey('home-widget-profile-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-widget-option-follow')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-widget-option-p1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-widget-option-p2')), findsNothing,
        reason: 'a viewer-role profile is not offered for the widget');

    await tester.tap(find.byKey(const ValueKey('home-widget-option-p1')));
    await tester.pumpAndSettle();

    expect(settings.get('widget_profile_id'), completion('p1'));
    // The tile subtitle now names the pinned profile.
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('picking "follow" clears the pin back to the empty string',
      (tester) async {
    final settings = FakeSettingsStore({'widget_profile_id': 'p1'});
    await _pumpSection(
      tester,
      settings: settings,
      profiles: _FakeProfilesRepository([_profile('p1', 'Alice')]),
      guardians: _FakeGuardiansRepository(const {}),
      auth: _signedInAuth('u1'),
    );

    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-widget-profile-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-widget-option-follow')));
    await tester.pumpAndSettle();

    expect(settings.get('widget_profile_id'), completion(''));
    expect(find.text("Follow the app's current profile"), findsOneWidget);
  });

  testWidgets('the section renders nothing on a platform without widgets',
      (tester) async {
    // Reset inside the test body: the binding verifies the foundation
    // override is unset before tearDowns run.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _pumpSection(
        tester,
        settings: FakeSettingsStore(),
        profiles: _FakeProfilesRepository([_profile('p1', 'Alice')]),
        guardians: _FakeGuardiansRepository(const {}),
        auth: _signedInAuth('u1'),
      );
      expect(find.byKey(const ValueKey('home-widget-profile-tile')),
          findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
