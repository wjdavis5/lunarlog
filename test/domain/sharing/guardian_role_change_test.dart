/// Unit tests for Issue #127's role-change gating helpers in
/// sharing_service.dart: [canUpdateGuardianRole], [allowedNewRoles], and
/// [roleChangeConsequence].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';

ProfileGuardian guardianRow(
  String userId,
  GuardianRole role, {
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p-1',
      userId: userId,
      role: role,
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('canUpdateGuardianRole', () {
    test('unknown caller role never qualifies', () {
      expect(
        canUpdateGuardianRole(
          callerRole: null,
          target: guardianRow('user-sue', GuardianRole.caregiver),
          currentUserId: 'user-mom',
          newRole: GuardianRole.viewer,
        ),
        isFalse,
      );
    });

    test('non-accepted target rows never qualify', () {
      for (final status in [GuardianStatus.pending, GuardianStatus.revoked]) {
        expect(
          canUpdateGuardianRole(
            callerRole: GuardianRole.primaryGuardian,
            target: guardianRow('user-sue', GuardianRole.caregiver,
                status: status),
            currentUserId: 'user-mom',
            newRole: GuardianRole.viewer,
          ),
          isFalse,
          reason: 'status $status must not offer a role control',
        );
      }
    });

    test('no caller may change their own role (AC4)', () {
      for (final caller in GuardianRole.values) {
        expect(
          canUpdateGuardianRole(
            callerRole: caller,
            target: guardianRow('user-mom', GuardianRole.caregiver),
            currentUserId: 'user-mom',
            newRole: GuardianRole.viewer,
          ),
          isFalse,
          reason: '$caller must not move their own row',
        );
      }
    });

    test('primary_guardian is never an assignable new role (AC5)', () {
      for (final caller in GuardianRole.values) {
        expect(
          canUpdateGuardianRole(
            callerRole: caller,
            target: guardianRow('user-sue', GuardianRole.caregiver),
            currentUserId: 'user-mom',
            newRole: GuardianRole.primaryGuardian,
          ),
          isFalse,
          reason: '$caller must never grant primary_guardian here',
        );
      }
    });

    test('re-applying the current role is not offered', () {
      for (final role in [
        GuardianRole.coParent,
        GuardianRole.caregiver,
        GuardianRole.viewer,
      ]) {
        expect(
          canUpdateGuardianRole(
            callerRole: GuardianRole.primaryGuardian,
            target: guardianRow('user-sue', role),
            currentUserId: 'user-mom',
            newRole: role,
          ),
          isFalse,
        );
      }
    });

    test('primary guardian may change anyone else to any assignable role',
        () {
      for (final target in [
        GuardianRole.primaryGuardian,
        GuardianRole.coParent,
        GuardianRole.caregiver,
        GuardianRole.viewer,
      ]) {
        for (final next in [
          GuardianRole.coParent,
          GuardianRole.caregiver,
          GuardianRole.viewer,
        ]) {
          if (next == target) continue;
          expect(
            canUpdateGuardianRole(
              callerRole: GuardianRole.primaryGuardian,
              target: guardianRow('user-sue', target),
              currentUserId: 'user-mom',
              newRole: next,
            ),
            isTrue,
            reason: 'primary may move $target -> $next',
          );
        }
      }
    });

    test('co-parent may move caregiver/viewer between each other (AC3)', () {
      expect(
        canUpdateGuardianRole(
          callerRole: GuardianRole.coParent,
          target: guardianRow('user-sue', GuardianRole.caregiver),
          currentUserId: 'user-dad',
          newRole: GuardianRole.viewer,
        ),
        isTrue,
      );
      expect(
        canUpdateGuardianRole(
          callerRole: GuardianRole.coParent,
          target: guardianRow('user-sue', GuardianRole.viewer),
          currentUserId: 'user-dad',
          newRole: GuardianRole.caregiver,
        ),
        isTrue,
      );
    });

    test('co-parent cannot touch primary/co-parent roles or mint a peer',
        () {
      // Cannot demote/promote the primary guardian or another co-parent.
      for (final target in [
        GuardianRole.primaryGuardian,
        GuardianRole.coParent,
      ]) {
        for (final next in [
          GuardianRole.coParent,
          GuardianRole.caregiver,
          GuardianRole.viewer,
        ]) {
          if (next == target) continue;
          expect(
            canUpdateGuardianRole(
              callerRole: GuardianRole.coParent,
              target: guardianRow('user-other', target),
              currentUserId: 'user-dad',
              newRole: next,
            ),
            isFalse,
            reason: 'co-parent must not move $target -> $next',
          );
        }
      }
      // Cannot promote a caregiver/viewer up to co-parent either.
      for (final target in [GuardianRole.caregiver, GuardianRole.viewer]) {
        expect(
          canUpdateGuardianRole(
            callerRole: GuardianRole.coParent,
            target: guardianRow('user-sue', target),
            currentUserId: 'user-dad',
            newRole: GuardianRole.coParent,
          ),
          isFalse,
        );
      }
    });

    test('caregiver and viewer callers may change nothing', () {
      for (final caller in [GuardianRole.caregiver, GuardianRole.viewer]) {
        for (final next in [
          GuardianRole.coParent,
          GuardianRole.caregiver,
          GuardianRole.viewer,
        ]) {
          expect(
            canUpdateGuardianRole(
              callerRole: caller,
              target: guardianRow('user-sue', GuardianRole.caregiver),
              currentUserId: 'user-x',
              newRole: next,
            ),
            isFalse,
            reason: '$caller must not move caregiver -> $next',
          );
        }
      }
    });
  });

  group('allowedNewRoles', () {
    test('primary sees every other assignable role in ladder order', () {
      expect(
        allowedNewRoles(
          callerRole: GuardianRole.primaryGuardian,
          target: guardianRow('user-sue', GuardianRole.viewer),
          currentUserId: 'user-mom',
        ),
        [GuardianRole.coParent, GuardianRole.caregiver],
      );
    });

    test('co-parent sees only the caregiver/viewer pair', () {
      expect(
        allowedNewRoles(
          callerRole: GuardianRole.coParent,
          target: guardianRow('user-sue', GuardianRole.caregiver),
          currentUserId: 'user-dad',
        ),
        [GuardianRole.viewer],
      );
    });

    test('empty when nothing is changeable (own row, viewer caller)', () {
      expect(
        allowedNewRoles(
          callerRole: GuardianRole.primaryGuardian,
          target: guardianRow('user-mom', GuardianRole.primaryGuardian),
          currentUserId: 'user-mom',
        ),
        isEmpty,
      );
      expect(
        allowedNewRoles(
          callerRole: GuardianRole.viewer,
          target: guardianRow('user-sue', GuardianRole.caregiver),
          currentUserId: 'user-doc',
        ),
        isEmpty,
      );
    });
  });

  group('roleChangeConsequence', () {
    test('viewer -> caregiver names the gained logging access', () {
      final copy = roleChangeConsequence(
        GuardianRole.viewer,
        GuardianRole.caregiver,
      );
      expect(copy, contains('gain'));
      expect(copy, contains('log entries'));
      expect(copy, isNot(contains('read-only')));
    });

    test('co_parent -> viewer names every loss plus the read-only outcome',
        () {
      final copy = roleChangeConsequence(
        GuardianRole.coParent,
        GuardianRole.viewer,
      );
      expect(copy, contains('lose'));
      expect(copy, contains('log entries'));
      expect(copy, contains('read-only'));
    });

    test('co_parent -> caregiver names management losses but stays writable',
        () {
      final copy = roleChangeConsequence(
        GuardianRole.coParent,
        GuardianRole.caregiver,
      );
      expect(copy, contains('lose'));
      expect(copy, contains('manage caregivers'));
      expect(copy, isNot(contains('read-only')));
    });

    test('caregiver -> co_parent names the gained management access', () {
      final copy = roleChangeConsequence(
        GuardianRole.caregiver,
        GuardianRole.coParent,
      );
      expect(copy, contains('gain'));
      expect(copy, contains('manage caregivers'));
    });
  });
}
