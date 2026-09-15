/// [PinCredentialStore] (issue #271 D-2, D-6): the PIN is hashed (never
/// stored raw), and the escalating lockout backoff. [pbkdf2Test.dart]
/// covers the KDF itself; this suite exercises the store's own contract
/// against an in-memory fake of `FlutterSecureStorage`, mirroring
/// `test/data/secure_local_storage_test.dart`'s fake shape.
///
/// Every test below (other than the dedicated "production wiring" group)
/// injects [_fastPbkdf2Runner] instead of the real, isolate-hopping
/// [defaultPbkdf2Runner] — it runs synchronously, in-process, at a
/// deliberately low round count, so this suite's many lockout-loop tests
/// (several `setPin`/`verifyPin` calls each) stay fast. This never touches
/// [kPbkdf2DefaultIterations] itself: [PinCredentialStore.setPin] always
/// requests that exact count from whichever runner is configured — a test
/// runner is simply free to ignore the round count it's asked for, the way
/// [_fastPbkdf2Runner] does, precisely so a test never has to (and never
/// does) turn that production constant down to get a fast suite.
library;

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/gate/pbkdf2.dart';
import 'package:lunarlog/data/gate/pin_credential_store.dart';
import 'package:lunarlog/domain/gate/pin_credential_service.dart';

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

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
  }) async =>
      values[key];

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A fast, synchronous, in-process [Pbkdf2Runner] for this suite (see the
/// library doc comment above): always hashes at [_fastTestIterations]
/// rounds, whatever [iterations] it's actually called with — so [setPin]'s
/// hard-coded [kPbkdf2DefaultIterations] request never slows this suite
/// down, while `setPin`/`verifyPin` still stay internally consistent (both
/// go through this same substitution, so a correct PIN still verifies and
/// a wrong one still doesn't).
const int _fastTestIterations = 10;

Future<Uint8List> _fastPbkdf2Runner({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int keyLengthBytes,
}) async =>
    pbkdf2HmacSha256(
      password: password,
      salt: salt,
      iterations: _fastTestIterations,
      keyLengthBytes: keyLengthBytes,
    );

void main() {
  late FakeSecureStorage backing;
  late DateTime now;
  late PinCredentialStore store;

  setUp(() {
    backing = FakeSecureStorage();
    now = DateTime(2026, 1, 1, 12);
    store = PinCredentialStore(
      storage: backing,
      now: () => now,
      derive: _fastPbkdf2Runner,
    );
  });

  test('no PIN set initially', () async {
    expect(await store.isPinSet(), isFalse);
  });

  test('the raw PIN is never stored — only a salted hash', () async {
    await store.setPin('1234');
    expect(await store.isPinSet(), isTrue);
    for (final value in backing.values.values) {
      expect(value.contains('1234'), isFalse,
          reason: 'the plaintext PIN must never appear in stored values');
    }
  });

  test('setPin then verifyPin with the same PIN succeeds', () async {
    await store.setPin('1234');
    final result = await store.verifyPin('1234');
    expect(result.outcome, PinCheckOutcome.correct);
  });

  test('verifyPin with a different PIN fails', () async {
    await store.setPin('1234');
    final result = await store.verifyPin('0000');
    expect(result.outcome, PinCheckOutcome.incorrect);
  });

  test('two PinCredentialStores over the same storage use different salts '
      'for the same PIN', () async {
    final backingA = FakeSecureStorage();
    final storeA =
        PinCredentialStore(storage: backingA, derive: _fastPbkdf2Runner);
    final backingB = FakeSecureStorage();
    final storeB =
        PinCredentialStore(storage: backingB, derive: _fastPbkdf2Runner);
    await storeA.setPin('1234');
    await storeB.setPin('1234');
    expect(
      backingA.values['lunarlog.pin.credential'],
      isNot(backingB.values['lunarlog.pin.credential']),
      reason: 'a random salt must make the same PIN hash differently each '
          'time it is set',
    );
  });

  test('clearPin removes the PIN and lockout state', () async {
    await store.setPin('1234');
    await store.verifyPin('wrong'); // records a failed attempt
    await store.clearPin();

    expect(await store.isPinSet(), isFalse);
    final lockout = await store.lockoutState();
    expect(lockout.lockedUntil, isNull);
  });

  test('setPin replaces an existing PIN and clears any lockout', () async {
    await store.setPin('1111');
    for (var i = 0; i < kPinFreeAttempts; i++) {
      await store.verifyPin('wrong');
    }
    await store.setPin('2222');

    expect((await store.verifyPin('1111')).outcome, PinCheckOutcome.incorrect,
        reason: 'the old PIN must no longer verify');
    expect((await store.verifyPin('2222')).outcome, PinCheckOutcome.correct);
  });

  group('lockout backoff (#271 D-6)', () {
    test('the first kPinFreeAttempts wrong guesses are not locked out',
        () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts; i++) {
        final result = await store.verifyPin('wrong');
        expect(result.outcome, PinCheckOutcome.incorrect);
        expect(result.remainingFreeAttempts, kPinFreeAttempts - (i + 1));
      }
    });

    test('the attempt after kPinFreeAttempts locks out for the first tier',
        () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts; i++) {
        await store.verifyPin('wrong');
      }
      final result = await store.verifyPin('wrong');

      expect(result.outcome, PinCheckOutcome.lockedOut);
      expect(result.lockedUntil, now.add(kPinLockoutSchedule[0]));
    });

    test('a guess made while locked out is refused without checking the '
        'stored hash, and does not extend the lockout', () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await store.verifyPin('wrong');
      }
      final lockedUntil = (await store.lockoutState()).lockedUntil;

      // Even the *correct* PIN is refused while locked out.
      final result = await store.verifyPin('1234');

      expect(result.outcome, PinCheckOutcome.lockedOut);
      expect(result.lockedUntil, lockedUntil,
          reason: 'a guess while locked out must not extend the lockout');
    });

    test('lockout escalates through the schedule on repeated failures after '
        'the lockout window has passed', () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await store.verifyPin('wrong');
      }
      // Time passes beyond the first lockout tier.
      now = now.add(kPinLockoutSchedule[0]).add(const Duration(seconds: 1));
      final result = await store.verifyPin('wrong');

      expect(result.outcome, PinCheckOutcome.lockedOut);
      expect(result.lockedUntil, now.add(kPinLockoutSchedule[1]),
          reason: 'the next failure after the first tier expires must '
              'escalate to the second tier');
    });

    test('the schedule caps at its last (longest) entry', () async {
      await store.setPin('1234');
      // Drive far past every tier, always waiting out the lockout in
      // between so each guess is actually checked (and recorded as a new
      // failure) rather than refused outright.
      for (var i = 0; i < kPinFreeAttempts + kPinLockoutSchedule.length + 3; i++) {
        final lockout = await store.lockoutState();
        if (lockout.lockedUntil != null) {
          now = lockout.lockedUntil!.add(const Duration(seconds: 1));
        }
        await store.verifyPin('wrong');
      }
      final result = await store.verifyPin('wrong');

      expect(
        result.lockedUntil,
        isNot(isNull),
      );
      final remaining = result.lockedUntil!.difference(now);
      expect(remaining, kPinLockoutSchedule.last,
          reason: 'lockout duration must never exceed the schedule\'s last '
              'entry, however many failures accumulate');
    });

    test('a correct guess clears the lockout state entirely', () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts; i++) {
        await store.verifyPin('wrong');
      }
      await store.verifyPin('1234'); // correct, still within free attempts

      final lockout = await store.lockoutState();
      expect(lockout.lockedUntil, isNull);
      // A fresh run of free attempts is available again.
      final result = await store.verifyPin('wrong');
      expect(result.outcome, PinCheckOutcome.incorrect);
      expect(result.remainingFreeAttempts, kPinFreeAttempts - 1);
    });

    test('lockoutState reports the lockout without attempting a verification',
        () async {
      await store.setPin('1234');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await store.verifyPin('wrong');
      }

      final lockout = await store.lockoutState();

      expect(lockout.lockedUntil, isNotNull);
      expect(lockout.isLockedOutAt(now), isTrue);
      expect(
        lockout.isLockedOutAt(lockout.lockedUntil!.add(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });

  group('production wiring (off-UI-isolate PBKDF2)', () {
    test(
        'defaultPbkdf2Runner (the real, isolate-hopping runner) returns the '
        'same digest as calling pbkdf2HmacSha256 directly', () async {
      final direct = pbkdf2HmacSha256(
        password: [1, 2, 3],
        salt: [4, 5, 6],
        iterations: 1000,
        keyLengthBytes: 32,
      );

      final viaIsolate = await defaultPbkdf2Runner(
        password: [1, 2, 3],
        salt: [4, 5, 6],
        iterations: 1000,
        keyLengthBytes: 32,
      );

      expect(viaIsolate, direct,
          reason: 'crossing the isolate boundary must not change the '
              'digest — only plain List<int>/int data crosses it');
    });

    test(
        'a PinCredentialStore built with no explicit derive: uses the real '
        'production runner and the fixed default iteration count, end to '
        'end (setPin -> verifyPin, off the UI isolate)', () async {
      final backing = FakeSecureStorage();
      // No `derive:` override — this is the exact production default,
      // including the real Isolate.run hop and the real 210,000-round
      // count (kPbkdf2DefaultIterations), so this one test is deliberately
      // slower than the rest of the suite.
      final productionStore = PinCredentialStore(storage: backing);

      await productionStore.setPin('4242');
      final stored = backing.values['lunarlog.pin.credential']!;
      expect(stored, contains('"iterations":$kPbkdf2DefaultIterations'),
          reason: 'the production default must never be silently lowered');

      final correct = await productionStore.verifyPin('4242');
      final wrong = await productionStore.verifyPin('0000');

      expect(correct.outcome, PinCheckOutcome.correct);
      expect(wrong.outcome, PinCheckOutcome.incorrect);
    });
  });
}
