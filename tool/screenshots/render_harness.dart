/// The render harness behind the screenshot run (issue #1104): one
/// provider tree over an in-memory Drift store seeded with
/// [fabricatedScreenshotProfiles], and one [ScenePlan] per manifest
/// screen id — the real production widgets, mounted exactly the way the
/// widget-test harnesses mount them (the same fakes-free recipe
/// `test/ui/overview_test.dart` and `test/ui/app_shell_test.dart` use),
/// at whatever device size the runner sets.
///
/// Nothing here reads the wall clock: every screen receives the fixed
/// `todayProvider`, and the only data is the fabricated set. This file
/// runs only under `flutter test` (the runner is
/// `render_screens_test.dart`); it is deliberately not exercised by the
/// CI suite, which renders nothing — the store-side unit tests live in
/// `test/tool/screenshots/`.
library;

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' show Random;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide DayEntry, Profile;
import 'package:lunarlog/data/db/ulid.dart' show UlidGenerator;
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/clue_importer.dart';
import 'package:lunarlog/data/repositories/drift_activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/app_shell.dart';
import 'package:lunarlog/ui/components/today_log_fab.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/settings/import_screen.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'fabricated_profile.dart';
import 'manifest.dart';

/// The RepaintBoundary every screenshot is captured from — the runner
/// finds it by this key after the scene settles.
const Key kScreenshotBoundaryKey = ValueKey('screenshot-boundary');

/// The fabricated auth-user id the caller guardian row carries (a
/// synthetic id, not a person's — user ids are not profile names and are
/// never rendered).
const String kFabricatedCallerUserId = 'fabricated-user-0001';

/// Loads the fonts the app ships (pubspec `fonts:` — Inter 400/500/600,
/// Fraunces 600, Roboto 400) into the test engine, so text renders with
/// the real glyphs instead of the test runner's fallback. Also loads
/// Material Icons from the Flutter SDK's own cache (`uses-material-design:
/// true` injects it into real builds; the test engine needs it by hand or
/// every icon renders as a tofu box). Idempotent.
bool _fontsLoaded = false;

Future<void> loadScreenshotFonts() async {
  if (_fontsLoaded) return;
  const families = <String, List<String>>{
    'Inter': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
    ],
    'Fraunces': ['assets/fonts/Fraunces-SemiBold.ttf'],
    'Roboto': ['assets/fonts/Roboto-Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final icons = _materialIconsFont();
  if (icons == null) {
    throw StateError(
      'Material Icons font not found under the Flutter SDK cache — the '
      'screenshots need it (FLUTTER_ROOT can point at the SDK root); '
      'icons would render as tofu boxes without it',
    );
  }
  final iconBytes = icons.readAsBytesSync();
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(ByteData.view(iconBytes.buffer)));
  await iconLoader.load();
  _fontsLoaded = true;
}

/// The Material Icons font inside the Flutter SDK cache, or null when no
/// candidate directory holds it.
///
/// The artifact's filename case changed across Flutter releases — a fresh
/// SDK downloads `MaterialIcons-Regular.otf`, while caches populated by
/// older releases hold `materialicons-regular.otf` — so the lookup is
/// case-insensitive over each candidate directory instead of an
/// exact-path existence check (a fresh CI runner and a long-lived dev
/// machine both have to work).
File? _materialIconsFont() {
  for (final dir in _materialFontsDirCandidates()) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entry in directory.listSync()) {
      if (entry is File &&
          entry.uri.pathSegments.last.toLowerCase() ==
              'materialicons-regular.otf') {
        return entry;
      }
    }
  }
  return null;
}

/// The candidate `material_fonts` cache directories: `$FLUTTER_ROOT` when
/// the tool provides it, else walked up from the running `flutter_tester`
/// executable (`bin/cache/artifacts/engine/<host>/` under the SDK root).
List<String> _materialFontsDirCandidates() {
  final candidates = <String>[];
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    candidates.add('$fromEnv/bin/cache/artifacts/material_fonts');
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    candidates.add('${dir.path}/bin/cache/artifacts/material_fonts');
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return candidates;
}

/// A minimal [SharingService] whose only live method is the pending-invite
/// list — empty, so the sharing screenshot shows the settled, accepted
/// state. The same shape
/// `test/ui/sharing/manage_guardians_delete_profile_test.dart` uses; the
/// screen never touches the other members on this path.
class _NoPendingInvitesSharingService implements SharingService {
  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Owns one screenshot run's database, seeded profiles, and provider
/// tree. Created fresh per screen so no state leaks between captures.
class ScreenshotWorld {
  ScreenshotWorld._(this._db, this.maya, this.riley);

  final LunarLogDatabase _db;
  final Profile maya;
  final Profile riley;

  late final DriftDayEntriesRepository _entries =
      DriftDayEntriesRepository(_db.storage);
  late final DriftSettingsStore _settings = DriftSettingsStore(_db.storage);

