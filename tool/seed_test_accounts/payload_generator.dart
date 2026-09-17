/// Deterministic sample-data generator for the test-account seeder
/// (issue #710).
///
/// Given a [SeedSpec] (months, seed, injected clock) this produces the full
/// JSON-ready `sync_push` payload — profiles, day entries, observations,
/// profile_modes, cycle_overrides, care_notes, visit_prep_items — plus the
/// derived reminder-window facts. The output is a pure function of the
/// spec: same seed + same clock => byte-identical payload (pinned by
/// `test/tool/seed/payload_generator_test.dart`).
///
/// Every row stays exactly within the current `sync_push` allowlists
/// (`20260915200001_sync_push_tombstone_resurrection_guard.sql`): no
/// `user_id`/`server_version`/attribution columns are ever emitted, and
/// `updated_at` is a single anchor timestamp (the injected clock's "now"),
/// which is always inside the server's `(now - 180d, now + 5min)` window —
/// the tombstone-resurrection guard only ever fires on *unknown ids* whose
/// `updated_at` is older than 180 days, so backdated `local_date`s are safe
/// while a single fresh `updated_at` keeps every insert on the happy path.
///
/// All names, notes, and values are fabricated; no real person's data.
library;

import 'dart:convert';
import 'dart:math';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/measurement_validation.dart';
import 'package:lunarlog/domain/tags.dart';

/// Minimum window the tool will generate (`--months` is clamped to this).
const int kMinSeedMonths = 12;

/// How the seeder describes one run's generation inputs.
///
/// The CLI clamps `--months` to [kMinSeedMonths]; [SeedSpec] itself accepts
/// a smaller window so the pgTAP fixture (`--emit-pgtap`) can embed an
/// intentionally small two-month payload.
class SeedSpec {
  const SeedSpec({
    required this.months,
    required this.seed,
    required this.clock,
    this.includeTeenProfile = true,
  });

  /// Months of history to generate (CLI-clamped to >= [kMinSeedMonths];
  /// default 18).
  final int months;

  /// Determinism seed for every random choice (RNG streams, ULIDs).
  final int seed;

  /// Injected clock; called once per build to anchor the window. Tests pass
  /// a fixed clock so the payload (and its digest) is reproducible.
  final DateTime Function() clock;

  /// Whether to also generate the fabricated teen profile (the second
  /// profile of the standard two-profile layout). The pgTAP fixture uses a
  /// single-profile layout to stay small.
  final bool includeTeenProfile;
}

/// The client-published reminder snapshot for one profile
/// (`upsert_reminder_window`, computed from the generated cycle math —
/// the server never recomputes predictions).
class ReminderWindowFact {
  const ReminderWindowFact({
    required this.profileId,
    required this.estimatedNextStart,
    required this.episodeOpen,
  });

  final String profileId;

  /// ISO calendar date (`YYYY-MM-DD`) of the next predicted period start.
  final String estimatedNextStart;

  /// Whether the anchor date falls inside the current bleed episode.
  final bool episodeOpen;
}

/// Everything one seeder run writes for one target account.
class SeedPayload {
  const SeedPayload({
    required this.anchor,
    required this.months,
    required this.seed,
    required this.profiles,
    required this.dayEntries,
    required this.observations,
    required this.profileModes,
    required this.cycleOverrides,
    required this.careNotes,
    required this.visitPrepItems,
    required this.reminderWindows,
  });

  /// The single `updated_at` used by every row (see the library doc).
  final DateTime anchor;
  final int months;
  final int seed;

  final List<Map<String, Object?>> profiles;
  final List<Map<String, Object?>> dayEntries;
  final List<Map<String, Object?>> observations;
  final List<Map<String, Object?>> profileModes;
  final List<Map<String, Object?>> cycleOverrides;
  final List<Map<String, Object?>> careNotes;
  final List<Map<String, Object?>> visitPrepItems;
  final List<ReminderWindowFact> reminderWindows;

