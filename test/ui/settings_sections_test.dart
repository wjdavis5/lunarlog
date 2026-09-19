/// Issue #226 acceptance coverage: the Settings screen's eight-section
/// structure (order as data, each headed by the shared `SettingsSection`
/// component), the caregiver alert preferences promoted into the Reminders
/// section (one tap from Settings, with the Manage Guardians path
/// untouched), the Calendar section's week-start and date-format pickers
/// persisting through the settings store, and the About section's
/// version/build/licences entries.
///
/// The harness mounts a tall viewport (the full sectioned list is far
/// taller than the default 800x600 test surface, and a `ListView` only
/// builds children near the viewport — assertions against the About
/// section at the bottom would otherwise race the build).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/list_section_header.dart';
import 'package:lunarlog/ui/settings/about_section.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../support/fake_notification_preferences_service.dart';
import '../support/fake_settings_store.dart';

/// A [ProfilesRepository] whose [watch] emits [profiles] immediately on
/// subscription and never changes thereafter (the same shape
/// `test/ui/settings_test.dart` uses).
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

/// Empty-row answers for everything `SettingsScreen`'s tree reads: the
/// clinical export tile's `listForProfile` (via [DayEntriesRepository]) and
/// the sharing overview controller's `watchForProfile` (via
/// [ProfileGuardiansRepository]).
class _FakeDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Future<bool> hasAnyEntries(String profileId) async => false;

  @override
  Stream<bool> watchHasAnyEntries(String profileId) => Stream.value(false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGuardiansRepository implements ProfileGuardiansRepository {
  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSharingService implements SharingService {
  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

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

Future<void> pumpSettings(
  WidgetTester tester, {
  FakeSettingsStore? settings,
  List<Profile> profiles = const [],
  ReminderConfigService? reminderService,
  NotificationPreferencesService? notificationService,
  bool withSharing = false,
  Locale? locale,
}) async {
  settings ??= FakeSettingsStore();
  addTearDown(settings.close);
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: locale == null
          ? AppLocalizations.supportedLocales
          : <Locale>[locale],
      home: MultiProvider(
        providers: [
          Provider<SettingsStore>.value(value: settings),
          Provider<ProfilesRepository>.value(
            value: _FakeProfilesRepository(profiles),
          ),
          Provider<DayEntriesRepository>.value(
            value: _FakeDayEntriesRepository(),
          ),
          if (reminderService != null)
            Provider<ReminderConfigService>.value(value: reminderService),
          if (notificationService != null)
            Provider<NotificationPreferencesService>.value(
              value: notificationService,
            ),
          if (withSharing) ...[
            Provider<SharingService>.value(value: _FakeSharingService()),
            Provider<ProfileGuardiansRepository>.value(
              value: _FakeGuardiansRepository(),
            ),
          ],
        ],
        child: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The `settings-section-<id>` Column keys in layout order — the ordering
/// assertion `SettingsSection`'s keyed Column exists for.
List<String> _sectionIdsInOrder(WidgetTester tester) => [
      for (final column in tester.widgetList<Column>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Column &&
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('settings-section-'),
        ),
      ))
        (column.key as ValueKey<String>).value.substring(
          'settings-section-'.length,
        ),
    ];

Future<PackageInfo> _fakePackageInfo() async => PackageInfo(
      appName: 'lunarlog',
      packageName: 'com.wjdavis5.lunarlog',
      version: '1.2.3',
      buildNumber: '42',
    );

Future<PackageInfo> _failingPackageInfo() async => throw Exception('no channel');

void main() {
  testWidgets(
      "Issue #226/#458: renders the nine sections, in the issue's order, each "
      'headed by the shared SettingsSection component', (tester) async {
    await pumpSettings(
      tester,
      profiles: [_profile('p1', 'Alice')],
      notificationService: FakeNotificationPreferencesService(),
      withSharing: true,
    );

    expect(
      _sectionIdsInOrder(tester),
      [
        'your-data',
        // Issue #458 opened the health tile on Android (this test platform)
        // for the import direction; it renders whenever the repos are wired.
        'health',
        'appearance',
        'reminders',
        'calendar',
        'family-sharing',
        'privacy-security',
        'help',
        'about',
      ],
    );
    // The headers render their localized titles.
    for (final title in [
      'Your data',
      'Health',
      'Appearance',
      'Reminders',
      'Calendar',
      'Family & sharing',
      'Privacy & security',
      'Help',
      'About',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '$title header');
    }
    // Issue #813: every section head renders through the one shared
    // component (one per section, nine sections here).
    expect(find.byType(ListSectionHeader), findsNWidgets(9),
        reason: 'each section is headed by the shared ListSectionHeader');
  });

  testWidgets(
      'the relock toggle keeps its explanation inside the Privacy & '
      'security section, among section-mates', (tester) async {
    await pumpSettings(tester, profiles: [_profile('p1', 'Alice')]);
    expect(find.byKey(const ValueKey('relock-toggle')), findsOneWidget);
    expect(
      find.textContaining('Locks the app after 1 hour'),
      findsOneWidget,
      reason: 'issue #762: the subtitle names the selected duration, '
          'defaulting to 1 hour',
    );
    expect(find.text('Privacy & security'), findsOneWidget);
    // Section-mates: the privacy policy tile renders under the same
    // header.
    expect(find.byKey(const ValueKey('privacy-policy-tile')), findsOneWidget);
  });

  testWidgets(
      'caregiver alert preferences are one tap from Settings (promoted out '
      'of Manage Guardians) — one tile per active profile', (tester) async {
    await pumpSettings(
      tester,
      profiles: [_profile('p1', 'Alice'), _profile('p2', 'Zoe')],
      notificationService: FakeNotificationPreferencesService(),
    );

    expect(find.text('Reminders'), findsOneWidget);
    final aliceTile = find.byKey(const ValueKey('caregiver-alerts-p1'));
    expect(aliceTile, findsOneWidget);
    expect(find.byKey(const ValueKey('caregiver-alerts-p2')), findsOneWidget);
    expect(find.text('Guardian alerts'), findsNWidgets(2));
    expect(find.text('Alice'), findsOneWidget);

    // One tap lands on the notification preferences screen itself.
    await tester.tap(aliceTile);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('alert-on-log-toggle')),
      findsOneWidget,
    );
  });

  testWidgets(
      'no notification preferences service: the caregiver alerts tiles '
      'self-hide and (with no reminder service either) so does the whole '
      'Reminders section', (tester) async {
    await pumpSettings(tester, profiles: [_profile('p1', 'Alice')]);

    expect(find.byKey(const ValueKey('caregiver-alerts-p1')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-section-reminders')),
      findsNothing,
    );
  });

  testWidgets(
      'first-day-of-week picker persists through the settings store and '
      'updates its own subtitle', (tester) async {
    final settings = FakeSettingsStore();
    await pumpSettings(
      tester,
      settings: settings,
      profiles: [_profile('p1', 'Alice')],
    );

    final tile = find.byKey(const ValueKey('first-day-of-week-tile'));
    expect(tile, findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget); // default subtitle

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first-day-option-monday')));
    await tester.pumpAndSettle();

    expect(
      await settings.get(SettingsKeys.calendarFirstDayOfWeek),
      'monday',
    );
    expect(find.text('Monday'), findsOneWidget);
  });

  testWidgets('date-format picker persists through the settings store',
      (tester) async {
    final settings = FakeSettingsStore();
    await pumpSettings(
      tester,
      settings: settings,
      profiles: [_profile('p1', 'Alice')],
    );

    final tile = find.byKey(const ValueKey('date-format-tile'));
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-format-option-monthDay')));
    await tester.pumpAndSettle();

    expect(await settings.get(SettingsKeys.dateFormat), 'month_day');
    expect(find.text('Month first (Sep 5)'), findsOneWidget);
  });

  testWidgets(
      'issue #884: the "System default" sample resolves through the locale '
      'instead of claiming a fixed order', (tester) async {
    await pumpSettings(
      tester,
      profiles: [_profile('p1', 'Alice')],
      locale: const Locale('en', 'US'),
    );
    expect(find.text('System default (Sep 5)'), findsOneWidget);
    expect(find.text('System default (5 Sep)'), findsNothing);
  });

  testWidgets(
      'issue #884: an en_GB locale shows the day-first "System default" '
      'sample', (tester) async {
    await pumpSettings(
      tester,
      profiles: [_profile('p1', 'Alice')],
      locale: const Locale('en', 'GB'),
    );
    expect(find.text('System default (5 Sept)'), findsOneWidget);
    expect(find.text('System default (Sep 5)'), findsNothing);
  });

  testWidgets(
      'About section shows the version and build number from PackageInfo '
      'and opens the licence page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: const [
              AboutSection(packageInfoReader: _fakePackageInfo),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-version-tile')), findsOneWidget);
    expect(find.text('Version 1.2.3 (build 42)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about-licenses-tile')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets(
      'About section degrades to "Not available" when the platform read '
      'fails (no method channel under test)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: const [
              AboutSection(packageInfoReader: _failingPackageInfo),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsOneWidget);
  });
}
