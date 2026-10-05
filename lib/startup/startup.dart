/// Conditional export: native platforms get the file-backed factory wiring;
/// anything else gets the placeholder that throws. App bootstrap (main.dart)
/// calls [buildDbFactory] and never branches on platform itself.
library;

export 'startup_unsupported.dart'
    if (dart.library.ffi) 'startup_native.dart';
