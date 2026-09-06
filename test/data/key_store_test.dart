/// `SecureDbKeyStore` (lib/data/db/key_store.dart): the accessibility
/// upgrade path (review findings on PR #86). A key minted under an earlier
/// Keychain accessibility must still be found -- and migrated forward --
/// rather than triggering a fresh mint that would quarantine the existing
/// SQLCipher database (db_factory.dart's `DatabaseQuarantineError`).
///
/// Also covers the migration's journal-and-resume design (round 4 review):
/// the old copy must never be the *only* copy at any point in the sequence,
/// and an interrupted migration (process kill, a throwing write, a
/// locked-device write) must be recovered on the next call rather than
/// permanently losing the key.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/db/key_store.dart';

/// Thrown by [FakeSecureStorage] in place of completing a configured write
/// or delete call -- stands in for a locked-device write failure, or (since
/// the caller never observes success either way) a process kill mid-call.
class SimulatedIOFailure implements Exception {
  SimulatedIOFailure(this.message);
  final String message;

  @override
  String toString() => 'SimulatedIOFailure: $message';
}

/// In-memory stand-in for [FlutterSecureStorage] that emulates the two
/// real-Keychain behaviors this migration depends on:
///
/// * `kSecAttrAccessible` is a *matching constraint* on reads (and writes'
///   own existence checks), not just a write-time attribute, so a value
///   written under one accessibility is invisible to a read under another.
///   Values are therefore bucketed by the accessibility requested on each
///   call -- `null` (no override passed) is its own bucket, standing in for
///   [SecureDbKeyStore]'s own configured (current) accessibility, exactly
///   like a real call to `_storage.read(key: ...)` with no `iOptions`
///   override resolves to the instance's configured options.
/// * Delete is the opposite: `flutter_secure_storage_darwin`'s
///   `performDelete` clears `accessibilityLevel` off the query before
///   calling `SecItemDelete`, so a delete call is **account-wide** --
///   it removes the key from every accessibility bucket, regardless of
///   which `iOptions` was passed. A delete scoped to just the requested
///   bucket would hide the ordering bug this migration depends on getting
///   right (deleting the legacy item before, not after, writing the new
///   one).
///
/// This mirrors the real platform rather than a plain key-value map, which
/// would hide this class of bug entirely. Note that accounts (the `key`
/// argument) are always distinguished -- only `iOptions` is collapsed by
/// delete -- so [SecureDbKeyStore.migratingStorageKey]'s journal entries are
/// never touched by a delete scoped to [SecureDbKeyStore.storageKey], and
/// vice versa.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, Map<KeychainAccessibility?, String>> _byAccount = {};
  final List<AppleOptions?> writeIOptions = [];
  final List<AppleOptions?> readIOptions = [];
  final List<AppleOptions?> deleteIOptions = [];

  int _writeCalls = 0;
  int _deleteCalls = 0;

  /// When set, the write() call with this 1-indexed call number throws
  /// [SimulatedIOFailure] instead of persisting -- e.g. a locked-device
  /// write failure. Since the caller (`key_store.dart`) never observes a
  /// completed side effect either way, this also stands in for a process
  /// kill during that same call.
  int? failWriteOnCall;

  /// Same as [failWriteOnCall], for delete().
  int? failDeleteOnCall;

  KeychainAccessibility? _bucketOf(AppleOptions? options) =>
      options?.accessibility;

  /// Seeds a value directly into the bucket matching [options] (`null` for
  /// the "current accessibility, no override" bucket) under [key],
  /// bypassing [write] -- simulates a key already persisted by earlier app
  /// code (or a prior, interrupted run) before the test starts.
  void seed(String key, AppleOptions? options, String value) {
    _byAccount.putIfAbsent(key, () => {})[_bucketOf(options)] = value;
  }

  bool has(String key, AppleOptions? options) =>
      (_byAccount[key] ?? const {}).containsKey(_bucketOf(options));

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _writeCalls++;
    writeIOptions.add(iOptions);
    if (_writeCalls == failWriteOnCall) {
      throw SimulatedIOFailure('write #$_writeCalls ($key)');
    }
    final bucket = _byAccount.putIfAbsent(key, () => {});
    if (value == null) {
      bucket.remove(_bucketOf(iOptions));
    } else {
      bucket[_bucketOf(iOptions)] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readIOptions.add(iOptions);
    return _byAccount[key]?[_bucketOf(iOptions)];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _deleteCalls++;
    deleteIOptions.add(iOptions);
    if (_deleteCalls == failDeleteOnCall) {
      throw SimulatedIOFailure('delete #$_deleteCalls ($key)');
    }
    // Account-wide, like the real plugin: `iOptions` is recorded (callers
    // assert on it) but does NOT scope which bucket loses the key -- every
    // bucket *for this account* does. Other accounts (different `key`
    // strings, e.g. the migration journal) are untouched.
    _byAccount[key]?.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Stands in for "no override passed" -- the bucket [SecureDbKeyStore]'s
/// plain `_storage.read(key: storageKey)` / `.write(...)` calls land in,
/// i.e. the store's own configured (current) accessibility.
const AppleOptions? _current = null;
final _firstUnlockThisDevice = SecureDbKeyStore.legacyIOSOptions[0];
final _unlockedThisDevice = SecureDbKeyStore.legacyIOSOptions[1];

const _storageKey = SecureDbKeyStore.storageKey;
const _journalKey = SecureDbKeyStore.migratingStorageKey;

/// 64 lowercase hex characters -- a well-formed database key.
const _validKey =
    'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

void main() {
  group('SecureDbKeyStore.legacyIOSOptions', () {
    test('lists first_unlock_this_device then unlocked_this_device, both '
        'distinct from the current accessibility', () {
      final accessibilities = SecureDbKeyStore.legacyIOSOptions.map(
        (o) => o.accessibility,
      );
      expect(accessibilities, [
        KeychainAccessibility.first_unlock_this_device,
        KeychainAccessibility.unlocked_this_device,
      ]);
      expect(
        accessibilities,
        isNot(contains(SecureDbKeyStore().storage.iOptions.accessibility)),
      );
    });
  });

  group('SecureDbKeyStore accessibility', () {
    test('is pinned to `unlocked` -- the flutter_secure_storage default, '
        'not a device-pinned accessibility -- because the database file '
        'itself carries no backup exclusion and would otherwise ride an '
        'iCloud backup/restore to a new device while a device-pinned key '
        'never would (docs/ops/ios-export-compliance.md)', () {
      final iOptions = SecureDbKeyStore().storage.iOptions;
      expect(iOptions.accessibility, KeychainAccessibility.unlocked);
    });
  });

  group('getOrCreateDbKey', () {
    test('returns the key found under the current accessibility without '
        'consulting any legacy accessibility', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _current, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(key, _validKey);
      expect(
        backing.readIOptions,
        hasLength(2),
        reason:
            'the journal-resume check, then found on the first storageKey '
            'read; no legacy fallback consulted',
      );
      expect(
        backing.writeIOptions,
        isEmpty,
        reason:
            'a key already under the current accessibility needs no '
            'migration write',
      );
    });

    test('AE (upgrade path): a key stored under first_unlock_this_device is '
        'found, migrated forward through the journal, and future reads see '
        'it directly', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(
        key,
        _validKey,
        reason:
            'the pre-existing key must be reused, not regenerated -- '
            'a fresh key here would quarantine the existing SQLCipher '
            'database',
      );
      expect(
        backing.has(_storageKey, _current),
        isTrue,
        reason: 'migrated forward to the current accessibility',
      );
      expect(
        backing.has(_storageKey, _firstUnlockThisDevice),
        isFalse,
        reason: 'the stale copy under the old accessibility is cleaned up',
      );
      expect(
        backing.has(_journalKey, _current),
        isFalse,
        reason: 'the journal is cleaned up once the migration completes',
      );

      // A second open must not need the legacy fallback (or the journal) at
      // all.
      backing.readIOptions.clear();
      final again = await store.getOrCreateDbKey();
      expect(again, _validKey);
      expect(
        backing.readIOptions,
        hasLength(2),
        reason:
            'the journal-resume check (a miss), then found on the first '
            'storageKey read',
      );
    });

    test('AE (upgrade path): a key stored under unlocked_this_device (this '
        'pull request\'s briefly-shipped, now-reverted accessibility) is '
        'found and migrated forward', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _unlockedThisDevice, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(key, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_storageKey, _unlockedThisDevice), isFalse);
      expect(backing.has(_journalKey, _current), isFalse);
    });

    test('mints a fresh key only when nothing is found under the current, '
        'the journal, or any legacy accessibility', () async {
      final backing = FakeSecureStorage();
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(isValidDbKeyHex(key), isTrue);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(
        backing.readIOptions,
        hasLength(4),
        reason:
            'journal-resume check, current, then both legacy '
            'accessibilities, all miss',
      );
    });

    test('a malformed key found under the current accessibility throws '
        'without falling back to a legacy read', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _current, 'not-hex');
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<CorruptDatabaseKeyError>()),
      );
      expect(
        backing.readIOptions,
        hasLength(2),
        reason: 'the journal-resume check (a miss), then the malformed read',
      );
    });

    test('a malformed key found under a legacy accessibility throws rather '
        'than minting a fresh key or checking further candidates', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _firstUnlockThisDevice, 'not-hex');
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<CorruptDatabaseKeyError>()),
      );
      expect(
        backing.has(_storageKey, _unlockedThisDevice),
        isFalse,
        reason: 'never got as far as checking the next candidate',
      );
      expect(
        backing.writeIOptions,
        isEmpty,
        reason: 'a corrupt key is never migrated or overwritten',
      );
    });

    test('a malformed key found in the migration journal throws, rather '
        'than resuming with corrupt data', () async {
      final backing = FakeSecureStorage()
        ..seed(_journalKey, _current, 'not-hex')
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<CorruptDatabaseKeyError>()),
      );
      expect(
        backing.writeIOptions,
        isEmpty,
        reason: 'a corrupt journal is never overwritten or recovered from',
      );
    });
  });

  group('getOrCreateDbKey migration atomicity (B-2/B-3)', () {
    test('journals the legacy value before deleting it, so a copy always '
        'exists: write(journal), delete(legacy), write(current), '
        'delete(journal), in that order', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      await store.getOrCreateDbKey();

      // The legacy copy is provably still present at the moment the current
      // copy first appears, because the write that created the journal
      // happened before the delete that removed the legacy copy.
      expect(backing.writeIOptions, hasLength(2));
      expect(backing.deleteIOptions, hasLength(2));
    });

    test('a throwing write to the current accessibility (e.g. a '
        'locked-device write) does not lose the key -- it survives in the '
        'journal and is recovered on the next call', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey)
        ..failWriteOnCall = 2; // the write(journal) call succeeds (#1); the
      // final write(current) call (#2) is the one that throws.
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<SimulatedIOFailure>()),
      );

      // Nothing was lost: the journal still has it even though the legacy
      // copy is already gone (delete ran before the failing write).
      expect(backing.has(_journalKey, _current), isTrue);
      expect(backing.has(_storageKey, _current), isFalse);

      // A fresh call (simulating the next app launch) recovers cleanly.
      backing.failWriteOnCall = null;
      final recoveredStore = SecureDbKeyStore(storage: backing);
      final recovered = await recoveredStore.getOrCreateDbKey();

      expect(recovered, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_journalKey, _current), isFalse);
      expect(backing.has(_storageKey, _firstUnlockThisDevice), isFalse);
    });

    test('a process kill equivalent to interruption between the journal '
        'write and the legacy delete is recovered on the next launch',
        () async {
      // Directly construct the on-disk state a kill would leave behind at
      // that point: the journal has the value, the legacy copy is still
      // there too (delete had not run yet), and nothing is under the
      // current accessibility.
      final backing = FakeSecureStorage()
        ..seed(_journalKey, _current, _validKey)
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final recovered = await store.getOrCreateDbKey();

      expect(recovered, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_journalKey, _current), isFalse);
      expect(
        backing.has(_storageKey, _firstUnlockThisDevice),
        isFalse,
        reason: 'resume finishes the interrupted legacy cleanup too',
      );
    });

    test('a process kill equivalent to interruption between the legacy '
        'delete and the final write is recovered on the next launch',
        () async {
      // The legacy copy is already gone; only the journal has the value.
      final backing = FakeSecureStorage()..seed(_journalKey, _current, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final recovered = await store.getOrCreateDbKey();

      expect(recovered, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_journalKey, _current), isFalse);
    });

    test('a process kill equivalent to interruption between the final '
        'write and the journal cleanup just finishes the cleanup, without '
        're-touching the already-correct current value', () async {
      final backing = FakeSecureStorage()
        ..seed(_journalKey, _current, _validKey)
        ..seed(_storageKey, _current, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final recovered = await store.getOrCreateDbKey();

      expect(recovered, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_journalKey, _current), isFalse);
      expect(
        backing.writeIOptions,
        isEmpty,
        reason:
            'the current value was already correct; resume never rewrites '
            'it, only cleans up the journal',
      );
    });

    test('a throwing delete of the legacy copy also survives via the '
        'journal and is recovered on the next call', () async {
      final backing = FakeSecureStorage()
        ..seed(_storageKey, _firstUnlockThisDevice, _validKey)
        ..failDeleteOnCall = 1; // the delete(legacy) call throws.
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<SimulatedIOFailure>()),
      );

      // The journal has it; the legacy copy is (for this failure mode)
      // still present too, since the delete never completed.
      expect(backing.has(_journalKey, _current), isTrue);
      expect(backing.has(_storageKey, _current), isFalse);
      expect(backing.has(_storageKey, _firstUnlockThisDevice), isTrue);

      backing.failDeleteOnCall = null;
      final recoveredStore = SecureDbKeyStore(storage: backing);
      final recovered = await recoveredStore.getOrCreateDbKey();

      expect(recovered, _validKey);
      expect(backing.has(_storageKey, _current), isTrue);
      expect(backing.has(_journalKey, _current), isFalse);
      expect(backing.has(_storageKey, _firstUnlockThisDevice), isFalse);
    });
  });
}
