/// Conditional export: native platforms get the SQLCipher factory
/// (native_db.dart), web gets the unencrypted WASM factory (web_db.dart).
///
/// App bootstrap (a later unit) resolves the database file location and key
/// store, then calls `.open()` on the factory from here.
library;

export 'factory_unsupported.dart'
    if (dart.library.ffi) 'native_db.dart'
    if (dart.library.js_interop) 'web_db.dart';
