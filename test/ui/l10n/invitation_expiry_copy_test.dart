import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/invitation_expiry_copy.dart';

void main() {
  final l10n = AppLocalizationsEn();
  String label(Duration remaining) => invitationExpiryLabel(l10n, remaining);

  group('invitationExpiryLabel', () {
    test('an invitation that lasts days is told in days (issue #1465)', () {
      // The case from the issue: six days used to read "expires in 144h".
      expect(label(const Duration(days: 6)), 'expires in 6 days');
      expect(label(const Duration(days: 7)), 'expires in 7 days');
      expect(label(const Duration(days: 30)), 'expires in 30 days');
    });

    test('days start at two full days, and hours run up to there', () {
      expect(
        label(const Duration(hours: 47, minutes: 59, seconds: 59)),
        'expires in 47h',
      );
      expect(label(const Duration(hours: 48)), 'expires in 2 days');
    });

    test('a day count rounds down, never up', () {
      expect(
        label(const Duration(days: 2, hours: 23, minutes: 59)),
        'expires in 2 days',
      );
      expect(label(const Duration(days: 3)), 'expires in 3 days');
    });

    test('hours start at one full hour, and minutes run up to there', () {
      expect(label(const Duration(minutes: 59, seconds: 59)), 'expires in 59m');
      expect(label(const Duration(hours: 1)), 'expires in 1h');
      expect(label(const Duration(hours: 6, minutes: 30)), 'expires in 6h');
    });

    test('the last minute still reads as one minute, not zero', () {
      expect(label(const Duration(seconds: 20)), 'expires in 1m');
      expect(label(Duration.zero), 'expires in 1m');
    });

    test('a lapsed invitation reads "expired", not a negative duration', () {
      expect(label(const Duration(seconds: -1)), 'expired');
      expect(label(const Duration(days: -3)), 'expired');
    });

    test('the catalogue has a singular for one day', () {
      // Not reachable through invitationExpiryLabel while days start at two,
      // but the plural must not read "1 days" if that threshold ever moves.
      expect(l10n.sharingManageGuardiansExpiryDays(1), 'expires in 1 day');
    });
  });
}
