/// Issue #802 client coverage, part 2: the one-time Teen-mode suggestion
/// for a manager when a minor subject joins.
///
/// * the predicate: minor + Standard + subject-joined (birth year
///   authoritative over the stored flag, the shared `isMinorAsOf` rule);
///   an adult subject keeps Standard; a non-Standard profile is never
///   offered;
/// * the offer: fires once per profile (the settings latch is written
///   even when declined), accepting writes `teen` through the profile
///   controller's rename seam, declining writes nothing;
/// * a tree without the seams never offers anything (the #802 null-gating
///   discipline).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/sharing/subject_teen_mode_offer.dart';
import 'package:provider/provider.dart';

import '../../support/fake_settings_store.dart';

Profile _profile({
  ProfileMode mode = ProfileMode.standard,
  bool isMinor = true,
  int? birthYear,
}) =>
    Profile(
      id: 'p-subject',
      displayName: 'Riley',
      isMinor: isMinor,
      mode: mode,
      birthYear: birthYear,
      relationship: ProfileRelationship.daughter,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Mutable [ProfilesRepository] fake: the teen-offer path only reads
/// `watch()` and writes through `update()`, so the fake records the
/// update and replays it into its own list.
class _FakeProfilesRepository implements ProfilesRepository {
  _FakeProfilesRepository(this._profiles);

  final List<Profile> _profiles;
  final updates = <Profile>[];

  @override
  Future<Profile> update(Profile profile) async {
    updates.add(profile);
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) _profiles[index] = profile;
    return profile;
  }

  @override
  Future<Profile?> findById(String id) async {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<List<Profile>> list() async => List.of(_profiles);

  @override
  Stream<List<Profile>> watch() => Stream.value(List.of(_profiles));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _tree({
  required FakeSettingsStore settings,
  ProfileController? controller,
}) =>
    MultiProvider(
      providers: [
        Provider<SettingsStore>.value(value: settings),
        if (controller != null)
          ChangeNotifierProvider<ProfileController>.value(value: controller),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: _OfferButtonHost()),
      ),
    );

class _OfferButtonHost extends StatelessWidget {
  const _OfferButtonHost();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => ElevatedButton(
        key: const ValueKey('offer-trigger'),
        onPressed: () => offerSubjectTeenModeFromTree(
          context,
          profile: _profile(),
        ),
        child: const Text('offer'),
      ),
    );
  }
}

void main() {
  final now = DateTime(2026, 9, 20);

  group('shouldOfferSubjectTeenMode (Issue #802)', () {
    test('a minor subject joining a Standard profile qualifies', () {
      expect(
        shouldOfferSubjectTeenMode(
          _profile(isMinor: true),
          subjectJoined: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('birth year is authoritative: a 2010 birth year is a minor in 2026 '
        'even with the stored flag off', () {
      expect(
        shouldOfferSubjectTeenMode(
          _profile(isMinor: false, birthYear: 2010),
          subjectJoined: true,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldOfferSubjectTeenMode(
          _profile(isMinor: true, birthYear: 2000),
          subjectJoined: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('an adult subject keeps Standard (no offer)', () {
      expect(
        shouldOfferSubjectTeenMode(
          _profile(isMinor: false),
          subjectJoined: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('a profile already in a non-Standard mode is never offered', () {
      expect(
        shouldOfferSubjectTeenMode(
          _profile(mode: ProfileMode.teen),
          subjectJoined: true,
          now: now,
        ),
        isFalse,
        reason: 'already teen',
      );
      expect(
        shouldOfferSubjectTeenMode(
          _profile(mode: ProfileMode.caregiver),
          subjectJoined: true,
          now: now,
        ),
        isFalse,
        reason: 'caregiver framing is a deliberate choice already made',
      );
    });

    test('no subject joined means no offer', () {
      expect(
        shouldOfferSubjectTeenMode(
          _profile(),
          subjectJoined: false,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('offerSubjectTeenModeFromTree (Issue #802)', () {
    testWidgets('accepting writes teen through the rename seam', (tester) async {
      final settings = FakeSettingsStore();
      final profiles = _FakeProfilesRepository([_profile()]);
      final controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: settings,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_tree(settings: settings, controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('offer-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('subject-teen-mode-title')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('subject-teen-mode-accept')));
      await tester.pumpAndSettle();

      expect(profiles.updates, hasLength(1));
      expect(profiles.updates.single.mode, ProfileMode.teen);
      // Everything else about the profile rides along unchanged.
      expect(profiles.updates.single.displayName, 'Riley');
      expect(profiles.updates.single.birthYear, isNull);
      expect(find.byKey(const ValueKey('subject-teen-mode-snack')),
          findsOneWidget);
    });

    testWidgets('declining writes nothing and the latch still lands',
        (tester) async {
      final settings = FakeSettingsStore();
      final profiles = _FakeProfilesRepository([_profile()]);
      final controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: settings,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_tree(settings: settings, controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('offer-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('subject-teen-mode-decline')));
      await tester.pumpAndSettle();

      expect(profiles.updates, isEmpty);
      final latch =
          await settings.get('${SettingsKeys.subjectTeenModeOffered}:p-subject');
      expect(latch, isNotNull,
          reason: 'the offer is once per profile whatever the answer');

      // A second kick on the same tree is a no-op — no dialog reappears.
      await tester.tap(find.byKey(const ValueKey('offer-trigger')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subject-teen-mode-title')),
          findsNothing);
    });

    testWidgets('a seeded latch never shows the dialog', (tester) async {
      final settings = FakeSettingsStore()
        ..setSilently(
          '${SettingsKeys.subjectTeenModeOffered}:p-subject',
          'shown',
        );
      final profiles = _FakeProfilesRepository([_profile()]);
      final controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: settings,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_tree(settings: settings, controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('offer-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('subject-teen-mode-title')),
          findsNothing);
    });

    testWidgets('a tree without a ProfileController never offers',
        (tester) async {
      final settings = FakeSettingsStore();
      await tester.pumpWidget(_tree(settings: settings));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('offer-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('subject-teen-mode-title')),
          findsNothing);
    });
  });
}
