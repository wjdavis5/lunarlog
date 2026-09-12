/// Issue #561: `protectDatabaseFile` must protect whichever file the app
/// actually opened (`LunarLogDbFactory.databasePath`), not always the
/// Application Support target — those differ when relocation fell back to
/// the legacy `Documents/` file. `MethodChannel` mocking mirrors
/// `local_auth_gate_test.dart`'s `applyPlatformPrivacyProtections` coverage
/// of the same `kPrivacyChannel`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart' show kPrivacyChannel;
import 'package:lunarlog/startup/startup_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('protectDatabaseFile', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), null);
    });

    test('no-ops on non-iOS platforms regardless of the given path', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), (call) async {
        invoked = true;
        return null;
      });

      await protectDatabaseFile('/some/legacy/path/lunarlog.db');

      expect(invoked, isFalse);
    });

    test('passes the given path — not a recomputed one — to the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      String? receivedPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), (call) async {
        receivedPath = (call.arguments as Map)['path'] as String;
        return null;
      });

      // The legacy fallback path issue #561 is about: the caller passes
      // whatever `LunarLogDbFactory.databasePath` actually is, which need
      // not be the Application Support target `localDatabaseFile()` would
      // recompute.
      const legacyFallbackPath = '/legacy/Documents/lunarlog.db';
      await protectDatabaseFile(legacyFallbackPath);

      expect(receivedPath, legacyFallbackPath);
    });

    test('a channel failure is swallowed (best-effort) regardless of path', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), (call) async {
        throw PlatformException(code: 'FAILED', message: 'nope');
      });

      await expectLater(protectDatabaseFile('/some/path/lunarlog.db'), completes);
    });
  });
}
