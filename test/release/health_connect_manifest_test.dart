/// Health Connect Android plumbing guard (issue #166). Mirrors
/// `export_compliance_test.dart`/`sentry_symbols_test.dart`'s shape: read the
/// Android manifest and Gradle file as text and assert the invariants the
/// permission/rationale plumbing depends on, since none of this compiles or
/// runs under `flutter test`. Issue #173 replaced the original "no client
/// dependency yet" assertion with its inverse: the first-party
/// `lunarlog/health` channel's Kotlin half (HealthConnectAdapter.kt) is a
/// real compile-time consumer of `connect-client`, so the dependency must
/// now exist, pinned, rather than be absent.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _gradlePath = 'android/app/build.gradle.kts';
const _rationaleActivityPath =
    'android/app/src/main/kotlin/com/wjdavis5/lunarlog/PermissionsRationaleActivity.kt';

void main() {
  group('Health Connect Android plumbing guard (issue #166)', () {
    late String manifest;
    late String gradle;

    setUpAll(() {
      manifest = readRepoFile(_manifestPath);
      gradle = readRepoFile(_gradlePath);
    });

    test('minSdk is pinned to 26, not left as flutter.minSdkVersion', () {
      expect(gradle, contains('minSdk = 26'));
      expect(gradle, isNot(contains('minSdk = flutter.minSdkVersion')));
    });

    test(
        'declares exactly the v1 menstruation-baseline health permissions -- '
        'not history/background/sexual-activity/BBT (those are '
        '#186/#210/#228)', () {
      for (final permission in [
        'android.permission.health.READ_MENSTRUATION',
        'android.permission.health.WRITE_MENSTRUATION',
        'android.permission.health.READ_INTERMENSTRUAL_BLEEDING',
        'android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING',
      ]) {
        expect(manifest, contains('android:name="$permission"'),
            reason: permission);
      }
      for (final outOfScope in [
        'READ_HEALTH_DATA_HISTORY',
        'READ_HEALTH_DATA_IN_BACKGROUND',
        'SEXUAL_ACTIVITY',
        'BASAL_BODY_TEMPERATURE',
      ]) {
        expect(manifest, isNot(contains(outOfScope)), reason: outOfScope);
      }
    });

    test('declares the Health Connect package-visibility query', () {
      expect(
        manifest,
        contains(
          '<package android:name="com.google.android.apps.healthdata"/>',
        ),
      );
    });

    test(
        'PermissionsRationaleActivity carries the '
        'SHOW_PERMISSIONS_RATIONALE intent filter', () {
      expect(manifest, contains('.PermissionsRationaleActivity'));
      expect(
        manifest,
        contains('androidx.health.connect.action.SHOW_PERMISSIONS_RATIONALE'),
      );
    });

    test(
        'an activity-alias carries the VIEW_PERMISSION_USAGE + '
        'HEALTH_PERMISSIONS filter required at targetSdk 34+, restricted to '
        'the platform caller', () {
      expect(manifest, contains('<activity-alias'));
      expect(
        manifest,
        contains('android.intent.action.VIEW_PERMISSION_USAGE'),
      );
      expect(
        manifest,
        contains('android.intent.category.HEALTH_PERMISSIONS'),
      );
      expect(
        manifest,
        contains('android.permission.START_VIEW_PERMISSION_USAGE'),
      );
    });

    test(
        'the rationale activity file exists and deep-links to the hosted '
        'privacy policy, naming the one-profile-at-a-time statement', () {
      final activity = readRepoFile(_rationaleActivityPath);
      expect(activity, contains('PRIVACY.md'));
      expect(activity, contains('one profile'));
    });

    test(
        'the Health Connect client dependency exists, pinned to a stable '
        'version (issue #173: HealthConnectAdapter.kt is a real consumer)',
        () {
      // Pinned to a concrete stable version -- never floating and never a
      // pre-release (-alpha/-beta/-rc), which would track API churn.
      expect(
        gradle,
        contains(RegExp(
            r'"androidx\.health\.connect:connect-client:\d+\.\d+\.\d+"')),
      );
      expect(
        gradle,
        isNot(contains(RegExp(
            r'"androidx\.health\.connect:connect-client:[^"]*-(alpha|beta|rc)'))),
      );
    });
  });
}
