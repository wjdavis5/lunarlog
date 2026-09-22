/// Unit tests for the Issue #957 [minimumAgeAcknowledgementCopy] branch: a
/// cold arrival keeps the 13-or-older statement and a parent-invitation
/// arrival gets the parent-invite wording, both backed by `app_en.arb`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/minimum_age_acknowledgement_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  group('minimumAgeAcknowledgementCopy', () {
    test('self_13_plus keeps the 13-or-older statement', () {
      final copy = minimumAgeAcknowledgementCopy(
        _l10n,
        MinimumAgeAcknowledgementContext.self13Plus,
      );
      expect(copy.label, 'I am 13 or older, or a guardian managing a family '
          'profile');
      expect(copy.hint,
          'lunarlog requires users to be at least 13 years old, or managed '
          'by a parent or legal guardian.');
    });

    test('parent_invite is the parent-invitation wording, never the flat 13+ '
        'affirmation', () {
      final copy = minimumAgeAcknowledgementCopy(
        _l10n,
        MinimumAgeAcknowledgementContext.parentInvite,
      );
      expect(
        copy.label,
        'My parent or guardian created this profile and invited me to use it',
      );
      expect(
        copy.hint,
        'Your parent or guardian set up this profile and sent you this '
        'invitation. That invitation is their permission for you to use '
        'lunarlog and log here yourself.',
      );
      expect(copy.label, isNot(contains('13 or older')));
    });
  });
}
