/// Unit tests for the issue #244 database relocation migration
/// (`relocateLegacyDatabase` in `lib/startup/startup_native.dart`) against
/// real temp-directory files. The platform-channel half of that file
/// (`protectDatabaseFile`) is iOS-only and cannot run under `flutter test` —
/// it is a thin, best-effort wrapper around a `MethodChannel` call with no
/// branching logic worth unit-testing in isolation (same treatment as the
/// other platform adapters in `tool/quality/exclusions.dart`), and is
/// exercised by the iOS device checklist instead (see AGENTS.md).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/startup/startup_native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<Directory> _freshTempDir(String name) async {
  final dir = Directory.systemTemp.createTempSync('lunarlog_relocate_${name}_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Writes a minimal-but-real sqlite database at [file] with one profile row,
/// so a test can assert the *data* survived relocation, not just the bytes.
void _seedRealDatabase(File file, {required String profileId}) {
  final raw = sqlite3.sqlite3.open(file.path);
  raw.execute(
      'CREATE TABLE "profiles" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))');
  raw.execute(
      "INSERT INTO profiles (id, display_name) VALUES ('$profileId', 'Relocated')");
  raw.close();
}

void main() {
  group('relocateLegacyDatabase (issue #244)', () {
    test('no-op when there is no legacy file', () async {
      final dir = await _freshTempDir('no_legacy');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target =
          File('${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(target.existsSync(), isFalse,
          reason: 'nothing to migrate, nothing should appear at the target');
    });

    test('no-op when the target already exists (never overwrites, never '
        'touches the legacy file)', () async {
      final dir = await _freshTempDir('target_exists');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      legacy.writeAsStringSync('legacy content');
      target.writeAsStringSync('already-migrated content');

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(target.readAsStringSync(), 'already-migrated content',
          reason: 'must never overwrite a target a prior run already wrote');
      expect(legacy.existsSync(), isTrue,
          reason: 'a short-circuited run must not delete the legacy file');
      expect(legacy.readAsStringSync(), 'legacy content');
    });

    test('moves the main file, handles every existing WAL/SHM sibling, and '
        'cleans up the legacy copies once the target verifies openable',
        () async {
      final dir = await _freshTempDir('full_move');
      final legacyDir = Directory('${dir.path}${Platform.pathSeparator}docs')
        ..createSync();
      final legacy = File('${legacyDir.path}${Platform.pathSeparator}old.db');
      final targetDir =
          Directory('${dir.path}${Platform.pathSeparator}support');
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p1');
      File('${legacy.path}-wal').writeAsStringSync('wal bytes');
      File('${legacy.path}-shm').writeAsStringSync('shm bytes');
      // No -journal sibling this time — the migration must not require one.

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      // The main file relocated with its data intact — see the dedicated
      // "no data loss" test below for a closer look at the row content.
      expect(target.existsSync(), isTrue);

      // Every legacy sibling that existed is gone — each one was either
      // copied to the target and then removed from the legacy path, or (for
      // -wal/-shm specifically) reconciled away by sqlite3 itself during the
      // verification open, exactly as it would be for a real WAL sidecar
      // reopened elsewhere; either way nothing is left behind at the old
      // location for a stray file to leak from.
      expect(legacy.existsSync(), isFalse,
          reason: 'legacy main file deleted only after the target verified');
      expect(File('${legacy.path}-wal').existsSync(), isFalse);
      expect(File('${legacy.path}-shm').existsSync(), isFalse);
      expect(File('${legacy.path}-journal').existsSync(), isFalse);
    });

    test('relocated file is an intact, independently readable database '
        '(no data loss) that the production factory treats as pre-existing',
        () async {
      final dir = await _freshTempDir('no_data_loss');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-migrated');

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      // Read the relocated file back with a fresh sqlite3 handle (not the
      // one relocateLegacyDatabase used to verify it) — proving the moved
      // bytes are a genuinely intact, independently readable database, not
      // just a file that happened to exist.
      final reopened = sqlite3.sqlite3.open(target.path);
      final rows = reopened.select('SELECT id FROM profiles');
      reopened.close();
      expect(rows.map((r) => r['id']), contains('p-migrated'));

      // The production factory's own existing-file check must see this as
      // a real, pre-existing file (not first-run) — that is what routes a
      // corrupt relocation target through the quarantine path instead of
      // silently recreating it, exactly as it would for any other
      // pre-existing database.
      final factory = nativeDbFactory(file: target);
      expect(await factory.existingFileCheck!(), isTrue);
    });

    test('rolls back a partial/corrupt copy and leaves the legacy file '
        'untouched for the next startup to retry', () async {
      final dir = await _freshTempDir('rollback');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      final garbage = 'not a sqlite file'.codeUnits;
      legacy.writeAsBytesSync(garbage);

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(target.existsSync(), isFalse,
          reason: 'a copy that fails verification must be rolled back');
      expect(legacy.existsSync(), isTrue,
          reason: 'the only good copy must survive a failed migration');
      expect(legacy.readAsBytesSync(), garbage);
    });

    test('creates the target directory when it does not exist yet',
        () async {
      final dir = await _freshTempDir('mkdir');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File('${dir.path}${Platform.pathSeparator}brand'
          '${Platform.pathSeparator}new${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p2');

      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(target.existsSync(), isTrue);
    });
  });
}
