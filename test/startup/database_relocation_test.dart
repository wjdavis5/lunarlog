/// Unit tests for the issue #244 database relocation migration
/// (`lib/startup/database_relocation.dart`) against real temp-directory
/// files, round 2: crash-safe staging/verify/atomic-rename/sentinel design
/// (replacing the original "does the target file exist" idempotency check
/// and "does sqlite3 open it" verification). The platform-channel half of
/// the original file (`protectDatabaseFile`, still in
/// `lib/startup/startup_native.dart`) is iOS-only and cannot run under
/// `flutter test` — it is a thin, best-effort wrapper around a
/// `MethodChannel` call with no branching logic worth unit-testing in
/// isolation (same treatment as the other platform adapters in
/// `tool/quality/exclusions.dart`), and is exercised by the iOS device
/// checklist instead (see `docs/ops/supabase-go-live.md`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/startup/database_relocation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<Directory> _freshTempDir(String name) async {
  final dir = Directory.systemTemp.createTempSync('lunarlog_relocate_${name}_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Writes a minimal-but-real sqlite database at [file] with one profile row
/// (and, when [withDayEntries] is set, a `day_entries` table too), so a
/// test can assert the *data* survived relocation, not just the bytes.
void _seedRealDatabase(
  File file, {
  required String profileId,
  bool withDayEntries = false,
}) {
  final raw = sqlite3.sqlite3.open(file.path);
  raw.execute(
      'CREATE TABLE "profiles" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))');
  raw.execute(
      "INSERT INTO profiles (id, display_name) VALUES ('$profileId', 'Relocated')");
  if (withDayEntries) {
    raw.execute(
        'CREATE TABLE "day_entries" ("id" TEXT NOT NULL, PRIMARY KEY ("id"))');
  }
  raw.close();
}

void main() {
  group('relocateLegacyDatabase (issue #244 round 2)', () {
    test('no-op when there is no legacy file', () async {
      final dir = await _freshTempDir('no_legacy');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path,
          reason: 'nothing to migrate — the caller opens (and creates) the '
              'target itself, same as a fresh install');
      expect(target.existsSync(), isFalse,
          reason: 'this function never itself creates the target file');
    });

    test('short-circuits when the target already carries the completion '
        'sentinel (never overwrites the target) and best-effort deletes a '
        'legacy copy left behind by a process killed between the sentinel '
        'write and the legacy delete (round 3, finding #2)', () async {
      final dir = await _freshTempDir('already_done');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      legacy.writeAsStringSync('legacy content');
      target.writeAsStringSync('already-migrated content');
      File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
          .writeAsStringSync('done');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.readAsStringSync(), 'already-migrated content',
          reason: 'must never overwrite a target a prior run already wrote');
      expect(legacy.existsSync(), isFalse,
          reason: 'a short-circuited run must best-effort delete a '
              'leftover legacy copy so plaintext health data does not '
              'linger forever in the iCloud-backed Documents/ directory');
    });

    test('a target that exists WITHOUT the sentinel is treated as an '
        'interrupted previous attempt: cleaned up and retried from the '
        'still-present legacy file', () async {
      final dir = await _freshTempDir('interrupted_retry');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-retry', withDayEntries: true);
      // A partial target left behind by a crashed previous attempt, no
      // sentinel written.
      target.writeAsStringSync('partial garbage');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isTrue);
      expect(legacy.existsSync(), isFalse,
          reason: 'the retry succeeded and cleaned up the legacy file');
      expect(
        File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
            .existsSync(),
        isTrue,
        reason: 'a successful relocation writes the sentinel last',
      );
      final reopened = sqlite3.sqlite3.open(target.path);
      final rows = reopened.select('SELECT id FROM profiles');
      reopened.close();
      expect(rows.map((r) => r['id']), contains('p-retry'));
    });

    test('a target that exists WITHOUT the sentinel and no legacy file is '
        'NEVER wiped when it is itself an openable database — round 3, '
        'finding #1: a target-first guard used to delete this '
        'unconditionally, silently wiping every fresh install\'s database '
        'on its second launch (a fresh install always looks exactly like '
        'this: a target with no sentinel and no legacy file)', () async {
      final dir = await _freshTempDir('interrupted_no_legacy');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');
      _seedRealDatabase(target, profileId: 'p-fresh-install');
      // No legacy file at all — this is exactly the state of every fresh
      // install on its second launch.

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isTrue,
          reason: 'a live, openable database at the target must never be '
              'wiped just because it lacks the sentinel and there is no '
              'legacy file to have migrated it from');
      final reopened = sqlite3.sqlite3.open(target.path);
      final rows = reopened.select('SELECT id FROM profiles');
      reopened.close();
      expect(rows.map((r) => r['id']), contains('p-fresh-install'));
      expect(
        File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
            .existsSync(),
        isTrue,
        reason: 'the target is retroactively marked done so the next '
            'launch short-circuits immediately instead of re-checking it',
      );
    });

    test('a target that exists WITHOUT the sentinel, isn\'t even an '
        'openable database, and has no legacy file left is cleaned up '
        '(genuine residue from a broken previous attempt, nothing to '
        'protect and nothing to retry from)', () async {
      final dir = await _freshTempDir('interrupted_no_legacy_garbage');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');
      target.writeAsStringSync('partial garbage');
      // No legacy file at all.

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isFalse,
          reason: 'the stale partial target was removed and nothing '
              'replaced it — the caller creates a fresh database there');
    });

    test('a REAL sqlite database at the target with no sentinel and no '
        'legacy file survives two consecutive relocateLegacyDatabase '
        'calls byte-for-byte (round 3, finding #1)', () async {
      final dir = await _freshTempDir('survives_two_calls');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir = Directory('${dir.path}${Platform.pathSeparator}support')
        ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');
      _seedRealDatabase(target, profileId: 'p-byte-for-byte');
      final originalBytes = target.readAsBytesSync();

      final first =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(first.path, target.path);
      expect(target.readAsBytesSync(), originalBytes,
          reason: 'the first call must not mutate the target at all');

      final second =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(second.path, target.path);
      expect(target.readAsBytesSync(), originalBytes,
          reason: 'the second call — now short-circuited by the sentinel '
              'the first call wrote — must also leave the target '
              'byte-for-byte untouched');
    });

    test('moves the main file, handles every existing WAL/SHM sibling, '
        'writes the sentinel, and cleans up the legacy copies once the '
        'staged copy verifies', () async {
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

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isTrue);
      expect(
        File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
            .existsSync(),
        isTrue,
      );

      // Every legacy sibling that existed is gone.
      expect(legacy.existsSync(), isFalse,
          reason: 'legacy main file deleted only after the target verified');
      expect(File('${legacy.path}-wal').existsSync(), isFalse);
      expect(File('${legacy.path}-shm').existsSync(), isFalse);
      expect(File('${legacy.path}-journal').existsSync(), isFalse);

      // No staging residue left behind either.
      for (final entity in targetDir.listSync()) {
        expect(entity.path, isNot(contains('.migrating')));
      }
    });

    test('relocated file is an intact, independently readable database '
        '(no data loss) that the production factory treats as pre-existing',
        () async {
      final dir = await _freshTempDir('no_data_loss');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-migrated');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(result.path, target.path);

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

    test('creates the target directory when it does not exist yet',
        () async {
      final dir = await _freshTempDir('mkdir');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File('${dir.path}${Platform.pathSeparator}brand'
          '${Platform.pathSeparator}new${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p2');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isTrue);
    });

    test('a copy failure partway through the sibling list leaves no '
        'staging residue, keeps the legacy file intact, falls back to it, '
        'and recovers cleanly on the next call', () async {
      final dir = await _freshTempDir('copier_kill');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir =
          Directory('${dir.path}${Platform.pathSeparator}support');
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-copier');
      File('${legacy.path}-wal').writeAsStringSync('wal bytes');

      Future<void> flakyCopier(File from, File to) async {
        if (from.path.endsWith('-wal')) {
          throw const FileSystemException('simulated failure mid-copy');
        }
        await from.copy(to.path);
      }

      final failedResult = await relocateLegacyDatabase(
        legacyFile: legacy,
        targetFile: target,
        copier: flakyCopier,
      );

      expect(failedResult.path, legacy.path,
          reason: 'a failed relocation must fall back to the legacy file');
      expect(legacy.existsSync(), isTrue,
          reason: 'the legacy file must survive a failed attempt untouched');
      expect(target.existsSync(), isFalse,
          reason: 'no partial target must be left behind');
      if (targetDir.existsSync()) {
        for (final entity in targetDir.listSync()) {
          expect(entity.path, isNot(contains('.migrating')),
              reason: 'no staging file should survive a failed attempt');
        }
      }
      expect(
        File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
            .existsSync(),
        isFalse,
      );

      // The very next call, with a working copier, must succeed cleanly —
      // this is the actual "recovers on the next call" assertion.
      final recovered =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(recovered.path, target.path);
      expect(target.existsSync(), isTrue);
      expect(legacy.existsSync(), isFalse);
    });

    test('a staged copy of visibly corrupt bytes fails verification, is '
        'rolled back, and the legacy file is preserved untouched',
        () async {
      final dir = await _freshTempDir('verify_fail_corrupt');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-corrupt');

      Future<void> corruptingCopier(File from, File to) async {
        await to.writeAsBytes('not actually a sqlite file'.codeUnits);
      }

      final result = await relocateLegacyDatabase(
        legacyFile: legacy,
        targetFile: target,
        copier: corruptingCopier,
      );

      expect(result.path, legacy.path);
      expect(target.existsSync(), isFalse);
      expect(legacy.existsSync(), isTrue);
    });

    test('a staged copy that opens fine but whose row counts do not match '
        'the legacy database is rejected by verification (issue #244 '
        'round 2 — the "does sqlite3 open it" check alone would have '
        'passed this)', () async {
      final dir = await _freshTempDir('verify_fail_counts');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'p-real');

      Future<void> wrongContentCopier(File from, File to) async {
        // A structurally valid, independently openable sqlite database —
        // but with zero profile rows, simulating a copy that silently
        // dropped data.
        final raw = sqlite3.sqlite3.open(to.path);
        raw.execute('CREATE TABLE "profiles" ("id" TEXT NOT NULL, '
            '"display_name" TEXT NOT NULL, PRIMARY KEY ("id"))');
        raw.close();
      }

      final result = await relocateLegacyDatabase(
        legacyFile: legacy,
        targetFile: target,
        copier: wrongContentCopier,
      );

      expect(result.path, legacy.path);
      expect(target.existsSync(), isFalse);
      expect(legacy.existsSync(), isTrue);
    });

    test('a row committed only to the legacy -wal sidecar (never '
        'checkpointed into the main file) survives relocation into the '
        'target', () async {
      final dir = await _freshTempDir('wal');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      // Keep this connection open for the whole test: closing the *last*
      // connection to a WAL-mode database auto-checkpoints it, which would
      // defeat the point of this test (the row must live only in -wal,
      // not yet folded into the main file, while relocation runs).
      final writer = sqlite3.sqlite3.open(legacy.path);
      var writerClosed = false;
      addTearDown(() {
        if (!writerClosed) writer.close();
      });
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute(
          'CREATE TABLE "profiles" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, '
          'PRIMARY KEY ("id"))');
      writer.execute(
          "INSERT INTO profiles (id, display_name) VALUES ('p-wal-only', 'WalOnly')");

      expect(File('${legacy.path}-wal').existsSync(), isTrue,
          reason: 'WAL mode must have produced a -wal sidecar next to the '
              'legacy main file');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(result.path, target.path);

      writer.close();
      writerClosed = true;

      final reopened = sqlite3.sqlite3.open(target.path);
      final rows = reopened.select('SELECT id FROM profiles');
      reopened.close();
      expect(rows.map((r) => r['id']), contains('p-wal-only'));
    });

    test('a staged copy whose profiles/day_entries counts match but whose '
        'row count differs in some other legacy table is still rejected — '
        'round 3 broadens the row-count check to every table in the '
        'legacy sqlite_master, not just profiles/day_entries (finding '
        '#4)', () async {
      final dir = await _freshTempDir('verify_fail_other_table');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      final raw = sqlite3.sqlite3.open(legacy.path);
      raw.execute('CREATE TABLE "profiles" ("id" TEXT NOT NULL, '
          '"display_name" TEXT NOT NULL, PRIMARY KEY ("id"))');
      raw.execute("INSERT INTO profiles (id, display_name) VALUES ('p1', 'A')");
      raw.execute(
          'CREATE TABLE "cycle_notes" ("id" TEXT NOT NULL, PRIMARY KEY ("id"))');
      raw.execute("INSERT INTO cycle_notes (id) VALUES ('n1')");
      raw.execute("INSERT INTO cycle_notes (id) VALUES ('n2')");
      raw.close();

      Future<void> droppingCopier(File from, File to) async {
        // Copies profiles (matching row count) but silently drops a row
        // from cycle_notes — a table the original profiles/day_entries-only
        // check never looked at.
        final stagedDb = sqlite3.sqlite3.open(to.path);
        stagedDb.execute('CREATE TABLE "profiles" ("id" TEXT NOT NULL, '
            '"display_name" TEXT NOT NULL, PRIMARY KEY ("id"))');
        stagedDb
            .execute("INSERT INTO profiles (id, display_name) VALUES ('p1', 'A')");
        stagedDb.execute(
            'CREATE TABLE "cycle_notes" ("id" TEXT NOT NULL, PRIMARY KEY ("id"))');
        stagedDb.execute("INSERT INTO cycle_notes (id) VALUES ('n1')");
        // 'n2' silently dropped.
        stagedDb.close();
      }

      final result = await relocateLegacyDatabase(
        legacyFile: legacy,
        targetFile: target,
        copier: droppingCopier,
      );

      expect(result.path, legacy.path,
          reason: 'the broadened row-count check must catch a dropped row '
              'in a table the original check never looked at');
      expect(target.existsSync(), isFalse);
      expect(legacy.existsSync(), isTrue);
    });
  });

  group('deleteRelocationArtifacts (issue #244 round 2, KTD16)', () {
    test('wipes the legacy file, the target and its siblings, and the '
        'sentinel, so a reopen performs no relocation and no wiped data '
        'comes back', () async {
      final dir = await _freshTempDir('delete_artifacts');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir =
          Directory('${dir.path}${Platform.pathSeparator}support')
            ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      _seedRealDatabase(legacy, profileId: 'legacy-data');
      _seedRealDatabase(target, profileId: 'target-data');
      File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
          .writeAsStringSync('done');

      await deleteRelocationArtifacts(legacyFile: legacy, targetFile: target);

      expect(legacy.existsSync(), isFalse);
      expect(target.existsSync(), isFalse);
      expect(
        File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
            .existsSync(),
        isFalse,
      );

      // The reopen path: relocateLegacyDatabase must not resurrect
      // anything — this is what `deleteLocalDatabase` (the native wrapper
      // this function backs) protects `resetDevice` (KTD16) with.
      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
      expect(result.path, target.path,
          reason: 'nothing left to migrate — a fresh database is created '
              'at the target, same as any other fresh install');
      expect(target.existsSync(), isFalse,
          reason: 'relocateLegacyDatabase never itself creates the target '
              'file — this only proves no data was resurrected');
    });

    test('tolerates every file already being absent', () async {
      final dir = await _freshTempDir('delete_artifacts_noop');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final target = File(
          '${dir.path}${Platform.pathSeparator}support${Platform.pathSeparator}new.db');

      await expectLater(
        deleteRelocationArtifacts(legacyFile: legacy, targetFile: target),
        completes,
      );
    });

    test('a new database created at the target after '
        'deleteRelocationArtifacts survives a further '
        'relocateLegacyDatabase call (round 3, finding #1 — resetDevice '
        'deletes the sentinel too, which used to re-arm the wipe)',
        () async {
      final dir = await _freshTempDir('reset_then_new_db');
      final legacy = File('${dir.path}${Platform.pathSeparator}old.db');
      final targetDir =
          Directory('${dir.path}${Platform.pathSeparator}support')
            ..createSync();
      final target = File('${targetDir.path}${Platform.pathSeparator}new.db');

      _seedRealDatabase(target, profileId: 'p-before-reset');
      File('${targetDir.path}${Platform.pathSeparator}$kRelocationSentinelName')
          .writeAsStringSync('done');

      await deleteRelocationArtifacts(legacyFile: legacy, targetFile: target);
      expect(target.existsSync(), isFalse);

      // Simulate the app creating a brand-new database at the target
      // right after the reset — exactly what resetDevice's own reopen
      // does, and exactly the state that used to be wiped again.
      _seedRealDatabase(target, profileId: 'p-after-reset');

      final result =
          await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);

      expect(result.path, target.path);
      expect(target.existsSync(), isTrue,
          reason: 'the fresh post-reset database must not be deleted just '
              'because deleteRelocationArtifacts also removed the '
              'sentinel');
      final reopened = sqlite3.sqlite3.open(target.path);
      final rows = reopened.select('SELECT id FROM profiles');
      reopened.close();
      expect(rows.map((r) => r['id']), contains('p-after-reset'));
    });
  });

  group('deleteDatabaseFiles', () {
    test('removes the database and its -wal/-shm/-journal siblings, and '
        'tolerates missing files', () async {
      final dir = await _freshTempDir('delete_siblings');
      final file = File('${dir.path}${Platform.pathSeparator}lunarlog.db');
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
  });
}
