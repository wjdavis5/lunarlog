import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/gate/device_settings_launcher.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// Records every launch and optionally throws for a chosen URI, so the
/// Android fallback path can be driven without a platform channel.
class _FakeLauncher {
  _FakeLauncher({this.throwFor = const {}});

  final Set<String> throwFor;
  final List<(Uri, LaunchMode)> calls = [];

  Future<bool> call(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) {
    calls.add((url, mode));
    if (throwFor.contains(url.toString())) {
      throw StateError('no activity for ${url.toString()}');
    }
    return Future.value(true);
  }
}

Future<void> _run({
  required TargetPlatform platform,
  required _FakeLauncher launcher,
  BreadcrumbLog? log,
  bool isWeb = false,
  Future<String> Function()? packageName,
}) => openDeviceSettingsWith(
  breadcrumbLog: log ?? BreadcrumbLog(),
  launch: launcher.call,
  packageName: packageName ?? () async => 'io.wjd.lunarlog',
  platform: platform,
  isWeb: isWeb,
);

void main() {
  group('openDeviceSettingsWith (#534)', () {
    test('web is a no-op regardless of platform', () async {
      final launcher = _FakeLauncher();
      await _run(
        platform: TargetPlatform.android,
        launcher: launcher,
        isWeb: true,
      );
      expect(launcher.calls, isEmpty);
    });

    test('iOS launches the app-settings: system scheme', () async {
      final launcher = _FakeLauncher();
      await _run(platform: TargetPlatform.iOS, launcher: launcher);
      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.$1.toString(), kIosAppSettingsUrl);
    });

    test('Android launches the Security settings intent externally', () async {
      final launcher = _FakeLauncher();
      await _run(platform: TargetPlatform.android, launcher: launcher);
      expect(launcher.calls, hasLength(1));
      expect(
        launcher.calls.single.$1.toString(),
        kAndroidSecuritySettingsIntent,
      );
      expect(launcher.calls.single.$2, LaunchMode.externalApplication);
    });

    test('Android falls back to this app\'s App-info page when the Security '
        'intent has no handler, and records a breadcrumb', () async {
      final launcher = _FakeLauncher(
        throwFor: {kAndroidSecuritySettingsIntent},
      );
      final log = BreadcrumbLog();
      await _run(
        platform: TargetPlatform.android,
        launcher: launcher,
        log: log,
        packageName: () async => 'io.example.app',
      );
      expect(launcher.calls, hasLength(2));
      expect(
        launcher.calls.last.$1.toString(),
        androidAppDetailsIntent('io.example.app'),
      );
      expect(launcher.calls.last.$2, LaunchMode.externalApplication);
      expect(
        log.snapshot(),
        contains('gate: AndroidSecuritySettingsUnavailable'),
      );
    });

    test('other platforms are a no-op', () async {
      final launcher = _FakeLauncher();
      await _run(platform: TargetPlatform.macOS, launcher: launcher);
      expect(launcher.calls, isEmpty);
    });

    test('a launch failure never throws; the error type is recorded', () async {
      // Both the primary and the fallback intent fail: the outer handler
      // must swallow it and leave only a breadcrumb behind.
      final launcher = _FakeLauncher(
        throwFor: {
          kAndroidSecuritySettingsIntent,
          androidAppDetailsIntent('io.wjd.lunarlog'),
        },
      );
      final log = BreadcrumbLog();
      await expectLater(
        _run(platform: TargetPlatform.android, launcher: launcher, log: log),
        completes,
      );
      expect(log.snapshot(), contains('gate: StateError'));
    });

    test('the iOS path also swallows a launch failure', () async {
      final launcher = _FakeLauncher(throwFor: {kIosAppSettingsUrl});
      final log = BreadcrumbLog();
      await expectLater(
        _run(platform: TargetPlatform.iOS, launcher: launcher, log: log),
        completes,
      );
      expect(log.snapshot(), contains('gate: StateError'));
    });
  });
}
