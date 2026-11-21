import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/gate/device_settings_launcher.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// Records every url_launcher launch and optionally throws for a chosen
/// URI, so the iOS path can be driven without a platform channel.
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

/// Records every channel call and answers a scripted result — `false` or a
/// throw — so the Android branch can be driven without a real
/// MethodChannel (issue #1939's injectable seam).
class _FakeChannelOpener {
  _FakeChannelOpener({this.returnValue = true, this.throwError = false});

  final bool returnValue;
  final bool throwError;
  int calls = 0;

  Future<bool> call() {
    calls++;
    if (throwError) throw StateError('device_settings channel exploded');
    return Future.value(returnValue);
  }
}

Future<void> _run({
  required TargetPlatform platform,
  required _FakeLauncher launcher,
  required _FakeChannelOpener channelOpener,
  BreadcrumbLog? log,
  bool isWeb = false,
}) => openDeviceSettingsWith(
  breadcrumbLog: log ?? BreadcrumbLog(),
  launch: launcher.call,
  openSecuritySettings: channelOpener.call,
  platform: platform,
  isWeb: isWeb,
);

void main() {
  // The real-channel wiring test below swaps a mock handler onto the
  // binding's messenger, so the test binding must exist before it runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('openDeviceSettingsWith (#534/#1939)', () {
    test('web is a no-op regardless of platform', () async {
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener();
      await _run(
        platform: TargetPlatform.android,
        launcher: launcher,
        channelOpener: channelOpener,
        isWeb: true,
      );
      expect(launcher.calls, isEmpty);
      expect(channelOpener.calls, 0);
    });

    test('other platforms are a no-op', () async {
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener();
      await _run(
        platform: TargetPlatform.macOS,
        launcher: launcher,
        channelOpener: channelOpener,
      );
      expect(launcher.calls, isEmpty);
      expect(channelOpener.calls, 0);
    });

    test('iOS launches the app-settings: system scheme and never touches '
        'the channel', () async {
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener();
      await _run(
        platform: TargetPlatform.iOS,
        launcher: launcher,
        channelOpener: channelOpener,
      );
      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.$1.toString(), kIosAppSettingsUrl);
      expect(channelOpener.calls, 0);
    });

    test('the iOS path also swallows a launch failure', () async {
      final launcher = _FakeLauncher(throwFor: {kIosAppSettingsUrl});
      final log = BreadcrumbLog();
      await expectLater(
        _run(
          platform: TargetPlatform.iOS,
          launcher: launcher,
          channelOpener: _FakeChannelOpener(),
          log: log,
        ),
        completes,
      );
      expect(log.snapshot(), contains('gate: StateError'));
    });

    test('Android opens Security settings through the channel, not '
        'url_launcher', () async {
      // #1939: the intent:// url_launcher path is gone — the Android
      // branch makes exactly one channel call and no launch at all.
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener();
      final log = BreadcrumbLog();
      await _run(
        platform: TargetPlatform.android,
        launcher: launcher,
        channelOpener: channelOpener,
        log: log,
      );
      expect(channelOpener.calls, 1);
      expect(launcher.calls, isEmpty);
      expect(log.snapshot(), isEmpty);
    });

    test('a channel `false` reaches the failure path (breadcrumb), never a '
        'silent no-op', () async {
      // #1939's core bug: a failed launch was a `false` return, not a
      // throw, so nothing was recorded. `false` means the native half
      // already tried SECURITY_SETTINGS and its App-info fallback and
      // neither resolved — so Dart records it rather than attempting
      // anything further.
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener(returnValue: false);
      final log = BreadcrumbLog();
      await expectLater(
        _run(
          platform: TargetPlatform.android,
          launcher: launcher,
          channelOpener: channelOpener,
          log: log,
        ),
        completes,
      );
      expect(channelOpener.calls, 1);
      expect(launcher.calls, isEmpty);
      expect(
        log.snapshot(),
        contains('gate: AndroidSecuritySettingsUnavailable'),
      );
    });

    test('a channel throw reaches the same breadcrumb path and never '
        'escapes', () async {
      final launcher = _FakeLauncher();
      final channelOpener = _FakeChannelOpener(throwError: true);
      final log = BreadcrumbLog();
      await expectLater(
        _run(
          platform: TargetPlatform.android,
          launcher: launcher,
          channelOpener: channelOpener,
          log: log,
        ),
        completes,
      );
      expect(channelOpener.calls, 1);
      expect(launcher.calls, isEmpty);
      expect(
        log.snapshot(),
        contains('gate: AndroidSecuritySettingsUnavailable'),
      );
    });

    test('defaultOpenDeviceSettings wires the real channel: Android '
        'invokes openSecuritySettings on lunarlog/device_settings',
        () async {
      // Exercises the production glue (not the injected seam): the real
      // [AndroidSecuritySettingsOpener] must invoke the channel's one
      // method with no arguments. The native half's own fallback (App
      // info on ActivityNotFoundException) is Kotlin and is verified on
      // device per the #1939 coordinator handoff.
      const channel = MethodChannel(kDeviceSettingsChannelName);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final log = BreadcrumbLog();
      try {
        await defaultOpenDeviceSettings(breadcrumbLog: log);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
      expect(calls, hasLength(1));
      expect(calls.single.method, 'openSecuritySettings');
      expect(calls.single.arguments, isNull);
      expect(log.snapshot(), isEmpty);
    });
  });
}
