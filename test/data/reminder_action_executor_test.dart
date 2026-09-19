/// Unit tests for the reminder action executor (Issue #136): what each
/// action button writes, the device-gate rule (KTD4 — never write while
/// locked), and the double-tap-leaves-one-entry idempotency guarantee.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_action_executor.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';

import '../support/fake_settings_store.dart';

/// In-memory stand-in mirroring the repository contract the executor
/// relies on: save is an upsert keyed by (profileId, localDate) with a
/// storage-assigned id when the incoming id is empty.
class _InMemoryDayEntries implements DayEntriesRepository {
  final Map<String, DayEntry> _rows = {};
  int _ids = 0;

  DayEntry? get saved => _rows.isEmpty ? null : _rows.values.single;

  @override
  Future<DayEntry> save(DayEntry entry) async {
    final stored = entry.id.isEmpty
        ? entry.copyWith(id: 'row-${++_ids}')
        : entry;
    _rows['${entry.profileId}|${entry.localDate.iso}'] = stored;
    return stored;
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async =>
      _rows['$profileId|${localDate.iso}'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory observations keyed by their day entry's id.
class _InMemoryObservations implements ObservationsRepository {
  final Map<String, List<Observation>> _byEntry = {};

  List<Observation> forEntry(String dayEntryId) =>
      _byEntry[dayEntryId] ?? const [];

  int get totalCount =>
      _byEntry.values.fold(0, (sum, list) => sum + list.length);

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      forEntry(dayEntryId);

  @override
  Future<Observation> save(Observation observation) async {
    final id = observation.id.isEmpty
        ? 'obs-${observation.dayEntryId}-${observation.category}'
        : observation.id;
    final stored =
        observation.id.isEmpty ? observation.copyWith(id: id) : observation;
    _byEntry
        .putIfAbsent(stored.dayEntryId, () => [])
        .removeWhere((o) => o.id == stored.id);
    _byEntry[stored.dayEntryId]!.add(stored);
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final today = LocalDate(2026, 9, 3);

  late _InMemoryDayEntries entries;
  late _InMemoryObservations observations;
  late FakeSettingsStore store;
  late ReminderConfigService configService;

  ReminderActionExecutor executor({
    bool Function()? isUnlocked,
    void Function(void Function())? addUnlockListener,
    void Function(void Function())? removeUnlockListener,
  }) =>
      ReminderActionExecutor(
        dayEntries: entries,
        observations: observations,
        configService: configService,
        isUnlocked: isUnlocked,
        addUnlockListener: addUnlockListener,
        removeUnlockListener: removeUnlockListener,
        today: () => today,
        timezoneProvider: () => 'America/New_York',
      );

  ReminderLaunch action(String actionId, {String profileId = 'p1'}) =>
      ReminderLaunch(
        profileId: profileId,
        kind: ReminderKind.late,
        actionId: actionId,
      );

  setUp(() {
    entries = _InMemoryDayEntries();
    observations = _InMemoryObservations();
    store = FakeSettingsStore();
    configService = ReminderConfigService(store);
  });

  tearDown(() => store.close());

  test('"Started" writes today\'s entry with the quick-log flow rule',
      () async {
    final ex = executor()..handleAction(action(kReminderActionStarted));
    await ex.idle;

    final entry = entries.saved;
    expect(entry, isNotNull);
    expect(entry!.profileId, 'p1');
    expect(entry.localDate, today, reason: 'the civil date at tap time');
    expect(entry.tz, 'America/New_York');
    expect(entry.flow, FlowLevel.medium, reason: 'kQuickLogFlowLevel');
  });

  test('"Started" never downgrades an existing flow, and a second tap '
      'leaves exactly one entry', () async {
    await entries.save(DayEntry(
      id: '',
      profileId: 'p1',
      localDate: today,
      tz: 'America/New_York',
      flow: FlowLevel.heavy,
      updatedAt: DateTime.now().toUtc(),
    ));

    final ex = executor();
    // The double tap: two action events in quick succession.
    ex.handleAction(action(kReminderActionStarted));
    ex.handleAction(action(kReminderActionStarted));
    await ex.idle;

    final entry = entries.saved;
    expect(entry, isNotNull);
    expect(entry!.flow, FlowLevel.heavy,
        reason: 'an existing heavier report is never downgraded');
    expect(entries._rows, hasLength(1),
        reason: 'double-tapping leaves exactly one entry');
  });

  test('"Spotting" creates the day entry (explicitly not bleeding) and '
      'one spotting observation; a second tap does not duplicate', () async {
    final ex = executor()..handleAction(action(kReminderActionSpotting));
    await ex.idle;

    final entry = entries.saved;
    expect(entry, isNotNull);
    expect(entry!.flow, FlowLevel.notBleeding,
        reason: 'the Issue #247 model: spotting is never a flow level');
    expect(observations.forEntry(entry.id), hasLength(1));
    expect(observations.forEntry(entry.id).single.category,
        ObservationCategory.spotting);
    expect(observations.forEntry(entry.id).single.code, 'spotting');

    // The double tap.
    ex.handleAction(action(kReminderActionSpotting));
    await ex.idle;
    expect(entries._rows, hasLength(1));
    expect(observations.totalCount, 1,
        reason: 'the day already had a spotting observation');
  });

  test('"Spotting" attaches to an existing entry without touching its '
      'flow', () async {
    await entries.save(DayEntry(
      id: '',
      profileId: 'p1',
      localDate: today,
      tz: 'America/New_York',
      flow: FlowLevel.medium,
      tags: const ['cramps'],
      updatedAt: DateTime.now().toUtc(),
    ));

    final ex = executor()..handleAction(action(kReminderActionSpotting));
    await ex.idle;

    final entry = entries.saved!;
    expect(entry.flow, FlowLevel.medium,
        reason: 'a logged day is never rewritten by a spotting tap');
    expect(entry.tags, ['cramps']);
    expect(observations.forEntry(entry.id), hasLength(1));
  });

  test('"Not yet" writes nothing and snoozes the late reminders three '
      'days', () async {
    final ex = executor()..handleAction(action(kReminderActionNotYet));
    await ex.idle;

    expect(entries.saved, isNull);
    expect(observations.totalCount, 0);
    expect(await configService.loadLateSnoozes(),
        {'p1': today.addDays(kNotYetSnoozeDays)});
  });

  test('a plain tap (no action id) is ignored here — it routes to the '
      'overview through the launch-payload seam', () async {
    final ex = executor()
      ..handleAction(const ReminderLaunch(profileId: 'p1'));
    await ex.idle;

    expect(entries.saved, isNull);
    expect(ex.hasPending, isFalse);
  });

  test('an action tap while locked latches and writes only on unlock '
      '(KTD4)', () async {
    var unlocked = false;
    final gateListeners = <void Function()>[];
    final ex = executor(
      isUnlocked: () => unlocked,
      addUnlockListener: gateListeners.add,
      removeUnlockListener: gateListeners.remove,
    );

    ex.handleAction(action(kReminderActionStarted));
    await ex.idle;
    expect(ex.hasPending, isTrue, reason: 'latched, not dropped');
    expect(entries.saved, isNull, reason: 'never written while locked');

    // The gate opens; the gate listener drains the latch.
    unlocked = true;
    for (final listener in List.of(gateListeners)) {
      listener();
    }
    await ex.idle;

    expect(entries.saved, isNotNull);
    expect(ex.hasPending, isFalse);
  });

  test('an action tap racing an already-unlocked gate writes immediately',
      () async {
    final ex = executor(isUnlocked: () => true)
      ..handleAction(action(kReminderActionNotYet));
    await ex.idle;

    expect(await configService.loadLateSnoozes(),
        {'p1': today.addDays(kNotYetSnoozeDays)});
  });

  test('a second, different action while locked replaces the latch — '
      'the latest intent wins, once', () async {
    var unlocked = false;
    final gateListeners = <void Function()>[];
    final ex = executor(
      isUnlocked: () => unlocked,
      addUnlockListener: gateListeners.add,
      removeUnlockListener: gateListeners.remove,
    );

    ex.handleAction(action(kReminderActionStarted));
    ex.handleAction(action(kReminderActionNotYet));
    expect(ex.hasPending, isTrue);

    unlocked = true;
    for (final listener in List.of(gateListeners)) {
      listener();
    }
    await ex.idle;

    expect(entries.saved, isNull,
        reason: '"Not yet" replaced the "Started" latch and writes nothing');
    expect(await configService.loadLateSnoozes(),
        {'p1': today.addDays(kNotYetSnoozeDays)});
  });

  test('dispose detaches the gate listener', () {
    const unlocked = false;
    final gateListeners = <void Function()>[];
    final ex = executor(
      isUnlocked: () => unlocked,
      addUnlockListener: gateListeners.add,
      removeUnlockListener: gateListeners.remove,
    );
    expect(gateListeners, hasLength(1));

    ex.dispose();
    expect(gateListeners, isEmpty,
        reason: 'the listener must not outlive the executor');
  });

  test('a queued action rechecks the gate at its turn: locked before it '
      'drains relatches instead of writing behind the lock (Issue #634, '
      'LLA-099)', () async {
    final gate = Completer<void>();
    final gated = _GatedDayEntries(gate);
    var unlocked = true;
    final ex = ReminderActionExecutor(
      dayEntries: gated,
      configService: configService,
      isUnlocked: () => unlocked,
      today: () => today,
      timezoneProvider: () => 'America/New_York',
    );

    // "Started" is admitted while unlocked and starts running — it parks
    // inside `_logStarted`'s `find()` call on the gate below.
    ex.handleAction(action(kReminderActionStarted));
    await pumpEventQueue();

    // A second action is admitted (still unlocked) and queues behind the
    // first on the drain chain; the gate then relocks before its turn
    // comes up.
    ex.handleAction(action(kReminderActionSpotting));
    unlocked = false;
    gate.complete();
    await ex.idle;

    expect(gated.saveCalls, 1,
        reason: '"Started" (already past the gate check) wrote once; '
            '"Spotting" found itself locked before its turn and never '
            'wrote');
    expect(ex.hasPending, isTrue,
        reason: 'the relocked action relatches rather than being dropped');

    ex.dispose();
  });

  test('a relocked queued action never clobbers a fresher latch that '
      'arrived while it waited — freshest intent still wins (Issue #634, '
      'LLA-099)', () async {
    // Single-slot, freshest-wins is this executor's established contract
    // for `_pending` (see `_PendingAction`'s own doc comment, and "a
    // second, different action while locked replaces the latch" above,
    // which covers two taps admitted while *already* locked). This test
    // covers the different, new code path LLA-099 added: an action
    // dequeued from the drain chain that finds the gate relocked must
    // relatch without overwriting a *fresher* latch that arrived directly
    // (via `handleAction`'s own already-locked branch) while it waited
    // its turn.
    final gate = Completer<void>();
    final gated = _GatedDayEntries(gate);
    var unlocked = true;
    final gateListeners = <void Function()>[];
    final ex = ReminderActionExecutor(
      dayEntries: gated,
      observations: observations,
      configService: configService,
      isUnlocked: () => unlocked,
      addUnlockListener: gateListeners.add,
      removeUnlockListener: gateListeners.remove,
      today: () => today,
      timezoneProvider: () => 'America/New_York',
    );

    // "Started" is admitted while unlocked and parks on the gate below.
    ex.handleAction(action(kReminderActionStarted));
    await pumpEventQueue();

    // "Spotting" is admitted (still unlocked) and queues behind
    // "Started" on the drain chain.
    ex.handleAction(action(kReminderActionSpotting));

    // The gate relocks, and a different, later tap ("Not yet") arrives
    // while locked — the pre-existing, documented single-slot latch path
    // in `handleAction`.
    unlocked = false;
    ex.handleAction(action(kReminderActionNotYet));
    expect(ex.hasPending, isTrue);

    // "Started" finishes; "Spotting" then reaches its own turn, finds the
    // gate relocked, and must not clobber the fresher "Not yet" latch.
    gate.complete();
    await ex.idle;

    expect(observations.totalCount, 0,
        reason: '"Spotting" found itself locked at its turn and never '
            'ran, so it left no observation');
    expect(ex.hasPending, isTrue,
        reason: 'the fresher "Not yet" latch is still the one waiting — '
            'the relocked "Spotting" must not have overwritten it');

    // Unlocking drains whatever is actually latched, proving it is still
    // "Not yet" and never became the relocked "Spotting".
    unlocked = true;
    for (final listener in List.of(gateListeners)) {
      listener();
    }
    await ex.idle;

    expect(await configService.loadLateSnoozes(),
        {'p1': today.addDays(kNotYetSnoozeDays)},
        reason: 'the fresher "Not yet" is what actually drained');
    expect(observations.totalCount, 0,
        reason: 'the older, relocked "Spotting" never ran, even after '
            'unlock');
  });

  test('dispose stops a still-queued action from writing after teardown '
      '(Issue #634, LLA-099)', () async {
    final gate = Completer<void>();
    final gated = _GatedDayEntries(gate);
    final ex = ReminderActionExecutor(
      dayEntries: gated,
      configService: configService,
      isUnlocked: () => true,
      today: () => today,
      timezoneProvider: () => 'America/New_York',
    );

    ex.handleAction(action(kReminderActionStarted));
    await pumpEventQueue();
    // "Not yet" writes through `configService`, not `gated` — a distinct
    // write path from "Started"'s, so this proves the second action
    // itself never ran rather than merely finding "Started"'s day entry
    // already there and skipping its own write for that reason.
    ex.handleAction(action(kReminderActionNotYet));
    ex.dispose();
    gate.complete();
    await ex.idle;

    expect(gated.saveCalls, 1,
        reason: "the disposed executor's still-queued second action "
            'never wrote');
    expect(await configService.loadLateSnoozes(), isEmpty,
        reason: 'the queued "Not yet" never ran either — dispose stops '
            'every write path, not just the one already tested');
  });

  test('a failing write is swallowed (best effort), not an unawaited '
      'crash', () async {
    final failing = _ThrowingDayEntries();
    final ex = ReminderActionExecutor(
      dayEntries: failing,
      configService: configService,
      today: () => today,
      timezoneProvider: () => 'America/New_York',
    )..handleAction(action(kReminderActionStarted));

    await ex.idle;
    expect(failing.saveCalls, 1, reason: 'the write was attempted once');
  });
}

/// A [DayEntriesRepository] whose [find] parks on [gate] — lets a test
/// hold an action mid-execution so a second, queued action can genuinely
/// find the gate state changed before its own turn (Issue #634, LLA-099).
class _GatedDayEntries implements DayEntriesRepository {
  _GatedDayEntries(this.gate);

  final Completer<void> gate;
  final Map<String, DayEntry> _rows = {};
  int saveCalls = 0;

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async {
    await gate.future;
    return _rows['$profileId|${localDate.iso}'];
  }

  @override
  Future<DayEntry> save(DayEntry entry) async {
    saveCalls++;
    final stored =
        entry.id.isEmpty ? entry.copyWith(id: 'row-$saveCalls') : entry;
    _rows['${entry.profileId}|${entry.localDate.iso}'] = stored;
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingDayEntries implements DayEntriesRepository {
  int saveCalls = 0;

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => null;

  @override
  Future<DayEntry> save(DayEntry entry) async {
    saveCalls++;
    throw StateError('disk full');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
