/// `LocalHealthDeviationService`'s policy (Issue #799): the binding guard
/// runs first, only the bound profile's snapshot is ever written or shown,
/// each sample's own zone/offset resolves its civil dates, one insight per
/// kind (the most recent) survives, and the dismissal latch is exact.
///
/// Read-only by construction: this service has no write path, and the
/// release test `health_deviation_read_types_test.dart` pins the four types
/// out of every written/share set.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_deviation_service.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
final _today = LocalDate(2026, 9, 15);

Profile _profile({String id = _profileId}) => Profile(
  id: id,
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

class _FakeSource implements HealthImportSource {
  HealthDeviationReadResult result =
      const HealthDeviationReadResult.samples([]);
  int calls = 0;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<HealthDeviationReadResult> readCycleDeviations(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  }) async {
    calls++;
    lastStart = start;
    lastEnd = end;
    return result;
  }

  @override
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
  }) async =>
      const HealthReadResult.unavailable();
}

class _FakeProfiles implements ProfilesRepository {
  Profile? profile = _profile();

  @override
  Future<Profile?> findById(String id) async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A sample resolved from its own IANA zone.
HealthDeviationSample _zonedSample({
  required HealthDeviationKind kind,
  required String id,
  required String startIso,
  required String endIso,
  String tzName = 'America/New_York',
}) {
  return HealthDeviationSample(
    kind: kind,
    recordId: id,
    start: DateTime.parse(startIso),
    end: DateTime.parse(endIso),
    tzName: tzName,
  );
}

/// A sample whose only zone is a raw offset (Apple computed samples carry no
/// IANA name; the iOS read forwards the device offset).
HealthDeviationSample _offsetSample({
  required HealthDeviationKind kind,
  required String id,
  required String startIso,
  required String endIso,
  Duration offset = const Duration(hours: -4),
}) {
  return HealthDeviationSample(
    kind: kind,
    recordId: id,
    start: DateTime.parse(startIso),
    end: DateTime.parse(endIso),
    offset: offset,
    offsetInferred: true,
  );
}

void main() {
  late FakeSettingsStore settings;
  late _FakeSource source;
  late _FakeProfiles profiles;
  late HealthSyncBinding binding;

  LocalHealthDeviationService build() => LocalHealthDeviationService(
    source: source,
    binding: binding,
    minorBindingAllowed: false,
    profiles: profiles,
    guardiansForProfile: (_) async => _owners(),
    signedInUserId: () => _ownerId,
    settings: settings,
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
    source = _FakeSource();
    profiles = _FakeProfiles();
    binding = HealthSyncBinding(settings);
  });

  tearDown(() => settings.close());

  test('no bound profile is a no-op: no health call, no snapshot written',
      () async {
    final snapshot = await build().refresh();
    expect(snapshot.isEmpty, isTrue);
    expect(source.calls, 0);
    expect(
      await settings.get(healthDeviationSnapshotSettingKey(_profileId)),
      isNull,
    );
  });

  test('a guard denial reads nothing and writes nothing', () async {
    settings.setSilently(SettingsKeys.healthStoreProfileId, 'someone-else');
    final snapshot = await build().refresh();
    expect(snapshot.isEmpty, isTrue);
    expect(source.calls, 0);
    expect(
      await settings.get(healthDeviationSnapshotSettingKey('someone-else')),
      isNull,
    );
  });

  test('a bound allowed profile reads the bounded window and persists the '
      'snapshot', () async {
    await bind();
    source.result = HealthDeviationReadResult.samples([
      _zonedSample(
        kind: HealthDeviationKind.irregularMenstrualCycles,
        id: 'dev-1',
        startIso: '2026-05-01T12:00:00Z',
        endIso: '2026-05-30T12:00:00Z',
      ),
    ]);

    final snapshot = await build().refresh();

    expect(source.calls, 1);
    expect(source.lastStart, isNotNull);
    expect(source.lastEnd!.isAfter(source.lastStart!), isTrue);
    expect(snapshot.insights, hasLength(1));
    final insight = snapshot.insights.single;
    expect(insight.kind, HealthDeviationKind.irregularMenstrualCycles);
    expect(insight.start, LocalDate(2026, 5, 1));
    expect(insight.end, LocalDate(2026, 5, 30));
    expect(snapshot.observedAt, DateTime.utc(2026, 9, 15, 12));

    final stored = await settings.get(
      healthDeviationSnapshotSettingKey(_profileId),
    );
    expect(decodeHealthDeviationSnapshot(stored).insights, hasLength(1));
  });

