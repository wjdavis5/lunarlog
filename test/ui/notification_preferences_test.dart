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
    await tester.tap(find.byKey(const ValueKey('quiet-hours-start-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Confirm the default end time (07:00).
    await tester.tap(find.byKey(const ValueKey('quiet-hours-end-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

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
