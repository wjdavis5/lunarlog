/// Tests for issue #133's symptom-layer query seam (U2): usage ranking,
/// deterministic tie-breaks, default layer selection, and per-day
/// matching.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/symptoms/symptom_layers.dart';

DayEntry _entry(
  String profileId,
  int day, {
  FlowLevel flow = FlowLevel.none,
  List<String> tags = const [],
}) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: LocalDate(2026, 8, day),
  tz: 'America/Chicago',
  flow: flow,
  tags: tags,
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  test('ranks by usage count, most-used first', () {
    final ranked = rankTagUsage([
      _entry('p', 1, tags: const ['headache']),
      _entry('p', 2, tags: const ['headache']),
      _entry('p', 3, tags: const ['cramps']),
      _entry('p', 4),
    ]);
    expect(ranked.map((u) => u.code).toList(), ['headache', 'cramps']);
    expect(ranked.first.count, 2);
    expect(ranked.last.count, 1);
  });

  test('ties break in taxonomy order (deterministic ranking)', () {
    // cramps, headache, fatigue all used twice; taxonomy order is
    // cramps (pain), headache (pain), fatigue (body).
    final ranked = rankTagUsage([
      _entry('p', 1, tags: const ['fatigue']),
      _entry('p', 2, tags: const ['headache']),
      _entry('p', 3, tags: const ['cramps']),
      _entry('p', 4, tags: const ['fatigue', 'headache', 'cramps']),
    ]);
    expect(ranked.map((u) => u.code).toList(), [
      'cramps',
      'headache',
      'fatigue',
    ]);
  });

  test('one day with several tags counts each tag once', () {
    final ranked = rankTagUsage([
      _entry('p', 1, tags: const ['cramps', 'headache']),
    ]);
    expect(ranked.map((u) => (u.code, u.count)).toList(), [
      ('cramps', 1),
      ('headache', 1),
    ]);
  });

  test('tombstoned entries are skipped', () {
    final ranked = rankTagUsage([
      DayEntry(
        id: '',
        profileId: 'p',
        localDate: LocalDate(2026, 8, 1),
        tz: 'America/Chicago',
        flow: FlowLevel.none,
        tags: const ['headache'],
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: DateTime.utc(2026, 1, 2),
      ),
      _entry('p', 2, tags: const ['cramps']),
    ]);
    expect(ranked.map((u) => u.code).toList(), ['cramps']);
  });

  test('unknown codes rank after known ones and keep their code', () {
    final ranked = rankTagUsage([
      _entry('p', 1, tags: const ['not_a_tag']),
      _entry('p', 2, tags: const ['cramps']),
    ]);
    expect(ranked.map((u) => u.code).toList(), ['cramps', 'not_a_tag']);
    expect(ranked.last.display, 'not_a_tag');
  });

  test('defaults take at most the three most-used tags', () {
    final defaults = defaultLayerTags([
      _entry('p', 1, tags: const ['headache']),
      _entry('p', 2, tags: const ['headache']),
      _entry('p', 3, tags: const ['headache']),
      _entry('p', 4, tags: const ['cramps']),
      _entry('p', 5, tags: const ['cramps']),
      _entry('p', 6, tags: const ['fatigue']),
      _entry('p', 7, tags: const ['fatigue']),
      _entry('p', 8, tags: const ['bloating']),
    ]);
    expect(defaults, ['headache', 'cramps', 'fatigue']);
  });

  test('defaults shrink with thinner usage and start empty', () {
    expect(
      defaultLayerTags([
        _entry('p', 1, tags: const ['cramps']),
      ]),
      ['cramps'],
    );
    expect(defaultLayerTags([_entry('p', 1)]), isEmpty);
    expect(defaultLayerTags(const []), isEmpty);
    expect(kMaxSymptomLayers, 3);
  });

  test('layerMatches is per-tag and skips absent or tombstoned days', () {
    final live = _entry('p', 1, tags: const ['cramps', 'fatigue']);
    final tombstoned = DayEntry(
      id: '',
      profileId: 'p',
      localDate: LocalDate(2026, 8, 2),
      tz: 'America/Chicago',
      flow: FlowLevel.none,
      tags: const ['cramps'],
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: DateTime.utc(2026, 1, 2),
    );
    expect(layerMatches(live, 'cramps'), isTrue);
    expect(layerMatches(live, 'headache'), isFalse);
    expect(layerMatches(null, 'cramps'), isFalse);
    expect(layerMatches(tombstoned, 'cramps'), isFalse);
  });
}
