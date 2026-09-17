/// Unit tests for the day-sheet autosave state machine (issue #601):
/// [DaySheetSaveState] and its pure transition functions, extracted out of
/// `_DaySheetState`'s old boolean cluster
/// (`_dirty`/`_saving`/`_saveQueued`/`_showSaved`/`_saveFailed`).
///
/// Every group below is named after the old field(s)/behaviour it pins, so
/// a diff against `lib/ui/logging/day_sheet.dart`'s pre-#601 history (or
/// its own doc comments, which still cross-reference the fields these
/// replace) shows the mapping directly. `test/ui/logging/
/// day_sheet_dispose_flush_test.dart` and `test/ui/logging_test.dart`
/// exercise the same properties end-to-end through the real widget; this
/// file is the fast, exhaustive unit-level complement issue #546's own
/// races deserve.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/day_sheet_save_state.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';

DayEntry _entry(String note) => DayEntry(
      id: '',
      profileId: 'p1',
      localDate: LocalDate(2026, 8, 30),
      tz: 'UTC',
      flow: FlowLevel.medium,
      note: note,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  final a = _entry('a');
  final b = _entry('b');
  final c = _entry('c');

  group('daySheetMarkDirty (old: _markDirty\'s unconditional _dirty=true, '
      '_pendingEntry=composed)', () {
    test('from Idle becomes Dirty', () {
      expect(daySheetMarkDirty(const DaySheetIdle(), a), isA<DaySheetDirty>());
      expect((daySheetMarkDirty(const DaySheetIdle(), a) as DaySheetDirty).pending, a);
    });

    test('from Dirty replaces the pending entry with the newest one', () {
      final next = daySheetMarkDirty(DaySheetDirty(a), b);
      expect(next, isA<DaySheetDirty>());
      expect((next as DaySheetDirty).pending, b);
    });

    test('from Saved becomes Dirty (documented simplification -- see '
        'DaySheetSaved\'s own doc)', () {
      expect(daySheetMarkDirty(const DaySheetSaved(), a), DaySheetDirty(a));
    });

    test('from Failed replaces the pending entry, same as Dirty', () {
      expect(daySheetMarkDirty(DaySheetFailed(a), b), DaySheetDirty(b));
    });

    test(
        'from Saving updates only queuedNext, leaving inFlight and '
        'retrigger untouched (old: _pendingEntry reassigned regardless of '
        '_saving, _saveQueued/_saving themselves untouched by _markDirty)',
        () {
      final saving = DaySheetSaving(a, retrigger: true);
      final next = daySheetMarkDirty(saving, b) as DaySheetSaving;
      expect(next.inFlight, a, reason: 'the in-flight snapshot never moves');
      expect(next.queuedNext, b);
      expect(next.retrigger, isTrue, reason: 'retrigger is preserved as-is');
    });

    test('a second edit while already queued behind a Saving write '
        'replaces queuedNext with the newest one, not the first', () {
      final saving = DaySheetSaving(a, queuedNext: b);
      final next = daySheetMarkDirty(saving, c) as DaySheetSaving;
      expect(next.inFlight, a);
      expect(next.queuedNext, c);
    });
  });

  group('daySheetBeginSave (old: _performAutosave\'s "not saving" branch, '
      'doubling as the Retry handler)', () {
    test('Dirty starts a write for its pending entry', () {
      expect(daySheetBeginSave(DaySheetDirty(a)), DaySheetSaving(a));
    });

    test('Failed starts a write for its pending entry -- Retry and a fresh '
        'debounced save share this one entry point', () {
      expect(daySheetBeginSave(DaySheetFailed(a)), DaySheetSaving(a));
    });

    test('Idle has nothing to start', () {
      expect(daySheetBeginSave(const DaySheetIdle()), isNull);
    });

    test('Saved has nothing to start', () {
      expect(daySheetBeginSave(const DaySheetSaved()), isNull);
    });

    test('Saving refuses to start a second, concurrent write (issue #546)',
        () {
      expect(daySheetBeginSave(DaySheetSaving(a)), isNull);
    });
  });

  group('daySheetRequestRetrigger (old: _saveQueued = true, set by the '
      'debounce timer refiring during a write, and by dispose())', () {
    test('marks retrigger when something is genuinely queued', () {
      final next =
          daySheetRequestRetrigger(DaySheetSaving(a, queuedNext: b));
      expect(next, isA<DaySheetSaving>());
      expect((next as DaySheetSaving).retrigger, isTrue);
      expect(next.queuedNext, b, reason: 'the queued entry is preserved');
      expect(next.inFlight, a, reason: 'the in-flight snapshot never moves');
    });

    test('is a no-op when nothing is queued -- old: both call sites only '
        'ever set _saveQueued from inside an `if (_dirty ...)` guard', () {
      final state = DaySheetSaving(a);
      expect(daySheetRequestRetrigger(state), same(state));
    });

    test('is a no-op on any non-Saving state (defensive)', () {
      expect(daySheetRequestRetrigger(const DaySheetIdle()),
          const DaySheetIdle());
      expect(daySheetRequestRetrigger(DaySheetDirty(a)), DaySheetDirty(a));
      expect(daySheetRequestRetrigger(const DaySheetSaved()),
          const DaySheetSaved());
      expect(daySheetRequestRetrigger(DaySheetFailed(a)), DaySheetFailed(a));
    });
  });

  group('daySheetSettleWrite (old: _onAutosaveSuccess + the catch blocks '
      'in _writePending, plus _performAutosave\'s trailing "if '
      '(_saveQueued)" retry)', () {
    test('a clean success with nothing queued settles to Saved, no '
        'retrigger', () {
      final (state, retrigger) =
          daySheetSettleWrite(DaySheetSaving(a), succeeded: true);
      expect(state, const DaySheetSaved());
      expect(retrigger, isFalse);
    });

    test(
        'success with a queued-but-not-yet-retriggered edit settles to '
        'Dirty holding the newer entry, no immediate retrigger (waits for '
        'that edit\'s own debounce timer, still armed)', () {
      final (state, retrigger) = daySheetSettleWrite(
        DaySheetSaving(a, queuedNext: b),
        succeeded: true,
      );
      expect(state, DaySheetDirty(b));
      expect(retrigger, isFalse);
    });

    test(
        'success with a retriggered queued edit settles to Dirty (about to '
        'be immediately re-started by the caller) and signals retrigger', () {
      final (state, retrigger) = daySheetSettleWrite(
        DaySheetSaving(a, queuedNext: b, retrigger: true),
        succeeded: true,
      );
      expect(state, DaySheetDirty(b));
      expect(retrigger, isTrue);
    });

    test('a clean failure with nothing queued settles to Failed, carrying '
        'the entry that failed so Retry can resend it', () {
      final (state, retrigger) =
          daySheetSettleWrite(DaySheetSaving(a), succeeded: false);
      expect(state, DaySheetFailed(a));
      expect(retrigger, isFalse);
    });

    test(
        'failure with a queued-but-not-retriggered edit settles to Failed '
        'carrying the NEWER entry, not the one that actually failed -- old: '
        '_pendingEntry was never reassigned in the catch blocks, so it '
        'already held whatever _markDirty last set regardless of the '
        'failure', () {
      final (state, retrigger) = daySheetSettleWrite(
        DaySheetSaving(a, queuedNext: b),
        succeeded: false,
      );
      expect(state, DaySheetFailed(b));
      expect(retrigger, isFalse);
    });

    test(
        'failure with a retriggered queued edit still settles to Failed '
        'first, but signals retrigger -- old: _writePending always set '
        '_saveFailed=true before _performAutosave\'s trailing check ran, '
        'even though an immediate retry overwrites it before any frame '
        'paints', () {
      final (state, retrigger) = daySheetSettleWrite(
        DaySheetSaving(a, queuedNext: b, retrigger: true),
        succeeded: false,
      );
      expect(state, DaySheetFailed(b));
      expect(retrigger, isTrue);
    });

    test('is a defensive no-op on any non-Saving state', () {
      expect(daySheetSettleWrite(const DaySheetIdle(), succeeded: true),
          (const DaySheetIdle(), false));
      expect(daySheetSettleWrite(DaySheetDirty(a), succeeded: true),
          (DaySheetDirty(a), false));
    });
  });

  group('end-to-end sequences (issue #546 regression shapes)', () {
    test(
        'edit -> debounce -> write starts -> a second edit arrives -> the '
        'write succeeds -> the second edit is still pending, not dropped '
        '(mirrors day_sheet_dispose_flush_test.dart\'s widget-level '
        'version of this exact race)', () {
      var state = daySheetMarkDirty(const DaySheetIdle(), a);
      final started = daySheetBeginSave(state)!;
      state = started;
      // A second edit arrives while the write above is "in flight".
      state = daySheetMarkDirty(state, b);
      // The write for `a` now resolves.
      final (settled, retrigger) =
          daySheetSettleWrite(state, succeeded: true);
      expect(settled, DaySheetDirty(b), reason: 'b is not lost');
      expect(retrigger, isFalse,
          reason: 'no timer refired yet, so no immediate retry -- the '
              'still-armed debounce timer for b handles it');
      // That still-armed timer now fires.
      final resumed = daySheetBeginSave(settled);
      expect(resumed, DaySheetSaving(b));
    });

    test(
        'edit -> write starts -> a second edit arrives -> the debounce '
        'timer for it refires while still saving -> the first write '
        'finishes -> the second is written immediately, without waiting '
        'for another timer (mirrors dispose()-time flush + a still-mounted '
        'refire identically)', () {
      var state = daySheetMarkDirty(const DaySheetIdle(), a);
      state = daySheetBeginSave(state)!;
      state = daySheetMarkDirty(state, b);
      // The timer for b's edit refires while a is still writing (or the
      // sheet is disposed) -- either way, this is the retrigger signal.
      state = daySheetRequestRetrigger(state);
      final (settled, retrigger) =
          daySheetSettleWrite(state, succeeded: true);
      expect(retrigger, isTrue);
      // The caller immediately starts the next write off `settled`.
      final resumed = daySheetBeginSave(settled);
      expect(resumed, DaySheetSaving(b));
    });

    test('a failed write is retried via the exact same beginSave entry '
        'point Retry uses, and succeeds', () {
      var state = daySheetMarkDirty(const DaySheetIdle(), a);
      state = daySheetBeginSave(state)!;
      final (afterFailure, retrigger) =
          daySheetSettleWrite(state, succeeded: false);
      expect(afterFailure, DaySheetFailed(a));
      expect(retrigger, isFalse);
      // Retry taps the InlineError action, which is wired to the same
      // entry point a debounced save uses.
      final retried = daySheetBeginSave(afterFailure);
      expect(retried, DaySheetSaving(a));
      final (afterRetry, _) =
          daySheetSettleWrite(retried!, succeeded: true);
      expect(afterRetry, const DaySheetSaved());
    });
  });

  group('DaySheetDeleting/DaySheetDeleted (issue #601 LLA-003 audit '
      'finding: an outstanding autosave must never resurrect an explicitly '
      'deleted entry)', () {
    test('daySheetMarkDirty is a no-op on Deleting -- a stray edit must '
        'never revive the write path once deletion has started', () {
      expect(
        daySheetMarkDirty(const DaySheetDeleting(), a),
        const DaySheetDeleting(),
      );
    });

    test('daySheetMarkDirty is a no-op on Deleted', () {
      expect(
        daySheetMarkDirty(const DaySheetDeleted(), a),
        const DaySheetDeleted(),
      );
    });

    test('daySheetBeginSave refuses to start on Deleting', () {
      expect(daySheetBeginSave(const DaySheetDeleting()), isNull);
    });

    test('daySheetBeginSave refuses to start on Deleted', () {
      expect(daySheetBeginSave(const DaySheetDeleted()), isNull);
    });

    test('daySheetRequestRetrigger is a no-op on Deleting (defensive -- '
        'the widget never calls it once here, but the pure function must '
        'still refuse if it somehow were)', () {
      expect(
        daySheetRequestRetrigger(const DaySheetDeleting()),
        const DaySheetDeleting(),
      );
    });

    test(
        'daySheetSettleWrite silently drops an in-flight write\'s result '
        'once the live state has moved to Deleting -- this is the actual '
        'fix: the write\'s own snapshot (state.inFlight) is never consulted, '
        'only the live state passed in', () {
      // The exact LLA-003 repro: a write starts (Saving), the widget
      // transitions to Deleting *while that write is still running* (the
      // widget does this before awaiting it, per `_delete`'s own doc), and
      // only then does the write settle.
      final (settled, retrigger) = daySheetSettleWrite(
        const DaySheetDeleting(),
        succeeded: true,
      );
      expect(settled, const DaySheetDeleting(),
          reason: 'the successful write must not overwrite Deleting with '
              'Saved or Dirty -- doing so would let it (or a queued edit '
              'behind it) write again and undo the delete');
      expect(retrigger, isFalse);
    });

    test('daySheetSettleWrite also drops a FAILED in-flight write\'s '
        'result once the live state has moved to Deleting', () {
      final (settled, retrigger) = daySheetSettleWrite(
        const DaySheetDeleting(),
        succeeded: false,
      );
      expect(settled, const DaySheetDeleting());
      expect(retrigger, isFalse);
    });

    test(
        'full LLA-003 sequence: edit -> write starts -> delete requested '
        '(state moves to Deleting, discarding nothing since nothing was '
        'queued) -> the write settles -> nothing further to write', () {
      var state = daySheetMarkDirty(const DaySheetIdle(), a);
      state = daySheetBeginSave(state)!; // Saving(a)
      // Delete is confirmed while the write for `a` is still in flight.
      state = const DaySheetDeleting();
      final (settled, retrigger) =
          daySheetSettleWrite(state, succeeded: true);
      expect(settled, const DaySheetDeleting());
      expect(retrigger, isFalse);
      expect(daySheetBeginSave(settled), isNull,
          reason: 'nothing can ever write again from this state');
    });

    test(
        'full LLA-003 sequence with a queued edit: edit A -> write starts '
        '-> edit B arrives (queued behind the in-flight write) -> delete '
        'requested -> the write for A settles -> B is discarded, not '
        'written -- deleting supersedes it', () {
      var state = daySheetMarkDirty(const DaySheetIdle(), a);
      state = daySheetBeginSave(state)!; // Saving(a)
      state = daySheetMarkDirty(state, b); // Saving(a, queuedNext: b)
      expect((state as DaySheetSaving).queuedNext, b);
      // Delete is confirmed -- the widget overwrites the live state with
      // Deleting *before* awaiting the in-flight write, discarding b.
      state = const DaySheetDeleting();
      final (settled, retrigger) =
          daySheetSettleWrite(state, succeeded: true);
      expect(settled, const DaySheetDeleting(),
          reason: 'b must never surface as Dirty/Saving from here on -- '
              'that would let it be written after the delete');
      expect(retrigger, isFalse);
      expect(daySheetBeginSave(settled), isNull);
    });

    test('daySheetMarkDirty/daySheetBeginSave are exhaustive switches over '
        'DaySheetSaveState (a compile-time guarantee, not just a runtime '
        'test) -- this test exists so the exhaustiveness claim in both '
        'functions\' doc comments has a concrete assertion attached to it, '
        'covering every variant once', () {
      for (final state in <DaySheetSaveState>[
        const DaySheetIdle(),
        DaySheetDirty(a),
        DaySheetSaving(a),
        const DaySheetSaved(),
        DaySheetFailed(a),
        const DaySheetDeleting(),
        const DaySheetDeleted(),
      ]) {
        // Neither call may throw for any variant -- exhaustiveness is
        // enforced by the compiler; this just proves every arm is
        // actually reachable and returns rather than looping/throwing.
        daySheetMarkDirty(state, c);
        daySheetBeginSave(state);
      }
    });
  });

  group('daySheetDisposeAction (issue #601 review: extracted out of '
      '_DaySheetState.dispose\'s own inline switch to keep that method\'s '
      'CRAP score low; every case below is the exact same decision the old '
      'switch made)', () {
    test('Idle -> Noop', () {
      expect(daySheetDisposeAction(const DaySheetIdle()),
          const DaySheetDisposeNoop());
    });

    test('Saved -> Noop', () {
      expect(daySheetDisposeAction(const DaySheetSaved()),
          const DaySheetDisposeNoop());
    });

    test('Dirty -> Flush the pending entry', () {
      expect(daySheetDisposeAction(DaySheetDirty(a)),
          DaySheetDisposeFlush(a));
    });

    test('Failed -> Flush the pending entry, same as Dirty', () {
      expect(daySheetDisposeAction(DaySheetFailed(a)),
          DaySheetDisposeFlush(a));
    });

    test('Saving with nothing queued -> Noop -- old: dispose\'s guard was '
        '`if (_dirty && !_discardUnsaved)`, so a write in flight with '
        'nothing newer behind it did nothing here (the in-flight write '
        'settles entirely on its own)', () {
      expect(daySheetDisposeAction(DaySheetSaving(a)),
          const DaySheetDisposeNoop());
    });

    test('Saving with something queued -> Retrigger, computed via '
        'daySheetRequestRetrigger', () {
      final action =
          daySheetDisposeAction(DaySheetSaving(a, queuedNext: b));
      expect(
        action,
        DaySheetDisposeRetrigger(
          DaySheetSaving(a, queuedNext: b, retrigger: true),
        ),
      );
    });

    test('Deleting -> Noop -- deletion, once requested, owns whatever '
        'happens next entirely on its own continuation (issue #601 '
        'LLA-003); dispose must never act again on its behalf', () {
      expect(daySheetDisposeAction(const DaySheetDeleting()),
          const DaySheetDisposeNoop());
    });

    test('Deleted -> Noop', () {
      expect(daySheetDisposeAction(const DaySheetDeleted()),
          const DaySheetDisposeNoop());
    });

    test('covers every DaySheetSaveState variant once (exhaustiveness is '
        'compiler-enforced; this just proves every arm actually returns)',
        () {
      for (final state in <DaySheetSaveState>[
        const DaySheetIdle(),
        DaySheetDirty(a),
        DaySheetSaving(a),
        DaySheetSaving(a, queuedNext: b),
        const DaySheetSaved(),
        DaySheetFailed(a),
        const DaySheetDeleting(),
        const DaySheetDeleted(),
      ]) {
        daySheetDisposeAction(state);
      }
    });
  });
}
