/// PBKDF2-HMAC-SHA256 (RFC 8018 §5.2) built on `crypto`'s [Hmac] — the
/// project carries no dedicated KDF package, and PBKDF2-HMAC-SHA256 needs
/// nothing more than what `crypto` (already a dependency, used elsewhere for
/// the Google Sign-In nonce hash) already provides.
///
/// Used only to hash the in-app PIN before it touches secure storage
/// (issue #271 D-2) — the PIN itself is never stored. This is deliberately
/// not a general-purpose password KDF: a short numeric PIN's dominant
/// defense is [PinCredentialStore]'s escalating lockout backoff, not the
/// hash's per-guess cost alone, so a moderate, fast-enough-for-every-unlock
/// iteration count is the right trade-off here.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// OWASP's 2023 minimum recommendation for PBKDF2-HMAC-SHA256.
const int kPbkdf2DefaultIterations = 210000;

/// 256 bits — matches SHA-256's own output size, so a single block covers
/// every call site in this app.
const int kPbkdf2DefaultKeyLengthBytes = 32;

/// Derives a [keyLengthBytes]-byte key from [password] and [salt] using
/// [iterations] rounds of HMAC-SHA256, per RFC 8018 §5.2's `PBKDF2` function.
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  int iterations = kPbkdf2DefaultIterations,
  int keyLengthBytes = kPbkdf2DefaultKeyLengthBytes,
}) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
  }
  if (keyLengthBytes < 1) {
    throw ArgumentError.value(keyLengthBytes, 'keyLengthBytes', 'must be >= 1');
  }
  const hashLengthBytes = 32; // SHA-256 output size.
  final blockCount = (keyLengthBytes / hashLengthBytes).ceil();
  final hmac = Hmac(sha256, password);
  final derived = BytesBuilder();
  for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
    derived.add(_deriveBlock(hmac, salt, blockIndex, iterations));
  }
  return Uint8List.fromList(derived.toBytes().sublist(0, keyLengthBytes));
}

/// RFC 8018's `F(P, S, c, i)`: `U1 = PRF(P, S || INT(i))`,
/// `U_j = PRF(P, U_(j-1))` for `j = 2..c`, result = `U1 XOR U2 XOR ... XOR Uc`.
List<int> _deriveBlock(
  Hmac hmac,
  List<int> salt,
  int blockIndex,
  int iterations,
) {
  final blockIndexBytes = ByteData(4)..setUint32(0, blockIndex, Endian.big);
  var u = hmac.convert([...salt, ...blockIndexBytes.buffer.asUint8List()]).bytes;
  final block = List<int>.from(u);
  for (var round = 1; round < iterations; round++) {
    u = hmac.convert(u).bytes;
    for (var byteIndex = 0; byteIndex < block.length; byteIndex++) {
      block[byteIndex] ^= u[byteIndex];
    }
  }
  return block;
}

/// Constant-time byte comparison — never short-circuits on the first
/// mismatch, so verifying a wrong PIN takes the same time regardless of how
/// many leading bytes happened to match.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
