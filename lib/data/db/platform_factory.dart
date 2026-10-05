/// Conditional export: native platforms get the file-backed factory
/// (native_db.dart); anything else gets the placeholder that throws.
///
/// App bootstrap (a later unit) resolves the database file location and key
/// store, then calls `.open()` on the factory from here.
library;

export 'factory_unsupported.dart'
    if (dart.library.ffi) 'native_db.dart';
