/// LLA-027 (issue #607) guard: on API 26/27 the fingerprint/device-credential
/// prompt local_auth shows (`lib/startup/gate/local_auth_gate.dart`) inherits
/// whatever theme is active on `MainActivity` at the time -- `NormalTheme`
/// once the splash frame has been drawn, not just `LaunchTheme`. The pinned
/// `local_auth` plugin's own README ("Android theme" section) says the
/// `LaunchTheme` parent "must be a valid Theme.AppCompat theme to prevent
/// crashes on Android 8 and below"; this app additionally fixes
/// `NormalTheme` for the same reason, since that is the theme actually in
/// effect when the gate calls `authenticate()` post-launch. Read as text
/// (mirrors `health_connect_manifest_test.dart`'s shape) since none of this
/// compiles or runs under `flutter test`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _lightStylesPath = 'android/app/src/main/res/values/styles.xml';
const _nightStylesPath = 'android/app/src/main/res/values-night/styles.xml';
const _gradlePath = 'android/app/build.gradle.kts';
const _mainActivityPath =
    'android/app/src/main/kotlin/com/wjdavis5/lunarlog/MainActivity.kt';

/// Matches `<style name="$name" parent="...">` and captures the parent
/// value, tolerant of the `@android:style/` framework-theme form the
/// pre-fix files used as well as the bare `Theme.AppCompat...` form.
RegExp _parentOf(String styleName) =>
    RegExp('<style name="$styleName" parent="([^"]+)">');

void main() {
  group('Android biometric-compatible theme guard (issue #607, LLA-027)', () {
    late String light;
    late String night;
    late String gradle;
    late String mainActivity;

    setUpAll(() {
      light = readRepoFile(_lightStylesPath);
      night = readRepoFile(_nightStylesPath);
      gradle = readRepoFile(_gradlePath);
      mainActivity = readRepoFile(_mainActivityPath);
    });

    test(
        'LaunchTheme and NormalTheme both inherit an AppCompat parent in the '
        'day (values/) styles, not a bare framework Theme.* -- a non-'
        'AppCompat parent is exactly what crashes local_auth\'s prompt on '
        'API 26/27', () {
      for (final name in ['LaunchTheme', 'NormalTheme']) {
        final match = _parentOf(name).firstMatch(light);
        expect(match, isNotNull, reason: '$name not found in $_lightStylesPath');
        final parent = match!.group(1)!;
        expect(parent, startsWith('Theme.AppCompat'),
            reason: '$name parent was "$parent"');
        expect(parent, isNot(startsWith('@android:style/')),
            reason: '$name parent was "$parent"');
      }
    });

    test(
        'LaunchTheme and NormalTheme both inherit an AppCompat parent in the '
        'night (values-night/) styles too', () {
      for (final name in ['LaunchTheme', 'NormalTheme']) {
        final match = _parentOf(name).firstMatch(night);
        expect(match, isNotNull, reason: '$name not found in $_nightStylesPath');
        final parent = match!.group(1)!;
        expect(parent, startsWith('Theme.AppCompat'),
            reason: '$name parent was "$parent"');
        expect(parent, isNot(startsWith('@android:style/')),
            reason: '$name parent was "$parent"');
      }
    });

    test(
        'the day styles pick a Light AppCompat variant and the night styles '
        'pick the dark (non-.Light) variant, preserving the pre-fix '
        'Theme.Light.NoTitleBar / Theme.Black.NoTitleBar split rather than '
        'collapsing both to one appearance', () {
      final lightParent = _parentOf('NormalTheme').firstMatch(light)!.group(1)!;
      final nightParent = _parentOf('NormalTheme').firstMatch(night)!.group(1)!;
      expect(lightParent, contains('.Light'), reason: lightParent);
      expect(nightParent, isNot(contains('.Light')), reason: nightParent);
    });

    test(
        'both themes still set android:windowBackground, so the splash/'
        'window-background behavior the pre-fix themes provided is not '
        'dropped by the parent change', () {
      for (final content in [light, night]) {
        expect(content, contains('android:windowBackground'));
      }
    });

    test(
        'build.gradle.kts declares androidx.appcompat, pinned to a concrete '
        'stable version -- the AppCompat theme parents above resolve to '
        'nothing at build time without this on the classpath, and pinned '
        'so it can\'t silently drift onto a pre-release', () {
      expect(
        gradle,
        contains(RegExp(r'"androidx\.appcompat:appcompat:\d+\.\d+\.\d+"')),
      );
      expect(
        gradle,
        isNot(contains(
            RegExp(r'"androidx\.appcompat:appcompat:[^"]*-(alpha|beta|rc)'))),
      );
    });

    test(
        'MainActivity still extends FlutterFragmentActivity, which '
        'local_auth\'s BiometricPrompt requires regardless of theme', () {
      expect(mainActivity, contains('FlutterFragmentActivity'));
      expect(mainActivity, contains('class MainActivity : FlutterFragmentActivity()'));
    });
  });
}
