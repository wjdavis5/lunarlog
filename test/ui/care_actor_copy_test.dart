/// Unit tests for the Issue #128 care-screen naming helpers:
/// [careActorCopy] (every branch: self, named guardian, nameless guardian,
/// stranger, null) and [careAttributionDate] (bare civil-date rendering).
/// Widget-level attribution is proven in `care_notes_screen_test.dart`;
/// this file pins the pure functions directly for the CRAP gate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/care/care_notes_screen.dart';

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
      expect(careActorCopy('user-mom', guardians, 'user-mom'), 'you');
    });

    test('a named guardian resolves to the display name', () {
      expect(
          careActorCopy('user-mom', guardians, 'user-dad'), 'Mom');
    });

    test('a nameless guardian resolves to the role label', () {
      expect(careActorCopy('user-nanny', guardians, 'user-dad'),
          'Caregiver');
    });

    test('a stranger resolves to the "Caregiver" fallback', () {
      expect(careActorCopy('user-stranger', guardians, 'user-dad'),
          'Caregiver');
      expect(careActorCopy('user-stranger', const [], 'user-dad'),
          'Caregiver');
    });

    test('a null user id resolves to the "Caregiver" fallback, never "you"',
        () {
      expect(careActorCopy(null, guardians, 'user-dad'), 'Caregiver');
      expect(careActorCopy(null, guardians, null), 'Caregiver');
    });
  });

  group('careAttributionDate', () {
    test('renders a bare civil date without the time of day', () {
      expect(careAttributionDate(DateTime.utc(2026, 9, 2, 10, 30)),
          '2026-09-02');
      expect(careAttributionDate(DateTime.utc(2026, 1, 5, 23, 59)),
          '2026-01-05');
    });
  });
}
