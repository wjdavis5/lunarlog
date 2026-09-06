/// `SecureDbKeyStore` (lib/data/db/key_store.dart): the accessibility
/// upgrade path (review findings on PR #86). A key minted under an earlier
/// Keychain accessibility must still be found -- and migrated forward --
/// rather than triggering a fresh mint that would quarantine the existing
/// SQLCipher database (db_factory.dart's `DatabaseQuarantineError`).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/db/key_store.dart';

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
/// would hide this class of bug entirely.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<KeychainAccessibility?, Map<String, String>> _byAccessibility = {};
  final List<AppleOptions?> writeIOptions = [];
  final List<AppleOptions?> readIOptions = [];
  final List<AppleOptions?> deleteIOptions = [];

  KeychainAccessibility? _bucketOf(AppleOptions? options) =>
      options?.accessibility;

  /// Seeds a value directly into the bucket matching [options] (`null` for
  /// the "current accessibility, no override" bucket), bypassing [write] --
  /// simulates a key already persisted by earlier app code before the test
  /// runs.
  void seed(AppleOptions? options, String key, String value) {
    _byAccessibility.putIfAbsent(_bucketOf(options), () => {})[key] = value;
  }

  bool has(AppleOptions? options, String key) =>
      (_byAccessibility[_bucketOf(options)] ?? const {}).containsKey(key);

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
    writeIOptions.add(iOptions);
    final bucket = _byAccessibility.putIfAbsent(_bucketOf(iOptions), () => {});
    if (value == null) {
      bucket.remove(key);
    } else {
      bucket[key] = value;
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
    return _byAccessibility[_bucketOf(iOptions)]?[key];
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
    deleteIOptions.add(iOptions);
    // Account-wide, like the real plugin: `iOptions` is recorded (callers
    // assert on it) but does NOT scope which bucket loses the key -- every
    // bucket does.
    for (final bucket in _byAccessibility.values) {
      bucket.remove(key);
    }
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
final _unlocked = SecureDbKeyStore.legacyIOSOptions[1];

const _storageKey = SecureDbKeyStore.storageKey;

/// 64 lowercase hex characters -- a well-formed database key.
const _validKey =
    'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

void main() {
  group('SecureDbKeyStore.legacyIOSOptions', () {
    test('lists first_unlock_this_device then unlocked, both distinct from '
        'the current accessibility', () {
      final accessibilities = SecureDbKeyStore.legacyIOSOptions.map(
        (o) => o.accessibility,
      );
      expect(accessibilities, [
        KeychainAccessibility.first_unlock_this_device,
        KeychainAccessibility.unlocked,
      ]);
      expect(
        accessibilities,
        isNot(contains(SecureDbKeyStore().storage.iOptions.accessibility)),
      );
    });
  });

  group('getOrCreateDbKey', () {
    test('returns the key found under the current accessibility without '
        'consulting any legacy accessibility', () async {
      final backing = FakeSecureStorage()
        ..seed(_current, _storageKey, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(key, _validKey);
      expect(
        backing.readIOptions,
        hasLength(1),
        reason: 'found on the first read; no legacy fallback consulted',
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
        'found, migrated forward, and future reads see it directly', () async {
      final backing = FakeSecureStorage()
        ..seed(_firstUnlockThisDevice, _storageKey, _validKey);
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
        backing.has(_current, _storageKey),
        isTrue,
        reason: 'migrated forward to the current accessibility',
      );
      expect(
        backing.has(_firstUnlockThisDevice, _storageKey),
        isFalse,
        reason: 'the stale copy under the old accessibility is cleaned up',
      );

      // A second open must not need the legacy fallback at all.
      backing.readIOptions.clear();
      final again = await store.getOrCreateDbKey();
      expect(again, _validKey);
      expect(
        backing.readIOptions,
        hasLength(1),
        reason: 'found on the first (current-accessibility) read',
      );
    });

    test('AE (upgrade path): a key stored under the flutter_secure_storage '
        '`unlocked` default (the pre-PR shipped accessibility) is found and '
        'migrated forward', () async {
      final backing = FakeSecureStorage()
        ..seed(_unlocked, _storageKey, _validKey);
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(key, _validKey);
      expect(backing.has(_current, _storageKey), isTrue);
      expect(backing.has(_unlocked, _storageKey), isFalse);
    });

    test('mints a fresh key only when nothing is found under the current or '
        'any legacy accessibility', () async {
      final backing = FakeSecureStorage();
      final store = SecureDbKeyStore(storage: backing);

      final key = await store.getOrCreateDbKey();

      expect(isValidDbKeyHex(key), isTrue);
      expect(backing.has(_current, _storageKey), isTrue);
      expect(
        backing.readIOptions,
        hasLength(3),
        reason: 'current, then both legacy accessibilities, all miss',
      );
    });

    test('a malformed key found under the current accessibility throws '
        'without falling back to a legacy read', () async {
      final backing = FakeSecureStorage()
        ..seed(_current, _storageKey, 'not-hex');
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<CorruptDatabaseKeyError>()),
      );
      expect(backing.readIOptions, hasLength(1));
    });

    test('a malformed key found under a legacy accessibility throws rather '
        'than minting a fresh key or checking further candidates', () async {
      final backing = FakeSecureStorage()
        ..seed(_firstUnlockThisDevice, _storageKey, 'not-hex');
      final store = SecureDbKeyStore(storage: backing);

      await expectLater(
        store.getOrCreateDbKey(),
        throwsA(isA<CorruptDatabaseKeyError>()),
      );
      expect(
        backing.has(_unlocked, _storageKey),
        isFalse,
        reason: 'never got as far as checking the next candidate',
      );
      expect(
        backing.writeIOptions,
        isEmpty,
        reason: 'a corrupt key is never migrated or overwritten',
      );
    });
  });
}
