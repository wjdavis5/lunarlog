/// `LocalHealthImportService`'s whole policy (Issues #217/#458): the binding
/// guard runs first (zero health calls on a deny), authorization precedes
/// the read, only the bound profile is written, each sample's OWN
/// zone/offset resolves its civil date, our own writes are excluded natively
/// (proven separately in the codec/channel tests), a hand-logged value is
/// never overwritten, an unlogged day is upgraded, provenance matches the
/// platform (`healthkit` / `health_connect`), and the computed deviation
/// types are never touched by any path here. The Android half adds
/// intermenstrual-bleeding records imported as `spotting` observations.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
const _tz = 'America/New_York';

/// The fixed "today" every pass resolves its window against. Since Issue
/// #992 the window is full history (1970 … today), not a fixed day count.
final _today = LocalDate(2026, 9, 15);

Profile _profile() => Profile(
  id: _profileId,
  displayName: 'Ada',
  isMinor: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

List<ProfileGuardian> _owners() => [
  ProfileGuardian(
    id: 'g1',
    profileId: _profileId,
    userId: _ownerId,
    role: GuardianRole.primaryGuardian,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  ),
];

class _FakePlatform implements HealthPlatformStore {
  HealthPlatformResult bindResult = const HealthPlatformAllowed();
  HealthPlatformResult authResult = const HealthPlatformAllowed();
  int bindCalls = 0;
  int authCalls = 0;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async {
    bindCalls++;
    return bindResult;
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async {
    authCalls++;
    return authResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSource implements HealthImportSource {
  /// A single page served on every call. Cursor is null, so a pass that
  /// uses this stops after one page — the shape the pre-#992 tests use.
  HealthReadResult result = const HealthReadResult.samples([]);

  /// When non-empty, pages are served in order (an exhausted fake returns
  /// an empty page with a null cursor). Lets a test drive the cursor loop.
  List<HealthReadResult> pages = const [];

  int calls = 0;
  DateTime? lastStart;
  DateTime? lastEnd;
  int? lastPageSize;
  String? lastCursor;
  final List<String?> cursorsSeen = [];

  @override
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
  }) async {
    lastStart = start;
    lastEnd = end;
    lastPageSize = pageSize;
    lastCursor = cursor;
    cursorsSeen.add(cursor);
    final index = calls;
    calls++;
    if (pages.isNotEmpty) {
      return index < pages.length
          ? pages[index]
          : const HealthReadResult.samples([]);
    }
    return result;
  }

  @override
  Future<HealthDeviationReadResult> readCycleDeviations(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthDeviationReadResult.unavailable();
}

class _FakeProfiles implements ProfilesRepository {
  Profile? profile = _profile();

  @override
  Future<Profile?> findById(String id) async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDayEntries implements DayEntriesRepository {
  final Map<String, DayEntry> live = {};
  final List<DayEntry> saved = [];
  int _nextId = 0;

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async =>
      live[localDate.iso];

  @override
  Future<DayEntry> save(DayEntry entry) async {
    final id = entry.id.isEmpty ? 'day-${++_nextId}' : entry.id;
    final stored = DayEntry(
      id: id,
      profileId: entry.profileId,
      localDate: entry.localDate,
      tz: entry.tz,
      flow: entry.flow,
      tags: entry.tags,
      note: entry.note,
      pms: entry.pms,
      updatedAt: entry.updatedAt,
      source: entry.source,
      sourceId: entry.sourceId,
    );
    saved.add(stored);
    live[stored.localDate.iso] = stored;
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeObservations implements ObservationsRepository {
  final List<Observation> saved = [];
  final Map<String, List<Observation>> byDay = {};
  int _nextId = 0;

  @override
  Future<Observation> save(Observation observation) async {
    final id = observation.id.isEmpty ? 'obs-${++_nextId}' : observation.id;
    final stored = Observation(
      id: id,
      dayEntryId: observation.dayEntryId,
      profileId: observation.profileId,
      localDate: observation.localDate,
      tz: observation.tz,
      category: observation.category,
      code: observation.code,
      source: observation.source,
      sourceId: observation.sourceId,
      updatedAt: observation.updatedAt,
    );
    saved.add(stored);
    byDay.putIfAbsent(stored.dayEntryId, () => []).add(stored);
    return stored;
  }

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
    String dayEntryId,
  ) async =>
      byDay[dayEntryId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

HealthFlowSample _sample({
  required String id,
  required HealthFlowValue flow,
  required String startIso,
  String? tzName = _tz,
  String? externalUuid,
}) {
  final start = DateTime.parse(startIso);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    tzName: tzName,
    externalUuid: externalUuid,
  );
}

HealthFlowSample _bleedingSample({
  required String id,
  required String startIso,
  Duration? offset,
}) {
  final start = DateTime.parse(startIso);
  return HealthFlowSample(
    recordId: id,
    kind: HealthSampleKind.intermenstrualBleeding,
    start: start,
    end: start,
    offset: offset,
  );
}

/// One Android import sample: a menstrual-flow record carrying only its raw
/// zone offset (no IANA name), the Health Connect shape.
HealthFlowSample _offsetSample({
  required String id,
  required HealthFlowValue flow,
  required String startIso,
  Duration offset = const Duration(hours: -4),
}) {
  final start = DateTime.parse(startIso);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start,
    offset: offset,
  );
}

/// One iOS import sample with no recorded IANA zone, carrying the
/// device-zone offset the iOS read synthesises (Issue #902).
HealthFlowSample _deviceZoneSample({
  required String id,
  required HealthFlowValue flow,
  required String startIso,
  Duration offset = const Duration(hours: -4),
}) {
  final start = DateTime.parse(startIso);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start,
    offset: offset,
    offsetInferred: true,
  );
}

void main() {
  late FakeSettingsStore settings;
  late _FakePlatform platform;
  late _FakeSource source;
  late _FakeProfiles profiles;
  late _FakeDayEntries dayEntries;
  late _FakeObservations observations;
  late HealthSyncBinding binding;

  LocalHealthImportService build({
    HealthImportPlatform importPlatform = HealthImportPlatform.appleHealth,
  }) => LocalHealthImportService(
    importPlatform: importPlatform,
    platform: platform,
    source: source,
    binding: binding,
    minorBindingAllowed: false,
    profiles: profiles,
    dayEntries: dayEntries,
    observations: observations,
    guardiansForProfile: (_) async => _owners(),
    signedInUserId: () => _ownerId,
    today: () => _today,
    now: () => DateTime.utc(2026, 9, 15, 12),
  );

  Future<void> bind() => binding.bind(
    profile: _profile(),
    signedInUserId: _ownerId,
    ownerUserId: _ownerId,
    minorBindingAllowed: false,
  );

  setUp(() {
    settings = FakeSettingsStore();
    platform = _FakePlatform();
    source = _FakeSource();
    profiles = _FakeProfiles();
    dayEntries = _FakeDayEntries();
    observations = _FakeObservations();
    binding = HealthSyncBinding(settings);
  });

  tearDown(() => settings.close());

  test('no bound profile is a no-op: no health call, no write', () async {
    final summary = await build().importNow();
    expect(summary.bound, isFalse);
    expect(platform.bindCalls, 0);
    expect(source.calls, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test('a guard denial ends the pass with the refusal and touches no '
      'health API', () async {
    // Bound to a different profile than the one asking — canWrite denies
    // with profileNotBound.
    settings.setSilently(SettingsKeys.healthStoreProfileId, 'someone-else');
    final summary = await build().importNow();
    expect(summary.isBlocked, isTrue);
    expect(
      (summary.blocked! as HealthPlatformRefused).check,
      HealthSyncCheck.profileNotBound,
    );
    expect(platform.bindCalls, 0);
    expect(source.calls, 0);
  });

  test(
    'binding is re-asserted and authorization requested before the read',
    () async {
      await bind();
      source.result = const HealthReadResult.samples([]);
      await build().importNow();
      expect(platform.bindCalls, 1);
      expect(platform.authCalls, 1);
      expect(source.calls, 1);
    },
  );

  test(
    'a fresh in-window sample creates a healthkit-provenance day entry',
    () async {
      await bind();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'hk-1',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T04:00:00Z',
        ),
      ]);
      final summary = await build().importNow();

      expect(summary.samplesRead, 1);
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved, hasLength(1));
      final row = dayEntries.saved.single;
      expect(row.localDate, LocalDate(2026, 9, 10));
      expect(row.flow, FlowLevel.medium);
      expect(row.source, DayEntrySource.healthkit);
      expect(row.sourceId, 'hk-1');
      expect(row.tz, _tz);
    },
  );

  test('the sample\'s OWN zone resolves the civil date, not the device '
      'zone', () async {
    await bind();
    // 02:00Z on the 15th is still the 14th in New York — the imported day
    // must be the 14th, resolved from the sample's own tz.
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-tz',
        flow: HealthFlowValue.light,
        startIso: '2026-09-15T02:00:00Z',
      ),
    ]);
    await build().importNow();
    expect(dayEntries.saved.single.localDate, LocalDate(2026, 9, 14));
  });

  test('a sample with no recorded zone is counted, never guessed from the '
      'device zone', () async {
    await bind();
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-no-tz',
        flow: HealthFlowValue.heavy,
        startIso: '2026-09-10T04:00:00Z',
        tzName: null,
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.samplesWithoutZone, 1);
    expect(summary.daysWritten, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test('an unspecified flow has no lunarlog equivalent and is counted, not '
      'written', () async {
    await bind();
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-u',
        flow: HealthFlowValue.unspecified,
        startIso: '2026-09-10T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.samplesUnsupported, 1);
    expect(dayEntries.saved, isEmpty);
  });

  test('a sample dated after today is ignored (the window still ends '
      'today)', () async {
    await bind();
    source.result = HealthReadResult.samples([
      // 2026-09-16 is one day after "today" (2026-09-15) — outside the
      // imported civil window even though the full history has no lower cap.
      _sample(
        id: 'hk-future',
        flow: HealthFlowValue.heavy,
        startIso: '2026-09-16T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.samplesRead, 1);
    expect(summary.daysWritten, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test(
    'the full-history query window runs from 1970 to tomorrow, one day of '
    'slack either side',
    () async {
      await bind();
      await build().importNow();
      // Lower bound is the first day of kHealthImportEarliestYear minus a
      // day; upper bound is today + 2 (exclusive end). Issue #992 removed
      // the 30-day cap, so a 2026-08-16 sample now imports.
      expect(source.lastStart, DateTime.utc(1969, 12, 31));
      expect(source.lastEnd, DateTime.utc(2026, 9, 17));
      expect(source.lastPageSize, kHealthImportPageSize);
      expect(source.lastCursor, isNull);
    },
  );

  test('a sample from before the old 30-day window now imports (Issue #992)',
      () async {
    await bind();
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-old',
        flow: HealthFlowValue.heavy,
        // 15:00Z is 10:00 in America/New_York, so the civil date is the 15th.
        startIso: '2024-01-15T15:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.daysWritten, 1);
    expect(dayEntries.saved.single.localDate, LocalDate(2024, 1, 15));
  });

  test('a hand-logged flow is never overwritten', () async {
    await bind();
    dayEntries.live['2026-09-10'] = DayEntry(
      id: 'manual-1',
      profileId: _profileId,
      localDate: LocalDate(2026, 9, 10),
      tz: _tz,
      flow: FlowLevel.heavy,
      source: DayEntrySource.manual,
      updatedAt: DateTime.utc(2026, 9, 10),
    );
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-2',
        flow: HealthFlowValue.light,
        startIso: '2026-09-10T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.daysKeptManual, 1);
    expect(summary.daysWritten, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test('an unlogged (none) day is upgraded and marked healthkit', () async {
    await bind();
    dayEntries.live['2026-09-10'] = DayEntry(
      id: 'empty-1',
      profileId: _profileId,
      localDate: LocalDate(2026, 9, 10),
      tz: _tz,
      flow: FlowLevel.none,
      tags: const ['mood'],
      note: 'kept',
      source: DayEntrySource.manual,
      updatedAt: DateTime.utc(2026, 9, 10),
    );
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-3',
        flow: HealthFlowValue.heavy,
        startIso: '2026-09-10T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.daysWritten, 1);
    final row = dayEntries.saved.single;
    expect(row.flow, FlowLevel.heavy);
    expect(row.source, DayEntrySource.healthkit);
    expect(row.sourceId, 'hk-3');
    // Additive merge: the row's own tags/note survive.
    expect(row.tags, ['mood']);
    expect(row.note, 'kept');
  });

  test(
    'the highest-intensity sample wins when several land on one day',
    () async {
      await bind();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'hk-l',
          flow: HealthFlowValue.light,
          startIso: '2026-09-10T04:00:00Z',
        ),
        _sample(
          id: 'hk-h',
          flow: HealthFlowValue.heavy,
          startIso: '2026-09-10T05:00:00Z',
        ),
        _sample(
          id: 'hk-m',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T06:00:00Z',
        ),
      ]);
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      final row = dayEntries.saved.single;
      expect(row.flow, FlowLevel.heavy);
      expect(row.sourceId, 'hk-h');
    },
  );

  test('a re-import of the same sample is a no-op', () async {
    await bind();
    dayEntries.live['2026-09-10'] = DayEntry(
      id: 'existing-hk',
      profileId: _profileId,
      localDate: LocalDate(2026, 9, 10),
      tz: _tz,
      flow: FlowLevel.medium,
      source: DayEntrySource.healthkit,
      sourceId: 'hk-1',
      updatedAt: DateTime.utc(2026, 9, 10),
    );
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-1',
        flow: HealthFlowValue.medium,
        startIso: '2026-09-10T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.daysUnchanged, 1);
    expect(summary.daysWritten, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test(
    'a changed value on a previously-imported day refreshes in place',
    () async {
      await bind();
      dayEntries.live['2026-09-10'] = DayEntry(
        id: 'existing-hk',
        profileId: _profileId,
        localDate: LocalDate(2026, 9, 10),
        tz: _tz,
        flow: FlowLevel.light,
        source: DayEntrySource.healthkit,
        sourceId: 'hk-old',
        updatedAt: DateTime.utc(2026, 9, 10),
      );
      source.result = HealthReadResult.samples([
        _sample(
          id: 'hk-new',
          flow: HealthFlowValue.heavy,
          startIso: '2026-09-10T04:00:00Z',
        ),
      ]);
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      final row = dayEntries.saved.single;
      expect(row.flow, FlowLevel.heavy);
      expect(row.sourceId, 'hk-new');
    },
  );

  test(
    'a read refusal maps to a blocked summary with the same check',
    () async {
      await bind();
      source.result = const HealthReadResult.refused(HealthSyncCheck.notOwner);
      final summary = await build().importNow();
      expect(
        (summary.blocked! as HealthPlatformRefused).check,
        HealthSyncCheck.notOwner,
      );
    },
  );

  test('an unavailable read maps to the unavailable blocked summary', () async {
    await bind();
    source.result = const HealthReadResult.unavailable();
    final summary = await build().importNow();
    expect(summary.blocked, isA<HealthPlatformUnavailable>());
  });

  test('a denied read and an empty result are both the neutral empty state '
      '(HealthKit opacity)', () async {
    await bind();
    source.result = const HealthReadResult.samples([]);
    final noData = await build().importNow();
    expect(noData.isBlocked, isFalse);
    expect(noData.isEmpty, isTrue);

    source.result = const HealthReadResult.permissionDenied();
    final denied = await build().importNow();
    // A denial is not distinguished from no data at the summary level: both
    // are "nothing usable came back", and the UI renders one neutral line.
    expect(denied.isEmpty, isTrue);
    expect(denied.isBlocked, isFalse);
  });

  test('a read failure surfaces as a blocked failed summary', () async {
    await bind();
    source.result = const HealthReadResult.failed('boom');
    final summary = await build().importNow();
    expect(summary.blocked, isA<HealthPlatformFailed>());
  });

  test('the pass writes only the bound profile', () async {
    await bind();
    source.result = HealthReadResult.samples([
      _sample(
        id: 'hk-1',
        flow: HealthFlowValue.light,
        startIso: '2026-09-10T04:00:00Z',
      ),
    ]);
    await build().importNow();
    expect(dayEntries.saved.single.profileId, _profileId);
  });

  group('Issue #458 Health Connect', () {
    test('imports write health_connect provenance and the clientRecordId',
        () async {
      await bind();
      source.result = HealthReadResult.samples([
        _offsetSample(
          id: 'hc-1',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T15:00:00Z',
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.daysWritten, 1);
      final row = dayEntries.saved.single;
      expect(row.source, DayEntrySource.healthConnect);
      expect(row.sourceId, 'hc-1');
      // The runner reports the platform the Settings copy names.
      expect(
        build(importPlatform: HealthImportPlatform.healthConnect).platform,
        HealthImportPlatform.healthConnect,
      );
    });

    test('the record\'s own zoneOffset resolves the civil date, not the '
        'device zone', () async {
      await bind();
      // 02:00Z on the 15th is still the 14th at -04:00.
      source.result = HealthReadResult.samples([
        _offsetSample(
          id: 'hc-tz',
          flow: HealthFlowValue.light,
          startIso: '2026-09-15T02:00:00Z',
        ),
      ]);
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      final row = dayEntries.saved.single;
      expect(row.localDate, LocalDate(2026, 9, 14));
      // No IANA name exists on a Health Connect record; the row carries the
      // record's fixed offset instead.
      expect(row.tz, 'UTC-04:00');
    });

    test('an intermenstrual-bleeding record becomes a spotting observation '
        'with health_connect provenance', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _bleedingSample(
          id: 'hc-spot',
          startIso: '2026-09-10T15:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.samplesRead, 1);
      expect(summary.spottingDaysWritten, 1);
      expect(observations.saved, hasLength(1));
      final observation = observations.saved.single;
      expect(observation.category, ObservationCategory.spotting);
      expect(observation.code, 'spotting');
      expect(observation.source, ObservationSource.healthConnect);
      expect(observation.sourceId, 'hc-spot');
      expect(observation.localDate, LocalDate(2026, 9, 10));
      // The carrier day entry exists so the observation has a home.
      expect(dayEntries.saved, hasLength(1));
      expect(dayEntries.saved.single.sourceId, isNull);
    });

    test('a day already carrying a spotting observation is never given a '
        'second one (a hand-logged value is not overwritten)', () async {
      await bind();
      final day = await dayEntries.save(
        DayEntry(
          id: '',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 10),
          tz: _tz,
          flow: FlowLevel.none,
          source: DayEntrySource.manual,
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );
      observations.byDay[day.id] = [
        Observation(
          id: 'manual-spot',
          dayEntryId: day.id,
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 10),
          tz: _tz,
          category: ObservationCategory.spotting,
          code: 'spotting',
          source: ObservationSource.manual,
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      ];
      source.result = HealthReadResult.samples([
        _bleedingSample(
          id: 'hc-spot',
          startIso: '2026-09-10T15:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.spottingDaysWritten, 0);
      expect(summary.daysKeptManual, 1);
      expect(observations.saved, isEmpty);
    });

    test('a re-import of the same intermenstrual record is a no-op',
        () async {
      await bind();
      source.result = HealthReadResult.samples([
        _bleedingSample(
          id: 'hc-spot',
          startIso: '2026-09-10T15:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(observations.saved, hasLength(1));

      // A second pass sees the existing health_connect spotting row.
      final second = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(second.spottingDaysWritten, 0);
      expect(second.daysUnchanged, 1);
      expect(observations.saved, hasLength(1));
    });

    test('an intermenstrual sample with no offset is skipped, not guessed',
        () async {
      await bind();
      source.result = HealthReadResult.samples([
        _bleedingSample(id: 'hc-no-zone', startIso: '2026-09-10T15:00:00Z'),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(summary.samplesWithoutZone, 1);
      expect(observations.saved, isEmpty);
    });
  });

  group('Issue #902 device-zone fallback', () {
    test('an iOS sample with no recorded zone but a device-zone offset is '
        'placed, not skipped', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _deviceZoneSample(
          id: 'hk-device-zone',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T04:00:00Z',
        ),
      ]);
      final summary = await build().importNow();

      expect(summary.samplesWithoutZone, 0);
      expect(summary.samplesFromDeviceZone, 1);
      expect(summary.samplesFromRecordedZone, 0);
      expect(summary.daysWritten, 1);
      final row = dayEntries.saved.single;
      expect(row.localDate, LocalDate(2026, 9, 10));
      expect(row.flow, FlowLevel.medium);
      // No IANA name exists for an inferred fallback; the row carries the
      // fixed-offset designator derived from the forwarded offset.
      expect(row.tz, 'UTC-04:00');
    });

    test('a device-zone row lands on the expected LocalDate, resolved from '
        'the forwarded offset', () async {
      await bind();
      // 02:00Z on the 15th is still the 14th at -04:00.
      source.result = HealthReadResult.samples([
        _deviceZoneSample(
          id: 'hk-device-midnight',
          flow: HealthFlowValue.light,
          startIso: '2026-09-15T02:00:00Z',
        ),
      ]);
      await build().importNow();
      expect(dayEntries.saved.single.localDate, LocalDate(2026, 9, 14));
    });

    test('a sample with a recorded tzName still uses that zone, even when a '
        'device offset also rides along (the #180 contract is unchanged)',
        () async {
      await bind();
      source.result = HealthReadResult.samples([
        HealthFlowSample(
          recordId: 'hk-tz-wins',
          flow: HealthFlowValue.light,
          start: DateTime.parse('2026-09-15T02:00:00Z'),
          end: DateTime.parse('2026-09-15T02:00:00Z'),
          tzName: 'America/New_York',
          offset: const Duration(hours: 9),
          offsetInferred: true,
        ),
      ]);
      final summary = await build().importNow();

      expect(summary.samplesFromRecordedZone, 1);
      expect(summary.samplesFromDeviceZone, 0);
      expect(dayEntries.saved.single.localDate, LocalDate(2026, 9, 14));
      expect(dayEntries.saved.single.tz, 'America/New_York');
    });

    test('the summary counts recorded-zone, device-zone and unplaceable rows '
        'separately', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'hk-recorded',
          flow: HealthFlowValue.light,
          startIso: '2026-09-10T04:00:00Z',
        ),
        _deviceZoneSample(
          id: 'hk-device',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-11T04:00:00Z',
        ),
        _sample(
          id: 'hk-unplaceable',
          flow: HealthFlowValue.heavy,
          startIso: '2026-09-12T04:00:00Z',
          tzName: null,
        ),
      ]);
      final summary = await build().importNow();

      expect(summary.samplesFromRecordedZone, 1);
      expect(summary.samplesFromDeviceZone, 1);
      expect(summary.samplesWithoutZone, 1);
    });
  });

  group('Issue #992 full-history paging', () {
    test('pages are read in order with the cursor the previous page '
        'returned, and a null cursor ends the pass', () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _sample(
              id: 'p1',
              flow: HealthFlowValue.light,
              startIso: '2026-09-09T04:00:00Z',
            ),
          ],
          nextCursor: 'cursor-2',
        ),
        const HealthReadResult.samples([], nextCursor: 'cursor-3'),
        HealthReadResult.samples(
          [
            _sample(
              id: 'p3',
              flow: HealthFlowValue.medium,
              startIso: '2026-09-10T04:00:00Z',
            ),
          ],
        ),
      ];
      final summary = await build().importNow();

      expect(summary.pagesRead, 3);
      expect(source.calls, 3);
      expect(source.cursorsSeen, [null, 'cursor-2', 'cursor-3']);
      expect(summary.samplesRead, 2);
      expect(summary.daysWritten, 2);
      expect(summary.repeatedCursor, isFalse);
      expect(summary.pageLimitReached, isFalse);
    });

    test('a page with no samples but a live cursor continues the pass',
        () async {
      await bind();
      source.pages = [
        // Every raw sample on this page was our own write, so it filtered
        // to nothing — but the page advanced, so the loop must continue.
        const HealthReadResult.samples([], nextCursor: 'cursor-2'),
        HealthReadResult.samples([
          _sample(
            id: 'later',
            flow: HealthFlowValue.heavy,
            startIso: '2026-09-10T04:00:00Z',
          ),
        ]),
      ];
      final summary = await build().importNow();
      expect(summary.pagesRead, 2);
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.sourceId, 'later');
    });

    test('the highest intensity wins even when the samples land on '
        'different pages', () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _sample(
              id: 'light-page',
              flow: HealthFlowValue.light,
              startIso: '2026-09-10T04:00:00Z',
            ),
          ],
          nextCursor: 'cursor-2',
        ),
        HealthReadResult.samples([
          _sample(
            id: 'heavy-page',
            flow: HealthFlowValue.heavy,
            startIso: '2026-09-10T05:00:00Z',
          ),
        ]),
      ];
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
      expect(dayEntries.saved.single.sourceId, 'heavy-page');
    });

    test('a repeated cursor stops the pass instead of spinning', () async {
      await bind();
      source.pages = [
        const HealthReadResult.samples([], nextCursor: 'same'),
        const HealthReadResult.samples([], nextCursor: 'same'),
      ];
      final summary = await build().importNow();
      expect(summary.repeatedCursor, isTrue);
      expect(summary.pagesRead, 2);
    });

    test('a cursor already seen this pass stops the pass', () async {
      await bind();
      source.pages = [
        const HealthReadResult.samples([], nextCursor: 'A'),
        const HealthReadResult.samples([], nextCursor: 'B'),
        const HealthReadResult.samples([], nextCursor: 'A'),
      ];
      final summary = await build().importNow();
      expect(summary.repeatedCursor, isTrue);
      expect(summary.pagesRead, 3);
    });

    test('the page cap stops a runaway adapter', () async {
      await bind();
      source.pages = [
        for (var i = 0; i < kHealthImportMaxPages + 5; i++)
          HealthReadResult.samples([], nextCursor: 'cursor-$i'),
      ];
      final summary = await build().importNow();
      expect(summary.pageLimitReached, isTrue);
      expect(summary.pagesRead, kHealthImportMaxPages);
    });

    test('onProgress reports the running counts after each page', () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _sample(
              id: 'a',
              flow: HealthFlowValue.light,
              startIso: '2026-09-09T04:00:00Z',
            ),
          ],
          nextCursor: 'cursor-2',
        ),
        HealthReadResult.samples([
          _sample(
            id: 'b',
            flow: HealthFlowValue.medium,
            startIso: '2026-09-10T04:00:00Z',
          ),
        ]),
      ];
      final ticks = <HealthImportProgress>[];
      await build().importNow(onProgress: ticks.add);
      expect(ticks, hasLength(2));
      expect(ticks[0].pagesRead, 1);
      expect(ticks[0].samplesRead, 1);
      expect(ticks[1].pagesRead, 2);
      expect(ticks[1].samplesRead, 2);
    });

    test('a large page is still resolved correctly through the isolate '
        'offload seam', () async {
      await bind();
      // More than kHealthImportResolveOffloadThreshold samples on ONE day,
      // so the page-resolution runs on a background isolate and the
      // accumulator still keeps the single highest flow.
      source.result = HealthReadResult.samples([
        for (var i = 0; i < kHealthImportResolveOffloadThreshold; i++)
          _sample(
            id: 'iso-$i',
            flow: HealthFlowValue.light,
            startIso: '2026-09-10T04:00:00Z',
          ),
        _sample(
          id: 'iso-heavy',
          flow: HealthFlowValue.heavy,
          startIso: '2026-09-10T05:00:00Z',
        ),
      ]);
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
      expect(dayEntries.saved.single.sourceId, 'iso-heavy');
    });
  });
}
