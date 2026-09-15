/// [pbkdf2HmacSha256] (issue #271 D-2): RFC 8018 test-vector conformance
/// plus the properties [PinCredentialStore] actually relies on (determinism,
/// salt/password/iteration sensitivity, requested output length) and
/// [constantTimeEquals]'s comparison semantics.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/gate/pbkdf2.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2HmacSha256', () {
    // Widely-cited PBKDF2-HMAC-SHA256 test vectors (used across multiple
    // independent implementations' own test suites, e.g. Go's
    // golang.org/x/crypto/pbkdf2 and Python's hazmat KDF tests).
    test('matches the c=1 PBKDF2-HMAC-SHA256 test vector', () {
      final result = pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLengthBytes: 32,
      );
      expect(
        hex(result),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('matches the c=2 PBKDF2-HMAC-SHA256 test vector', () {
      final result = pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 2,
        keyLengthBytes: 32,
      );
      expect(
        hex(result),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('is deterministic for the same inputs', () {
      final a = pbkdf2HmacSha256(
          password: utf8.encode('1234'), salt: utf8.encode('salt-a'));
      final b = pbkdf2HmacSha256(
          password: utf8.encode('1234'), salt: utf8.encode('salt-a'));
      expect(hex(a), hex(b));
    });

    test('a different password changes the output', () {
      final a = pbkdf2HmacSha256(
          password: utf8.encode('1234'), salt: utf8.encode('salt-a'));
      final b = pbkdf2HmacSha256(
          password: utf8.encode('4321'), salt: utf8.encode('salt-a'));
      expect(hex(a), isNot(hex(b)));
    });

    test('a different salt changes the output (defeats a shared rainbow table)',
        () {
      final a = pbkdf2HmacSha256(
          password: utf8.encode('1234'), salt: utf8.encode('salt-a'));
      final b = pbkdf2HmacSha256(
          password: utf8.encode('1234'), salt: utf8.encode('salt-b'));
      expect(hex(a), isNot(hex(b)));
    });

    test('a different iteration count changes the output', () {
      final a = pbkdf2HmacSha256(
          password: utf8.encode('1234'),
          salt: utf8.encode('salt-a'),
          iterations: 1000);
      final b = pbkdf2HmacSha256(
          password: utf8.encode('1234'),
          salt: utf8.encode('salt-a'),
          iterations: 1001);
      expect(hex(a), isNot(hex(b)));
    });

    test('returns exactly the requested key length, spanning multiple blocks',
        () {
      final result = pbkdf2HmacSha256(
        password: utf8.encode('1234'),
        salt: utf8.encode('salt'),
        iterations: 10,
        keyLengthBytes: 50, // > one SHA-256 block (32 bytes)
      );
      expect(result.length, 50);
    });

    test('rejects a non-positive iteration count or key length', () {
      expect(
        () => pbkdf2HmacSha256(password: [1], salt: [2], iterations: 0),
        throwsArgumentError,
      );
      expect(
        () => pbkdf2HmacSha256(
            password: [1], salt: [2], keyLengthBytes: 0),
        throwsArgumentError,
      );
    });
  });

  group('constantTimeEquals', () {
    test('true for identical byte lists', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('false for a different length', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });

    test('false for a single differing byte anywhere in the list', () {
      expect(constantTimeEquals([1, 2, 3], [1, 9, 3]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [9, 2, 3]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 9]), isFalse);
    });

    test('true for two empty lists', () {
      expect(constantTimeEquals(<int>[], <int>[]), isTrue);
    });
  });
}
