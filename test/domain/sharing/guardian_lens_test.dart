/// Unit tests for the per-viewer guardian lens resolver (Issue #850, D-1):
/// membership identity (`isSubject`) decides the lens, never
/// `ProfileRelationship` or the role ladder, and an unknown viewer fails
/// open to the subject lens.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';

ProfileGuardian _guardian(
  String userId,
  GuardianRole role, {
  GuardianStatus status = GuardianStatus.accepted,
  bool isSubject = false,
}) =>
    ProfileGuardian(
      id: 'g-$userId-${role.name}',
      profileId: 'p-1',
      userId: userId,
      role: role,
      status: status,
      isSubject: isSubject,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('guardianLensFor (Issue #850, D-1)', () {
    test('the subject\'s own accepted membership reads as the subject lens',
        () {
      final rows = [
        _guardian('u-mom', GuardianRole.primaryGuardian),
        _guardian('u-teen', GuardianRole.caregiver, isSubject: true),
      ];
      expect(guardianLensFor(rows, 'u-teen'), GuardianLens.subject);
    });

    test('any other accepted membership reads as the guardian lens, whatever '
        'its role', () {
      for (final role in GuardianRole.values) {
        final rows = [
          _guardian('u-teen', GuardianRole.caregiver, isSubject: true),
          _guardian('u-viewer', role),
        ];
        expect(
          guardianLensFor(rows, 'u-viewer'),
          GuardianLens.guardian,
          reason: 'role ${role.name} is a guardian lens',
        );
      }
    });

    test('a primary guardian who created the profile is not the subject '
        '(isSubject=false) and gets the guardian lens', () {
      final rows = [_guardian('u-mom', GuardianRole.primaryGuardian)];
      expect(guardianLensFor(rows, 'u-mom'), GuardianLens.guardian);
    });

    test('a null viewer id reads as the subject lens (fail open)', () {
      final rows = [_guardian('u-mom', GuardianRole.primaryGuardian)];
      expect(guardianLensFor(rows, null), GuardianLens.subject);
    });

    test('no synced rows reads as the subject lens (fail open)', () {
      expect(guardianLensFor(const [], 'u-mom'), GuardianLens.subject);
    });

    test('a stranger with no matching row reads as the subject lens '
        '(fail open)', () {
      final rows = [_guardian('u-mom', GuardianRole.primaryGuardian)];
      expect(guardianLensFor(rows, 'u-stranger'), GuardianLens.subject);
    });

    test('revoked rows are ignored — a revoked member reads as the subject '
        'lens, not a guardian', () {
      final rows = [
        _guardian('u-mom', GuardianRole.primaryGuardian),
        _guardian('u-sitter', GuardianRole.caregiver,
            status: GuardianStatus.revoked),
      ];
      expect(guardianLensFor(rows, 'u-sitter'), GuardianLens.subject);
    });

    test('pending rows are ignored too — only accepted membership counts',
        () {
      final rows = [
        _guardian('u-sitter', GuardianRole.caregiver,
            status: GuardianStatus.pending),
      ];
      expect(guardianLensFor(rows, 'u-sitter'), GuardianLens.subject);
    });

    test('a revoked subject row falls back to the subject lens (fail open)',
        () {
      final rows = [
        _guardian('u-teen', GuardianRole.caregiver,
            status: GuardianStatus.revoked, isSubject: true),
      ];
      expect(guardianLensFor(rows, 'u-teen'), GuardianLens.subject);
    });
  });

  group('guardianRoleFor delegates to acceptedGuardianFor', () {
    test('carries the accepted membership role through', () {
      final rows = [
        _guardian('u-mom', GuardianRole.primaryGuardian),
        _guardian('u-dad', GuardianRole.coParent),
      ];
      expect(guardianRoleFor(rows, 'u-dad'), GuardianRole.coParent);
    });

    test('a subject membership still reports its role', () {
      final rows = [
        _guardian('u-teen', GuardianRole.caregiver, isSubject: true),
      ];
      expect(guardianRoleFor(rows, 'u-teen'), GuardianRole.caregiver);
      expect(guardianLensFor(rows, 'u-teen'), GuardianLens.subject);
    });

    test('null for a null viewer id, no rows, or a non-accepted row', () {
      final rows = [
        _guardian('u-sitter', GuardianRole.caregiver,
            status: GuardianStatus.revoked),
      ];
      expect(guardianRoleFor(rows, null), isNull);
      expect(guardianRoleFor(const [], 'u-sitter'), isNull);
      expect(guardianRoleFor(rows, 'u-sitter'), isNull);
    });
  });
}
