/// Widget tests for the per-profile reminder settings screen (Issue #136):
/// the four type toggles, per-profile persistence through
/// [ReminderConfigService], and the profile switcher.
///
/// The screen is a lazy ListView, so every below-the-fold lookup first
/// scrolls the target into view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/reminder_settings_screen.dart';
import 'package:provider/provider.dart';

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

Profile _profile(String id, String name) => Profile(
      id: id,
      displayName: name,
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester,
  List<Profile> profiles,
  FakeSettingsStore store, {
  ReminderTimePicker? timePicker,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(
          value: _FakeProfilesRepository(profiles),
        ),
        Provider<SettingsStore>.value(value: store),
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: _FakeProfilesRepository(profiles),
            settingsStore: store,
          )..load(),
        ),
        Provider<ReminderConfigService>.value(
          value: ReminderConfigService(store),
        ),
      ],
      child: MaterialApp(
        home: ReminderSettingsScreen(timePicker: timePicker ?? _stubPicker),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The stub picker every test gets unless it overrides: fails the test if
/// a dialog would open without the test expecting one.
Future<TimeOfDay?> _stubPicker(BuildContext context, TimeOfDay initialTime) =>
    throw StateError('unexpected time-picker prompt');

/// Drags the list until [key]'s widget is on screen.
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Drags the list back to its top until the profile picker is visible
/// (a lazy ListView disposes scrolled-out rows, so a below-the-fold
/// scroll leaves the header unbuilt).
Future<void> _scrollToTop(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    if (find
        .byKey(const ValueKey('reminder-profile-dropdown'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
  }
}

/// The rendered time text inside a type's Time row.
String _timeLabel(WidgetTester tester, ReminderKind kind) {
  final row = tester.widget<ListTile>(
    find.byKey(ValueKey('reminder-time-${kind.name}')),
  );
  return ((row.trailing ?? row.title) as Text).data!;
}

SwitchListTile _switchOf(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('renders all four reminder types with their defaults',
      (tester) async {
    final store = FakeSettingsStore();
    await _pump(tester, [_profile('p1', 'Alice')], store);

    expect(_switchOf(tester, 'reminder-upcoming-switch').value, isTrue);
    expect(
        _timeLabel(tester, ReminderKind.upcoming), '09:00',
        reason: 'the stock default time every type ships with');

    // Below the fold: scroll to the opt-in types.
    for (final kind in [ReminderKind.pms, ReminderKind.late, ReminderKind.log]) {
      await _scrollTo(tester, ValueKey('reminder-${kind.name}-switch'));
      final enabled = switch (kind) {
        ReminderKind.upcoming || ReminderKind.late => true,
        _ => false,
      };
      expect(
        _switchOf(tester, 'reminder-${kind.name}-switch').value,
        enabled,
        reason: '${kind.name} ships ${enabled ? 'on' : 'off'}',
      );
      expect(_timeLabel(tester, kind), '09:00');
    }
  });

  testWidgets('toggling a type persists per profile and keeps other '
      'profiles untouched', (tester) async {
    final store = FakeSettingsStore();
    final alice = _profile('alice', 'Alice');
    final bea = _profile('bea', 'Bea');
    // Alice is the active profile (the screen's default selection).
    await store.set(SettingsKeys.lastActiveProfile, 'alice');
    final service = ReminderConfigService(store);
    await _pump(tester, [alice, bea], store);

    await _scrollTo(tester, const ValueKey('reminder-log-switch'));
    await tester.tap(find.byKey(const ValueKey('reminder-log-switch')));
    await tester.pumpAndSettle();

    final aliceConfig = await service.load('alice');
    expect(aliceConfig, isNotNull);
    expect(aliceConfig!.log.enabled, isTrue,
        reason: 'the toggle wrote through the service');

    // Back to the top, then switch to Bea: her config is still the
    // untouched default (nudge off) — the schedules are per profile.
    await _scrollToTop(tester);
    await tester.tap(find.byKey(const ValueKey('reminder-profile-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bea').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('reminder-log-switch'));
    expect(_switchOf(tester, 'reminder-log-switch').value, isFalse,
        reason: 'Bea never configured anything');
  });

  testWidgets('a stored config renders instead of the defaults', (tester)
      async {
    final store = FakeSettingsStore();
    final service = ReminderConfigService(store);
    await service.save(
      'alice',
      ReminderConfig.standard.copyWith(
        late: ReminderTypeConfig(enabled: false, timeOfDayMinutes: 9 * 60),
        log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 20 * 60 + 15),
      ),
    );
    await _pump(tester, [_profile('alice', 'Alice')], store);

    await _scrollTo(tester, const ValueKey('reminder-late-switch'));
    expect(_switchOf(tester, 'reminder-late-switch').value, isFalse);
    await _scrollTo(tester, const ValueKey('reminder-log-switch'));
    expect(_switchOf(tester, 'reminder-log-switch').value, isTrue);
    expect(find.text('20:15'), findsOneWidget);
  });

  testWidgets('quiet hours can be enabled and render their boundaries',
      (tester) async {
    final store = FakeSettingsStore();
    final service = ReminderConfigService(store);
    await _pump(tester, [_profile('alice', 'Alice')], store);

    await _scrollTo(tester, const ValueKey('reminder-quiet-switch'));
    await tester.tap(find.byKey(const ValueKey('reminder-quiet-switch')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reminder-quiet-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-quiet-end')), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);

    final stored = await service.load('alice');
    expect(stored!.quietHours, isNotNull);
    expect(stored.quietHours!.startMinutes, 22 * 60);
    expect(stored.quietHours!.endMinutes, 7 * 60);
  });

  testWidgets('an empty profile list shows the create-a-profile note',
      (tester) async {
    final store = FakeSettingsStore();
    await _pump(tester, [], store);

    expect(find.text('Create a profile to set up reminders.'), findsOneWidget);
  });

  testWidgets('the Time row opens the picker and stores the picked time',
      (tester) async {
    final store = FakeSettingsStore();
    final service = ReminderConfigService(store);
    await _pump(
      tester,
      [_profile('alice', 'Alice')],
      store,
      timePicker: (context, initialTime) async {
        expect(initialTime, const TimeOfDay(hour: 9, minute: 0),
            reason: 'the prompt starts at the currently configured time');
        return const TimeOfDay(hour: 8, minute: 15);
      },
    );

    await tester.tap(find.byKey(const ValueKey('reminder-time-upcoming')));
    await tester.pumpAndSettle();

    final stored = await service.load('alice');
    expect(stored!.upcoming.timeOfDayMinutes, 8 * 60 + 15);
    expect(find.text('08:15'), findsOneWidget);
  });

  testWidgets('a dismissed prompt changes nothing', (tester) async {
    final store = FakeSettingsStore();
    final service = ReminderConfigService(store);
    await _pump(
      tester,
      [_profile('alice', 'Alice')],
      store,
      timePicker: (context, initialTime) async => null,
    );

    await tester.tap(find.byKey(const ValueKey('reminder-time-upcoming')));
    await tester.pumpAndSettle();

    expect(await service.load('alice'), isNull,
        reason: 'nothing was saved');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reminder-time-upcoming')),
        matching: find.text('09:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('quiet-hours boundaries pick independently', (tester) async {
    final store = FakeSettingsStore();
    final service = ReminderConfigService(store);
    var picks = 0;
    await _pump(
      tester,
      [_profile('alice', 'Alice')],
      store,
      timePicker: (context, initialTime) async {
        picks++;
        return picks == 1
            ? const TimeOfDay(hour: 23, minute: 45)
            : const TimeOfDay(hour: 6, minute: 30);
      },
    );

    await _scrollTo(tester, const ValueKey('reminder-quiet-switch'));
    await tester.tap(find.byKey(const ValueKey('reminder-quiet-switch')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('reminder-quiet-start'));
    await tester.tap(find.byKey(const ValueKey('reminder-quiet-start')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const ValueKey('reminder-quiet-end'));
    await tester.tap(find.byKey(const ValueKey('reminder-quiet-end')));
    await tester.pumpAndSettle();
    expect(picks, 2, reason: 'both boundary prompts opened');

    final stored = await service.load('alice');
    expect(stored!.quietHours!.startMinutes, 23 * 60 + 45);
    expect(stored.quietHours!.endMinutes, 6 * 60 + 30);
    expect(find.text('23:45'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);
  });
}
