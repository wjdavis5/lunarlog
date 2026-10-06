/// Unit tests for the device-local memory of deleted health-store records
/// (Issue #1561): its storage shape and the three pure operations on it.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';

void main() {
  final at = DateTime.utc(2026, 9, 12, 8);

  test('the key is per profile', () {
    expect(healthImportDeletionsKey('p1'), 'health_import_deleted_p1');
    expect(
      healthImportDeletionsKey('p1'),
      isNot(healthImportDeletionsKey('p2')),
    );
  });

  test('a record is named by its source and its id', () {
    expect(healthImportDeletionId('healthkit', 'rec-1'), 'healthkit|rec-1');
    // Health Connect's key carries a time after an @; it is kept whole.
    expect(
      healthImportDeletionId('health_connect', 'rec-1@1791000000000'),
      'health_connect|rec-1@1791000000000',
    );
  });

  group('decoding', () {
    test('what was encoded reads back, as UTC instants', () {
      final stored = encodeHealthImportDeletions({'healthkit|rec-1': at});
      final decoded = decodeHealthImportDeletions(stored);
      expect(decoded, {'healthkit|rec-1': at});
      expect(decoded.values.single.isUtc, isTrue);
    });

    test('nothing stored, or something unreadable, is nothing remembered',
        () {
      for (final stored in [null, '', 'not json', '[]', '"text"', '7']) {
        expect(decodeHealthImportDeletions(stored), isEmpty, reason: '$stored');
      }
    });

    test('an entry of the wrong shape is skipped, and the rest kept', () {
      final stored = jsonEncode({
        'healthkit|rec-1': at.millisecondsSinceEpoch,
        'healthkit|rec-2': 'yesterday',
        'healthkit|rec-3': null,
        'healthkit|rec-4': 1.5,
      });
      expect(decodeHealthImportDeletions(stored), {'healthkit|rec-1': at});
    });
  });

  test('what is stored says which record and when, and nothing else', () {
    final stored = encodeHealthImportDeletions({'healthkit|rec-1': at});
    expect(jsonDecode(stored), {'healthkit|rec-1': at.millisecondsSinceEpoch});
  });

  test('past the cap the oldest deletions are dropped first', () {
    final many = {
      for (var i = 0; i < kHealthImportDeletionsCap + 5; i++)
        'healthkit|rec-$i': at.add(Duration(minutes: i)),
    };
    final kept = decodeHealthImportDeletions(encodeHealthImportDeletions(many));
    expect(kept, hasLength(kHealthImportDeletionsCap));
    expect(kept.containsKey('healthkit|rec-0'), isFalse);
    expect(kept.containsKey('healthkit|rec-4'), isFalse);
    expect(kept.containsKey('healthkit|rec-5'), isTrue);
    expect(
      kept.containsKey('healthkit|rec-${kHealthImportDeletionsCap + 4}'),
      isTrue,
    );
  });

  group('remembering', () {
    test('a health-store record is added with the moment of deletion', () {
      final after = rememberHealthImportDeletions(
        const {},
        [('healthkit', 'rec-1'), ('apple_health', 'spot-1')],
        at,
      );
      expect(after, {'healthkit|rec-1': at, 'apple_health|spot-1': at});
    });

    test('each health-store source counts', () {
      for (final source in kHealthStoreSources) {
        expect(
          rememberHealthImportDeletions(const {}, [(source, 'r')], at),
          hasLength(1),
          reason: source,
        );
      }
    });

    test('a row she logged herself, one from a file import, and one with no '
        'record id are left out, and then nothing changes', () {
      final before = {'healthkit|rec-1': at};
      final after = rememberHealthImportDeletions(
        before,
        [('manual', null), ('manual', 'x'), ('clue_import', 'c-1'), ('healthkit', null)],
        at.add(const Duration(hours: 1)),
      );
      expect(identical(after, before), isTrue,
          reason: 'the caller writes nothing when nothing was added');
    });

    test('deleting the same record again moves its time forward', () {
      final later = at.add(const Duration(days: 1));
      final after = rememberHealthImportDeletions(
        {'healthkit|rec-1': at},
        [('healthkit', 'rec-1')],
        later,
      );
      expect(after, {'healthkit|rec-1': later});
    });
  });

  test('forgetting a source drops its records and keeps the others', () {
    final before = {
      'healthkit|rec-1': at,
      'healthkit|rec-2': at,
      'apple_health|spot-1': at,
      'health_connect|rec-3@5': at,
    };
    expect(forgetHealthImportSource(before, 'healthkit'), {
      'apple_health|spot-1': at,
      'health_connect|rec-3@5': at,
    });
    expect(forgetHealthImportSource(before, 'clue_import'), before);
    // A source whose name starts another's is not caught by it.
    expect(
      forgetHealthImportSource({'health_connect|r': at}, 'health'),
      {'health_connect|r': at},
    );
  });
}