  test('one insight per kind survives, the most recent', () async {
    await bind();
    source.result = HealthDeviationReadResult.samples([
      _zonedSample(
        kind: HealthDeviationKind.prolongedMenstrualPeriods,
        id: 'old',
        startIso: '2026-03-01T12:00:00Z',
        endIso: '2026-03-10T12:00:00Z',
      ),
      _zonedSample(
        kind: HealthDeviationKind.prolongedMenstrualPeriods,
        id: 'new',
        startIso: '2026-06-01T12:00:00Z',
        endIso: '2026-06-09T12:00:00Z',
      ),
    ]);

    final snapshot = await build().refresh();

    expect(snapshot.insights, hasLength(1));
    expect(snapshot.insights.single.recordId, 'new');
  });

  test('a sample with only an offset resolves from that offset', () async {
    await bind();
    source.result = HealthDeviationReadResult.samples([
      _offsetSample(
        kind: HealthDeviationKind.persistentIntermenstrualBleeding,
        id: 'dev-1',
        startIso: '2026-06-01T02:00:00Z',
        endIso: '2026-06-02T02:00:00Z',
      ),
    ]);

    final snapshot = await build().refresh();

    // 02:00Z at UTC-4 is the previous civil day (2026-05-31).
    expect(snapshot.insights.single.start, LocalDate(2026, 5, 31));
  });

  test('a non-sample read persists an empty snapshot, never a throw',
      () async {
    await bind();
    source.result = const HealthDeviationReadResult.unavailable();
    final snapshot = await build().refresh();
    expect(snapshot.isEmpty, isTrue);
    expect(
      decodeHealthDeviationSnapshot(
        await settings.get(healthDeviationSnapshotSettingKey(_profileId)),
      ).isEmpty,
      isTrue,
    );
  });

  test('visibleSnapshot is null unless the profile is the bound one', () async {
    await settings.set(
      healthDeviationSnapshotSettingKey(_profileId),
      encodeHealthDeviationSnapshot(
        HealthDeviationSnapshot(
          insights: [
            HealthDeviationInsight(
              kind: HealthDeviationKind.irregularMenstrualCycles,
              start: LocalDate(2026, 5, 1),
              end: LocalDate(2026, 5, 30),
            ),
          ],
          observedAt: DateTime.utc(2026, 9, 15),
        ),
      ),
    );
    expect(await build().visibleSnapshot(_profileId), isNull);

    await bind();
    final visible = await build().visibleSnapshot(_profileId);
    expect(visible, isNotNull);
    expect(visible!.insights, hasLength(1));
  });

  test('dismissing hides exactly the dismissed fingerprint', () async {
    await bind();
    final snapshot = HealthDeviationSnapshot(
      insights: [
        HealthDeviationInsight(
          kind: HealthDeviationKind.irregularMenstrualCycles,
          start: LocalDate(2026, 5, 1),
          end: LocalDate(2026, 5, 30),
        ),
      ],
      observedAt: DateTime.utc(2026, 9, 15),
    );
    await settings.set(
      healthDeviationSnapshotSettingKey(_profileId),
      encodeHealthDeviationSnapshot(snapshot),
    );
    final service = build();
    expect(await service.visibleSnapshot(_profileId), isNotNull);

    await service.dismiss(_profileId, snapshot);
    expect(await service.visibleSnapshot(_profileId), isNull);

    // A later, different snapshot shows again.
    final newer = HealthDeviationSnapshot(
      insights: [
        HealthDeviationInsight(
          kind: HealthDeviationKind.irregularMenstrualCycles,
          start: LocalDate(2026, 7, 1),
          end: LocalDate(2026, 7, 20),
        ),
      ],
      observedAt: DateTime.utc(2026, 9, 16),
    );
    await settings.set(
      healthDeviationSnapshotSettingKey(_profileId),
      encodeHealthDeviationSnapshot(newer),
    );
    expect(await service.visibleSnapshot(_profileId), isNotNull);
  });
}
