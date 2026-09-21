/// Unit tests for the widget quick-log executor (issue #141): the write
/// is the same quick-log upsert as everywhere else; it never lands while
/// the device gate is locked (latched, then executed on unlock — the
/// #136/KTD4 shape); it is idempotent under a double tap; and it
/// re-verifies the logging role and the target profile at write time, so
/// a stale widget container can never authorize anything.
///
/// Issue #1016 adds the outcome channel: every execution that reaches the
/// write stage emits exactly one [WidgetQuickLogOutcome] — `logged` (with
/// the pre-write entry Undo restores), `alreadyLogged` (nothing written
/// over an at-or-above flow), or `dropped` (role/profile/failure).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/widget_quick_log_executor.dart';
import 'package:lunarlog/domain/logging/quick_log_undo.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_outcome.dart';

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
  Future<void> delete(String profileId, LocalDate localDate) async {
    _rows.remove('$profileId|${localDate.iso}');
  }

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

  /// Subscribes to [ex]'s outcome channel and collects every emission in
  /// order (issue #1016). Registered before `handle` so no emission is
  /// missed once it is delivered.
  List<WidgetQuickLogOutcome> record(WidgetQuickLogExecutor ex) {
    final seen = <WidgetQuickLogOutcome>[];
    ex.outcomes.listen(seen.add);
    return seen;
  }

  /// Drains the write queue *and* the outcome channel's async delivery:
  /// [WidgetQuickLogExecutor.outcomes] is a broadcast stream, so a listener
  /// sees a just-emitted value one microtask after the write resolves.
  Future<void> settle(WidgetQuickLogExecutor executor) async {
    await executor.idle;
    await pumpEventQueue();
  }

  setUp(() {
    entries = _InMemoryDayEntries();
    profiles = _InMemoryProfiles()..live['p1'] = _profile('p1');
  });

  test('an unlocked tap writes today\'s entry with the quick-log rule',
      () async {
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(quickLogUri);
    await settle(ex);

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
    await settle(ex);
    expect(entries.saved, isNull, reason: 'nothing written while locked');

    unlocked = true;
    for (final listener in unlockListeners) {
      listener();
    }
    await settle(ex);

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
    await settle(ex);

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
    await settle(ex);

    expect(ex.hasPending, isTrue, reason: 're-latched, not dropped');
    expect(entries.saved, isNull);
  });

  test('a viewer role drops the intent at write time', () async {
    final ex = executor(canQuickLogNow: (_) async => false)
      ..handle(quickLogUri);
    await settle(ex);

    expect(entries.saved, isNull,
        reason: 'the render flag is never an authorization');
  });

  test('an intent for a since-deleted profile is dropped', () async {
    final staleUri = Uri.parse(widgetQuickLogUri('gone'));
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(staleUri);
    await settle(ex);

    expect(entries.saved, isNull);
  });

  test('a non-quick-log URI does nothing at all', () async {
    final ex = executor(canQuickLogNow: (_) async => true)
      ..handle(Uri.parse(widgetOpenUri()))
      ..handle(null);
    await settle(ex);

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
    await settle(ex);
    expect(entries.saved, isNull);
  });

  group('outcome channel (issue #1016)', () {
    test('a fresh write emits logged carrying no previous entry', () async {
      final ex = executor(canQuickLogNow: (_) async => true);
      final seen = record(ex);
      ex.handle(quickLogUri);
      await settle(ex);

      expect(seen, hasLength(1));
      final outcome = seen.single;
      expect(outcome, isA<WidgetQuickLogLogged>());
      final logged = outcome as WidgetQuickLogLogged;
      expect(logged.profileId, 'p1');
      expect(logged.date, today);
      expect(logged.previous, isNull,
          reason: 'the tap created today, so Undo tombstones it');
    });

    test('raising a lighter entry emits logged with that prior entry, and '
        'Undo restores it exactly', () async {
      final prior = DayEntry(
        id: 'row-light',
        profileId: 'p1',
        localDate: today,
        tz: 'America/Chicago',
        flow: FlowLevel.light,
        note: 'cramps',
        updatedAt: DateTime(2026),
      );
      await entries.save(prior);

      final ex = executor(canQuickLogNow: (_) async => true);
      final seen = record(ex);
      ex.handle(quickLogUri);
      await settle(ex);

      final logged = seen.single as WidgetQuickLogLogged;
      expect(logged.previous, isNotNull);
      expect(logged.previous!.flow, FlowLevel.light);
      expect(entries.saved!.flow, FlowLevel.medium,
          reason: 'the tap raised the lighter hand-logged value');

      await undoQuickLogToday(
        dayEntries: entries,
        profileId: logged.profileId,
        date: logged.date,
        previous: logged.previous,
      );
      final restored = entries.saved!;
      expect(restored.flow, FlowLevel.light);
      expect(restored.note, 'cramps');
      expect(restored.tz, 'America/Chicago');
    });

    test('an at-or-above flow emits alreadyLogged and writes nothing',
        () async {
      await entries.save(DayEntry(
        id: 'row-heavy',
        profileId: 'p1',
        localDate: today,
        tz: 'America/New_York',
        flow: FlowLevel.heavy,
        updatedAt: DateTime(2026),
      ));

      final ex = executor(canQuickLogNow: (_) async => true);
      final seen = record(ex);
      ex.handle(quickLogUri);
      await settle(ex);

      expect(seen.single, isA<WidgetQuickLogAlreadyLogged>());
      expect(entries.saved!.flow, FlowLevel.heavy,
          reason: 'a hand-logged heavier value is never downgraded');
      expect(entries.rows, hasLength(1),
          reason: 'nothing new was written at all');
    });

    test('a viewer role emits dropped and never logs', () async {
      final ex = executor(canQuickLogNow: (_) async => false);
      final seen = record(ex);
      ex.handle(quickLogUri);
      await settle(ex);

      expect(seen.single, isA<WidgetQuickLogDropped>());
      expect(seen.single.profileId, 'p1');
      expect(entries.saved, isNull,
          reason: 'the render flag is never an authorization');
    });

    test('a since-deleted profile emits dropped', () async {
      final ex = executor(canQuickLogNow: (_) async => true);
      final seen = record(ex);
      ex.handle(Uri.parse(widgetQuickLogUri('gone')));
      await settle(ex);

      expect(seen.single, isA<WidgetQuickLogDropped>());
      expect(entries.saved, isNull);
    });

    test('a locked tap emits nothing until it actually executes', () async {
      var unlocked = false;
      final listeners = <void Function()>[];
      final ex = executor(
        canQuickLogNow: (_) async => true,
        isUnlocked: () => unlocked,
        addUnlockListener: listeners.add,
        removeUnlockListener: listeners.remove,
      );
      final seen = record(ex);
      ex.handle(quickLogUri);
      expect(seen, isEmpty, reason: 'latched, not resolved');
      await settle(ex);
      expect(seen, isEmpty);

      unlocked = true;
      for (final listener in listeners) {
        listener();
      }
      await settle(ex);

      expect(seen.single, isA<WidgetQuickLogLogged>());
    });

    test('a re-latched (not executed) intent emits nothing', () async {
      var unlocked = true;
      final ex = executor(
        canQuickLogNow: (_) async => true,
        isUnlocked: () => unlocked,
      );
      final seen = record(ex);
      ex.handle(quickLogUri);
      unlocked = false;
      await settle(ex);

      expect(ex.hasPending, isTrue);
      expect(seen, isEmpty, reason: 'nothing resolved against the gate');
    });

    test('a non-quick-log URI emits nothing', () async {
      final ex = executor(canQuickLogNow: (_) async => true);
      final seen = record(ex);
      ex.handle(Uri.parse(widgetOpenUri()));
      ex.handle(null);
      await settle(ex);

      expect(seen, isEmpty);
    });
  });
}
