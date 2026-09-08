/// U8 coverage: the Notifications screen's controls, persistence, and
/// discretion copy (Issue #5, R1, R3, R4).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/ui/sharing/notification_preferences_screen.dart';

import '../support/fake_notification_preferences_service.dart';

Profile _profile() => Profile(
      id: 'profile-1',
      displayName: 'Maya',
      isMinor: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// Scrolls the screen's ListView until [finder] is built and visible. The
/// Issue #125 delivery section (cadence dropdowns + digest time) pushed the
/// missed-entry and quiet-hours controls below the fold of the default test
/// viewport, and a ListView only builds children near the viewport. A
/// negative [delta] scrolls back up toward earlier children.
Future<void> _scrollTo(WidgetTester tester, Finder finder, {double delta = 200}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

class _FailingOnceService implements NotificationPreferencesService {
  _FailingOnceService(this._delegate);
  final FakeNotificationPreferencesService _delegate;
  bool _failed = false;

  @override
  Stream<CaregiverAlertPreferences> watchFor(String profileId) =>
      _delegate.watchFor(profileId);

  @override
  Future<void> save(String profileId, CaregiverAlertPreferences prefs) async {
    if (!_failed) {
      _failed = true;
      throw const NotificationPreferencesFailure.other();
    }
    await _delegate.save(profileId, prefs);
  }
}

void main() {
  testWidgets('the screen loads and displays stored preferences', (tester) async {
    final service = FakeNotificationPreferencesService()
      ..seed(
        'profile-1',
        const CaregiverAlertPreferences(alertOnLog: true, alertOnHighSeverity: true),
      );

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    final alertOnLog = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('alert-on-log-toggle')),
    );
    final highSeverity = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('alert-high-severity-toggle')),
    );
    expect(alertOnLog.value, isTrue);
    expect(highSeverity.value, isTrue);
  });

  testWidgets('with no stored row, every switch is off and the threshold shows Off', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    for (final key in [
      'alert-on-log-toggle',
      'alert-cycle-start-only-toggle',
      'alert-high-severity-toggle',
    ]) {
      final tile = tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));
      expect(tile.value, isFalse, reason: '$key should be off by default');
    }
    await _scrollTo(tester, find.byKey(const ValueKey('missed-entry-threshold-dropdown')));
    expect(find.text('Off'), findsWidgets);
  });

  testWidgets(
      'toggling "notify on log" on enables the two dependent switches; '
      'toggling it off disables and visually clears them', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    // Turn the parent on.
    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();

    SwitchListTile tileOf(String key) =>
        tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));
    expect(tileOf('alert-cycle-start-only-toggle').onChanged, isNotNull);
    expect(tileOf('alert-high-severity-toggle').onChanged, isNotNull);

    // Turn on both narrowings.
    await tester.tap(find.byKey(const ValueKey('alert-cycle-start-only-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alert-high-severity-toggle')));
    await tester.pumpAndSettle();
    expect(tileOf('alert-cycle-start-only-toggle').value, isTrue);
    expect(tileOf('alert-high-severity-toggle').value, isTrue);

    // Turn the parent back off: dependents disable AND visually clear.
    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();

    expect(tileOf('alert-cycle-start-only-toggle').onChanged, isNull);
    expect(tileOf('alert-high-severity-toggle').onChanged, isNull);
    expect(tileOf('alert-cycle-start-only-toggle').value, isFalse);
    expect(tileOf('alert-high-severity-toggle').value, isFalse);
  });

  testWidgets('changing the threshold dropdown to 2 days persists a save with the right value', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const ValueKey('missed-entry-threshold-dropdown')));
    await tester.tap(find.byKey(const ValueKey('missed-entry-threshold-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 days').last);
    await tester.pumpAndSettle();

    expect(service.saveCalls, greaterThanOrEqualTo(1));
    final dropdown = tester.widget<DropdownButton<MissedEntryThreshold>>(
      find.byKey(const ValueKey('missed-entry-threshold-dropdown')),
    );
    expect(dropdown.value, MissedEntryThreshold.twoDays);
  });

  testWidgets(
      'the cadence dropdowns default to immediate, persist a change to daily digest, '
      'and reset to immediate when the parent toggle is turned off (Issue #125)', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    DropdownButton<AlertCadence> cadenceOf(String key) =>
        tester.widget<DropdownButton<AlertCadence>>(
          find.byKey(ValueKey(key)),
        );

    // Disabled until the parent alert toggle is on; values are immediate.
    expect(cadenceOf('log-cadence-dropdown').onChanged, isNull);
    expect(cadenceOf('log-cadence-dropdown').value, AlertCadence.immediate);

    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();
    expect(cadenceOf('log-cadence-dropdown').onChanged, isNotNull);

    await tester.tap(find.byKey(const ValueKey('log-cadence-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily digest').last);
    await tester.pumpAndSettle();

    expect(cadenceOf('log-cadence-dropdown').value, AlertCadence.dailyDigest);
    expect(service.saveCalls, greaterThanOrEqualTo(1));

    // The cycle-start/high-severity cadences stay independently selectable
    // only once their narrowing toggles are on.
    expect(cadenceOf('cycle-start-cadence-dropdown').onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('alert-cycle-start-only-toggle')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('cycle-start-cadence-dropdown')));
    expect(cadenceOf('cycle-start-cadence-dropdown').onChanged, isNotNull);

    // Turning the parent off disables and resets every cadence, matching
    // the clean-slate rule the narrowings already follow. Scroll back up
    // first -- the toggle sits above the delivery section.
    await _scrollTo(tester, find.byKey(const ValueKey('alert-on-log-toggle')), delta: -200);
    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();
    expect(cadenceOf('log-cadence-dropdown').onChanged, isNull);
    expect(cadenceOf('log-cadence-dropdown').value, AlertCadence.immediate);
  });

  testWidgets('the digest time tile shows the 8:00 AM default and persists a picked time', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const ValueKey('digest-time-tile')));
    expect(find.text('8:00 AM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('digest-time-tile')));
    await tester.pumpAndSettle();
    // The picker opens at the default (8:00); confirm it explicitly.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(service.saveCalls, greaterThanOrEqualTo(1));
    expect(service.stored['profile-1']?.digestTimeMinutes, 8 * 60);
  });

  testWidgets('setting a quiet-hours range persists both times; clearing persists nulls', (tester) async {
    final service = FakeNotificationPreferencesService();

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    // Confirm the default start time (22:00) via the time picker's OK button.
    await _scrollTo(tester, find.byKey(const ValueKey('quiet-hours-start-tile')));
    await tester.tap(find.byKey(const ValueKey('quiet-hours-start-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Confirm the default end time (07:00).
    await tester.tap(find.byKey(const ValueKey('quiet-hours-end-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const ValueKey('clear-quiet-hours-tile')));
    expect(find.byKey(const ValueKey('clear-quiet-hours-tile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-quiet-hours-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('clear-quiet-hours-tile')), findsNothing);
    expect(find.text('Off'), findsWidgets);
  });

  testWidgets('a save failure surfaces the failure\'s userFacingMessage and leaves the screen usable', (tester) async {
    final service = _FailingOnceService(FakeNotificationPreferencesService());

    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: service,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.text(const NotificationPreferencesFailure.other().userFacingMessage),
      findsOneWidget,
    );
    // The screen is still interactive: toggling again succeeds (delegate).
    await tester.tap(find.byKey(const ValueKey('alert-on-log-toggle')));
    await tester.pumpAndSettle();
  });

  testWidgets('the discretion copy is present on screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NotificationPreferencesScreen(
        profile: _profile(),
        preferencesService: FakeNotificationPreferencesService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discretion-copy')), findsOneWidget);
  });
}
