/// Mobile/desktop gate (U7, R7): wraps `local_auth` — biometric where
/// enrolled, device passcode as fallback (`biometricOnly: false`).
///
/// Fail-closed posture: any unavailable, cancelled, or errored
/// authentication returns false — never a bypass.
library;

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';

import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Native factory: the shell imports `gate.dart` and calls this without
/// branching on platform.
AppGate defaultAppGate() => LocalAuthAppGate();

class LocalAuthAppGate implements AppGate {
  LocalAuthAppGate({
    LocalAuthentication? localAuth,
    BreadcrumbLog? breadcrumbLog,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _breadcrumbLog = breadcrumbLog ?? defaultBreadcrumbLog;

  final LocalAuthentication _localAuth;
  final BreadcrumbLog _breadcrumbLog;

  @override
  bool get requiresUnlock => true;

  @override
  Future<bool> requestAccess() async {
    try {
      final bool canAuthenticate;
      try {
        canAuthenticate = await _localAuth.canCheckBiometrics ||
            await _localAuth.isDeviceSupported();
      } on PlatformException catch (error, stackTrace) {
        _breadcrumbLog.record('gate', error.runtimeType.toString());
        unawaited(Sentry.captureException(error, stackTrace: stackTrace));
        return false;
      }
      if (!canAuthenticate) {
        // No device credential at all: fail closed (the lock screen tells
        // the operator to set a screen lock).
        return false;
      }
      return await _localAuth.authenticate(
        localizedReason: 'Unlock your lunarlog data',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on Exception catch (error, stackTrace) {
      _breadcrumbLog.record('gate', error.runtimeType.toString());
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      return false;
    }
  }
}
