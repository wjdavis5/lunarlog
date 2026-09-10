/// `HealthFlowWriteCoordinator`'s trigger contract: an already-bound
/// profile syncs under its existing cursor (restart-safe), entry changes
/// debounce into one pass, an unbind retires the cursor via the service's
/// unbind path, and a bind-while-bound replace retires the *old* binding's
/// consent before the new profile syncs — so no history is ever backfilled
/// under the previous cursor.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_write_coordinator.dart'
    show HealthFlowWriteCoordinator;
import 'package:lunarlog/domain/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _bindingKey = SettingsKeys.healthStoreProfileId;

class _RecordingService implements HealthFlowWriteService {
  _RecordingService(this._settings);

  final SettingsStore _settings;

  int syncCalls = 0;
  int unboundCalls = 0;
  final Completer<void> _firstSync = Completer<void>();

  Future<void> get firstSync => _firstSync.future;

  @override
  Future<HealthFlowSyncReport> syncNow() async {
    syncCalls++;
    if (!_firstSync.isCompleted) _firstSync.complete();
    return const HealthFlowSyncReport(bound: true);
  }

  @override
  Future<void> onUnbound() async {
    unboundCalls++;
    // Mirror the real service's cursor clear so rebind tests can observe
    // the sequencing through the settings store.
    await _settings.set(SettingsKeys.healthSyncWrittenThroughMs, '');
  }
}

class _FakeDayEntries implements DayEntriesRepository {
  final _changes = StreamController<List<DayEntry>>.broadcast();

  /// Adds [entries] once the coordinator's watch subscription is actually
  /// attached: the binding watch is an async* chain, so an event fired on
  /// a broadcast stream immediately after `settings.set` would otherwise
  /// be dropped with no listener attached yet.
  Future<void> emit(List<DayEntry> entries) async {
    var spins = 0;
    while (!_changes.hasListener) {
      await Future<void>.delayed(Duration.zero);
      spins++;
      if (spins > 1000) {
        fail('coordinator never subscribed to the entries stream');
      }
    }
    _changes.add(entries);
  }

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      _changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late FakeSettingsStore settings;
  late _FakeDayEntries dayEntries;
  late _RecordingService service;
  late HealthFlowWriteCoordinator coordinator;

  setUp(() {
    settings = FakeSettingsStore();
    dayEntries = _FakeDayEntries();
    service = _RecordingService(settings);
    coordinator = HealthFlowWriteCoordinator(
      binding: HealthSyncBinding(settings),
      dayEntries: dayEntries,
      service: service,
      debounce: const Duration(milliseconds: 10),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    settings.close();
  });

  /// Seeds the settings and *then* starts the coordinator: the seeded
  /// watch delivers the binding through its seed value deterministically,
  /// whereas a `settings.set` fired immediately after `start()` can race
  /// the async* seed chain's own subscription to the broadcast controller
  /// and be dropped.
  void startBound(String profileId) {
    settings.setSilently(_bindingKey, profileId);
    coordinator.start();
  }

  test('an already-bound profile syncs without clearing the cursor '
      '(restart-safe)', () async {
    settings.setSilently(
      SettingsKeys.healthSyncWrittenThroughMs,
      '1000',
    );
    startBound('p1');

    await dayEntries.emit(const []);
    await service.firstSync;

    expect(service.syncCalls, 1);
    expect(service.unboundCalls, 0);
    expect(await settings.get(SettingsKeys.healthSyncWrittenThroughMs),
        '1000');
  });

  test('entry changes debounce into one pass', () async {
    startBound('p1');

    await dayEntries.emit(const []);
    await service.firstSync;
    await dayEntries.emit(const []);
    await dayEntries.emit(const []);

    // Inside the debounce window: exactly one more pass is scheduled.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.syncCalls, 2);
  });

  test('unbind retires the cursor through the service unbind path',
      () async {
    startBound('p1');
    await dayEntries.emit(const []);
    await service.firstSync;

    await settings.set(_bindingKey, '');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.unboundCalls, 1);
    expect(await settings.get(SettingsKeys.healthSyncWrittenThroughMs), '');
  });

  test('rebinding after unbind syncs the new binding freshly', () async {
    startBound('p1');
    await dayEntries.emit(const []);
    await service.firstSync;

    await settings.set(_bindingKey, '');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final syncsAtUnbind = service.syncCalls;

    await settings.set(_bindingKey, 'p2');
    await dayEntries.emit(const []);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.unboundCalls, 1);
    expect(service.syncCalls, greaterThan(syncsAtUnbind));
  });

  test('a bind-while-bound replace retires the old consent before the new '
      'profile syncs', () async {
    startBound('p1');
    await dayEntries.emit(const []);
    await service.firstSync;
    final syncsBeforeReplace = service.syncCalls;

    await settings.set(_bindingKey, 'p2');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.unboundCalls, 1);
    // The cursor was cleared by the replace (the recording service mirrors
    // the real one), so nothing of p1's consent survives.
    expect(await settings.get(SettingsKeys.healthSyncWrittenThroughMs), '');

    await dayEntries.emit(const []);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.syncCalls, greaterThan(syncsBeforeReplace));
  });

  test('a throwing pass never kills the subscription', () async {
    // A service whose syncNow throws on the first call (an unexpected
    // storage error) — the coordinator must swallow it and re-arm on the
    // next change.
    final failing = _ThrowingService();
    settings.setSilently(_bindingKey, 'p1');
    final flakyCoordinator = HealthFlowWriteCoordinator(
      binding: HealthSyncBinding(settings),
      dayEntries: dayEntries,
      service: failing,
      debounce: const Duration(milliseconds: 10),
    );
    flakyCoordinator.start();
    addTearDown(flakyCoordinator.dispose);

    await dayEntries.emit(const []);
    await failing.firstSync;
    await dayEntries.emit(const []);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(failing.syncCalls, 2);
  });
}

class _ThrowingService implements HealthFlowWriteService {
  _ThrowingService();

  int syncCalls = 0;
  final Completer<void> _firstSync = Completer<void>();
  bool _threw = false;

  Future<void> get firstSync => _firstSync.future;

  @override
  Future<HealthFlowSyncReport> syncNow() async {
    syncCalls++;
    if (!_threw) {
      _threw = true;
      if (!_firstSync.isCompleted) _firstSync.complete();
      throw StateError('storage exploded');
    }
    return const HealthFlowSyncReport(bound: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
