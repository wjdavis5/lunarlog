import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/sync/conflict_rules.dart';

/// KTD5 fixture table. The same cases are meant to be mirrored by the
/// server-side pgTAP suite (U2): one rule, two implementations.
void main() {
  final t0 = DateTime.utc(2026, 9, 1, 12, 0, 0, 0, 0);
  final t1 = t0.add(const Duration(microseconds: 1));
  const smaller = '01J0000000000000000000000A';
  const larger = '01J0000000000000000000000B';

  group('compareInstants', () {
    test('compares absolute instants, never renderings', () {
      final plusZero = DateTime.parse('2026-09-01T12:00:00.123+00:00');
      final zulu = DateTime.parse('2026-09-01T12:00:00.123000Z');
      expect(compareInstants(plusZero, zulu), 0);
      expect(sameInstant(plusZero, zulu), isTrue);
      final local = DateTime.utc(2026, 9, 1, 12).toLocal();
      expect(compareInstants(local, DateTime.utc(2026, 9, 1, 12)), 0);
      expect(compareInstants(t0, t1), lessThan(0));
      expect(compareInstants(t1, t0), greaterThan(0));
    });
  });

  group('per-id rule', () {
    final cases = <({String name, DateTime local, DateTime remote, bool remoteWins})>[
      (name: 'remote newer wins', local: t0, remote: t1, remoteWins: true),
      (name: 'local newer wins', local: t1, remote: t0, remoteWins: false),
      (name: 'equal: remote wins', local: t0, remote: t0, remoteWins: true),
      (
        name: 'equal across renderings: remote wins',
        local: DateTime.parse('2026-09-01T12:00:00.123000Z'),
        remote: DateTime.parse('2026-09-01T12:00:00.123+00:00'),
        remoteWins: true,
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(
          remoteWinsById(localUpdatedAt: c.local, remoteUpdatedAt: c.remote),
          c.remoteWins,
        );
      });
    }
  });

  group('same-date rule', () {
    DayEntryCandidate live(String id, DateTime at) =>
        DayEntryCandidate(id: id, updatedAt: at);
    DayEntryCandidate dead(String id, DateTime at) =>
        DayEntryCandidate(id: id, updatedAt: at, deletedAt: at);

    final cases = <({
      String name,
      DayEntryCandidate a,
      DayEntryCandidate b,
      String? winner,
    })>[
      (name: 'newer wins (a)', a: live(larger, t1), b: live(smaller, t0), winner: larger),
      (name: 'newer wins (b)', a: live(smaller, t0), b: live(larger, t1), winner: larger),
      (name: 'equal: smaller ULID wins (a)', a: live(smaller, t0), b: live(larger, t0), winner: smaller),
      (name: 'equal: smaller ULID wins (b)', a: live(larger, t0), b: live(smaller, t0), winner: smaller),
      (name: 'tombstone never competes (a dead)', a: dead(smaller, t1), b: live(larger, t0), winner: larger),
      (name: 'tombstone never competes (b dead)', a: live(larger, t0), b: dead(smaller, t1), winner: larger),
      (name: 'both tombstones: no winner', a: dead(smaller, t1), b: dead(larger, t1), winner: null),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(sameDateWinner(c.a, c.b)?.id, c.winner);
        expect(sameDateWinner(c.b, c.a)?.id, c.winner,
            reason: 'the rule is symmetric');
      });
    }
  });

  group('mergeTags (Issue #3 gap-closure plan, U4/U5) - mirrors '
      'merge_tag_arrays exactly', () {
    test('disjoint inputs return the union, sorted, no duplicates', () {
      expect(mergeTags(['b', 'a'], ['c']), ['a', 'b', 'c']);
    });

    test('overlapping inputs deduplicate', () {
      expect(mergeTags(['a', 'b'], ['b', 'c']), ['a', 'b', 'c']);
    });

    test('empty and single-sided inputs', () {
      expect(mergeTags([], []), <String>[]);
      expect(mergeTags([], ['a']), ['a']);
      expect(mergeTags(['a'], []), ['a']);
    });

    test('is commutative', () {
      expect(mergeTags(['c'], ['b', 'a']), mergeTags(['b', 'a'], ['c']));
    });

    test('is idempotent when applied to its own output (R9)', () {
      final once = mergeTags(['a'], ['b']);
      expect(mergeTags(once, ['a', 'b']), once);
      expect(mergeTags(once, once), once);
    });
  });
}
