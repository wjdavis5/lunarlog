/// Conditional export: native platforms get the file-backed factory wiring,
/// web gets the WASM factory wiring. App bootstrap (main.dart) calls
/// [buildDbFactory] and never branches on platform itself.
library;

export 'startup_unsupported.dart'
    if (dart.library.ffi) 'startup_native.dart'
    if (dart.library.js_interop) 'startup_web.dart';
