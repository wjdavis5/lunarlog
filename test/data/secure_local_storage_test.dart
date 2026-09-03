/// U4 (KTD7, R5): the Supabase session and PKCE verifier live in
/// flutter_secure_storage with the device-bound iOS Keychain class, never
/// in SharedPreferences. The fake asserts the option on every write.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/secure_local_storage.dart';

/// In-memory stand-in for [FlutterSecureStorage]; records the options each
/// call carried so the test can assert the Keychain accessibility class.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  final List<AppleOptions?> writeIOptions = [];
  final List<AndroidOptions?> writeAOptions = [];
  final List<AppleOptions?> readIOptions = [];
  final List<AppleOptions?> deleteIOptions = [];
  final List<AppleOptions?> containsIOptions = [];

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
    writeAOptions.add(aOptions);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
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
    return values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    containsIOptions.add(iOptions);
    return values.containsKey(key);
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
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const deviceBound = KeychainAccessibility.first_unlock_this_device;

void main() {
  late FakeSecureStorage backing;
  late SecureLocalStorage storage;

  setUp(() {
    backing = FakeSecureStorage();
    storage = SecureLocalStorage(storage: backing);
  });

  test('session round-trips through persistSession / accessToken / '
      'hasAccessToken / removePersistedSession', () async {
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);

    await storage.persistSession('{"access_token":"abc"}');
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), '{"access_token":"abc"}');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('PKCE items round-trip through the GotrueAsyncStorage surface',
      () async {
    const key = 'supabase.auth.token-code-verifier';
    expect(await storage.getItem(key: key), isNull);
    await storage.setItem(key: key, value: 'verifier/passwordRecovery');
    expect(await storage.getItem(key: key), 'verifier/passwordRecovery');
    await storage.removeItem(key: key);
    expect(await storage.getItem(key: key), isNull);
  });

  test('every write carries the first_unlock_this_device iOS option and the '
      'default Android encrypted-preferences options', () async {
    await storage.persistSession('s');
    await storage.setItem(key: 'k', value: 'v');
    expect(backing.writeIOptions, hasLength(2));
    for (final options in backing.writeIOptions) {
      expect(options, isNotNull);
      expect(options!.accessibility, deviceBound);
      expect(options.synchronizable, isFalse,
          reason: 'never synced to iCloud Keychain');
    }
    for (final options in backing.writeAOptions) {
      expect(options, isNotNull);
    }
  });

  test('reads, deletes, and existence checks use the same Keychain class so '
      'the items are found again', () async {
    await storage.persistSession('s');
    await storage.accessToken();
    await storage.hasAccessToken();
    await storage.getItem(key: 'k');
    await storage.removePersistedSession();
    await storage.removeItem(key: 'k');
    final all = [
      ...backing.readIOptions,
      ...backing.containsIOptions,
      ...backing.deleteIOptions,
    ];
    expect(all, hasLength(5));
    for (final options in all) {
      expect(options?.accessibility, deviceBound);
    }
  });

  test('session and PKCE keys are namespaced and distinct', () async {
    await storage.persistSession('session');
    await storage.setItem(key: 'session', value: 'pkce');
    expect(backing.values.keys, hasLength(2));
    expect(backing.values.keys.every((k) => k.startsWith('lunarlog.')),
        isTrue);
    expect(await storage.accessToken(), 'session');
    expect(await storage.getItem(key: 'session'), 'pkce');
  });

  test('default construction builds a real FlutterSecureStorage with the '
      'device-bound options', () {
    final real = SecureLocalStorage();
    expect(real.iosOptions.accessibility, deviceBound);
    expect(real.iosOptions.synchronizable, isFalse);
  });
}
