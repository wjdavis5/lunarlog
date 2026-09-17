/// Unit tests for [notificationPreferencesFailureCopy] (Issue #545, moved
/// out of `lib/domain/notifications/notification_preferences_service.dart`'s
/// `userFacingMessage` getters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/notification_preferences_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  const failures = <NotificationPreferencesFailure>[
    NotificationPreferencesFailure.unauthorized(),
    NotificationPreferencesFailure.network(),
    NotificationPreferencesFailure.invalidTimeZone(),
    NotificationPreferencesFailure.other(),
  ];

  test('every case has non-empty, distinct copy', () {
    final messages = failures
        .map((f) => notificationPreferencesFailureCopy(_l10n, f))
        .toList();
    for (final message in messages) {
      expect(message, isNotEmpty);
    }
    expect(messages.toSet().length, messages.length);
  });

  test('no case echoes a raw provider message', () {
    expect(
        notificationPreferencesFailureCopy(
            _l10n, const NotificationPreferencesFailure.other()),
        'Failed to save notification preferences. Please try again.');
  });
}
