/// Unit tests for the widget quick-log executor (issue #141): the write
/// is the same quick-log upsert as everywhere else; it never lands while
/// the device gate is locked (latched, then executed on unlock — the
/// #136/KTD4 shape); it is idempotent under a double tap; and it
/// re-verifies the logging role and the target profile at write time, so
/// a stale widget container can never authorize anything.
///
/// Issue #1016: every materialized write also emits an outcome on
/// `outcomes` — the acknowledgement payload the app shell surfaces as the
/// same snackbar + Undo the in-app Today card shows. Drops (role, missing
/// profile) and relatches emit nothing: silence on non-writes is the
/// shipped posture (the issue's one-line "dropped" message is explicitly
/// out of scope).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/widget_quick_log_executor.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';

/// In-memory day entries (upsert keyed by (profileId, localDate)) — the
/// same shape as the reminder-action executor test's fake.
class _InMemoryDayEntries implements DayEntriesRepository {
  final Map<String, DayEntry> _rows = {};
  int _ids = 0;

  DayEntry? get saved => _rows.isEmpty ? null : _rows.values.single;

  Map<String, DayEntry> get rows => _rows;

  @override
  Future<DayEntry> save(DayEntry entry) async {
    final stored =
        entry.id.isEmpty ? entry.copyWith(id: 'row-${++_ids}') : entry;
    _rows['${entry.profileId}|${entry.localDate.iso}'] = stored;
    return stored;
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async =>
      _rows['$profileId|${localDate.iso}'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory profiles: findById plus a live/archived flag.
class _InMemoryProfiles implements ProfilesRepository {
  final Map<String, Profile> live = {};
  final Set<String> archived = {};

  @override
  Future<Profile?> findById(String id) async {
    if (archived.contains(id)) return live[id];
    return live[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final today = LocalDate(2026, 9, 20);
  final quickLogUri = Uri.parse(widgetQuickLogUri('p1'));

  late _InMemoryDayEntries entries;
  late _InMemoryProfiles profiles;

  WidgetQuickLogExecutor executor({
    required Future<bool> Function(String profileId) canQuickLogNow,
    bool Function()? isUnlocked,
    void Function(void Function())? addUnlockListener,
    void Function(void Function())? removeUnlockListener,
  }) =>
      WidgetQuickLogExecutor(
        dayEntries: entries,
        profiles: profiles,
        canQuickLogNow: canQuickLogNow,
        isUnlocked: isUnlocked,
        addUnlockListener: addUnlockListener,
        removeUnlockListener: removeUnlockListener,
        today: () => today,
        timezoneProvider: () => 'America/New_York',
      );

  setUp(() {
    entries = _InMemoryDayEntries();
    profiles = _InMemoryProfiles()..live['p1'] = _profile('p1');
  });

  /// Subscribes to the executor's outcomes, runs [action], and returns
  /// every outcome the executor emitted (drained through the broadcast
  /// stream's delivery queue).
  Future<List<WidgetQuickLogOutcome>> collectOutcomes(
    WidgetQuickLogExecutor ex,
    Future<void> Function() action,
  ) async {
    final outcomes = <WidgetQuickLogOutcome>[];
    final sub = ex.outcomes.listen(outcomes.add);
    await action();
    await ex.idle;
    await pumpEventQueue();
    await sub.cancel();
    return outcomes;
  }

  test('an unlocked tap writes today\'s entry with the quick-log rule',
      () async {
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(quickLogUri);
    await ex.idle;

    final entry = entries.saved;
    expect(entry, isNotNull);
    expect(entry!.profileId, 'p1');
    expect(entry.localDate, today);
    expect(entry.tz, 'America/New_York');
    expect(entry.flow, FlowLevel.medium);
  });

  test('a locked tap latches and writes on unlock (never while locked)',
      () async {
    var unlocked = false;
    final unlockListeners = <void Function()>[];
    final ex = executor(
      canQuickLogNow: (_) async => true,
      isUnlocked: () => unlocked,
      addUnlockListener: unlockListeners.add,
      removeUnlockListener: unlockListeners.remove,
    )..handle(quickLogUri);
    expect(ex.hasPending, isTrue, reason: 'latched behind the lock');
    await ex.idle;
    expect(entries.saved, isNull, reason: 'nothing written while locked');

    unlocked = true;
    for (final listener in unlockListeners) {
      listener();
    }
    await ex.idle;

    expect(ex.hasPending, isFalse);
    expect(entries.saved?.flow, FlowLevel.medium);
  });

  test('a double tap leaves exactly one entry and never downgrades',
      () async {
    await entries.save(DayEntry(
      id: '',
      profileId: 'p1',
      localDate: today,
      tz: 'America/New_York',
      flow: FlowLevel.heavy,
      updatedAt: DateTime.now().toUtc(),
    ));

    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(quickLogUri)
      ..handle(quickLogUri);
    await ex.idle;

    final entry = entries.saved;
    expect(entry!.flow, FlowLevel.heavy,
        reason: 'an existing heavier report is never downgraded');
    expect(entries.rows, hasLength(1));
  });

  test('the gate relocking while queued re-latches instead of writing',
      () async {
    var unlocked = true;
    final ex = executor(
      canQuickLogNow: (_) async => true,
      isUnlocked: () => unlocked,
    )..handle(quickLogUri);
    // The gate relocks before the queued write's turn comes up.
    unlocked = false;
    await ex.idle;

    expect(ex.hasPending, isTrue, reason: 're-latched, not dropped');
    expect(entries.saved, isNull);
  });

  test('a viewer role drops the intent at write time', () async {
    final ex = executor(canQuickLogNow: (_) async => false)
      ..handle(quickLogUri);
    await ex.idle;

    expect(entries.saved, isNull,
        reason: 'the render flag is never an authorization');
  });

  test('an intent for a since-deleted profile is dropped', () async {
    final staleUri = Uri.parse(widgetQuickLogUri('gone'));
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(staleUri);
    await ex.idle;

    expect(entries.saved, isNull);
  });

  test('a non-quick-log URI does nothing at all', () async {
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(Uri.parse(widgetOpenUri()))
      ..handle(null);
    await ex.idle;

    expect(ex.hasPending, isFalse);
    expect(entries.saved, isNull);
  });

  test('dispose discards the latch: a torn-down executor never writes',
      () async {
    var unlocked = false;
    final ex = executor(
      canQuickLogNow: (_) async => true,
      isUnlocked: () => unlocked,
    )..handle(quickLogUri);
    ex.dispose();

    unlocked = true;
    await ex.idle;
    expect(entries.saved, isNull);
  });

  group('issue #1016: materialized writes emit an outcome for the shell to '
      'acknowledge', () {
    test('a write onto an empty day emits logged with a null previous entry',
        () async {
      final ex = executor(canQuickLogNow: (_) async => true);
      final outcomes =
          await collectOutcomes(ex, () async => ex.handle(quickLogUri));

      expect(outcomes, hasLength(1));
      expect(outcomes.single.profileId, 'p1');
      expect(outcomes.single.date, today);
      expect(outcomes.single.previousEntry, isNull,
          reason: 'the tap created the day, so the Undo is a tombstone');
    });

    test('a write that upgrades a lighter day carries the pre-write entry '
        'for the shared Undo', () async {
      final prior = await entries.save(DayEntry(
        id: '',
        profileId: 'p1',
        localDate: today,
        tz: 'America/New_York',
        flow: FlowLevel.light,
        note: 'tender',
        updatedAt: DateTime.now().toUtc(),
      ));

      final ex = executor(canQuickLogNow: (_) async => true);
      final outcomes =
          await collectOutcomes(ex, () async => ex.handle(quickLogUri));

      expect(outcomes, hasLength(1));
      expect(outcomes.single.previousEntry, isNotNull);
      expect(outcomes.single.previousEntry!.flow, FlowLevel.light);
      expect(outcomes.single.previousEntry!.note, 'tender');
      expect(outcomes.single.previousEntry, prior);
      // The write itself upgraded the flow and kept the note.
      expect(entries.saved!.flow, FlowLevel.medium);
      expect(entries.saved!.note, 'tender');
    });

    test('a viewer-role drop emits nothing', () async {
      final ex = executor(canQuickLogNow: (_) async => false);
      final outcomes =
          await collectOutcomes(ex, () async => ex.handle(quickLogUri));

      expect(outcomes, isEmpty,
          reason: 'nothing was written, so nothing is acknowledged');
      expect(entries.saved, isNull);
    });

    test('a since-deleted-profile drop emits nothing', () async {
      final ex = executor(canQuickLogNow: (_) async => true);
      final outcomes = await collectOutcomes(
        ex,
        () async => ex.handle(Uri.parse(widgetQuickLogUri('gone'))),
      );

      expect(outcomes, isEmpty);
      expect(entries.saved, isNull);
    });

    test('a latched intent emits only when it actually writes on unlock',
        () async {
      var unlocked = false;
      final unlockListeners = <void Function()>[];
      final ex = executor(
        canQuickLogNow: (_) async => true,
        isUnlocked: () => unlocked,
        addUnlockListener: unlockListeners.add,
        removeUnlockListener: unlockListeners.remove,
      );

      final outcomes = await collectOutcomes(ex, () async {
        ex.handle(quickLogUri);
        unlocked = true;
        for (final listener in unlockListeners) {
          listener();
        }
      });

      expect(outcomes, hasLength(1),
          reason: 'exactly one outcome, for the one materialized write');
      expect(entries.saved?.flow, FlowLevel.medium);
    });

    test('a relocked relatch emits nothing (the write never happened)',
        () async {
      var unlocked = true;
      final ex = executor(
        canQuickLogNow: (_) async => true,
        isUnlocked: () => unlocked,
      );

      final outcomes = await collectOutcomes(ex, () async {
        ex.handle(quickLogUri);
        // The gate relocks before the queued write's turn comes up: the
        // intent relatches instead of writing (issue #141) and, issue
        // #1016, emits nothing.
        unlocked = false;
      });

      expect(outcomes, isEmpty);
      expect(ex.hasPending, isTrue);
      expect(entries.saved, isNull);
    });
  });
}
