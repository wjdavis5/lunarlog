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

    // Issue #228 update (deliberate, not a weakened assertion): this guard
    // originally pinned BBT (and the rest of the fertility family) as out of
    // scope. #228 shipped those write types, so the previously-absent
    // BASAL_BODY_TEMPERATURE permission is now required, and the three
    // fertility/measurement WRITE permissions join the expected-present set.
    // Issue #992 adds READ_HEALTH_DATA_HISTORY (the full-history import);
    // issue #993 adds READ_HEALTH_DATA_IN_BACKGROUND for the periodic
    // background-import worker (HealthBackgroundImportWorker.kt), so it
    // joins the expected-present set too. Sexual-activity remains
    // deliberately absent (#210).
    test(
        'declares the menstruation baseline plus the #228 fertility/measurement '
        'WRITE permissions plus #992 history plus #993 background read -- '
        'not sexual-activity',
        () {
      for (final permission in [
        'android.permission.health.WRITE_MENSTRUATION',
        'android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING',
        // Issue #458: the read/import direction the owner's #781 decision
        // unblocked, matching HealthConnectAdapter.kt's readPermissions set
        // and the user-initiated paged read call site.
        'android.permission.health.READ_MENSTRUATION',
        'android.permission.health.READ_INTERMENSTRUAL_BLEEDING',
        // Issue #992: full-history import. Without this permission Health
        // Connect returns only the 30 days before the grant.
        'android.permission.health.READ_HEALTH_DATA_HISTORY',
        // Issue #993: background reads, served by the periodic
        // background-import worker -- the same import pass the Settings
        // tap runs, never a write and never new data types.
        'android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND',
        // Issue #228: write-only (no read-back in scope), matching
        // HealthConnectAdapter.kt's writePermissions set.
        'android.permission.health.WRITE_CERVICAL_MUCUS',
        'android.permission.health.WRITE_OVULATION_TEST',
        'android.permission.health.WRITE_BASAL_BODY_TEMPERATURE',
      ]) {
        expect(manifest, contains('android:name="$permission"'),
            reason: permission);
      }
      // Assert the *declaration* is absent, not the bare name: the manifest
      // comments name the deferred permissions on purpose, and only an
      // actual android:name declaration grants anything.
      for (final outOfScope in [
        'SEXUAL_ACTIVITY',
      ]) {
        expect(
          manifest,
          isNot(contains('android:name="android.permission.health.$outOfScope"')),
          reason: outOfScope,
        );
      }
    });

    test(
        'the #993 background-import worker exists and never touches health '
        'data itself (it wakes Dart; the guarded import stays in Dart)',
        () {
      final worker = readRepoFile(
          'android/app/src/main/kotlin/com/wjdavis5/lunarlog/'
          'HealthBackgroundImportWorker.kt');
      // The worker reaches Dart through the one shared channel's trigger
      // push, and reads only the binding mirror -- no Health Connect
      // client, no record read, no write call anywhere in the worker.
      // Issue #1211: the one permission gate the tick consults is asked
      // through HealthConnectAdapter's backgroundReadRefused helper, so
      // the worker still holds no Health Connect types and queries no
      // permission set of its own.
      expect(worker, contains('onBackgroundImportTriggered'));
      expect(worker, contains('HealthConnectAdapter.BOUND_PROFILE_KEY'));
      expect(worker, contains('backgroundReadRefused'));
      expect(worker, isNot(contains('HealthConnectClient')));
      expect(worker, isNot(contains('getGrantedPermissions')));
      expect(worker, isNot(contains('getChanges')));
      expect(worker, isNot(contains('readRecords')));
      expect(worker, isNot(contains('insert')));
      // The WorkManager dependency the schedule needs, pinned like the
      // connect-client above.
      expect(
        gradle,
        contains(RegExp(r'"androidx\.work:work-runtime-ktx:\d+\.\d+\.\d+"')),
      );
    });

    test(
        'the Kotlin adapter requests the read permissions a read call site '
        'now exists for (#458 reads, #992 full history) -- not just the '
        'write set #515 left in place', () {
      final adapter =
          readRepoFile('android/app/src/main/kotlin/com/wjdavis5/lunarlog/'
              'HealthConnectAdapter.kt');
      expect(adapter, contains('readPermissions = setOf('));
      expect(adapter, contains('getReadPermission('));
      expect(adapter, contains('PERMISSION_READ_HEALTH_DATA_HISTORY'));
      // The single authorization sheet carries write + read together.
      expect(adapter, contains('allPermissions'));
    });

    test(
        'the declared background-read permission is requested at runtime, '
        'gated on the feature check, and kept out of the granted-all '
        'status check (issue #1211: declared-in-manifest means '
        'requested-at-runtime)', () {
      final adapter =
          readRepoFile('android/app/src/main/kotlin/com/wjdavis5/lunarlog/'
              'HealthConnectAdapter.kt');
      // The #1211 bug shape, pinned in both directions: #993 declared
      // READ_HEALTH_DATA_IN_BACKGROUND in this manifest while the adapter's
      // comment still called it "deliberately absent" from the requested
      // set. Health Connect treats it as a runtime permission, so every
      // WorkManager-triggered background pass was refused despite the
      // declaration. Declaring without requesting is the gap; requesting
      // without declaring fails the grant outright; the two sides must
      // stay in lockstep.
      final declared = manifest.contains(
          'android:name='
          '"android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"');
      final requested = adapter.contains(
          'HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND');
      expect(requested, declared,
          reason: 'READ_HEALTH_DATA_IN_BACKGROUND must be declared in the '
              'manifest and requested by HealthConnectAdapter.kt together');
      if (declared) {
        // The request rides the feature check the background-read
        // documentation requires -- connect-client 1.1.0 has no
        // isFeatureAvailable, so the check is getFeatureStatus against
        // FEATURE_STATUS_AVAILABLE.
        expect(adapter, contains('FEATURE_READ_HEALTH_DATA_IN_BACKGROUND'));
        expect(adapter, contains('FEATURE_STATUS_AVAILABLE'));
        // ...and the permission stays OUT of what permissionStatus calls
        // "granted": foregroundStatusPermissions subtracts it from
        // allPermissions, so a user who declines background reads can
        // still import by tap (the worker skips its own pass instead --
        // pinned in the worker test below).
        expect(adapter, contains('foregroundStatusPermissions'));
        expect(adapter, contains('containsAll(foregroundStatusPermissions)'));
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
      // Issue #1101: the canonical policy is https://lunarlog.app/privacy,
      // the marketing site's build of PRIVACY.md -- the same URL the
      // in-app privacy dialog and the store listings cite.
      expect(activity, contains('https://lunarlog.app/privacy'));
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
