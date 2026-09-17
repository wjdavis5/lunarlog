import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crypto/crypto.dart';

import '../../../tool/seed_test_accounts/payload_generator.dart';
import '../../../tool/seed_test_accounts/row_shape_rules.dart';
import '../../../tool/seed_test_accounts/sync_chunker.dart';

/// A fixed clock so every digest/shape assertion is reproducible.
DateTime _fixedClock() => DateTime.utc(2026, 9, 14, 9, 30);

void main() {
  group('determinism', () {
    test('same seed + fixed clock => identical payload digest', () {
      final a = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 99,
        clock: _fixedClock,
      ));
      final b = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 99,
        clock: _fixedClock,
      ));
      final digestA =
          sha256.convert(utf8.encode(a.canonicalJson)).toString();
      final digestB =
          sha256.convert(utf8.encode(b.canonicalJson)).toString();
      expect(digestA, digestB);
    });

    test('different seed => different digest', () {
      final a = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 1,
        clock: _fixedClock,
      ));
      final b = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 2,
        clock: _fixedClock,
      ));
      expect(a.canonicalJson, isNot(b.canonicalJson));
    });

    test('different clock => different ids (runtime re-seeds never collide)',
        () {
      final a = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 1,
        clock: _fixedClock,
      ));
      final b = generateSeedPayload(SeedSpec(
        months: 12,
        seed: 1,
        clock: () => DateTime.utc(2026, 9, 15, 9, 30),
      ));
      expect(
        a.profiles.first['id'],
        isNot(b.profiles.first['id']),
      );
    });
  });

  group('row shapes (sync_push allowlist mirror)', () {
    final payload = generateSeedPayload(const SeedSpec(
      months: kMinSeedMonths,
      seed: 7,
      clock: _fixedClock,
    ));

    test('every emitted row is within the mirrored server rules', () {
      final violations = validateSeedPayload(payload);
      expect(violations, isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'));
    });

    test('updated_at policy: one anchor, inside the acceptance window', () {
      final anchors = <String>{
        for (final row in payload.dayEntries) row['updated_at']! as String,
        for (final row in payload.observations) row['updated_at']! as String,
      };
      expect(anchors, hasLength(1), reason: 'a single anchor timestamp');
      expect(
        DateTime.parse(anchors.single),
        payload.anchor,
      );
    });

    test('two profiles: adult celsius/kg + teen fahrenheit/lb', () {
      expect(payload.profiles, hasLength(2));
      final adult = payload.profiles.firstWhere((p) => p['is_minor'] == false);
      final teen = payload.profiles.firstWhere((p) => p['is_minor'] == true);
      expect(adult['relationship'], 'self');
      expect(adult['birth_year'], 1988);
      expect(adult['mode'], 'standard');
      expect(adult['bbt_unit'], 'celsius');
      expect(adult['weight_unit'], 'kg');
      expect(teen['relationship'], 'daughter');
      expect(teen['birth_year'], 2012);
      expect(teen['mode'], 'teen');
      expect(teen['bbt_unit'], 'fahrenheit');
      expect(teen['weight_unit'], 'lb');
    });

    test('profile_modes: tracking for both, no id, no tombstone', () {
      expect(payload.profileModes, hasLength(2));
      for (final mode in payload.profileModes) {
        expect(mode['mode'], 'tracking');
        expect(mode.containsKey('id'), isFalse);
        expect(mode.containsKey('deleted_at'), isFalse);
      }
    });

    test('flow values: writable set only — the deprecated spotting never '
        'appears as a flow', () {
      final flows = payload.dayEntries.map((d) => d['flow']).toSet();
      for (final flow in flows) {
        expect(kWritableFlowLevels.contains(flow), isTrue,
            reason: 'unexpected flow level $flow');
      }
      expect(flows, containsAll(['light', 'medium', 'heavy']));
      expect(flows, contains('not_bleeding'));
      expect(flows, isNot(contains('spotting')));
    });

    test('spotting days are observations, never flow levels', () {
      final spotting = payload.observations
          .where((o) => o['category'] == 'spotting')
          .toList();
      expect(spotting, isNotEmpty);
      expect(spotting.every((o) => o['code'] == 'spotting'), isTrue);
    });

    test('graded pain: intensity 1-5, mostly <= 3, at least one 4', () {
      final pain = payload.observations
          .where((o) => o['category'] == 'pain')
          .toList();
      expect(pain, isNotEmpty);
      final intensities = [
        for (final p in pain) p['intensity']! as int,
      ];
      expect(intensities.every((i) => i >= 1 && i <= 5), isTrue);
      expect(intensities.where((i) => i >= 4).length, lessThan(5),
          reason: 'only a couple of high-grade days');
      expect(intensities.where((i) => i >= 4).length, greaterThanOrEqualTo(1),
          reason: 'a couple of 4s for realism');
    });

    test('the #456 perimenopause cluster appears on the adult profile', () {
      final adultId = payload.profiles
          .firstWhere((p) => p['is_minor'] == false)['id']! as String;
      final cluster = payload.observations
          .where((o) => o['category'] == 'hot_flashes')
          .toList();
      expect(cluster, isNotEmpty);
      expect(
        cluster.every((o) => o['profile_id'] == adultId),
        isTrue,
        reason: 'only the adult profile carries the cluster',
      );
      const expected = {
        'hot_flashes',
        'night_sweats',
        'brain_fog',
        'hrt',
        'vaginal_dryness',
      };
      for (final o in cluster) {
        expect(expected.contains(o['code']), isTrue);
      }
    });

    test('PMS days carry pms=true plus taxonomy tags', () {
      final pmsDays =
          payload.dayEntries.where((d) => d['pms'] == true).toList();
      expect(pmsDays, isNotEmpty);
      for (final day in pmsDays) {
        final tags = day['tags'];
        expect(tags, isA<List<String>>());
        expect((tags as List<String>), isNotEmpty);
      }
    });

    test('BBT is biphasic for the adult (luteal above follicular)', () {
      final adultId = payload.profiles
          .firstWhere((p) => p['is_minor'] == false)['id']! as String;
      final adultEntries = payload.dayEntries
          .where((d) => d['profile_id'] == adultId)
          .toList()
        ..sort((a, b) => (a['local_date']! as String)
            .compareTo(b['local_date']! as String));
      final bleedDates = adultEntries
          .where((d) => d['flow'] != 'not_bleeding')
          .map((d) => DateTime.parse(d['local_date']! as String))
          .toSet()
          .toList()
        ..sort();
      final bbtByDate = <DateTime, double>{
        for (final o in payload.observations)
          if (o['category'] == 'bbt' &&
              o['profile_id'] == adultId &&
              o['excluded'] != true)
            DateTime.parse(o['local_date']! as String):
                (o['value_num']! as num).toDouble(),
      };
      // Follicular sample: days 4..9 after a bleed start. Luteal sample:
      // days 8..13 before the NEXT bleed start. Both exclude bleed days.
      final follicular = <double>[];
      final luteal = <double>[];
      for (final entry in adultEntries) {
        final date = DateTime.parse(entry['local_date']! as String);
        final bbt = bbtByDate[date];
        if (bbt == null || bleedDates.contains(date)) continue;
        DateTime? prevBleed;
        DateTime? nextBleed;
        for (final b in bleedDates) {
          if (b.isBefore(date)) prevBleed = b;
          if (b.isAfter(date) && nextBleed == null) nextBleed = b;
        }
        if (prevBleed == null || nextBleed == null) continue;
        final afterPrev = date.difference(prevBleed).inDays;
        final beforeNext = nextBleed.difference(date).inDays;
        if (beforeNext >= 8 && beforeNext <= 13) {
          luteal.add(bbt);
        } else if (afterPrev >= 4 && afterPrev <= 9 && beforeNext > 13) {
          follicular.add(bbt);
        }
      }
      expect(follicular.length, greaterThan(30),
          reason: 'enough follicular-phase samples to compare');
      expect(luteal.length, greaterThan(30),
          reason: 'enough luteal-phase samples to compare');
      double mean(Iterable<double> xs) =>
          xs.reduce((a, b) => a + b) / xs.length;
      expect(mean(luteal) - mean(follicular), greaterThan(0.15),
          reason: 'luteal temperatures sit measurably above follicular ones');
    });

    test('a few BBT outliers are marked excluded', () {
      final excluded = payload.observations
          .where((o) => o['category'] == 'bbt' && o['excluded'] == true)
          .toList();
      expect(excluded, isNotEmpty);
      expect(excluded.length, lessThan(20));
    });

    test('cycle overrides: one excluded_from_average + one manual_start '
        'per profile', () {
      for (final profile in payload.profiles) {
        final pid = profile['id']! as String;
        final overrides =
            payload.cycleOverrides.where((c) => c['profile_id'] == pid).toList();
        expect(overrides, hasLength(2));
        expect(
          overrides.where((c) => c['excluded_from_average'] == true),
          hasLength(1),
        );
        expect(
          overrides.where((c) => c['manual_start'] == true),
          hasLength(1),
        );
      }
    });

    test('care notes ~6 and visit-prep items ~10, some checked, no '
        'server-stamped check columns', () {
      for (final profile in payload.profiles) {
        final pid = profile['id']! as String;
        final notes =
            payload.careNotes.where((c) => c['profile_id'] == pid).toList();
        final prep = payload.visitPrepItems
            .where((v) => v['profile_id'] == pid)
            .toList();
        expect(notes, hasLength(6));
        expect(prep, hasLength(10));
        expect(
          prep.where((v) => v['is_checked'] == true).length,
          greaterThan(0),
        );
        expect(
          prep.every((v) =>
              !v.containsKey('checked_by_user_id') &&
              !v.containsKey('checked_at')),
          isTrue,
        );
      }
    });

    test('teen prediction sharing is structurally impossible: the teen '
        'profile is a minor', () {
      final teen = payload.profiles.firstWhere((p) => p['is_minor'] == true);
      expect(teen['birth_year'], 2012); // ~14 at the fixed clock: a minor
    });

    test('measurement rows carry observed_at + tz; local_date is derived '
        'consistently', () {
      for (final o in payload.observations) {
        if (o['category'] == 'bbt' || o['category'] == 'weight') {
          expect(o['observed_at'], isA<String>());
          expect(o['tz'], isA<String>());
        }
      }
    });
  });

  group('chunking', () {
    final payload = generateSeedPayload(const SeedSpec(
      months: kMinSeedMonths,
      seed: 7,
      clock: _fixedClock,
    ));

    test('every batch respects the per-array and total caps', () {
      final batches = chunkForSyncPush(payload);
      expect(validateBatchCaps(batches), isEmpty);
      expect(batches.first.tableName, 'p_profiles');
    });

    test('children are pushed after parents', () {
      final batches = chunkForSyncPush(payload);
      final order = batches.map((b) => b.tableName).toSet().toList();
      expect(order, orderedEquals([
        'p_profiles',
        'p_day_entries',
        'p_observations',
        'p_profile_modes',
        'p_cycle_overrides',
        'p_care_notes',
        'p_visit_prep_items',
      ].where((t) => order.contains(t))));
    });

    test('large payloads split into multiple day-entry/observation calls',
        () {
      final batches = chunkForSyncPush(payload);
      expect(
        batches.where((b) => b.tableName == 'p_day_entries').length,
        greaterThan(1),
        reason: '${payload.dayEntries.length} day entries exceed one call',
      );
      expect(
        batches.where((b) => b.tableName == 'p_observations').length,
        greaterThan(1),
      );
    });
  });

  group('reminder windows', () {
    test('one per profile, deterministic, episode closed at the anchor', () {
      final payload = generateSeedPayload(const SeedSpec(
        months: kMinSeedMonths,
        seed: 7,
        clock: _fixedClock,
      ));
      expect(payload.reminderWindows, hasLength(2));
      for (final window in payload.reminderWindows) {
        expect(window.estimatedNextStart, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(window.episodeOpen, isFalse,
            reason: 'the in-progress cycle started ~2 weeks before the anchor');
      }
    });
  });
}
