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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_import_declined.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';
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
  @override
  bool writesCycleStart = true;

  HealthPlatformResult bindResult = const HealthPlatformAllowed();
  HealthPlatformResult authResult = const HealthPlatformAllowed();
  int bindCalls = 0;

  /// Issue #1515: there are two permission requests now. The import's own
  /// ([requestImportAuthorization]) and the write path's
  /// ([requestWriteAuthorization]) are counted apart, so a test can prove
  /// which one a tap of Import raises; [authCalls] is both together, for
  /// the tests that only care that nothing prompted.
  int importAuthCalls = 0;
  int writeAuthCalls = 0;
  int get authCalls => importAuthCalls + writeAuthCalls;

  /// Issue #959: the WRITE-side OS-permission probe. The write pass reads
  /// it; since Issue #1491 the import never does, so the default is
  /// granted and the tests below count its calls to prove that.
  HealthPermissionStatus permissionStatusResult =
      HealthPermissionStatus.granted;
  int permissionStatusCalls = 0;

  /// Issue #1491: the READ-side probe the background pass consults instead
  /// of prompting (Issue #993). Defaults to granted, like an install that
  /// already completed its first user-initiated pass.
  HealthPermissionStatus importPermissionStatusResult =
      HealthPermissionStatus.granted;
  int importPermissionStatusCalls = 0;

  /// Issue #1549: whether a read reaches data from before access was
  /// first allowed ("Access past data").
  bool reachesPastData = false;

  @override
  Future<bool> importReachesPastData() async => reachesPastData;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async {
    bindCalls++;
    return bindResult;
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async {
    writeAuthCalls++;
    return authResult;
  }

  @override
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) async {
    importAuthCalls++;
    return authResult;
  }

  @override
  Future<HealthPermissionStatus> permissionStatus() async {
    permissionStatusCalls++;
    return permissionStatusResult;
  }

  @override
  Future<HealthPermissionStatus> importPermissionStatus() async {
    importPermissionStatusCalls++;
    return importPermissionStatusResult;
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

  /// Issue #1652: whether the read asked for the whole history, one entry
  /// per call.
  final List<bool> wholeHistorySeen = [];

  /// Issue #1212's overlap test: when set, the FIRST read awaits this gate
  /// before returning — holds one pass open inside its read so a test can
  /// start a second pass while it is mid-flight.
  Completer<void>? firstReadGate;

  @override
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
    bool wholeHistory = false,
  }) async {
    lastStart = start;
    lastEnd = end;
    lastPageSize = pageSize;
    lastCursor = cursor;
    cursorsSeen.add(cursor);
    wholeHistorySeen.add(wholeHistory);
    final index = calls;
    calls++;
    final gate = index == 0 ? firstReadGate : null;
    if (gate != null && !gate.isCompleted) await gate.future;
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

  int commitCalls = 0;
  final List<String> committedTokens = [];

  @override
  Future<HealthPlatformResult> commitImport(
    HealthGuardFacts facts,
    String commitToken,
  ) async {
    commitCalls++;
    committedTokens.add(commitToken);
    return const HealthPlatformResult.allowed();
  }

  /// Issue #1573: whether the store has an "Access past data" switch, each
  /// request raised for it, and what the port answers.
  bool pastDataOffered = true;
  final List<HealthGuardFacts> pastDataRequests = [];
  HealthPlatformResult pastDataResult = const HealthPlatformResult.allowed();

  /// Run while the prompt is up, to play the person's answer.
  void Function()? onPastDataRequest;

  @override
  Future<bool> pastDataSwitchOffered() async => pastDataOffered;

  @override
  Future<HealthPlatformResult> requestPastDataAccess(
    HealthGuardFacts facts,
  ) async {
    pastDataRequests.add(facts);
    onPastDataRequest?.call();
    return pastDataResult;
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

class _FakeDayEntries
    implements
        DayEntriesRepository,
        DeletedDayEntryReader,
        HealthImportDeclinedStore {
  final Map<String, DayEntry> live = {};
  final List<DayEntry> saved = [];

  /// The health-store records the device remembers she deleted (Issue
  /// #1561), each with the moment of the deletion.
  final Map<String, DateTime> deletedRecords = {};

  /// Issue #1652: the records the device remembers the import declined,
  /// keyed `<source>|<record id>`.
  final Map<String, HealthImportDeclinedRecord> declinedRecords = {};

  /// What the import asked to be forgotten from the declined memory, one
  /// set per call.
  final List<Set<String>> forgottenDeclined = [];

  /// Records that become remembered after the first reading of
  /// [deletedRecords]: a deletion she makes while a pass is running.
  final Map<String, DateTime> deletedMidPass = {};

  /// What the import asked to be forgotten, one map per call.
  final List<Map<String, DateTime>> forgotten = [];

  /// Makes every [save] throw, to end a pass part-way.
  bool failSaves = false;
  int _reads = 0;
  int _nextId = 0;
  Object? saveError;

  /// Runs once, after the next [find] has read its answer — the seam a
  /// test uses to hand-log a row between the import's first look at a
  /// date and its write (Issue #1587 item 4).
  void Function()? onAfterFind;

  @override
  Future<Map<String, DateTime>> deletedHealthRecords(
    String profileId,
  ) async {
    if (_reads++ > 0) deletedRecords.addAll(deletedMidPass);
    return {...deletedRecords};
  }

  @override
  Future<void> forgetDeletedHealthRecords(
    String profileId,
    Map<String, DateTime> deletedAt,
  ) async {
    forgotten.add({...deletedAt});
    // Only while it still carries the moment given, as the storage does.
    deletedRecords.removeWhere((id, at) => deletedAt[id] == at);
  }

  /// Issue #1652: the declined memory, as the real repository reads and
  /// writes it.
  @override
  Future<Map<String, HealthImportDeclinedRecord>> readDeclinedHealthRecords(
    String profileId,
  ) async => {...declinedRecords};

  @override
  Future<void> rememberDeclinedHealthRecord(
    String profileId, {
    required String source,
    required String recordId,
    required HealthImportDeclinedKind kind,
    required LocalDate date,
  }) async {
    final key = healthImportDeclinedId(source, recordId);
    declinedRecords[key] = HealthImportDeclinedRecord(
      key: key,
      kind: kind,
      date: date,
    );
  }

  @override
  Future<void> forgetDeclinedHealthRecords(
    String profileId,
    Set<String> keys,
  ) async {
    forgottenDeclined.add({...keys});
    for (final key in keys) {
      declinedRecords.remove(key);
    }
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async {
    final row = live[localDate.iso];
    final hook = onAfterFind;
    if (hook != null) {
      onAfterFind = null;
      hook();
    }
    return row;
  }

  /// The pass's row scan (Issues #1594/#1683) reads the profile's rows
  /// through this.
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      live.values.toList();

  @override
  Future<DayEntry> save(DayEntry entry) async {
    if (failSaves) throw StateError('save failed');
    if (saveError != null) throw saveError!;
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
  Future<List<Observation>> listForProfile(String profileId) async =>
      [for (final rows in byDay.values) ...rows];

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
  DateTime? modifiedAt,
}) {
  final start = DateTime.parse(startIso);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    tzName: tzName,
    externalUuid: externalUuid,
    modifiedAt: modifiedAt,
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

/// One Health Connect `MenstruationPeriodRecord`: an interval from a period's
/// first-day local midnight to the last instant of its last day, with a zone
/// offset per endpoint (Issue #1556). [offset]/[endOffset] default to −04:00
/// on both endpoints — pass null for a record that carries no zone at all,
/// or a different [endOffset] for a span crossing a DST transition.
HealthFlowSample _periodSample({
  required String id,
  required String startIso,
  required String endIso,
  Duration? offset = const Duration(hours: -4),
  Duration? endOffset = const Duration(hours: -4),
  DateTime? modifiedAt,
}) {
  return HealthFlowSample(
    recordId: id,
    kind: HealthSampleKind.menstruationPeriod,
    start: DateTime.parse(startIso),
    end: DateTime.parse(endIso),
    offset: offset,
    endOffset: endOffset,
    modifiedAt: modifiedAt,
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

  // Issue #1515. The tap import used to ask through the write path's
  // request, which on Android carries every permission — so someone who had
  // allowed reading and declined writing was shown the write permissions
  // again on each tap of Import. It asks through a request of its own now.
  group('Issue #1515 the import asks through its own request', () {
    test('a tap of Import raises the import\'s request, once, and never '
        'the write path\'s', () async {
      await bind();
      source.result = const HealthReadResult.samples([]);

      await build().importNow();

      expect(platform.importAuthCalls, 1);
      expect(
        platform.writeAuthCalls,
        0,
        reason: 'the Import button has no reason to ask for write access',
      );
    });

    test('every tap asks the same way: a second import raises the import\'s '
        'request again and still not the write path\'s', () async {
      await bind();
      source.result = const HealthReadResult.samples([]);
      final service = build();

      await service.importNow();
      await service.importNow();

      expect(platform.importAuthCalls, 2);
      expect(platform.writeAuthCalls, 0);
    });

    test('a refused request ends the pass before any read, as before',
        () async {
      await bind();
      platform.authResult = const HealthPlatformPermissionDenied();

      final summary = await build().importNow();

      expect(summary.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.importAuthCalls, 1);
      expect(platform.writeAuthCalls, 0);
      expect(source.calls, 0);
    });

    test('a guard refusal raises neither request', () async {
      settings.setSilently(SettingsKeys.healthStoreProfileId, 'someone-else');

      await build().importNow();

      expect(platform.authCalls, 0);
    });

    test('a failed bind re-write raises neither request', () async {
      await bind();
      platform.bindResult = const HealthPlatformUnavailable();

      final summary = await build().importNow();

      expect(summary.blocked, isA<HealthPlatformUnavailable>());
      expect(platform.authCalls, 0);
      expect(source.calls, 0);
    });
  });

  test(
    'issue #1212: a background pass fired while an importNow pass runs '
    'queues behind it — the passes never interleave',
    () async {
      await bind();
      // Issue #1215: with no completed first import, a background pass is
      // a silent no-op before the serialization tail is ever reached — the
      // gate has its own tests. This test pins #1212's overlap contract
      // (two passes never interleave), so the gate is open before the
      // overlap starts.
      await binding.markFirstImportCompleted();
      // One page serving both entry points: a flow day plus an
      // intermenstrual-bleeding record for the SAME date. Two passes
      // merging that page concurrently is exactly the overlap the issue
      // describes — each `_mergeSpotting` reads then saves across an
      // await, so interleaved passes could each see no spotting and each
      // save one.
      source.result = HealthReadResult.samples([
        _sample(
          id: 'hk-flow',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T04:00:00Z',
        ),
        _bleedingSample(
          id: 'hk-spotting',
          startIso: '2026-09-10T05:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);
      final gate = Completer<void>();
      source.firstReadGate = gate;

      final service = build();
      final nowPass = service.importNow();
      // Let pass 1 reach (and hold inside) its first read.
      await pumpEventQueue();

      final backgroundPass = service.importInBackground();
      // Pass 2 resolves its binding, passes the guard, probes the
      // permission — and then must WAIT at `_runPass`'s tail: its read has
      // not started even once the event queue has fully drained.
      for (var i = 0; i < 3; i++) {
        await pumpEventQueue();
      }
      expect(
        source.calls,
        1,
        reason: 'the background pass must not read while the '
            'user-initiated pass is mid-flight',
      );

      gate.complete();
      final summaries = await Future.wait([nowPass, backgroundPass]);

      // Both passes ran, strictly one after the other.
      expect(source.calls, 2);
      expect(summaries[0].daysWritten, 1);
      expect(summaries[0].spottingDaysWritten, 1);
      // Pass 2 saw pass 1's rows: the day is already imported and the
      // spotting observation already exists — nothing new written.
      expect(summaries[1].daysUnchanged, 1);
      expect(summaries[1].spottingDaysWritten, 0);
      // The duplicate the issue describes never materializes: exactly one
      // spotting observation for the day despite two passes.
      expect(
        observations.saved
            .where((o) => o.category == ObservationCategory.spotting)
            .toList(),
        hasLength(1),
      );
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

  // Issue #1559. The day sheet keeps an imported row's `source` and
  // `sourceId` when she edits it by hand, so a corrected day still looks
  // imported. The import used to put the store's value back over it on
  // every whole-history read, which on an iPhone is every import.
  //
  // The row's `sourceId` now says which of the store's records it was
  // written from: the sample id (HealthKit), or the record id, `@`, and the
  // time the store last changed it (Health Connect). The import adopts a
  // different value only when the store's record is not that one.
  group('a hand correction to an imported day (#1559)', () {
    const day = '2026-09-10';
    final t0 = DateTime.utc(2026, 9, 11);
    final hc = HealthImportPlatform.healthConnect;
    String keyAt(String id, DateTime time) =>
        '$id@${time.millisecondsSinceEpoch}';

    // An imported day as the day sheet leaves it after she changes it: her
    // flow, her edit time, and the import's provenance untouched.
    DayEntry imported({
      required FlowLevel flow,
      required String? sourceId,
      DayEntrySource source = DayEntrySource.healthkit,
    }) =>
        DayEntry(
          id: 'imported-1',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 10),
          tz: _tz,
          flow: flow,
          tags: const ['cramps'],
          source: source,
          sourceId: sourceId,
          updatedAt: DateTime.utc(2026, 9, 12, 8),
        );

    HealthReadResult store(
      String id,
      HealthFlowValue flow, {
      DateTime? modifiedAt,
    }) =>
        HealthReadResult.samples([
          _sample(
            id: id,
            flow: flow,
            startIso: '2026-09-10T04:00:00Z',
            modifiedAt: modifiedAt,
          ),
        ]);

    test('the import, her correction, and the import again, start to finish',
        () async {
      await bind();
      source.result = store('rec-1', HealthFlowValue.heavy);
      await build().importNow();
      final written = dayEntries.live[day]!;
      expect(written.flow, FlowLevel.heavy);
      expect(written.sourceId, 'rec-1');

      // What the day sheet saves: her flow, the row's provenance kept.
      dayEntries.live[day] = written.copyWith(flow: FlowLevel.light);
      dayEntries.saved.clear();

      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(summary.daysWritten, 0);
      expect(dayEntries.saved, isEmpty, reason: 'nothing to write at all');
      expect(dayEntries.live[day]!.flow, FlowLevel.light);
    });

    test('the same, on Health Connect', () async {
      await bind();
      source.result = store('rec-1', HealthFlowValue.heavy, modifiedAt: t0);
      await build(importPlatform: hc).importNow();
      final written = dayEntries.live[day]!;
      expect(written.sourceId, keyAt('rec-1', t0));

      dayEntries.live[day] = written.copyWith(flow: FlowLevel.light);
      dayEntries.saved.clear();

      final summary = await build(importPlatform: hc).importNow();
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });

    // The column outlives the row's content: a deleted day keeps it, on
    // the server and in every guardian's copy. It may say which record, and
    // never what was logged.
    test('what the row remembers says nothing about the flow', () async {
      await bind();
      for (final flow in HealthFlowValue.values) {
        dayEntries.live.clear();
        dayEntries.saved.clear();
        source.result = store('rec-1', flow, modifiedAt: t0);
        await build(importPlatform: hc).importNow();
        for (final row in dayEntries.saved) {
          expect(row.sourceId, keyAt('rec-1', t0), reason: '$flow');
        }
      }
    });

    test('a day she cleared stays cleared', () async {
      await bind();
      dayEntries.live[day] = imported(flow: FlowLevel.none, sourceId: 'rec-1');
      source.result = store('rec-1', HealthFlowValue.heavy);
      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });

    test('a new record for the day is adopted, and the rest of the day kept',
        () async {
      await bind();
      dayEntries.live[day] = imported(flow: FlowLevel.light, sourceId: 'rec-1');
      source.result = store('rec-2', HealthFlowValue.medium);
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      final row = dayEntries.saved.single;
      expect(row.flow, FlowLevel.medium);
      expect(row.sourceId, 'rec-2');
      expect(row.tags, ['cramps']);
    });

    // The first review's finding. The row's `updatedAt` moves on any edit,
    // so it cannot say whether the store's change came before or after hers.
    test('Health Connect: a tag added after the store changed does not hide '
        'the change', () async {
      await bind();
      // Imported as light at t0. The store then changed the same record to
      // heavy (t1), and after that she added a tag (the row's time, 08:00
      // on the 12th, is later than t1).
      final t1 = DateTime.utc(2026, 9, 12, 7);
      dayEntries.live[day] = imported(
        flow: FlowLevel.light,
        sourceId: keyAt('rec-1', t0),
        source: DayEntrySource.healthConnect,
      );
      source.result = store('rec-1', HealthFlowValue.heavy, modifiedAt: t1);
      final summary = await build(importPlatform: hc).importNow();
      expect(summary.daysWritten, 1);
      expect(summary.daysKeptManual, 0);
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
      expect(dayEntries.saved.single.sourceId, keyAt('rec-1', t1));
    });

    test('a record replaced by one with the same value moves the key, so a '
        'correction made afterwards is still hers', () async {
      await bind();
      dayEntries.live[day] = imported(flow: FlowLevel.heavy, sourceId: 'rec-1');
      source.result = store('rec-2', HealthFlowValue.heavy);
      final summary = await build().importNow();
      expect(summary.daysUnchanged, 1);
      expect(summary.daysWritten, 0);
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
      expect(dayEntries.saved.single.sourceId, 'rec-2');

      // She corrects it; the store still holds rec-2.
      dayEntries.live[day] =
          dayEntries.live[day]!.copyWith(flow: FlowLevel.light);
      dayEntries.saved.clear();
      expect((await build().importNow()).daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });

    group('a Health Connect row from before the key carried a time', () {
      test('the same record changed after the row did is the store\'s news; '
          'not changed since is her edit, and the row gets its key', () async {
        await bind();
        for (final (modifiedAt, adopted) in [
          (DateTime.utc(2026, 9, 12, 9), true),
          (DateTime.utc(2026, 9, 11), false),
          // The very instant of her edit is not after it.
          (DateTime.utc(2026, 9, 12, 8), false),
        ]) {
          dayEntries.saved.clear();
          dayEntries.live[day] = imported(
            flow: FlowLevel.light,
            sourceId: 'rec-1',
            source: DayEntrySource.healthConnect,
          );
          source.result = store(
            'rec-1',
            HealthFlowValue.heavy,
            modifiedAt: modifiedAt,
          );
          final summary = await build(importPlatform: hc).importNow();
          final row = dayEntries.saved.single;
          expect(row.sourceId, keyAt('rec-1', modifiedAt),
              reason: '$modifiedAt');
          expect(
            row.flow,
            adopted ? FlowLevel.heavy : FlowLevel.light,
            reason: '$modifiedAt',
          );
          expect(summary.daysWritten, adopted ? 1 : 0, reason: '$modifiedAt');

          // Keyed now: the same record read again changes nothing.
          dayEntries.saved.clear();
          await build(importPlatform: hc).importNow();
          expect(dayEntries.saved, isEmpty, reason: '$modifiedAt');
        }
      });

      test('an untouched day is not rewritten', () async {
        await bind();
        dayEntries.live[day] = imported(
          flow: FlowLevel.heavy,
          sourceId: 'rec-1',
          source: DayEntrySource.healthConnect,
        );
        source.result = store('rec-1', HealthFlowValue.heavy, modifiedAt: t0);
        final summary = await build(importPlatform: hc).importNow();
        expect(summary.daysUnchanged, 1);
        expect(dayEntries.saved, isEmpty,
            reason: 'no burst of writes on the first pass after an update');
      });
    });

    test('a hand-logged day with no flow is still filled in', () async {
      await bind();
      dayEntries.live[day] = DayEntry(
        id: 'manual-none',
        profileId: _profileId,
        localDate: LocalDate(2026, 9, 10),
        tz: _tz,
        flow: FlowLevel.none,
        source: DayEntrySource.manual,
        updatedAt: DateTime.utc(2026, 9, 12, 8),
      );
      source.result = store('rec-1', HealthFlowValue.heavy);
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
      expect(dayEntries.saved.single.sourceId, 'rec-1');
    });

    // A row the spotting import created to hang an observation on has this
    // store's `source` and no `sourceId`. A flow on it is one she logged.
    test('a flow she logged on a spotting-only imported day is hers',
        () async {
      await bind();
      dayEntries.live[day] = imported(
        flow: FlowLevel.light,
        sourceId: null,
        source: DayEntrySource.healthConnect,
      );
      source.result = store('rec-1', HealthFlowValue.heavy, modifiedAt: t0);
      final summary = await build(importPlatform: hc).importNow();
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);

      // With no flow of her own, the store's is taken.
      dayEntries.live[day] = imported(
        flow: FlowLevel.none,
        sourceId: null,
        source: DayEntrySource.healthConnect,
      );
      await build(importPlatform: hc).importNow();
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
    });

    // A row that carries the other store's provenance is not this
    // importer's: only an empty flow is filled.
    test('a day imported from the other store is left alone', () async {
      await bind();
      dayEntries.live[day] = imported(
        flow: FlowLevel.light,
        sourceId: 'hc-rec@1',
        source: DayEntrySource.healthConnect,
      );
      source.result = store('rec-1', HealthFlowValue.heavy);
      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });
  });

  // Issue #1561. The import looked for a live row only, found none for a day
  // she had deleted, and inserted it again on every whole-history read.
  //
  // What she deletes is remembered on the device, by the store's record id,
  // when she deletes it. It is not read off deleted rows: removing a store's
  // imported data leaves deleted rows too, and an import after that must
  // bring the days back. What the storage layer remembers, and when, is
  // pinned against a real database in
  // `health_import_deletions_storage_test.dart`; the two together, in
  // `health_import_deleted_days_test.dart`.
  group('a day she deleted (#1561)', () {
    const day = '2026-09-10';
    final deletedAt = DateTime.utc(2026, 9, 12, 8);
    final hc = HealthImportPlatform.healthConnect;
    final spottingId = healthImportDeletionId('apple_health', 'hk-spot');
    String keyAt(String id, DateTime time) =>
        '$id@${time.millisecondsSinceEpoch}';

    // What the device remembers when she deletes an imported row.
    void sheDeleted(String sourceId, {String source = 'healthkit'}) {
      dayEntries.deletedRecords[healthImportDeletionId(source, sourceId)] =
          deletedAt;
    }

    DayEntry liveRow({
      required FlowLevel flow,
      DayEntrySource source = DayEntrySource.manual,
      String? sourceId,
      List<String> tags = const [],
    }) =>
        DayEntry(
          id: 'live-1',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 10),
          tz: _tz,
          flow: flow,
          tags: tags,
          source: source,
          sourceId: sourceId,
          updatedAt: DateTime.utc(2026, 9, 13),
        );

    Observation spotting({
      required String id,
      ObservationSource source = ObservationSource.appleHealth,
      String? sourceId = 'hk-spot',
    }) =>
        Observation(
          id: id,
          dayEntryId: 'live-1',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 10),
          tz: _tz,
          category: ObservationCategory.spotting,
          code: ObservationCategory.spotting.wireCode,
          source: source,
          sourceId: sourceId,
          updatedAt: deletedAt,
        );

    HealthReadResult store(
      String id, {
      DateTime? modifiedAt,
      HealthFlowValue flow = HealthFlowValue.heavy,
    }) =>
        HealthReadResult.samples([
          _sample(
            id: id,
            flow: flow,
            startIso: '2026-09-10T04:00:00Z',
            modifiedAt: modifiedAt,
          ),
        ]);

    HealthReadResult storeSpotting() => HealthReadResult.samples([
          _bleedingSample(
            id: 'hk-spot',
            startIso: '2026-09-10T04:00:00Z',
            offset: Duration.zero,
          ),
        ]);

    test('stays deleted while the store holds the same record, pass after '
        'pass', () async {
      await bind();
      sheDeleted('rec-1');
      source.result = store('rec-1');
      for (var pass = 0; pass < 2; pass++) {
        final summary = await build().importNow();
        expect(summary.daysWritten, 0);
        expect(summary.daysKeptManual, 1);
      }
      expect(dayEntries.saved, isEmpty);
      expect(dayEntries.forgotten, isEmpty);
    });

    test('comes back when the store has a different record for the day',
        () async {
      await bind();
      sheDeleted('rec-1');
      source.result = store('rec-2');
      final summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.sourceId, 'rec-2');
      expect(dayEntries.saved.single.flow, FlowLevel.heavy);
    });

    test('Health Connect: the same record, unchanged, stays deleted; '
        'changed since, it comes back', () async {
      await bind();
      final t0 = DateTime.utc(2026, 9, 11);
      final later = DateTime.utc(2026, 9, 13);
      sheDeleted(keyAt('rec-1', t0), source: 'health_connect');

      source.result = store('rec-1', modifiedAt: t0);
      expect(
        (await build(importPlatform: hc).importNow()).daysKeptManual,
        1,
      );
      expect(dayEntries.saved, isEmpty);

      source.result = store('rec-1', modifiedAt: later);
      final summary = await build(importPlatform: hc).importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.sourceId, keyAt('rec-1', later));
    });

    test('Health Connect: a day deleted before the key carried a time is '
        'decided by the record\'s time and the deletion\'s', () async {
      await bind();
      sheDeleted('rec-1', source: 'health_connect');
      for (final (modifiedAt, comesBack) in [
        // Changed after she deleted the day.
        (DateTime.utc(2026, 9, 12, 9), true),
        // Not changed since: what she deleted.
        (DateTime.utc(2026, 9, 11), false),
        (deletedAt, false),
      ]) {
        dayEntries.saved.clear();
        dayEntries.live.clear();
        source.result = store('rec-1', modifiedAt: modifiedAt);
        final summary = await build(importPlatform: hc).importNow();
        expect(summary.daysWritten, comesBack ? 1 : 0, reason: '$modifiedAt');
        expect(dayEntries.saved, comesBack ? hasLength(1) : isEmpty,
            reason: '$modifiedAt');
      }
    });

    test('what she deleted from the other store does not count', () async {
      await bind();
      sheDeleted('rec-1', source: 'health_connect');
      source.result = store('rec-1');
      expect((await build().importNow()).daysWritten, 1);
    });

    // What she deleted is read when the merge starts. A day deleted after
    // that has no live row for that reason, and was not in that reading:
    // writing it would undo a deletion made a moment ago. So it is read
    // again before a day with no live row is written.
    test('a day she deletes while the pass is running is not written back',
        () async {
      await bind();
      dayEntries.deletedMidPass[healthImportDeletionId('healthkit', 'rec-1')] =
          deletedAt;
      source.result = store('rec-1');
      final summary = await build().importNow();
      expect(summary.daysWritten, 0);
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });

    // Issue #1587 item 4: the first look at the date and the write are a
    // few awaits apart, with the memory read in between; she can hand-log
    // a day in that window. It must be merged with, not overwritten.
    test('a day hand-logged while the pass is running is merged with, not '
        'overwritten', () async {
      await bind();
      dayEntries.onAfterFind = () {
        dayEntries.live[day] = liveRow(flow: FlowLevel.light);
      };
      source.result = store('rec-1');

      final summary = await build().importNow();

      expect(summary.daysWritten, 0);
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.live[day]!.flow, FlowLevel.light);
      expect(dayEntries.live[day]!.sourceId, isNull);
      expect(dayEntries.saved, isEmpty);
    });

    // She deletes the imported day, then logs only a symptom on it. The
    // import must not fill that day's empty flow from the record she
    // deleted, or give the row that record's key.
    test('a symptom logged on the day afterwards does not let the deleted '
        'record back in', () async {
      await bind();
      sheDeleted('rec-1');
      dayEntries.live[day] = liveRow(
        flow: FlowLevel.none,
        tags: const ['cramps'],
      );
      source.result = store('rec-1');
      final summary = await build().importNow();
      expect(summary.daysWritten, 0);
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
    });

    test('a flow logged on the day afterwards is counted as unchanged when '
        'it matches the deleted record and as kept when it does not, and '
        'neither is written', () async {
      await bind();
      sheDeleted('rec-1');
      source.result = store('rec-1');

      dayEntries.live[day] = liveRow(flow: FlowLevel.heavy);
      var summary = await build().importNow();
      expect(summary.daysUnchanged, 1);
      expect(summary.daysKeptManual, 0);

      dayEntries.live[day] = liveRow(flow: FlowLevel.light);
      summary = await build().importNow();
      expect(summary.daysUnchanged, 0);
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
      expect(dayEntries.forgotten, isEmpty);
    });

    // Undo saves the deleted row again, with the record it came from. The
    // record stops counting as deleted when the import next sees that row.
    // What follows is the review's case: a heavier record is added and
    // adopted, then removed, and the first record is offered again.
    test('a deletion she undid is forgotten, and does not hold the day at a '
        'value the store no longer has', () async {
      await bind();
      sheDeleted('rec-1');
      dayEntries.live[day] = liveRow(
        flow: FlowLevel.light,
        source: DayEntrySource.healthkit,
        sourceId: 'rec-1',
      );

      source.result = store('rec-1', flow: HealthFlowValue.light);
      var summary = await build().importNow();
      expect(summary.daysUnchanged, 1);
      expect(dayEntries.saved, isEmpty);
      // Forgotten with the moment that was read, so that a record deleted
      // again in the meantime would be kept.
      expect(dayEntries.forgotten, [
        {healthImportDeletionId('healthkit', 'rec-1'): deletedAt},
      ]);
      expect(dayEntries.deletedRecords, isEmpty);

      source.result = store('rec-2');
      summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.live[day]!.sourceId, 'rec-2');
      expect(dayEntries.live[day]!.flow, FlowLevel.heavy);

      source.result = store('rec-1', flow: HealthFlowValue.light);
      summary = await build().importNow();
      expect(summary.daysWritten, 1);
      expect(dayEntries.live[day]!.sourceId, 'rec-1');
      expect(dayEntries.live[day]!.flow, FlowLevel.light);
    });

    // A pass that fails part-way has noted the row as live and forgotten
    // nothing. If the row is gone by the next pass (deleted on another
    // device, which this phone does not remember), her own earlier
    // deletion of that record still stands.
    test('what a failed pass saw does not carry into the next one',
        () async {
      await bind();
      sheDeleted('rec-1');
      dayEntries.live[day] = liveRow(
        flow: FlowLevel.heavy,
        source: DayEntrySource.healthkit,
        sourceId: 'rec-1',
      );
      source.result = HealthReadResult.samples([
        _sample(
          id: 'rec-1',
          flow: HealthFlowValue.heavy,
          startIso: '2026-09-10T04:00:00Z',
        ),
        _sample(
          id: 'rec-9',
          flow: HealthFlowValue.light,
          startIso: '2026-09-11T04:00:00Z',
        ),
      ]);
      final service = build();
      dayEntries.failSaves = true;
      await expectLater(service.importNow(), throwsStateError);
      expect(dayEntries.forgotten, isEmpty);

      dayEntries.failSaves = false;
      dayEntries.live.remove(day);
      final summary = await service.importNow();
      expect(dayEntries.live.containsKey(day), isFalse);
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.forgotten, isEmpty);
    });

    test('a spotting entry she removed stays removed, and no empty day is '
        'made for it', () async {
      await bind();
      dayEntries.deletedRecords[spottingId] = deletedAt;
      source.result = storeSpotting();
      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(dayEntries.saved, isEmpty);
      expect(observations.saved, isEmpty);

      // The same id under the other store's name does not keep it out.
      dayEntries.deletedRecords
        ..clear()
        ..[healthImportDeletionId('health_connect', 'hk-spot')] = deletedAt;
      await build().importNow();
      expect(observations.saved.single.sourceId, 'hk-spot');
    });

    test('a spotting entry she removes while the pass is running is not '
        'written back', () async {
      await bind();
      dayEntries.deletedMidPass[spottingId] = deletedAt;
      source.result = storeSpotting();
      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(observations.saved, isEmpty);
      expect(dayEntries.saved, isEmpty);
    });

    test('spotting she logged herself after removing the imported entry is '
        'kept, and the removal is still remembered', () async {
      await bind();
      dayEntries.deletedRecords[spottingId] = deletedAt;
      dayEntries.live[day] = liveRow(flow: FlowLevel.none);
      observations.byDay['live-1'] = [
        spotting(
          id: 'hand-1',
          source: ObservationSource.manual,
          sourceId: null,
        ),
      ];
      source.result = storeSpotting();
      final summary = await build().importNow();
      expect(summary.daysKeptManual, 1);
      expect(observations.saved, isEmpty);
      expect(dayEntries.forgotten, isEmpty);
    });

    test('a removed spotting entry that is live again is unchanged, and its '
        'removal is forgotten', () async {
      await bind();
      dayEntries.deletedRecords[spottingId] = deletedAt;
      dayEntries.live[day] = liveRow(flow: FlowLevel.none);
      observations.byDay['live-1'] = [spotting(id: 'imported-1')];
      source.result = storeSpotting();
      final summary = await build().importNow();
      expect(summary.daysUnchanged, 1);
      expect(summary.daysKeptManual, 0);
      expect(observations.saved, isEmpty);
      expect(dayEntries.forgotten, [
        {spottingId: deletedAt},
      ]);
    });
  });

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

  group('Issue #1523 a pass knows whether it read only what changed', () {
    test('a pass over change pages is incremental, and one that brings '
        'nothing back is still the empty state', () async {
      await bind();
      source.result = const HealthReadResult.samples([], incremental: true);
      final summary = await build().importNow();
      expect(summary.incremental, isTrue);
      expect(summary.isEmpty, isTrue);
      expect(summary.isBlocked, isFalse);
    });

    test('a full-history pass is not incremental, empty or not', () async {
      await bind();
      source.result = const HealthReadResult.samples([]);
      final empty = await build().importNow();
      expect(empty.incremental, isFalse);
      expect(empty.isEmpty, isTrue);

      source.result = HealthReadResult.samples([
        _sample(
          id: 'full-1',
          flow: HealthFlowValue.light,
          startIso: '2026-09-10T04:00:00Z',
        ),
      ]);
      final withData = await build().importNow();
      expect(withData.incremental, isFalse);
      expect(withData.daysWritten, 1);
    });

    test('an incremental pass that does bring days back says so too',
        () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _sample(
              id: 'chg-1',
              flow: HealthFlowValue.medium,
              startIso: '2026-09-11T04:00:00Z',
            ),
          ],
          nextCursor: 'chg:2',
          incremental: true,
        ),
        const HealthReadResult.samples([], incremental: true),
      ];
      final summary = await build().importNow();
      expect(summary.incremental, isTrue);
      expect(summary.isEmpty, isFalse);
      expect(summary.daysWritten, 1);
    });

    test('a read the store refuses is never reported as incremental',
        () async {
      await bind();
      source.result = const HealthReadResult.permissionDenied();
      final denied = await build().importNow();
      // Still the neutral empty state, and with no claim that the pass
      // only looked at what changed: nothing was read at all.
      expect(denied.isEmpty, isTrue);
      expect(denied.incremental, isFalse);
    });
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

  // Issue #1556: a source that records a period as one start-to-end record
  // and no per-day flow records used to import nothing. The record now
  // expands into bleed days across its span; a real flow record for the
  // same day always wins, so a both-types source still yields one entry
  // per day.
  //
  // Issue #1682: each expanded day carries its own record id — the record's
  // id, the day's date, and (through `_recordKey`) the record's
  // last-changed time — so the days never share a `source_id` and the
  // server's (profile_id, source, source_id) unique index admits them all.
  group('Issue #1556 period records', () {
    // The moment Health Connect last changed the record; every day's key
    // carries it after the day's own date.
    final changedAt = DateTime.utc(2026, 9, 10, 6);
    final changedMs = changedAt.millisecondsSinceEpoch;
    String dayKey(int day) =>
        'hc-period#2026-09-${day.toString().padLeft(2, '0')}@$changedMs';

    // Sep 10–12 2026 at a fixed −04:00: the start instant is the 10th's
    // local midnight, the end instant the 12th's last second.
    HealthReadResult threeDayPeriod() => HealthReadResult.samples([
          _periodSample(
            id: 'hc-period',
            startIso: '2026-09-10T04:00:00Z',
            endIso: '2026-09-13T03:59:59Z',
            modifiedAt: changedAt,
          ),
        ]);

    test('a period-only source imports its span as bleed days', () async {
      await bind();
      source.result = threeDayPeriod();
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.daysWritten, 3);
      expect(dayEntries.saved, hasLength(3));
      final byDate = {for (final day in dayEntries.saved) day.localDate: day};
      expect(byDate.keys, containsAll([
        LocalDate(2026, 9, 10),
        LocalDate(2026, 9, 11),
        LocalDate(2026, 9, 12),
      ]));
      for (final day in dayEntries.saved) {
        // The chosen level (health_flow_mapping.dart's
        // kPeriodRecordImportFlowLevel): the weakest real bleed level, so
        // an intensity the record does not carry is understated, never
        // invented as medium.
        expect(day.flow, FlowLevel.light);
        expect(day.source, DayEntrySource.healthConnect);
        expect(day.tz, 'UTC-04:00');
      }
      // Each day carries its own record key — the record id, the day's
      // date, the record's time — never one shared by the span. That is
      // what lets every day through the server's unique index; before
      // Issue #1682 all three read back 'hc-period' and only one synced.
      expect(
        {for (final day in dayEntries.saved) day.sourceId},
        {dayKey(10), dayKey(11), dayKey(12)},
      );
      // One record placed, counted once — not once per expanded day.
      expect(summary.samplesFromRecordedZone, 1);
      expect(summary.samplesRead, 1);
    });

    test('a second import of the same period record brings nothing new',
        () async {
      await bind();
      source.result = threeDayPeriod();
      final service = build(importPlatform: HealthImportPlatform.healthConnect);
      await service.importNow();
      expect(dayEntries.saved, hasLength(3));

      final second = await service.importNow();
      expect(second.daysWritten, 0);
      expect(second.daysUnchanged, 3);
      expect(dayEntries.saved, hasLength(3));
    });

    test('deleting one day of the span keeps it deleted while the other '
        'days stay live, and forgets nothing', () async {
      await bind();
      source.result = threeDayPeriod();
      final service = build(importPlatform: HealthImportPlatform.healthConnect);
      await service.importNow();

      // She deletes the 11th on the day sheet: the storage layer remembers
      // that day's own key (Issue #1561), and the row goes.
      dayEntries.deletedRecords[healthImportDeletionId(
        'health_connect',
        dayKey(11),
      )] = DateTime.utc(2026, 9, 13, 8);
      dayEntries.live.remove('2026-09-11');

      // The next pass sees the 10th and 12th live. Their rows name their
      // own keys, so neither counts as seeing the deleted day's record
      // again — before Issue #1682 the shared key did, and the deletion
      // was undone.
      final summary = await service.importNow();
      expect(summary.daysKeptManual, 1);
      expect(summary.daysUnchanged, 2);
      expect(dayEntries.live.keys, isNot(contains('2026-09-11')));
      expect(dayEntries.saved, hasLength(3),
          reason: 'the deleted day is not written back');
      expect(dayEntries.forgotten, isEmpty,
          reason: 'a sibling day naming the same record does not undo it');
    });

    test('a span written by the previous build re-keys every day on its '
        'next pass', () async {
      await bind();
      // Before Issue #1682 every day of the span shared the record's key.
      final shared = 'hc-period@$changedMs';
      for (var day = 10; day <= 12; day++) {
        await dayEntries.save(DayEntry(
          id: 'old-$day',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, day),
          tz: 'UTC-04:00',
          flow: FlowLevel.light,
          source: DayEntrySource.healthConnect,
          sourceId: shared,
          updatedAt: DateTime.utc(2026, 9, 13),
        ));
      }
      dayEntries.saved.clear();

      source.result = threeDayPeriod();
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.daysUnchanged, 3);
      expect(
        {for (final day in dayEntries.live.values) day.sourceId},
        {dayKey(10), dayKey(11), dayKey(12)},
        reason: 'each row takes its own day key, so the days the server '
            'rejected before can now be pushed',
      );
    });

    test('a day she corrected keeps her flow while the span re-keys',
        () async {
      await bind();
      final shared = 'hc-period@$changedMs';
      for (var day = 10; day <= 12; day++) {
        await dayEntries.save(DayEntry(
          id: 'old-$day',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, day),
          tz: 'UTC-04:00',
          // The 11th is hers: a hand edit keeps the row's provenance but
          // changes the flow.
          flow: day == 11 ? FlowLevel.heavy : FlowLevel.light,
          source: DayEntrySource.healthConnect,
          sourceId: shared,
          updatedAt: DateTime.utc(2026, 9, 13),
        ));
      }
      dayEntries.saved.clear();

      source.result = threeDayPeriod();
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(summary.daysKeptManual, 1);
      expect(summary.daysUnchanged, 2);
      final corrected = dayEntries.live['2026-09-11']!;
      expect(corrected.flow, FlowLevel.heavy,
          reason: 'the store did not change the record, so this is her edit');
      expect(corrected.sourceId, dayKey(11),
          reason: 'and the row still takes its own day key');
    });

    test('a both-types source yields one entry per day with the flow '
        'record winning', () async {
      await bind();
      // The period record arrives BEFORE the flow record, so this pins the
      // rank rule, not page order: any flow record outranks a period fill.
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-09-10T04:00:00Z',
          endIso: '2026-09-13T03:59:59Z',
          modifiedAt: changedAt,
        ),
        _offsetSample(
          id: 'hc-flow-11',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-11T15:00:00Z',
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      // Exactly one entry per day: the two days with no flow record are
      // filled by the period, the covered day carries the flow record.
      expect(summary.daysWritten, 3);
      final byDate = {for (final day in dayEntries.saved) day.localDate: day};
      final filledDay = byDate[LocalDate(2026, 9, 10)]!;
      expect(filledDay.flow, FlowLevel.light);
      expect(filledDay.sourceId, dayKey(10));
      final flowDay = byDate[LocalDate(2026, 9, 11)]!;
      expect(flowDay.flow, FlowLevel.medium);
      expect(flowDay.sourceId, 'hc-flow-11');
      expect(byDate[LocalDate(2026, 9, 12)]!.sourceId, dayKey(12));
    });

    test('a spotting record on a day inside the span coexists with the '
        'period day — they are different rows, nothing double counts',
        () async {
      await bind();
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-09-10T04:00:00Z',
          endIso: '2026-09-13T03:59:59Z',
        ),
        _bleedingSample(
          id: 'hc-spot-11',
          startIso: '2026-09-11T15:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      // Three bleed days AND the one spotting observation: a period record
      // never suppresses an intermenstrual record, and a spotting record
      // never becomes a second flow day.
      expect(summary.daysWritten, 3);
      expect(summary.spottingDaysWritten, 1);
      expect(observations.saved.single.localDate, LocalDate(2026, 9, 11));
      expect(observations.saved.single.sourceId, 'hc-spot-11');
    });

    test('a hand-logged day inside the span is never overwritten', () async {
      await bind();
      await dayEntries.save(
        DayEntry(
          id: '',
          profileId: _profileId,
          localDate: LocalDate(2026, 9, 11),
          tz: _tz,
          flow: FlowLevel.heavy,
          source: DayEntrySource.manual,
          updatedAt: DateTime.utc(2026, 9, 11),
        ),
      );
      source.result = threeDayPeriod();
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      // The hand-logged day keeps her value; the period fills the two
      // days she did not log.
      expect(summary.daysKeptManual, 1);
      expect(summary.daysWritten, 2);
      final byDate = {for (final day in dayEntries.saved) day.localDate: day};
      expect(byDate[LocalDate(2026, 9, 11)]!.flow, FlowLevel.heavy);
      expect(byDate[LocalDate(2026, 9, 11)]!.source, DayEntrySource.manual);
    });

    test('a record with no offset on either endpoint is skipped, not '
        'guessed', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-09-10T04:00:00Z',
          endIso: '2026-09-13T03:59:59Z',
          offset: null,
          endOffset: null,
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(summary.samplesWithoutZone, 1);
      expect(dayEntries.saved, isEmpty);
    });

    test('the end instant resolves in its own zone: on a DST-transition '
        'span the end offset, not the start offset, places the last day',
        () async {
      await bind();
      // US DST ended 2025-11-02 (the suite's clock sits at 2026-09-15, so
      // the span must lie before it). The end instant is Nov 3's last
      // second at −05:00; resolved in the start zone (−04:00) it would land
      // on Nov 4 and add a day that never existed.
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2025-11-02T04:00:00Z',
          endIso: '2025-11-04T04:59:59Z',
          offset: const Duration(hours: -4),
          endOffset: const Duration(hours: -5),
        ),
      ]);
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      final dates = dayEntries.saved.map((day) => day.localDate).toList();
      expect(dates, [LocalDate(2025, 11, 2), LocalDate(2025, 11, 3)]);
      final last = dayEntries.saved.last;
      expect(last.tz, 'UTC-05:00');
    });

    test('a span longer than any real period is counted, never expanded',
        () async {
      await bind();
      // ~5 months: Health Connect itself refuses to store a period record
      // longer than 31 days of elapsed time, so this is a corrupt record
      // (kMaxPeriodRecordSpanDays bounds the expansion).
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-01-01T05:00:00Z',
          endIso: '2026-06-01T05:00:00Z',
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(summary.samplesUnsupported, 1);
      expect(dayEntries.saved, isEmpty);
    });

    test('an end before the start is counted, never expanded', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-09-12T04:00:00Z',
          endIso: '2026-09-10T03:59:59Z',
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(summary.samplesUnsupported, 1);
      expect(dayEntries.saved, isEmpty);
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

  group('Issue #993 background pass (importInBackground)', () {
    /// Issue #1215: the tests below pin the pipeline's own properties (the
    /// prompt-free shape, the probe, the provenance), so they open the
    /// first-import consent gate directly rather than re-proving the
    /// importNow chain every time — the gate itself has its own tests.
    Future<void> completeFirstImport() => binding.markFirstImportCompleted();

    test('a background pass before the first user-initiated import is a '
        'no-op (issue #1215)', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'bg-early',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T12:00:00Z',
        ),
      ]);

      final summary = await build().importInBackground();

      // The consent gate, not the OS probe: the pass ends before either
      // permission probe is consulted, and nothing is read or written.
      expect(summary.firstImportNotStarted, isTrue);
      expect(summary.blocked, isNull);
      expect(platform.importPermissionStatusCalls, 0);
      expect(platform.permissionStatusCalls, 0);
      expect(source.calls, 0);
      expect(dayEntries.saved, isEmpty);
    });

    test('the first completed importNow opens the gate (issue #1215)',
        () async {
      await bind();
      // A first import that completes — even over an empty store — is the
      // consent the gate reads.
      await build().importNow();

      await build().importInBackground();
      expect(
        platform.importPermissionStatusCalls,
        1,
        reason: 'the gate opened past the consent check, all the way to '
            'the probe',
      );

      source.result = HealthReadResult.samples([
        _sample(
          id: 'bg-after-first',
          flow: HealthFlowValue.light,
          startIso: '2026-09-11T12:00:00Z',
        ),
      ]);
      final second = await build().importInBackground();
      expect(second.daysWritten, 1);
      expect(dayEntries.saved.single.sourceId, 'bg-after-first');
    });

    test('a first import that was blocked before its read never opens '
        'the gate (issue #1215)', () async {
      await bind();
      // The authorization sheet is refused: importNow ends blocked, and a
      // blocked pass stamps no consent.
      platform.authResult = const HealthPlatformPermissionDenied();
      final blocked = await build().importNow();
      expect(blocked.isBlocked, isTrue);

      platform.authResult = const HealthPlatformAllowed();
      final summary = await build().importInBackground();
      expect(summary.firstImportNotStarted, isTrue);
      expect(source.calls, 0);
    });

    test('re-binding re-gates the background pass (issue #1215)', () async {
      await bind();
      await build().importNow();
      // Same profile, a fresh binding: the consent belonged to the old one.
      await bind();

      final summary = await build().importInBackground();
      expect(summary.firstImportNotStarted, isTrue);
    });

    test('runs the same merge with zero prompts: no bind re-write, no '
        'authorization request', () async {
      await bind();
      await completeFirstImport();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'bg-1',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T12:00:00Z',
        ),
      ]);
      final summary = await build().importInBackground();

      // The merge is the user-initiated pipeline's: one written day with
      // the platform's provenance.
      expect(summary.blocked, isNull);
      expect(summary.daysWritten, 1);
      final entry = dayEntries.saved.single;
      expect(entry.flow, FlowLevel.medium);
      expect(entry.source, DayEntrySource.healthkit);
      expect(entry.sourceId, 'bg-1');

      // The background-specific property: the OS permission was probed —
      // the read-side probe, once, and never the write one (Issue #1491) —
      // and nothing prompt-shaped ever ran.
      expect(platform.importPermissionStatusCalls, 1);
      expect(platform.permissionStatusCalls, 0);
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
    });

    test('a not-granted OS permission ends the pass before any read',
        () async {
      await bind();
      await completeFirstImport();
      platform.importPermissionStatusResult = HealthPermissionStatus.notAsked;

      final summary = await build().importInBackground();

      expect(summary.bound, isTrue);
      expect(summary.blocked, isA<HealthPlatformPermissionDenied>());
      expect(source.calls, 0);
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
      expect(dayEntries.saved, isEmpty);
    });

    test('a revoked OS permission stops the next background pass', () async {
      await bind();
      await completeFirstImport();
      platform.importPermissionStatusResult = HealthPermissionStatus.denied;

      final summary = await build().importInBackground();

      expect(summary.blocked, isA<HealthPlatformPermissionDenied>());
      expect(source.calls, 0);
    });

    // Issue #1491. The background pass used to stop unless the WRITE
    // probe read granted, so someone who let lunarlog read from Health
    // Connect but not write to it got a working Import button and a
    // background import that never ran. It is gated on the read-side
    // probe now; the write probe is the write path's alone.
    test('reads on, writes off: a background pass imports (issue #1491)',
        () async {
      await bind();
      await completeFirstImport();
      platform.importPermissionStatusResult = HealthPermissionStatus.granted;
      platform.permissionStatusResult = HealthPermissionStatus.denied;
      source.result = HealthReadResult.samples([
        _offsetSample(
          id: 'bg-reads-only',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-12T12:00:00Z',
        ),
      ]);

      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importInBackground();

      expect(summary.blocked, isNull);
      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.sourceId, 'bg-reads-only');
      expect(dayEntries.saved.single.source, DayEntrySource.healthConnect);
      // Still prompt-free.
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
    });

    test('the read-side probe decides, whatever the write probe says: '
        'anything but granted stops before any read (issue #1491)',
        () async {
      await bind();
      await completeFirstImport();
      source.result = HealthReadResult.samples([
        _sample(
          id: 'bg-never-read',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T12:00:00Z',
        ),
      ]);
      // Every write permission is on; the reads are not.
      platform.permissionStatusResult = HealthPermissionStatus.granted;

      for (final notGranted in [
        HealthPermissionStatus.notAsked,
        HealthPermissionStatus.denied,
        HealthPermissionStatus.unavailable,
      ]) {
        platform.importPermissionStatusResult = notGranted;

        final summary = await build().importInBackground();

        expect(
          summary.blocked,
          isA<HealthPlatformPermissionDenied>(),
          reason: '$notGranted must stop the pass',
        );
      }
      expect(source.calls, 0);
      expect(dayEntries.saved, isEmpty);
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
      expect(
        platform.permissionStatusCalls,
        0,
        reason: 'the write probe is not the import\'s to read',
      );
    });

    test('the tap import consults neither probe: it asks through its own '
        'authorization request (issues #1491, #1515)', () async {
      await bind();
      // Whatever either probe would say, a tap is the person asking.
      platform.importPermissionStatusResult = HealthPermissionStatus.denied;
      platform.permissionStatusResult = HealthPermissionStatus.denied;
      source.result = HealthReadResult.samples([
        _sample(
          id: 'tap-1',
          flow: HealthFlowValue.light,
          startIso: '2026-09-10T12:00:00Z',
        ),
      ]);

      final summary = await build().importNow();

      expect(summary.daysWritten, 1);
      expect(platform.bindCalls, 1);
      expect(platform.importAuthCalls, 1);
      expect(platform.writeAuthCalls, 0);
      expect(platform.importPermissionStatusCalls, 0);
      expect(platform.permissionStatusCalls, 0);
    });

    test('the guard runs before the probe: a refused binding touches no '
        'health API at all', () async {
      // A stored binding that does not name the profile the pass resolves —
      // canWrite denies with profileNotBound before the OS permission is
      // asked. (Binding a minor with the flag off cannot set up the other
      // deny: the bind itself refuses and stores nothing.)
      await bind();
      settings.setSilently(SettingsKeys.healthStoreProfileId, 'someone-else');

      final summary = await build().importInBackground();

      expect(summary.bound, isTrue);
      final blocked = summary.blocked;
      expect(blocked, isA<HealthPlatformRefused>());
      expect(
        (blocked! as HealthPlatformRefused).check,
        HealthSyncCheck.profileNotBound,
      );
      expect(platform.importPermissionStatusCalls, 0);
      expect(platform.permissionStatusCalls, 0);
      expect(source.calls, 0);
      expect(dayEntries.saved, isEmpty);
    });

    test('an unbound device is a no-op: no probe, no read', () async {
      final summary = await build().importInBackground();

      expect(summary.bound, isFalse);
      expect(platform.importPermissionStatusCalls, 0);
      expect(platform.permissionStatusCalls, 0);
      expect(source.calls, 0);
      expect(dayEntries.saved, isEmpty);
    });

    test('the Health Connect provenance rides the background merge too',
        () async {
      await bind();
      await completeFirstImport();
      source.result = HealthReadResult.samples([
        _offsetSample(
          id: 'bg-hc-1',
          flow: HealthFlowValue.light,
          startIso: '2026-09-11T12:00:00Z',
        ),
      ]);
      final summary = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importInBackground();

      expect(summary.daysWritten, 1);
      expect(dayEntries.saved.single.source, DayEntrySource.healthConnect);
      expect(dayEntries.saved.single.sourceId, 'bg-hc-1');
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
    });
  });

  // Issue #1573: the Health sync screen's button raises Health Connect's
  // own prompt for "Access past data". The port's answer does not say what
  // was granted, so the service answers from what a read reaches after it.
  group('asking for past data (Issue #1573)', () {
    test('with no bound profile nothing is asked, and the answer is still '
        'the store\'s', () async {
      expect(await build().requestPastDataAccess(), isFalse);
      platform.reachesPastData = true;
      expect(await build().requestPastDataAccess(), isTrue);

      expect(source.pastDataRequests, isEmpty);
    });

    test('the prompt is raised for the bound profile, and a grant is yes',
        () async {
      await bind();
      source.onPastDataRequest = () => platform.reachesPastData = true;

      expect(await build().requestPastDataAccess(), isTrue);
      expect(source.pastDataRequests.single.profile.id, _profileId);
      expect(platform.authCalls, 0,
          reason: 'neither of the two other requests is raised');
    });

    test('the port answering allowed is not a grant: Health Connect drops a '
        'twice-declined request and answers the same', () async {
      await bind();
      source.pastDataResult = const HealthPlatformResult.allowed();

      expect(await build().requestPastDataAccess(), isFalse);
      expect(source.pastDataRequests, hasLength(1));
    });

    test('and the port answering no is not a refusal, if a read reaches the '
        'older data all the same', () async {
      await bind();
      source.pastDataResult = const HealthPlatformResult.permissionDenied();
      platform.reachesPastData = true;

      expect(await build().requestPastDataAccess(), isTrue);
    });

    test('whether there is a switch at all is the store\'s answer', () async {
      expect(await build().pastDataSwitchOffered(), isTrue);
      source.pastDataOffered = false;
      expect(await build().pastDataSwitchOffered(), isFalse);
    });
  });

  group('commitImport (Issue #1560)', () {
    test('commits position once after days are stored', () async {
      await bind();
      source.result = HealthReadResult.samples(
        [
          _offsetSample(
            id: 'hc-1',
            flow: HealthFlowValue.medium,
            startIso: '2026-09-10T12:00:00Z',
          ),
        ],
        commitToken: 'commit-token-abc',
      );

      final summary = await build().importNow();

      expect(summary.daysWritten, 1);
      expect(source.commitCalls, 1);
      expect(source.committedTokens, ['commit-token-abc']);
    });

    test('multi-page read commits only the token from the final page', () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _offsetSample(
              id: 'hc-1',
              flow: HealthFlowValue.medium,
              startIso: '2026-09-10T12:00:00Z',
            ),
          ],
          nextCursor: 'cursor-page-2',
          commitToken: 'intermediate-token',
        ),
        HealthReadResult.samples(
          [
            _offsetSample(
              id: 'hc-2',
              flow: HealthFlowValue.light,
              startIso: '2026-09-11T12:00:00Z',
            ),
          ],
          nextCursor: null,
          commitToken: 'final-commit-token',
        ),
      ];

      final summary = await build().importNow();

      expect(summary.daysWritten, 2);
      expect(source.commitCalls, 1);
      expect(source.committedTokens, ['final-commit-token']);
    });

    test('a merge that throws never commits the position', () async {
      await bind();
      dayEntries.saveError = StateError('disk I/O error');
      source.result = HealthReadResult.samples(
        [
          _offsetSample(
            id: 'hc-1',
            flow: HealthFlowValue.medium,
            startIso: '2026-09-10T12:00:00Z',
          ),
        ],
        commitToken: 'commit-token-abc',
      );

      expect(() => build().importNow(), throwsA(isA<StateError>()));
      expect(source.commitCalls, 0);
    });

    test('a blocked pass never commits the position', () async {
      await bind();
      source.pages = [
        HealthReadResult.samples(
          [
            _offsetSample(
              id: 'hc-1',
              flow: HealthFlowValue.medium,
              startIso: '2026-09-10T12:00:00Z',
            ),
          ],
          nextCursor: 'cursor-page-2',
        ),
        const HealthReadResult.failed('store error'),
      ];

      final summary = await build().importNow();

      expect(summary.isBlocked, isTrue);
      expect(source.commitCalls, 0);
    });

    test('a pass with null commitToken does not call commitImport', () async {
      await bind();
      source.result = HealthReadResult.samples([
        _offsetSample(
          id: 'hc-1',
          flow: HealthFlowValue.medium,
          startIso: '2026-09-10T12:00:00Z',
        ),
      ]);

      final summary = await build().importNow();

      expect(summary.daysWritten, 1);
      expect(source.commitCalls, 0);
    });
  });

  // Issue #1652. The merge declines a store record over her own value, and
  // an anchored or changes read never returns a record that did not
  // change — so without a memory the record was never offered again, and
  // clearing her flow (or removing her spotting entry) could not let the
  // store's value in.
  group('issue #1652: a declined record is offered again', () {
    final day = LocalDate(2026, 9, 10);

    DayEntry herDay(FlowLevel flow, DateTime updatedAt) => DayEntry(
      id: 'her-day',
      profileId: _profileId,
      localDate: day,
      tz: _tz,
      flow: flow,
      updatedAt: updatedAt,
    );

    HealthReadResult theStoreRecord() => HealthReadResult.samples([
      _sample(
        id: 'apple-rec-1',
        flow: HealthFlowValue.heavy,
        startIso: '2026-09-10T12:00:00Z',
      ),
    ]);

    test('a flow record declined over her own day comes back when she '
        'clears her flow', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.light,
        DateTime.utc(2026, 9, 10, 8),
      );
      source.result = theStoreRecord();

      final first = await build().importNow();

      expect(first.daysKeptManual, 1);
      final declined = dayEntries.declinedRecords.values.single;
      expect(declined.key, healthImportDeclinedId('healthkit', 'apple-rec-1'));
      expect(declined.kind, HealthImportDeclinedKind.flow);
      expect(declined.date, day);

      // Her flow is still there: nothing is owed, and the memory stays.
      source.wholeHistorySeen.clear();
      await build().importNow();
      expect(source.wholeHistorySeen, [false]);
      expect(dayEntries.declinedRecords, hasLength(1));

      // She clears her flow. The merge would now adopt the store's value,
      // but the record did not change, so only a whole read returns it.
      dayEntries.live[day.iso] = herDay(
        FlowLevel.none,
        DateTime.utc(2026, 9, 11, 8),
      );
      source.wholeHistorySeen.clear();

      final second = await build().importNow();

      expect(source.wholeHistorySeen, [true]);
      expect(second.daysWritten, 1);
      final adopted = dayEntries.live[day.iso]!;
      expect(adopted.flow, FlowLevel.heavy);
      expect(adopted.source, DayEntrySource.healthkit);
      expect(adopted.sourceId, 'apple-rec-1');
      expect(dayEntries.declinedRecords, isEmpty);
    });

    test('a flow record declined over her own day comes back when she '
        'deletes that day', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.light,
        DateTime.utc(2026, 9, 10, 8),
      );
      source.result = theStoreRecord();
      await build().importNow();
      expect(dayEntries.declinedRecords, hasLength(1));

      dayEntries.live.remove(day.iso);
      source.wholeHistorySeen.clear();

      final second = await build().importNow();

      expect(source.wholeHistorySeen, [true]);
      expect(second.daysWritten, 1);
      final inserted = dayEntries.live[day.iso]!;
      expect(inserted.flow, FlowLevel.heavy);
      expect(inserted.source, DayEntrySource.healthkit);
      expect(dayEntries.declinedRecords, isEmpty);
    });

    test('a record the store reports deleted is forgotten, so no whole read '
        'is owed for it', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.light,
        DateTime.utc(2026, 9, 10, 8),
      );
      source.result = theStoreRecord();
      await build().importNow();
      expect(dayEntries.declinedRecords, hasLength(1));

      // A later changes read reports the record deleted in the store.
      source.result = HealthReadResult.samples(
        const [],
        deletedRecordIds: const ['apple-rec-1'],
        incremental: true,
      );
      await build().importNow();
      expect(dayEntries.declinedRecords, isEmpty);

      // She clears her flow; there is nothing left to ask for again.
      dayEntries.live[day.iso] = herDay(
        FlowLevel.none,
        DateTime.utc(2026, 9, 11, 8),
      );
      source.wholeHistorySeen.clear();

      await build().importNow();

      expect(source.wholeHistorySeen, [false]);
      expect(dayEntries.live[day.iso]!.flow, FlowLevel.none);
    });

    test('a period-expanded day declined over her flow is dropped when the '
        'store reports the period record deleted (issue #1682)', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.medium,
        DateTime.utc(2026, 9, 10, 8),
      );
      source.result = HealthReadResult.samples([
        _periodSample(
          id: 'hc-period',
          startIso: '2026-09-10T04:00:00Z',
          endIso: '2026-09-11T03:59:59Z',
        ),
      ]);
      final first = await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(first.daysKeptManual, 1);
      expect(
        dayEntries.declinedRecords.keys,
        [healthImportDeclinedId('health_connect', 'hc-period#2026-09-10')],
      );

      // The store reports the period record deleted, by its bare id.
      source.result = HealthReadResult.samples(
        const [],
        deletedRecordIds: const ['hc-period'],
        incremental: true,
      );
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(dayEntries.declinedRecords, isEmpty);
    });

    test('a declined record a finished whole read does not return is '
        'forgotten', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.light,
        DateTime.utc(2026, 9, 10, 8),
      );
      source.result = theStoreRecord();
      await build().importNow();
      expect(dayEntries.declinedRecords, hasLength(1));

      // She clears her flow, and the store no longer holds the record
      // (deleted without a report: a whole read is what tells).
      dayEntries.live[day.iso] = herDay(
        FlowLevel.none,
        DateTime.utc(2026, 9, 11, 8),
      );
      source.result = const HealthReadResult.samples([]);
      source.wholeHistorySeen.clear();

      await build().importNow();

      expect(source.wholeHistorySeen, [true]);
      expect(dayEntries.declinedRecords, isEmpty);

      // Nothing is owed on the next pass.
      source.wholeHistorySeen.clear();
      await build().importNow();
      expect(source.wholeHistorySeen, [false]);
    });

    test('an intermenstrual record declined over her own spotting comes '
        'back when she removes it', () async {
      await bind();
      dayEntries.live[day.iso] = herDay(
        FlowLevel.none,
        DateTime.utc(2026, 9, 10, 8),
      );
      observations.byDay['her-day'] = [
        Observation(
          id: 'her-spot',
          dayEntryId: 'her-day',
          profileId: _profileId,
          localDate: day,
          tz: _tz,
          category: ObservationCategory.spotting,
          code: 'spotting',
          updatedAt: DateTime.utc(2026, 9, 10, 8),
        ),
      ];
      source.result = HealthReadResult.samples([
        _bleedingSample(
          id: 'ib-rec-1',
          startIso: '2026-09-10T12:00:00Z',
          offset: const Duration(hours: -4),
        ),
      ]);

      final first = await build().importNow();

      expect(first.spottingDaysWritten, 0);
      final declined = dayEntries.declinedRecords.values.single;
      expect(declined.key, healthImportDeclinedId('apple_health', 'ib-rec-1'));
      expect(declined.kind, HealthImportDeclinedKind.spotting);
      expect(declined.date, day);

      // She removes her own spotting entry.
      observations.byDay['her-day'] = [];
      source.wholeHistorySeen.clear();

      final second = await build().importNow();

      expect(source.wholeHistorySeen, [true]);
      expect(second.spottingDaysWritten, 1);
      expect(observations.saved.single.sourceId, 'ib-rec-1');
      expect(dayEntries.declinedRecords, isEmpty);
    });
  });

  // Issue #1690. An earlier build expanded every day of one Health Connect
  // period record with the same sourceId, which the server accepts only
  // once; a changes-only read never returns the unchanged record, so the
  // merge never re-keys those rows.
  group('issue #1690: old shared-key period days', () {
    DayEntry importedDay(String isoDay, String sourceId) => DayEntry(
      id: 'day-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: 'UTC',
      flow: FlowLevel.light,
      source: DayEntrySource.healthConnect,
      sourceId: sourceId,
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    );

    test('a shared period key is re-keyed per day, without a re-read', () async {
      await bind();
      dayEntries.live['2026-09-10'] =
          importedDay('2026-09-10', 'hc-period@111');
      dayEntries.live['2026-09-11'] =
          importedDay('2026-09-11', 'hc-period@111');
      dayEntries.live['2026-09-12'] =
          importedDay('2026-09-12', 'hc-period@111');
      // A record only one day carries is not shared: left as it is.
      dayEntries.live['2026-09-13'] =
          importedDay('2026-09-13', 'hc-single@222');

      source.result = const HealthReadResult.samples([]);
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(dayEntries.live['2026-09-10']!.sourceId,
          'hc-period#2026-09-10@111');
      expect(dayEntries.live['2026-09-11']!.sourceId,
          'hc-period#2026-09-11@111');
      expect(dayEntries.live['2026-09-12']!.sourceId,
          'hc-period#2026-09-12@111');
      expect(dayEntries.live['2026-09-13']!.sourceId, 'hc-single@222');
      expect(dayEntries.saved, hasLength(3),
          reason: 'only the three shared days are rewritten');

      // Idempotent: nothing is shared any more, nothing is written.
      dayEntries.saved.clear();
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();
      expect(dayEntries.saved, isEmpty);
    });

    test('a day logged by hand, and an import from another source, are '
        'left alone', () async {
      await bind();
      dayEntries.live['2026-09-10'] = DayEntry(
        id: 'day-her',
        profileId: _profileId,
        localDate: LocalDate.fromIso('2026-09-10'),
        tz: 'UTC',
        flow: FlowLevel.light,
        updatedAt: DateTime.utc(2026, 9, 1, 8),
      );
      dayEntries.live['2026-09-11'] = DayEntry(
        id: 'day-other',
        profileId: _profileId,
        localDate: LocalDate.fromIso('2026-09-11'),
        tz: 'UTC',
        flow: FlowLevel.light,
        source: DayEntrySource.healthkit,
        sourceId: 'hk-shared@111',
        updatedAt: DateTime.utc(2026, 9, 1, 8),
      );

      source.result = const HealthReadResult.samples([]);
      await build(
        importPlatform: HealthImportPlatform.healthConnect,
      ).importNow();

      expect(dayEntries.live['2026-09-10']!.sourceId, isNull);
      expect(dayEntries.live['2026-09-11']!.sourceId, 'hk-shared@111');
      expect(dayEntries.saved, isEmpty);
    });
  });
}
