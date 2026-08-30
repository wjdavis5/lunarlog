/// Pure-Dart, monotonic-safe ULID generation (spec: https://github.com/ulid/spec).
///
/// A ULID is 26 characters of Crockford base32 encoding a 128-bit value:
/// 48 bits of millisecond timestamp + 80 bits of randomness. ULIDs generated
/// by the same [UlidGenerator] are strictly lexicographically sortable and
/// never regress even if the system clock does, which makes them suitable
/// client-generated stable IDs for sync (R15).
library;

import 'dart:math';

const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final RegExp _validUlid = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$');

/// Generates monotonic ULIDs.
class UlidGenerator {
  UlidGenerator({DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final DateTime Function() _clock;
  final Random _random;

  int? _lastTimeMs;
  List<int>? _lastRandomness;

  /// Returns the next ULID. Guaranteed to sort strictly greater than every
  /// ULID previously returned by this generator.
  String next() {
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;

    int timeMs;
    List<int> randomness;
    final lastTime = _lastTimeMs;
    if (lastTime != null && nowMs <= lastTime) {
      // Same millisecond (or a clock regression): increment the previous
      // randomness to stay strictly monotonic.
      timeMs = lastTime;
      randomness = List<int>.of(_lastRandomness!);
      _increment(randomness);
    } else {
      timeMs = nowMs;
      randomness = List<int>.generate(10, (_) => _random.nextInt(256));
    }

    _lastTimeMs = timeMs;
    _lastRandomness = randomness;

    return _encodeTime(timeMs) + _encodeRandomness(randomness);
  }

  static void _increment(List<int> bytes) {
    for (var i = bytes.length - 1; i >= 0; i--) {
      if (bytes[i] < 255) {
        bytes[i]++;
        return;
      }
      bytes[i] = 0;
    }
    // Overflow of 80 bits of randomness within one millisecond (~10^24 ids)
    // is unreachable in practice.
    throw StateError('ULID randomness overflow within one millisecond');
  }

  static String _encodeTime(int timeMs) {
    // 48-bit timestamp -> 10 characters (most significant first).
    final chars = List<int>.filled(10, 0);
    var t = timeMs;
    for (var i = 9; i >= 0; i--) {
      chars[i] = _crockford.codeUnitAt(t & 0x1F);
      t = t >>> 5;
    }
    return String.fromCharCodes(chars);
  }

  static String _encodeRandomness(List<int> bytes) {
    // 80-bit randomness -> exactly 16 characters of 5 bits each.
    final buffer = StringBuffer();
    var bitBuffer = 0;
    var bitCount = 0;
    for (final byte in bytes) {
      bitBuffer = (bitBuffer << 8) | byte;
      bitCount += 8;
      while (bitCount >= 5) {
        bitCount -= 5;
        buffer.write(_crockford[(bitBuffer >> bitCount) & 0x1F]);
      }
    }
    return buffer.toString();
  }
}

/// Whether [id] is a syntactically valid ULID (26 Crockford base32 chars).
bool isValidUlid(String id) => _validUlid.hasMatch(id);

/// The millisecond timestamp encoded in a ULID, or null if [id] is invalid.
int? ulidTimestampMs(String id) {
  if (!isValidUlid(id)) return null;
  var time = 0;
  for (var i = 0; i < 10; i++) {
    final value = _crockford.indexOf(id[i]);
    if (value < 0) return null;
    time = (time << 5) | value;
  }
  return time;
}