  /// Builds the world: the two fabricated profiles, their seeded day
  /// entries, and the sharing screenshot's guardian rows. Fails before
  /// anything renders if a name is off the generator's list (the
  /// [FabricatedNameError] from the data builder propagates here).
  ///
  /// The database's clock and ULID generator are frozen with the data:
  /// generated row ids carry the ULID's timestamp bits, and UI like the
  /// profile avatar derives its colour from the profile id — wall-clock
  /// ids would make two runs of the same commit render differently.
  static Future<ScreenshotWorld> create() async {
    final specs = fabricatedScreenshotProfiles();
    DateTime fixedClock() => DateTime.utc(2026, 9, 1, 12);
    final db = LunarLogDatabase(
      NativeDatabase.memory(),
      clock: fixedClock,
      ulid: UlidGenerator(clock: fixedClock, random: Random(20260928)),
    );
    final profilesRepo = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);

    Future<Profile> mount(FabricatedProfile spec, ProfileMode mode) async {
      final profile = await profilesRepo.create(
        displayName: spec.name,
        isMinor: spec.isMinor,
        birthYear: spec.birthYear,
        mode: mode,
      );
      for (final day in spec.days) {
        await entries.save(DayEntry(
          id: '',
          profileId: profile.id,
          localDate: day.date,
          tz: 'America/Chicago',
          flow: day.flow,
          tags: day.tags,
          note: day.note,
          updatedAt: DateTime.utc(2026, 9, 1, 12),
        ));
      }
      return profile;
    }

    final maya = await mount(specs[0], ProfileMode.standard);
    final riley = await mount(specs[1], ProfileMode.teen);

    // The sharing screenshot's accepted guardians: the caller
    // (primary_guardian) and the seed partner (co_parent, fabricated
    // label from the seeder). Accepted rows only — pending invites carry
    // wall-clock countdowns, which would break byte-identity.
    await db.storage.applyRemoteRows([
      _guardianRow(riley.id, 'g-caller', kFabricatedCallerUserId,
          'primary_guardian', null),
      _guardianRow(riley.id, 'g-partner', 'fabricated-user-0002', 'co_parent',
          kFabricatedGuardianLabels.single),
    ]);
    return ScreenshotWorld._(db, maya, riley);
  }

  static RemoteProfileGuardianRow _guardianRow(
    String profileId,
    String id,
    String userId,
    String role,
    String? displayName,
  ) =>
      RemoteProfileGuardianRow(
        id: id,
        profileId: profileId,
        userId: userId,
        role: role,
        status: 'accepted',
        displayName: displayName,
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        serverVersion: 1,
      );

  /// Closes the database. Call after the captures for this world.
  Future<void> dispose() => _db.close();
}

/// Everything the runner needs to render one manifest screen: the widget
/// to mount as the MaterialApp's `home`, and an optional interaction to
/// perform once the first frame has settled (open the day sheet, open the
/// life-stage dropdown, present the article).
class ScenePlan {
  const ScenePlan({required this.home, this.interact});

  final Widget home;

  /// Runs after `pumpAndSettle` on the mounted tree; another
  /// `pumpAndSettle` follows it before the capture.
  final Future<void> Function(WidgetTester tester)? interact;
}

/// The provider tree the whole screenshot app mounts under — the same
/// collaborators `test/ui/overview_test.dart`'s harness wires, over the
/// world's real repositories. The scope wraps the MaterialApp (not the
/// home widget) exactly as `lib/app.dart` scopes the production tree:
/// modal routes — the day sheet, the article sheet — read providers from
/// the root navigator's context, which sits above any provider nested
/// inside `home`. Nullable services the shell tolerates (sync status,
/// auth) are left unprovided: the screenshots show the app's local-only
/// posture, which is also its unconfigured-build look.
Widget providersFor(ScreenshotWorld world, {required Widget child}) =>
    MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(
          value: DriftProfilesRepository(world._db.storage),
        ),
        Provider<DayEntriesRepository>.value(value: world._entries),
        Provider<ObservationsRepository>.value(
          value: DriftObservationsRepository(world._db.storage),
        ),
        Provider<SettingsStore>.value(value: world._settings),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(world._entries,
              settings: world._settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(world._entries, settings: world._settings),
        ),
        Provider<CycleExclusionList>.value(
          value: CycleExclusionList(world._settings),
        ),
        ChangeNotifierProvider<NotificationPermissionState>.value(
          value:
              NotificationPermissionState(NotificationAvailability.available),
        ),
        Provider<ProfileGuardiansRepository>.value(
          value: DriftProfileGuardiansRepository(world._db.storage),
        ),
        Provider<ActivityFeedRepository>.value(
          value: DriftActivityFeedRepository(world._db.storage),
        ),
        Provider<CareContentRepository>.value(
          value: DriftCareContentRepository(world._db.storage),
        ),
        Provider<ProfileModesRepository>.value(
          value: DriftProfileModesRepository(world._db.storage),
        ),
        ChangeNotifierProvider<ProfileController>(
          create: (_) {
            final controller = ProfileController(
              profilesRepository: DriftProfilesRepository(world._db.storage),
              settingsStore: world._settings,
            );
            unawaited(controller.load());
            return controller;
          },
        ),
      ],
      child: child,
    );