  /// Stable JSON encoding of the full sync payload (the determinism
  /// digest's input — reminder windows are excluded since they ride their
  /// own RPC, not `sync_push`).
  String get canonicalJson => jsonEncode({
        'profiles': profiles,
        'day_entries': dayEntries,
        'observations': observations,
        'profile_modes': profileModes,
        'cycle_overrides': cycleOverrides,
        'care_notes': careNotes,
        'visit_prep_items': visitPrepItems,
      });
}

/// One generated cycle (all dates are UTC calendar days).
class _Cycle {
  _Cycle(this.startDate, this.cycleLength, this.periodLength);

  final DateTime startDate;
  final int cycleLength;
  final int periodLength;

  DateTime get endDate =>
      startDate.add(Duration(days: cycleLength - 1)); // inclusive
  DateTime get periodEndDate =>
      startDate.add(Duration(days: periodLength - 1)); // inclusive
}

String _isoDate(DateTime d) {
  final u = d.toUtc();
  final mm = u.month.toString().padLeft(2, '0');
  final dd = u.day.toString().padLeft(2, '0');
  return '${u.year}-$mm-$dd';
}

String _isoInstant(DateTime d) => d.toUtc().toIso8601String();

DateTime _utcDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The per-profile generation inputs (fabricated identity + unit prefs).
class _ProfileSpec {
  const _ProfileSpec({
    required this.displayName,
    required this.relationship,
    required this.birthYear,
    required this.isMinor,
    required this.profileModeWire,
    required this.lifeStageModeWire,
    required this.bbtUnit,
    required this.weightUnit,
    required this.tz,
    required this.rngSalt,
  });

  final String displayName;
  final String relationship;
  final int birthYear;
  final bool isMinor;
  final String profileModeWire; // profiles.mode (#131 care-mode axis)
  final String lifeStageModeWire; // profile_modes.mode (#188 axis)
  final BbtUnit bbtUnit;
  final WeightUnit weightUnit;
  final String tz;
  final int rngSalt;
}

const _ProfileSpec _adultSpec = _ProfileSpec(
  displayName: 'Maya',
  relationship: 'self',
  birthYear: 1988,
  isMinor: false,
  profileModeWire: 'standard',
  lifeStageModeWire: 'tracking',
  bbtUnit: BbtUnit.celsius,
  weightUnit: WeightUnit.kg,
  tz: 'America/New_York',
  rngSalt: 101,
);

const _ProfileSpec _teenSpec = _ProfileSpec(
  displayName: 'Riley',
  relationship: 'daughter',
  birthYear: 2012,
  isMinor: true,
  profileModeWire: 'teen',
  lifeStageModeWire: 'tracking',
  bbtUnit: BbtUnit.fahrenheit,
  weightUnit: WeightUnit.lb,
  tz: 'America/Chicago',
  rngSalt: 211,
);

const List<String> _painCodes = [
  'cramps',
  'headache',
  'back_pain',
  'breast_tenderness',
];

const List<String> _moodTagCodes = [
  'irritable',
  'anxious',
  'mood_swings',
  'sad',
  'sensitive',
];

const List<String> _symptomPools = [
  // feelings
  'irritable|happy|sad|anxious|indifferent|sensitive|mood_swings|calm',
  // mind
  'distracted|focused|stressed',
  // energy
  'tired|fatigue|energetic|exhausted',
  // sleep
  'sleep_trouble',
  // digestion
  'bloating|nausea|gassy',
  // cravings
  'sweet|salty|chocolate|cravings',
];

const List<String> _perimenopauseCodes = [
  'hot_flashes',
  'night_sweats',
  'brain_fog',
  'hrt',
  'vaginal_dryness',
];

const List<String> _notePool = [
  'Slept better than usual last night.',
  'Long walk in the evening; energy felt steady all day.',
  'Drank more water and it seemed to help.',
  'Busy day at work, forgot the afternoon log until late.',
  'Mild cramps in the morning, gone by noon.',
  'Tracked temperature a bit later than usual today.',
  'Rest day from exercise.',
  'Headache after screen time in the evening.',
  'Felt calm and focused most of the day.',
  'Traveled today; routine was off schedule.',
];

