import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/db/key_store.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/startup/startup_native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// In-memory stand-in for the secure key store: mints a fresh key when none
/// is held, forgets it on [deleteKey], and records every mint so a test can
/// prove a new key was generated.
class MemoryKeyStore implements DbKeyStore {
  MemoryKeyStore();

  String? _key;
  final List<String> minted = [];

  String? get key => _key;

  @override
  Future<String> getOrCreateDbKey() async {
    final existing = _key;
    if (existing != null) return existing;
    final fresh = SecureDbKeyStore.generateKey();
    minted.add(fresh);
    _key = fresh;
    return fresh;
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
  }
}

bool hostHasSqlcipher() {
  final mem = sqlite3.sqlite3.openInMemory();
  try {
    return mem.select('PRAGMA cipher_version').isNotEmpty;
  } finally {
    mem.close();
  }
}

Future<File> freshDbFile(String name) async {
  final dir = Directory.systemTemp.createTempSync('lunarlog_reset_${name}_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// U3 device-reset primitives (KTD16, AE10). `deleteDatabaseFiles` and
/// `DbKeyStore.deleteKey` are the two building blocks `resetDevice`
/// composes; these tests pin the ordering the plan mandates.
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

  test('AE10: delete files then delete key: the next open sees no existing '
      'file, mints a new key, and succeeds empty', () async {
    final file = await freshDbFile('reset_order');
    final keys = MemoryKeyStore();
    final encrypted = hostHasSqlcipher();

    final factory = nativeDbFactory(
      file: file,
      keyStore: keys,
      requireEncryption: encrypted,
    );
    final db = await factory.open();
    await db.storage.upsertProfile(displayName: 'Before', isMinor: false);
    await db.close();
    expect(file.existsSync(), isTrue);
    final firstKey = keys.key;
    if (encrypted) {
      expect(firstKey, isNotNull);
      expect(keys.minted, hasLength(1));
    }

    // The plan's order: files first, then the key.
    await deleteDatabaseFiles(file);
    await keys.deleteKey();
    expect(keys.key, isNull);

    final reopened = await factory.open();
    addTearDown(() => reopened.close());
    expect(await reopened.storage.isEmpty(), isTrue);
    expect(file.existsSync(), isTrue, reason: 'a fresh file was created');
    if (encrypted) {
      expect(keys.minted, hasLength(2), reason: 'a new key was minted');
      expect(keys.key, isNot(firstKey));
    }
  });

  test(
    'AE10 counterexample: deleting the key first and crashing before the '
    'file is removed quarantines the next open (why files go first)',
    () async {
      final file = await freshDbFile('key_first');
      final keys = MemoryKeyStore();
      final factory = nativeDbFactory(file: file, keyStore: keys);
      final db = await factory.open();
      await db.storage.upsertProfile(displayName: 'Before', isMinor: false);
      await db.close();

      await keys.deleteKey();
      // Simulated crash: the file deletion never happens.

      await expectLater(
        factory.open(),
        throwsA(isA<DatabaseQuarantineError>()),
      );
      expect(
        keys.minted,
        hasLength(2),
        reason: 'a new key was minted over the old encrypted file',
      );
      expect(file.existsSync(), isTrue, reason: 'quarantine never wipes');
    },
    skip: hostHasSqlcipher()
        ? false
        : 'sqlcipher native library not active on this host',
  );

  test('SecureDbKeyStore exposes deleteKey on the interface', () {
    // Compile-time proof that the production store implements the primitive;
    // the platform channel is not exercised here.
    expect(SecureDbKeyStore.new, isA<Function>());
    expect(SecureDbKeyStore(), isA<DbKeyStore>());
  });

  test('SecureDbKeyStore pins the Keychain accessibility to '
      'unlocked_this_device -- device-bound like the flutter_secure_storage '
      '`unlocked` default, never first_unlock_this_device '
      '(docs/ops/ios-export-compliance.md)', () {
    final iOptions = SecureDbKeyStore().storage.iOptions;
    expect(iOptions.accessibility, KeychainAccessibility.unlocked_this_device);
  });
}