/// The fixed "today" seam every shell-mounted screen receives.
LocalDate _fixedToday() => kScreenshotToday;

/// Settles a scene deterministically and with a hard ceiling: fixed pump
/// steps (so the rendered frames are identical run to run), and a bounded
/// total — a screen with an animation that never stops must fail its
/// capture loudly, not hang the whole manifest walk the way an unbounded
/// `pumpAndSettle` would.
Future<void> settleScene(WidgetTester tester) async {
  const step = Duration(milliseconds: 100);
  const maxSteps = 60; // 6 simulated seconds; far past every screen's animations
  for (var i = 0; i < maxSteps; i++) {
    await tester.pump(step);
  }
  // One more pump so any post-frame work scheduled by the last step
  // completes before the capture.
  await tester.pump(const Duration(milliseconds: 1));
}

AppShell _shell(Profile profile) => AppShell(
      profile: profile,
      todayProvider: _fixedToday,
      timezoneProvider: () => 'America/Chicago',
    );

/// Resolves a manifest screen id to the scene the renderer mounts. The
/// provider scope is applied by the runner around the whole MaterialApp
/// (see [providersFor]), so the scenes here stay plain widgets.
ScenePlan sceneFor(ScreenshotWorld world, ScreenshotScreen screen) {
  switch (screen.id) {
    case 'today':
      return ScenePlan(home: _shell(world.maya));
    case 'estimates':
      // The teen profile's three-cycle history renders the learning
      // tier's range estimate — the confidence framing the site shows
      // next to Today's high-confidence date.
      return ScenePlan(home: _shell(world.riley));
    case 'calendar':
      return ScenePlan(
        home: _shell(world.maya),
        interact: (tester) async {
          await tester
              .tap(find.byKey(const ValueKey('app-shell-tab-calendar')));
          await settleScene(tester);
        },
      );
    case 'log-day':
      return ScenePlan(
        home: _shell(world.maya),
        interact: (tester) async {
          await tester.tap(find.byType(TodayLogFab));
          await settleScene(tester);
          expect(
            find.byType(DaySheet),
            findsOneWidget,
            reason: 'the FAB must open the day sheet for the capture',
          );
        },
      );
    case 'guardians':
      // Constructor-injected the way the widget tests mount it — no
      // provider tree needed. No ProfileErasureService: the Danger zone
      // stays out of the marketing shot.
      return ScenePlan(
        home: ManageGuardiansScreen(
          profile: world.riley,
          guardiansRepository:
              DriftProfileGuardiansRepository(world._db.storage),
          sharingService: _NoPendingInvitesSharingService(),
          currentUserId: kFabricatedCallerUserId,
        ),
      );
    case 'life-stage':
      return ScenePlan(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () =>
                    showProfileEditSheet(context, existing: world.riley),
                child: const Text('edit'),
              ),
            ),
          ),
        ),
        interact: (tester) async {
          await tester.tap(find.text('edit'));
          await settleScene(tester);
          await tester
              .tap(find.byKey(const ValueKey('edit-lifecycle-dropdown')));
          await settleScene(tester);
        },
      );
    case 'import':
      return ScenePlan(
        home: ImportScreen(
          coordinator: DriftAccountImportCoordinator(
            profilesRepository: DriftProfilesRepository(world._db.storage),
            dayEntriesRepository: DriftDayEntriesRepository(world._db.storage),
            observationsRepository:
                DriftObservationsRepository(world._db.storage),
            storage: world._db.storage,
          ),
          clueRunner: ClueImporter(world._db.storage),
          profilesRepository: DriftProfilesRepository(world._db.storage),
        ),
      );
    case 'export':
      // The provider scope supplies the SettingsStore; with no
      // AuthController provided, this is the app's unconfigured look —
      // Your data present, no account section.
      return ScenePlan(home: const SettingsScreen());
    case 'article':
      return ScenePlan(
        home: const Scaffold(body: SizedBox.shrink()),
        interact: (tester) async {
          final context = tester.element(find.byType(Scaffold).first);
          unawaited(CycleLiteracyArticleSheet.show(
            context,
            CycleLiteracyLibrary.whyCrampsHappen,
          ));
          await settleScene(tester);
          expect(
            find.byType(CycleLiteracyArticleSheet),
            findsOneWidget,
            reason: 'the article sheet must be up for the capture',
          );
        },
      );
  }
  throw StateError('no scene plan for screen id "${screen.id}" — add one '
      'to sceneFor() when adding the manifest entry');
}

/// The MaterialApp the runner mounts every scene inside: the production
/// themes (both wired, per the repo's theme-wiring posture), the fixed
/// locale, and the [kScreenshotBoundaryKey] repaint boundary the capture
/// rasterizes.
Widget screenshotApp({
  required ScreenshotTheme theme,
  required Widget child,
}) =>
    RepaintBoundary(
      key: kScreenshotBoundaryKey,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            theme == ScreenshotTheme.light ? ThemeMode.light : ThemeMode.dark,
        // The test binding runs in debug mode, which otherwise paints the
        // red "DEBUG" corner banner into every capture.
        debugShowCheckedModeBanner: false,
        home: child,
      ),
    );
