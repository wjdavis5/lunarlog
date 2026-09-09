/// Widget tests for the "Your data" section (Issue #222; source: B-17):
/// reachable without a cloud account. Every collaborator is a fake (KTD6):
/// the profiles/day-entries repositories and the export collaborator never
/// touch drift, `path_provider`, or `share_plus`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/settings/your_data_section.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Alice',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A [ProfilesRepository] whose [watch] emits the current list immediately
/// on subscription, then relays [setProfiles] calls - the same reactive
/// shape `DriftProfilesRepository.watch` gives the real app.
class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository([List<Profile> initial = const []])
      : _profiles = initial;

  List<Profile> _profiles;
  final _controller = StreamController<List<Profile>>.broadcast();

  void setProfiles(List<Profile> profiles) {
    _profiles = profiles;
    _controller.add(profiles);
  }

  /// Simulates the underlying stream breaking (e.g. a drift/sqlite3
  /// failure) after the section has already subscribed.
  void addError(Object error) => _controller.addError(error);

  @override
  Future<List<Profile>> list() async => _profiles;

  @override
  Stream<List<Profile>> watch() async* {
    yield _profiles;
    yield* _controller.stream;
  }

  void dispose() => unawaited(_controller.close());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDayEntriesRepository implements DayEntriesRepository {
  Map<String, List<DayEntry>> entriesByProfile = const {};

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      entriesByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthController _signedIn() {
  final service = FakeAuthService()
    ..emit(AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'));
  addTearDown(service.dispose);
  final controller = AuthController(authService: service);
  addTearDown(controller.dispose);
  return controller;
}

AuthController _signedOut() {
  final service = FakeAuthService();
  addTearDown(service.dispose);
  final controller = AuthController(authService: service);
  addTearDown(controller.dispose);
  return controller;
}

AuthController _passwordRecovery() {
  final service = FakeAuthService()
    ..latchRecovery(user: const AuthUser(id: 'u1', email: 'a@b.c'));
  addTearDown(service.dispose);
  final controller = AuthController(authService: service);
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfilesRepository profiles,
  FakeDayEntriesRepository? dayEntries,
  bool? showExport,
  ExportAccountCollaborator? exportAccount,
  AuthController? auth,
}) async {
  addTearDown(profiles.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ProfilesRepository>.value(value: profiles),
          Provider<DayEntriesRepository>.value(
              value: dayEntries ?? FakeDayEntriesRepository()),
          if (auth != null)
            ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: Scaffold(
          body: YourDataSection(
            showExport: showExport,
            exportAccount: exportAccount,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('reachability (Issue #222 - the core fix)', () {
    testWidgets(
        'signed out with a profile: the tile renders and export runs the '
        'local-only document (no AuthController at all needed)',
        (tester) async {
      var exportCalls = 0;
      List<Profile>? capturedProfiles;
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(
        tester,
        profiles: profiles,
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          exportCalls++;
          capturedProfiles = profiles;
        },
      );

      expect(key('your-data-export'), findsOneWidget);
      expect(find.text('Save your profiles and day entries as a JSON file.'),
          findsOneWidget,
          reason: 'signed out: no claim of server data being included');

      await tester.tap(key('your-data-export'));
      await tester.pumpAndSettle();

      expect(exportCalls, 1);
      expect(capturedProfiles?.single.id, 'p1');
      expect(key('your-data-export-error'), findsNothing);
    });

    testWidgets('no profiles: the tile is absent', (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('your-data-export'), findsNothing);
    });

    testWidgets('web (showExport: false): the tile is absent even with a '
        'profile', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles, showExport: false);
      expect(key('your-data-export'), findsNothing);
    });

    testWidgets(
        'no ProfilesRepository provided at all (unconfigured build): the '
        'tile is absent, same as no profiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: YourDataSection())),
      );
      await tester.pumpAndSettle();
      expect(key('your-data-export'), findsNothing);
    });

    testWidgets(
        'signed in: the same tile still renders, now naming the account\'s '
        'server data', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles, auth: _signedIn());

      expect(key('your-data-export'), findsOneWidget);
      expect(
        find.text(
          "Save your profiles and day entries as a JSON file, including "
          "your account's server data.",
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'password recovery: counts as signed in for the subtitle, matching '
        "AccountSection's _isSignedIn", (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles, auth: _passwordRecovery());

      expect(key('your-data-export'), findsOneWidget);
      expect(
        find.text(
          "Save your profiles and day entries as a JSON file, including "
          "your account's server data.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a profile arriving after first build (first-run completes '
        'while Settings is open) makes the tile appear reactively',
        (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('your-data-export'), findsNothing);

      profiles.setProfiles([_profile('p1')]);
      await tester.pumpAndSettle();
      expect(key('your-data-export'), findsOneWidget);
    });
  });

  group('export failure', () {
    testWidgets('a failed export surfaces copy, not an exception',
        (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(
        tester,
        profiles: profiles,
        exportAccount: ({
          required profiles,
          required entriesByProfile,
          required appVersion,
        }) async {
          throw StateError('disk full');
        },
      );

      await tester.tap(key('your-data-export'));
      await tester.pumpAndSettle();

      expect(key('your-data-export-error'), findsOneWidget);
      expect(
        tester.widget<InlineError>(key('your-data-export-error')).message,
        kAccountExportFailureCopy,
      );
    });
  });

  group('signed out with a signed-out AuthController present', () {
    testWidgets('reads exactly like no AuthController at all', (
      tester,
    ) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles, auth: _signedOut());
      expect(key('your-data-export'), findsOneWidget);
      expect(find.text('Save your profiles and day entries as a JSON file.'),
          findsOneWidget);
    });
  });

  group('profiles watch failure', () {
    testWidgets(
        'a broken profiles stream hides the section instead of throwing an '
        'unhandled zone error', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles);
      expect(key('your-data-export'), findsOneWidget);

      profiles.addError(StateError('drift stream broke'));
      await tester.pumpAndSettle();

      expect(key('your-data-export'), findsNothing);
    });
  });
}
