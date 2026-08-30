import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/ulid.dart';

void main() {
  group('UlidGenerator', () {
    test('produces 26-character Crockford base32 strings', () {
      final gen = UlidGenerator();
      for (var i = 0; i < 100; i++) {
        final id = gen.next();
        expect(isValidUlid(id), isTrue, reason: '$id should be a valid ULID');
      }
    });

    test('encodes the creation timestamp in the first 10 characters', () {
      final before = DateTime.now().toUtc().millisecondsSinceEpoch;
      final id = UlidGenerator().next();
      final after = DateTime.now().toUtc().millisecondsSinceEpoch;
      final ts = ulidTimestampMs(id);
      expect(ts, isNotNull);
      expect(ts! >= before, isTrue);
      expect(ts <= after, isTrue);
    });

    test('rapid generation is strictly monotonic (sortable)', () {
      final gen = UlidGenerator();
      var previous = gen.next();
      for (var i = 0; i < 1000; i++) {
        final next = gen.next();
        expect(next.compareTo(previous), greaterThan(0),
            reason: 'ULIDs generated later must sort greater');
        previous = next;
      }
    });

    test('same millisecond (fixed clock) still yields strictly increasing ids',
        () {
      final fixed = DateTime.utc(2026, 1, 1);
      final gen = UlidGenerator(clock: () => fixed);
      var previous = gen.next();
      final seen = <String>{previous};
      for (var i = 0; i < 500; i++) {
        final next = gen.next();
        expect(next.compareTo(previous), greaterThan(0));
        expect(seen.add(next), isTrue, reason: 'ids must be unique');
        previous = next;
      }
    });

    test('clock regression does not produce smaller ids', () {
      var now = DateTime.utc(2026, 6, 1, 12);
      final gen = UlidGenerator(clock: () => now);
      final a = gen.next();
      // Clock jumps backwards mid-process.
      now = DateTime.utc(2026, 5, 1);
      final b = gen.next();
      expect(b.compareTo(a), greaterThan(0),
          reason: 'monotonic-safe ULIDs never regress, even if the clock does');
    });

    test('independent generators produce different ids', () {
      final fixed = DateTime.utc(2026, 3, 3);
      final a = UlidGenerator(clock: () => fixed);
      final b = UlidGenerator(clock: () => fixed);
      expect(a.next(), isNot(equals(b.next())));
    });
  });

  group('isValidUlid', () {
    test('accepts a generated ULID', () {
      expect(isValidUlid(UlidGenerator().next()), isTrue);
    });

    test('rejects wrong length', () {
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FA'), isFalse);
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAVV'), isFalse);
    });

    test('rejects non-Crockford characters', () {
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAI'), isFalse); // I excluded
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAL'), isFalse); // L excluded
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAO'), isFalse); // O excluded
      expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAU'), isFalse); // U excluded
      expect(isValidUlid('01arz3ndektsv4rrffq69g5fav'), isFalse); // lowercase
      expect(isValidUlid(''), isFalse);
    });
  });
}
