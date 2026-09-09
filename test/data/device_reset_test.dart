import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/startup/database_relocation.dart';

Future<File> freshDbFile(String name) async {
  final dir = Directory.systemTemp.createTempSync('lunarlog_reset_${name}_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// U3 device-reset primitive (KTD16): `deleteDatabaseFiles` is the building
/// block `resetDevice` calls on native.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('deleteDatabaseFiles removes the database and its -wal/-shm/-journal '
      'siblings, and tolerates missing files', () async {
    final file = await freshDbFile('siblings');
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      File('${file.path}$suffix').writeAsStringSync('x');
    }
    final unrelated = File('${file.path}.bak')..writeAsStringSync('keep');

    await deleteDatabaseFiles(file);

    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      expect(
        File('${file.path}$suffix').existsSync(),
        isFalse,
        reason: 'sibling "$suffix" must be deleted',
      );
    }
    expect(unrelated.existsSync(), isTrue);

    // Idempotent on an already-clean directory.
    await expectLater(deleteDatabaseFiles(file), completes);
  });
}
