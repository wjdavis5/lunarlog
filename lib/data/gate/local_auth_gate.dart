/// Mobile/desktop gate (U7, R7): wraps `local_auth` — biometric where
/// enrolled, device passcode as fallback (`biometricOnly: false`).
///
/// Fail-closed posture: any unavailable, cancelled, or errored
/// authentication returns false — never a bypass.
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';

import 'app_gate.dart';

class LocalAuthAppGate implements AppGate {
  LocalAuthAppGate({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  bool get requiresUnlock => true;

  @override
  Future<bool> requestAccess() async {
    try {
      final bool canAuthenticate;
      try {
        canAuthenticate = await _localAuth.canCheckBiometrics ||
            await _localAuth.isDeviceSupported();
      } on PlatformException {
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
    } on Exception {
      return false;
    }
  }
}
