/// Conditional export: native platforms get the local_auth-backed gate,
/// web gets the no-op gate. The shell (`lib/app_lifecycle.dart`) calls
/// [defaultAppGate] and never branches on platform itself.
library;

export 'gate_unsupported.dart'
    if (dart.library.ffi) 'local_auth_gate.dart'
    if (dart.library.js_interop) 'web_gate.dart';
