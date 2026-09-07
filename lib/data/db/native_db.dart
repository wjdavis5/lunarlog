/// Native (mobile/desktop) database wiring: a plain sqlite3 file, opened
/// via drift's background isolate. At-rest protection is the OS's (iOS Data
/// Protection / Android's platform encryption), not an app-managed cipher —
/// see docs/ops/ios-export-compliance.md.
library;

import 'dart:io';

import 'package:drift/native.dart';

import 'db_factory.dart';

/// Factory for native platforms.
LunarLogDbFactory nativeDbFactory({required File file}) {
  return LunarLogDbFactory(
    databasePath: file.path,
    existingFileCheck: file.exists,
    executorBuilder: () => NativeDatabase.createInBackground(file),
  );
}
