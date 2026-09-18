/// `LocalAppleHealthImportService`'s whole policy (Issue #217): the binding
/// guard runs first (zero health calls on a deny), authorization precedes
/// the read, only the bound profile is written, the sample's OWN zone
/// resolves its civil date, our own writes are excluded natively (proven
/// separately in the codec/channel tests), a hand-logged value is never
/// overwritten, an unlogged day is upgraded, provenance is `healthkit`, and
/// the four Apple-computed deviation types are never touched by any path
/// here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
const _tz = 'America/New_York';

/// The fixed "today" every pass resolves its window against. The window is
/// [kAppleHealthImportWindowDays] days back inclusive, i.e. 2026-08-17 …
/// 2026-09-15.
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
  HealthReadResult result = const HealthReadResult.samples([]);
  int calls = 0;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<HealthReadResult> readMenstrualFlow(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  }) async {
    calls++;
    lastStart = start;
    lastEnd = end;
    return result;
  }
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

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async =>
      live[localDate.iso];

  @override
  Future<DayEntry> save(DayEntry entry) async {
    saved.add(entry);
    live[entry.localDate.iso] = entry;
    return entry;
  }

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

void main() {
  late FakeSettingsStore settings;
  late _FakePlatform platform;
  late _FakeSource source;
  late _FakeProfiles profiles;
  late _FakeDayEntries dayEntries;
  late HealthSyncBinding binding;

  LocalAppleHealthImportService build() => LocalAppleHealthImportService(
    platform: platform,
    source: source,
    binding: binding,
    minorBindingAllowed: false,
    profiles: profiles,
    dayEntries: dayEntries,
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

  test('samples outside the bounded window are ignored', () async {
    await bind();
    source.result = HealthReadResult.samples([
      // 2026-08-16 is one day before the 30-day window opens.
      _sample(
        id: 'hk-old',
        flow: HealthFlowValue.heavy,
        startIso: '2026-08-16T04:00:00Z',
      ),
    ]);
    final summary = await build().importNow();
    expect(summary.samplesRead, 1);
    expect(summary.daysWritten, 0);
    expect(dayEntries.saved, isEmpty);
  });

  test(
    'the query window is widened a day either side of the civil window',
    () async {
      await bind();
      await build().importNow();
      // Window opens 2026-08-17, closes 2026-09-15; query is padded by one
      // day before and two days after (exclusive end).
      expect(source.lastStart, DateTime.utc(2026, 8, 16));
      expect(source.lastEnd, DateTime.utc(2026, 9, 17));
    },
  );

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
}
