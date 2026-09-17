import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/startup/gate/local_auth_gate.dart';

class FakeLocalAuthentication extends Fake implements LocalAuthentication {
  bool canCheck = true;
  bool isSupported = true;
  bool authResult = true;
  Object? canCheckError;
  Object? isSupportedError;
  Object? authError;

  @override
  Future<bool> get canCheckBiometrics async {
    if (canCheckError != null) throw canCheckError!;
    return canCheck;
  }

  @override
  Future<bool> isDeviceSupported() async {
    if (isSupportedError != null) throw isSupportedError!;
    return isSupported;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #authenticate) {
      if (authError != null) throw authError!;
      return Future.value(authResult);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAuthAppGate', () {
    test('successful authentication records no breadcrumbs and returns true', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = true
        ..authResult = true;
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      final result = await gate.requestAccess();

      expect(result, isTrue);
      expect(log.snapshot(), isEmpty);
    });

    test('device unsupported returns false with no breadcrumbs', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = false
        ..isSupported = false;
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      final result = await gate.requestAccess();

      expect(result, isFalse);
      expect(log.snapshot(), isEmpty);
    });

    test('canCheckBiometrics PlatformException records breadcrumb and fails closed', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheckError = PlatformException(code: 'UNAVAILABLE', message: 'Biometrics unavailable');
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      final result = await gate.requestAccess();

      expect(result, isFalse);
      expect(log.snapshot(), ['gate: PlatformException']);
      expect(log.snapshot().single, isNot(contains('Biometrics unavailable')));
    });

    test('authenticate PlatformException records breadcrumb and fails closed', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = true
        ..authError = PlatformException(code: 'FAILED', message: 'Auth failed');
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      final result = await gate.requestAccess();

      expect(result, isFalse);
      expect(log.snapshot(), ['gate: PlatformException']);
      expect(log.snapshot().single, isNot(contains('Auth failed')));
    });

    test('authenticate general Exception records breadcrumb and fails closed', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = true
        ..authError = Exception('unexpected auth error');
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      final result = await gate.requestAccess();

      expect(result, isFalse);
      expect(log.snapshot(), ['gate: _Exception']);
      expect(log.snapshot().single, isNot(contains('unexpected auth error')));
    });
  });

  // Issue #534: [LocalAuthAppGate.canAuthenticate] is the availability
  // check `GateController.unlock` now calls *before* [requestAccess], so it
  // can tell "the operator declined the prompt" apart from "there was
  // never a prompt to decline". These pin its own contract independent of
  // `requestAccess`'s (which delegates to it).
  group('LocalAuthAppGate.canAuthenticate', () {
    test('true when biometrics can be checked', () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = true
        ..isSupported = false;
      final gate = LocalAuthAppGate(
          localAuth: fakeAuth, breadcrumbLog: BreadcrumbLog());

      expect(await gate.canAuthenticate(), isTrue);
    });

    test('true when the device supports credentials but not biometrics',
        () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = false
        ..isSupported = true;
      final gate = LocalAuthAppGate(
          localAuth: fakeAuth, breadcrumbLog: BreadcrumbLog());

      expect(await gate.canAuthenticate(), isTrue);
    });

    test('false when neither biometrics nor a device credential is enrolled',
        () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheck = false
        ..isSupported = false;
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      expect(await gate.canAuthenticate(), isFalse);
      expect(log.snapshot(), isEmpty,
          reason: 'a negative answer is not a platform error');
    });

    test('false with a breadcrumb on a canCheckBiometrics PlatformException',
        () async {
      final fakeAuth = FakeLocalAuthentication()
        ..canCheckError =
            PlatformException(code: 'UNAVAILABLE', message: 'nope');
      final log = BreadcrumbLog();
      final gate = LocalAuthAppGate(localAuth: fakeAuth, breadcrumbLog: log);

      expect(await gate.canAuthenticate(), isFalse);
      expect(log.snapshot(), ['gate: PlatformException']);
    });
  });

  group('applyPlatformPrivacyProtections', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), null);
    });

    test('no-ops on non-Android platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final log = BreadcrumbLog();

      await applyPlatformPrivacyProtections(breadcrumbLog: log);

      expect(log.snapshot(), isEmpty);
    });

    test('invokes channel on Android and records breadcrumb on error', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), (call) async {
        throw PlatformException(code: 'SECURE_FAILED', message: 'Window is null');
      });
      final log = BreadcrumbLog();

      await applyPlatformPrivacyProtections(breadcrumbLog: log);

      expect(log.snapshot(), ['privacy: PlatformException']);
      expect(log.snapshot().single, isNot(contains('Window is null')));
    });

    test('succeeds without recording breadcrumbs on successful Android invoke', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kPrivacyChannel), (call) async => null);
      final log = BreadcrumbLog();

      await applyPlatformPrivacyProtections(breadcrumbLog: log);

      expect(log.snapshot(), isEmpty);
    });
  });
}
