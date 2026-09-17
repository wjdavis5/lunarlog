import 'package:flutter_test/flutter_test.dart';

import '../../../tool/seed_test_accounts/state_store.dart';

void main() {
  group('round-trip', () {
    test('encode/parse preserves records and ids', () {
      final state = SeedState(runs: {
        'seed.e2e.local@example.com': SeedStateRecord(
          targetEmail: 'seed.e2e.local@example.com',
          partnerEmail: 'seed.partner@example.com',
          profileIds: const ['01ARZ3NDEKTSV4RRFFQ69G5AAA', '01ARZ3NDEKTSV4RRFFQ69G5AAB'],
          retiredProfileIds: const ['01ARZ3NDEKTSV4RRFFQ69G5AAC'],
          months: 18,
          seed: 42,
          targetUserId: 'uid-1',
          partnerUserId: 'uid-2',
        ),
      });
      final parsed = SeedState.parse(state.encode());
      final record =
          parsed.runs['seed.e2e.local@example.com']!;
      expect(record.profileIds, hasLength(2));
      expect(record.retiredProfileIds, ['01ARZ3NDEKTSV4RRFFQ69G5AAC']);
      expect(record.months, 18);
      expect(record.seed, 42);
      expect(record.partnerEmail, 'seed.partner@example.com');
    });

    test('empty content parses to empty state', () {
      expect(SeedState.parse('').runs, isEmpty);
      expect(SeedState.parse('  \n').runs, isEmpty);
    });
  });

  group('allowedProfileIdsFor (the foreign-profile guard input)', () {
    test('an account sees ids from records where it is target OR partner', () {
      final state = SeedState(runs: {
        'a@example.com': SeedStateRecord(
          targetEmail: 'a@example.com',
          partnerEmail: 'b@example.com',
          profileIds: const ['A1', 'A2'],
          months: 18,
          seed: 1,
        ),
        'c@example.com': SeedStateRecord(
          targetEmail: 'c@example.com',
          partnerEmail: 'd@example.com',
          profileIds: const ['C1'],
          months: 18,
          seed: 1,
        ),
      });
      expect(state.allowedProfileIdsFor('a@example.com'), {'A1', 'A2'});
      expect(state.allowedProfileIdsFor('B@Example.com'), {'A1', 'A2'});
      expect(state.allowedProfileIdsFor('d@example.com'), {'C1'});
      expect(state.allowedProfileIdsFor('nobody@example.com'), isEmpty);
    });

    test('retired ids stay recognized across resets', () {
      final state = SeedState(runs: {
        'a@example.com': SeedStateRecord(
          targetEmail: 'a@example.com',
          partnerEmail: 'b@example.com',
          profileIds: const [],
          retiredProfileIds: const ['OLD1'],
          months: 18,
          seed: 1,
        ),
      });
      expect(state.allowedProfileIdsFor('a@example.com'), {'OLD1'});
    });
  });
}
