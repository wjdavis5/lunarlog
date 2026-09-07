/// Native (mobile/desktop) startup wiring for the database factory: a file
/// in the app documents directory, opened by U2's factory (fail-closed on
/// an existing file that won't open). Also the native half of the
/// device-reset primitives (KTD16).
library;

import 'dart:io';

import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:path_provider/path_provider.dart';

/// The one database file this install uses.
Future<File> localDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

Future<LunarLogDbFactory> buildDbFactory() async =>
    nativeDbFactory(file: await localDatabaseFile());

/// Deletes this install's database file and its `-wal`, `-shm` and
/// `-journal` siblings. A device-reset primitive only: the caller
/// (`resetDevice`, KTD16) must have closed the database first. Nothing else
/// is touched.
Future<void> deleteLocalDatabase() async =>
    deleteDatabaseFiles(await localDatabaseFile());

/// Sibling suffixes sqlite may leave beside a database file.
const List<String> kDatabaseSiblingSuffixes = ['', '-wal', '-shm', '-journal'];

/// [deleteLocalDatabase] for an explicit [dbFile] (testable without the
/// platform's documents directory). Missing files are skipped.
Future<void> deleteDatabaseFiles(File dbFile) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    final sibling = File('${dbFile.path}$suffix');
    if (await sibling.exists()) {
      await sibling.delete();
    }
  }
}