const List<String> _careNotePool = [
  'Cramps responded well to a heat pad this cycle.',
  'Sleep quality improved on evenings without screens.',
  'Energy dips consistently mid-afternoon; worth watching.',
  'Hydration seems correlated with fewer headaches.',
  'Iron-rich meals on heavy days seem to help fatigue.',
  'Check-in: mood steady this month overall.',
];

const List<String> _visitPrepPool = [
  'Bring the cycle history printout',
  'Note down questions about cramp relief',
  'Record average cycle length for the last 6 months',
  'List current supplements and medications',
  'Write down sleep hours for the past week',
  'Note any mid-cycle pain days',
  'Bring the temperature tracking chart',
  'Record how many heavy-flow days this cycle',
  'Note mood changes in the week before the period',
  'Confirm next appointment date',
];

/// Generates the full payload. See the library doc for the determinism and
/// updated_at policies.
SeedPayload generateSeedPayload(SeedSpec spec) {
  tzdata.initializeTimeZones();
  final anchor = spec.clock().toUtc();
  final anchorDate = _utcDate(anchor);
  final anchorIso = _isoInstant(anchor);
  final windowDays = (spec.months * 30.44).round();

  final idGen = UlidGenerator(
    clock: () => anchor,
    random: Random(spec.seed ^ 0x5EED),
  );

  final profiles = <Map<String, Object?>>[];
  final dayEntries = <Map<String, Object?>>[];
  final observations = <Map<String, Object?>>[];
  final profileModes = <Map<String, Object?>>[];
  final cycleOverrides = <Map<String, Object?>>[];
  final careNotes = <Map<String, Object?>>[];
  final visitPrepItems = <Map<String, Object?>>[];
  final reminderWindows = <ReminderWindowFact>[];

  final profileSpecs = <_ProfileSpec>[
    _adultSpec,
    if (spec.includeTeenProfile) _teenSpec,
  ];

  for (var p = 0; p < profileSpecs.length; p++) {
    final pspec = profileSpecs[p];
    final profileId = idGen.next();
    final rng = Random(spec.seed * 1000003 + pspec.rngSalt);

    // ---- Cycles -------------------------------------------------------
    final cycles = <_Cycle>[];
    var currentStart = anchorDate.subtract(Duration(days: 12 + rng.nextInt(5)));
    while (currentStart.isAfter(
      anchorDate.subtract(Duration(days: windowDays)),
    )) {
      final cycleLength = 26 + rng.nextInt(7); // 26..32
      final periodLength = 4 + rng.nextInt(3); // 4..6
      cycles.add(_Cycle(currentStart, cycleLength, periodLength));
      currentStart = currentStart.subtract(Duration(days: cycleLength));
    }
    // cycles[0] is the in-progress cycle (latest start); generate oldest
    // first for a natural day-by-day walk below.
    final ordered = cycles.reversed.toList();

    final meanCycle = (cycles.map((c) => c.cycleLength).reduce((a, b) => a + b) /
            cycles.length)
        .round();
    final meanPeriod =
        (cycles.map((c) => c.periodLength).reduce((a, b) => a + b) /
                cycles.length)
            .round();

    // ---- Profile row ----------------------------------------------------
    profiles.add({
      'id': profileId,
      'display_name': pspec.displayName,
      'is_minor': pspec.isMinor,
      'sort_order': p,
      'created_at': anchorIso,
      'updated_at': anchorIso,
      'birth_year': pspec.birthYear,
      'relationship': pspec.relationship,
      'mode': pspec.profileModeWire,
      'last_period_start': _isoDate(cycles.first.startDate),
      'typical_cycle_length_days': meanCycle,
      'typical_period_length_days': meanPeriod,
      'bbt_unit': pspec.bbtUnit.toDb(),
      'weight_unit': pspec.weightUnit.toDb(),
    });
    profileModes.add({
      'profile_id': profileId,
      'mode': pspec.lifeStageModeWire,
      'mode_started_on': _isoDate(
        anchorDate.subtract(Duration(days: windowDays)),
      ),
      'updated_at': anchorIso,
    });

    // ---- Cycle overrides: one excluded_from_average, one manual_start ----
    // The excluded one sits on the cycle whose length is furthest from the
    // mean (the "vacation threw it off" cycle); the manual start on a quiet
    // mid-window cycle.
    _Cycle mostAtypical = ordered.first;
    for (final c in ordered) {
      if ((c.cycleLength - meanCycle).abs() >
          (mostAtypical.cycleLength - meanCycle).abs()) {
        mostAtypical = c;
      }
    }
    final manualCycle = ordered[ordered.length ~/ 3];
    cycleOverrides.add({
      'id': idGen.next(),
      'profile_id': profileId,
      'cycle_start_date': _isoDate(mostAtypical.startDate),
      'excluded_from_average': true,
      'manual_start': false,
      'updated_at': anchorIso,
    });
    cycleOverrides.add({
      'id': idGen.next(),
      'profile_id': profileId,
      'cycle_start_date': _isoDate(manualCycle.startDate),
      'excluded_from_average': false,
      'manual_start': true,
      'updated_at': anchorIso,
    });

    // ---- Day-by-day content ---------------------------------------------
    final windowStart = anchorDate.subtract(Duration(days: windowDays));
    // Bleed days: cycle start -> start+periodLength-1.
    final bleedDays = <DateTime, int>{}; // date -> day index within period
    for (final c in ordered) {
      for (var i = 0; i < c.periodLength; i++) {
        bleedDays[_utcDate(c.startDate).add(Duration(days: i))] = i;
      }
    }
    // PMS days: the 2-3 days before each period start.
    final pmsDays = <DateTime>{};
    for (final c in ordered) {
      final lead = 2 + rng.nextInt(2);
      for (var i = 1; i <= lead; i++) {
        pmsDays.add(_utcDate(c.startDate).subtract(Duration(days: i)));
      }
    }
    // Spotting days: 1-2 days right after a period end, ~30% of cycles,
    // modelled as observations (never a flow level — #247).
    final spottingDays = <DateTime>{};
    for (final c in ordered) {
      if (rng.nextDouble() < 0.3) {
        spottingDays.add(c.periodEndDate.add(const Duration(days: 1)));
        if (rng.nextBool()) {
          spottingDays.add(c.periodEndDate.add(const Duration(days: 2)));
        }
      }
    }

    // The few graded-pain 4s (a couple, for realism; the rest are <= 3).
    final totalDays = windowDays + 1;
    final pain4Days = <DateTime>{
      windowStart.add(Duration(days: rng.nextInt(totalDays))),
      windowStart.add(Duration(days: rng.nextInt(totalDays))),
    };

    // Weight days: weekly.
    var weightKg = pspec.isMinor ? 52.0 : 63.5;
    final weightDrift = (rng.nextDouble() - 0.5) * 0.6; // total drift, kg

    final location = tz.getLocation(pspec.tz);

    for (var d = 0; d <= windowDays; d++) {
      final date = windowStart.add(Duration(days: d));
      final dateKey = _utcDate(date);
      final isBleed = bleedDays.containsKey(dateKey);
      final periodDayIndex = bleedDays[dateKey] ?? 0;
      final isPms = pmsDays.contains(dateKey);
      final isSpotting = spottingDays.contains(dateKey);

      // -- day entry (exactly one live row per profile/date) --
      final flowWire = isBleed
          ? _bleedFlow(periodDayIndex, rng)
          : FlowLevel.notBleeding.toDb();
      Object? note;
      if (rng.nextDouble() < 0.05) {
        note = _notePool[rng.nextInt(_notePool.length)];
      }
      final tags = <String>[];
      if (isPms) {
        final tagCount = 1 + rng.nextInt(3);
        final pool = [..._moodTagCodes]..shuffle(rng);
        tags.addAll(pool.take(tagCount));
        validateTagCodes(tags);
      }
      dayEntries.add({
        'id': idGen.next(),
        'profile_id': profileId,
        'local_date': _isoDate(date),
        'tz': pspec.tz,
        'flow': flowWire,
        if (tags.isNotEmpty) 'tags': tags,
        'note': ?note,
        'pms': isPms,
        'updated_at': anchorIso,
      });
      final dayEntryId = dayEntries.last['id']! as String;

      // -- BBT (biphasic; daily; observed at 07:00 local) --
      final cycle = _cycleFor(ordered, dateKey);
      final isLuteal = cycle != null &&
          dateKey.isAfter(cycle.startDate.add(
            Duration(days: max(1, cycle.cycleLength - 15)),
          ));
      var celsius = 36.3 + rng.nextDouble() * 0.3; // follicular 36.3-36.6
      if (isLuteal) celsius += 0.2 + rng.nextDouble() * 0.3;
      celsius += (rng.nextDouble() - 0.5) * 0.08; // measurement noise
      var excluded = false;
      if (rng.nextDouble() < 0.01) {
        excluded = true;
        celsius += (rng.nextBool() ? 1 : -1) * (0.9 + rng.nextDouble() * 0.3);
      }
      celsius = celsius.clamp(kMinBbtCelsius, kMaxBbtCelsius).toDouble();
      final bbtValue =
          convertTemperature(celsius, from: BbtUnit.celsius, to: pspec.bbtUnit);
      if (!isValidBbt(bbtValue, pspec.bbtUnit)) {
        throw StateError('generated BBT outside sanity range');
      }
      final bbtInstant = tz.TZDateTime(location, date.year, date.month,
          date.day, 7, rng.nextInt(2) * 15);
      observations.add({
        'id': idGen.next(),
        'day_entry_id': dayEntryId,
        'profile_id': profileId,
        'local_date': _isoDate(tz.TZDateTime.from(bbtInstant, location)),
        'observed_at': _isoInstant(bbtInstant),
        'tz': pspec.tz,
        'category': 'bbt',
        'value_num': _round(bbtValue, 2),
        'unit': pspec.bbtUnit.toDb(),
        if (excluded) 'excluded': true,
        'updated_at': anchorIso,
      });

      // -- weight (weekly, slow drift; observed at 08:00 local) --
      if (d % 7 == 3) {
        final progress = d / windowDays;
        final kg = weightKg + weightDrift * progress +
            (rng.nextDouble() - 0.5) * 0.2;
        weightKg = kg;
        final value = convertWeight(kg, from: WeightUnit.kg, to: pspec.weightUnit);
        if (!isValidWeight(value, pspec.weightUnit)) {
          throw StateError('generated weight outside sanity range');
        }
        final weightInstant = tz.TZDateTime(
            location, date.year, date.month, date.day, 8, rng.nextInt(4) * 15);
        observations.add({
          'id': idGen.next(),
          'day_entry_id': dayEntryId,
          'profile_id': profileId,
          'local_date': _isoDate(tz.TZDateTime.from(weightInstant, location)),
          'observed_at': _isoInstant(weightInstant),
          'tz': pspec.tz,
          'category': 'weight',
          'value_num': _round(value, 1),
          'unit': pspec.weightUnit.toDb(),
          'updated_at': anchorIso,
        });
      }

      // -- graded pain (mostly <= 3; the two pinned days are 4s) --
      final painChance = isBleed ? 0.55 : 0.12;
      if (rng.nextDouble() < painChance) {
        final code = isBleed && rng.nextBool()
            ? 'cramps'
            : _painCodes[rng.nextInt(_painCodes.length)];
        observations.add({
          'id': idGen.next(),
          'day_entry_id': dayEntryId,
          'profile_id': profileId,
          'local_date': _isoDate(date),
          'tz': pspec.tz,
          'category': 'pain',
          'code': code,
          'intensity': pain4Days.contains(dateKey) ? 4 : 1 + rng.nextInt(3),
          'updated_at': anchorIso,
        });
      }

      // -- symptom/mood tags as observations (taxonomy codes) --
      if (rng.nextDouble() < 0.35) {
        final usedCodes = <String>{};
        final poolCount = 1 + rng.nextInt(2);
        final pools = [..._symptomPools]..shuffle(rng);
        for (final pool in pools.take(poolCount)) {
          final codes = pool.split('|').toList()..shuffle(rng);
          final code = codes.first;
          if (usedCodes.contains(code)) continue;
          usedCodes.add(code);
          final tag = tagByCode(code);
          if (tag == null) {
            throw StateError('generated tag code not in taxonomy: $code');
          }
          observations.add({
            'id': idGen.next(),
            'day_entry_id': dayEntryId,
            'profile_id': profileId,
            'local_date': _isoDate(date),
            'tz': pspec.tz,
            'category': tag.category.wireName,
            'code': code,
            'updated_at': anchorIso,
          });
        }
      }

      // -- spotting as its own observation category (#247) --
      if (isSpotting) {
        observations.add({
          'id': idGen.next(),
          'day_entry_id': dayEntryId,
          'profile_id': profileId,
          'local_date': _isoDate(date),
          'tz': pspec.tz,
          'category': 'spotting',
          'code': 'spotting',
          'updated_at': anchorIso,
        });
      }

      // -- #456 perimenopause cluster (adult only, occasional) --
      if (!pspec.isMinor && rng.nextDouble() < 0.03) {
        observations.add({
          'id': idGen.next(),
          'day_entry_id': dayEntryId,
          'profile_id': profileId,
          'local_date': _isoDate(date),
          'tz': pspec.tz,
          'category': 'hot_flashes',
          'code': _perimenopauseCodes[rng.nextInt(_perimenopauseCodes.length)],
          'updated_at': anchorIso,
        });
      }
    }

    // ---- Care notes and visit-prep items ---------------------------------
    for (var i = 0; i < _careNotePool.length; i++) {
      careNotes.add({
        'id': idGen.next(),
        'profile_id': profileId,
        'body': _careNotePool[i],
        'updated_at': anchorIso,
      });
    }
    final prepOrder = [..._visitPrepPool]..shuffle(rng);
    for (var i = 0; i < prepOrder.length; i++) {
      visitPrepItems.add({
        'id': idGen.next(),
        'profile_id': profileId,
        'body': prepOrder[i],
        'is_checked': i < 4, // some already checked off (server stamps who)
        'updated_at': anchorIso,
      });
    }

    // ---- Reminder window (from the generated cycle math) -----------------
    final current = cycles.first;
    reminderWindows.add(ReminderWindowFact(
      profileId: profileId,
      estimatedNextStart: _isoDate(
        current.startDate.add(Duration(days: meanCycle)),
      ),
      episodeOpen: !anchorDate.isAfter(current.periodEndDate),
    ));
  }

  return SeedPayload(
    anchor: anchor,
    months: spec.months,
    seed: spec.seed,
    profiles: profiles,
    dayEntries: dayEntries,
    observations: observations,
    profileModes: profileModes,
    cycleOverrides: cycleOverrides,
    careNotes: careNotes,
    visitPrepItems: visitPrepItems,
    reminderWindows: reminderWindows,
  );
}

/// Flow pattern within a period: heavier on days 0-1, tapering after.
String _bleedFlow(int dayIndex, Random rng) {
  String pick(List<String> options) =>
      options[rng.nextInt(options.length)];
  if (dayIndex == 0) return pick(['light', 'medium', 'medium', 'heavy']);
  if (dayIndex == 1) {
    return pick(['medium', 'heavy', 'heavy', 'super_heavy']);
  }
  if (dayIndex == 2) return pick(['light', 'medium']);
  return 'light';
}

_Cycle? _cycleFor(List<_Cycle> ordered, DateTime date) {
  _Cycle? found;
  for (final c in ordered) {
    final start = _utcDate(c.startDate);
    if (!date.isBefore(start) && !date.isAfter(c.endDate)) found = c;
  }
  return found;
}

double _round(double v, int places) {
  final factor = pow(10, places).toDouble();
  return (v * factor).roundToDouble() / factor;
}
