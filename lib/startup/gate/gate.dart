/// Conditional export: native platforms get the local_auth-backed gate;
/// anything else gets the placeholder that throws. The shell
/// (`lib/app_lifecycle.dart`) calls [defaultAppGate] and never branches on
/// platform itself.
library;

export 'gate_unsupported.dart'
    if (dart.library.ffi) 'local_auth_gate.dart';
