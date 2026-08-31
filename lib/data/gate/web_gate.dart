/// Web gate (U7, R7): no-op. Browser storage carries no device-credential
/// gate in v1 and the web dev banner (unencrypted-storage warning) is U8 —
/// deliberately not built here.
library;

import 'app_gate.dart';

/// Web factory (see `gate.dart` conditional export).
AppGate defaultAppGate() => WebAppGate();

class WebAppGate implements AppGate {
  @override
  bool get requiresUnlock => false;

  @override
  Future<bool> requestAccess() async => true;
}
