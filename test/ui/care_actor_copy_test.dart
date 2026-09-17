/// Unit tests for the Issue #128 care-screen naming helpers:
/// [careActorCopy] (every branch: self, named guardian, nameless guardian,
/// stranger, null) and [careAttributionDate] (bare, locale-aware civil-date
/// rendering, issue #554). Widget-level attribution is proven in
/// `care_notes_screen_test.dart`; this file pins the pure/near-pure
/// functions directly for the CRAP gate -- `careAttributionDate` needs a
/// `BuildContext` (for locale) since #554, so its own group runs as a
/// `testWidgets` with a bare `Builder` rather than a plain `test`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;

final _l10n = AppLocalizationsEn();

ProfileGuardian _guardian(
  String userId, {
  String? displayName,
  GuardianRole role = GuardianRole.coParent,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: role,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('careActorCopy', () {
    final guardians = [
      _guardian('user-mom',
          displayName: 'Mom', role: GuardianRole.primaryGuardian),
      _guardian('user-nanny', role: GuardianRole.caregiver),
    ];

    test('the current operator reads as "you"', () {
      expect(careActorCopy(_l10n, 'user-mom', guardians, 'user-mom'), 'you');
    });

    test('a named guardian resolves to the display name', () {
      expect(
          careActorCopy(_l10n, 'user-mom', guardians, 'user-dad'), 'Mom');
    });

    test('a nameless guardian resolves to the role label', () {
      expect(careActorCopy(_l10n, 'user-nanny', guardians, 'user-dad'),
          'Caregiver');
    });

    test('a stranger resolves to the "Caregiver" fallback', () {
      expect(careActorCopy(_l10n, 'user-stranger', guardians, 'user-dad'),
          'Caregiver');
      expect(careActorCopy(_l10n, 'user-stranger', const [], 'user-dad'),
          'Caregiver');
    });

    test('a null user id resolves to the "Caregiver" fallback, never "you"',
        () {
      expect(careActorCopy(_l10n, null, guardians, 'user-dad'), 'Caregiver');
      expect(careActorCopy(_l10n, null, guardians, null), 'Caregiver');
    });
  });

  group('careAttributionDate', () {
    testWidgets(
        'renders a bare, locale-aware civil date without the time of day '
        '-- delegating to dates.formatShortDate(instant.toLocal(), locale) '
        'rather than a hand-rolled always-YYYY-MM-DD string (issue #554)',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ));

      for (final instant in [
        DateTime.utc(2026, 9, 2, 10, 30),
        DateTime.utc(2026, 1, 5, 23, 59),
      ]) {
        expect(
          careAttributionDate(capturedContext, instant),
          dates.formatShortDate(instant.toLocal(), locale: 'en'),
        );
      }
    });
  });
}
