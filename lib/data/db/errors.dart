/// Re-export of the domain-owned fail-closed database error.
///
/// The type moved to `lib/domain/models/database_error.dart` so `lib/ui` can
/// pattern-match it without importing `lib/data`. This shim keeps existing
/// `lib/data` importers working.
library;

export 'package:lunarlog/domain/models/database_error.dart';
