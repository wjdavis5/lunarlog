/// The day sheet's autosave state machine (issue #601), extracted out of
/// `lib/ui/logging/day_sheet.dart`'s `_DaySheetState` boolean cluster
/// (`_dirty`/`_saving`/`_saveQueued`/`_showSaved`/`_saveFailed`) into one
/// sealed [DaySheetSaveState] plus the pure transition functions below.
/// Pure Dart (R14/R16) — no Flutter, no timers, no repository access; the
/// widget still owns every side effect (the debounce [Timer], the
/// "Saved" banner's dismiss timer, `setState`, and the actual repository
/// write) and drives them off these transitions.
///
/// **Every transition here is an exact, behaviour-preserving translation**
/// of the boolean cluster's own logic (issue #546's hard-won dismissal
/// -race fixes included) — see each function's doc for the old field(s)
/// and call site it replaces. The one deliberate, narrow simplification is
/// documented on [DaySheetSaved]: it is not worth the extra plumbing to
/// chase.
library;

import '../models/day_entry.dart';

sealed class DaySheetSaveState {
  const DaySheetSaveState();
}

/// Nothing pending, no write in flight, no banner. Old:
/// `_dirty=false, _saving=false, _showSaved=false, _saveFailed=false`.
final class DaySheetIdle extends DaySheetSaveState {
  const DaySheetIdle();
}

/// A change is composed and waiting out the debounce (or ready to be
/// flushed immediately on dismissal). Old: `_dirty=true, _saving=false`.
final class DaySheetDirty extends DaySheetSaveState {
  const DaySheetDirty(this.pending);

  /// The entry the next write will persist.
  final DayEntry pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySheetDirty && other.pending == pending;

  @override
  int get hashCode => pending.hashCode;
}

/// [inFlight] is being written right now.
///
/// [queuedNext], once non-null, is the latest composed entry once it
/// differs from [inFlight] — set the instant a further change arrives
/// (mirrors the old `_pendingEntry`, which `_markDirty` reassigned
/// unconditionally, `_saving` or not). It is what a Retry-less follow-up
/// save writes once this one settles.
///
/// [retrigger] mirrors the old `_saveQueued`: true once *another* save
/// attempt was explicitly made against this same in-flight write — the
/// debounce timer firing again, or a dismissal, while [inFlight] was still
/// running — rather than merely "a newer edit exists" ([queuedNext] alone
/// covers that). The distinction matters: an edit that hasn't had its own
/// debounce elapse yet should still wait for it once this write settles
/// (`queuedNext != null, retrigger == false` → settles to
/// [DaySheetDirty], picked up later by the still-armed [Timer]); a
/// [retrigger] means "elapsed already (or the sheet is going away and no
/// timer will ever fire again) — start the next write the moment this one
/// finishes" (settles straight back to [DaySheetSaving]).
final class DaySheetSaving extends DaySheetSaveState {
  const DaySheetSaving(this.inFlight, {this.queuedNext, this.retrigger = false});

  final DayEntry inFlight;
  final DayEntry? queuedNext;
  final bool retrigger;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySheetSaving &&
          other.inFlight == inFlight &&
          other.queuedNext == queuedNext &&
          other.retrigger == retrigger;

  @override
  int get hashCode => Object.hash(inFlight, queuedNext, retrigger);
}

/// Transient post-success confirmation ("Saved" + checkmark), cleared by
/// the widget's own timer after `kDaySheetSavedIndicatorDuration`. Old:
/// `_showSaved=true, _saving=false, _saveFailed=false`.
///
/// **Documented simplification:** the old booleans let `_showSaved=true`
/// linger even once a further edit had arrived mid-write but not yet had
/// its own debounce elapse (`_dirty=true` alongside `_showSaved=true`,
/// invisible in the UI either way since `_autosaveStatusSlot` never reads
/// `_dirty`, and superseded by "Saving…" within, at most, one more debounce
/// window). [daySheetSettleWrite] instead moves straight to
/// [DaySheetDirty] in that case, dropping the banner immediately rather
/// than lingering — a strictly *more* honest read of "is there unsaved
/// content right now", never observed by any existing test, and not worth
/// carrying a `queuedNext` field on this variant just to reproduce a
/// cosmetic window measured in the low hundreds of milliseconds.
final class DaySheetSaved extends DaySheetSaveState {
  const DaySheetSaved();
}

/// A write failed; [pending] is preserved (never dropped) so Retry — or a
/// later successful autosave once the operator keeps editing — can resend
/// it. Old: `_saveFailed=true, _dirty=true`.
final class DaySheetFailed extends DaySheetSaveState {
  const DaySheetFailed(this.pending);

  final DayEntry pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySheetFailed && other.pending == pending;

  @override
  int get hashCode => pending.hashCode;
}

/// **Terminal.** Deletion has been requested and is in flight (issue #601's
/// LLA-003 audit finding: an already in-flight autosave write completing
/// *after* delete was confirmed used to still land — its own upsert writes
/// `deletedAt: null`, resurrecting the row the operator just deleted).
/// Reaching this state is what closes the race: [daySheetMarkDirty] and
/// [daySheetBeginSave] both refuse to act once here (so neither a
/// not-yet-started queued edit nor a fresh debounce can ever write again),
/// and [daySheetSettleWrite] only ever inspects a *live* [DaySheetSaving]
/// state — once the widget has overwritten it with this value, that
/// in-flight write's own eventual settle call finds `state is!
/// DaySheetSaving` and silently drops its result instead of applying or
/// retriggering it. The widget is responsible for reaching this state
/// *before* awaiting whatever write was already in flight (see
/// `_DaySheetState._delete`) — that ordering, not anything in this file
/// alone, is what actually serializes the terminal delete behind it.
final class DaySheetDeleting extends DaySheetSaveState {
  const DaySheetDeleting();
}

/// **Terminal.** Deletion has completed. The sheet is dismissed immediately
/// after reaching this state in real usage, but it is a distinct value
/// (never reused as [DaySheetIdle]) so nothing — a stray timer, a stray
/// listener callback that fires between the delete completing and the
/// sheet actually unmounting — can mistake "deleted" for "nothing has ever
/// happened here" and start a new write.
final class DaySheetDeleted extends DaySheetSaveState {
  const DaySheetDeleted();
}

/// Records a pending change (issue #198 B-13; #247/#256's chip/note/toggle
/// handlers all funnel through this). Old: `_markDirty`'s unconditional
/// `_dirty = true; _pendingEntry = composed;` — fires the same way whether
/// or not a write is currently in flight, which is exactly why
/// [DaySheetSaving.queuedNext] exists: a write already running keeps
/// [DaySheetSaving.inFlight] untouched (that snapshot was already taken)
/// and only [queuedNext] moves to [composed].
///
/// **Exhaustive, not a wildcard fallback** (issue #601's LLA-003 audit
/// finding): [DaySheetDeleting]/[DaySheetDeleted] must never fall through
/// to the "treat it like Idle/Saved and start being Dirty" arm below —
/// that would silently resurrect a just-deleted (or being-deleted) entry
/// through a completely different path than the one the audit found. A
/// future new variant added to the sealed hierarchy fails to compile here
/// until this switch is updated to say what it means, rather than
/// silently inheriting the wildcard's behaviour.
DaySheetSaveState daySheetMarkDirty(
  DaySheetSaveState state,
  DayEntry composed,
) =>
    switch (state) {
      DaySheetSaving(:final inFlight, :final retrigger) =>
        DaySheetSaving(inFlight, queuedNext: composed, retrigger: retrigger),
      DaySheetDeleting() || DaySheetDeleted() => state,
      DaySheetIdle() ||
      DaySheetDirty() ||
      DaySheetSaved() ||
      DaySheetFailed() =>
        DaySheetDirty(composed),
    };

/// Starts a write if there is anything to write. Returns `null` when there
/// is not — old: `_performAutosave`'s `if (_saving) { ...; return; }` (a
/// write already in flight — nothing new to *start*, see
/// [daySheetRequestRetrigger] for that case) and its `if (!_dirty ||
/// pending == null) return;` (idle or already-settled-to-Saved: nothing
/// pending at all).
///
/// [DaySheetFailed] starts a write the same way [DaySheetDirty] does —
/// this is also the Retry handler's entry point (old: `_performAutosave`
/// wired directly as `InlineError.onRetry`, and it never distinguished "a
/// debounced dirty edit" from "a manual retry of a failed one" — both are
/// just "there is a pending entry, and nothing currently in flight").
///
/// [DaySheetDeleting]/[DaySheetDeleted] (issue #601's LLA-003 audit
/// finding) also refuse — exhaustively listed, not folded into a wildcard,
/// for the same reason as [daySheetMarkDirty]'s own doc.
DaySheetSaving? daySheetBeginSave(DaySheetSaveState state) => switch (state) {
      DaySheetDirty(:final pending) => DaySheetSaving(pending),
      DaySheetFailed(:final pending) => DaySheetSaving(pending),
      DaySheetSaving() || DaySheetIdle() || DaySheetSaved() => null,
      DaySheetDeleting() || DaySheetDeleted() => null,
    };

/// Marks that another save attempt was made against an already-in-flight
/// write (the debounce timer firing again, or a dismissal-time flush)
/// (old: `_saveQueued = true`, set at both of those call sites). A no-op
/// unless [state] is [DaySheetSaving] with a [DaySheetSaving.queuedNext]
/// already set — mirroring the old code, where both call sites only ever
/// reached the `_saveQueued = true` line already guarded by `_dirty` (or,
/// for the debounce-timer path, by construction: the timer that just
/// fired is always the one the most recent `_markDirty` armed, so `_dirty`
/// is guaranteed true whenever it fires while still saving).
DaySheetSaveState daySheetRequestRetrigger(DaySheetSaveState state) =>
    switch (state) {
      DaySheetSaving(:final inFlight, :final queuedNext)
          when queuedNext != null =>
        DaySheetSaving(inFlight, queuedNext: queuedNext, retrigger: true),
      _ => state,
    };

/// Settles a write that just finished against the *current* [state] — read
/// fresh, not the snapshot [DaySheetSaving.inFlight] was taken from,
/// because [state] may already carry a [DaySheetSaving.queuedNext] (or a
/// [DaySheetSaving.retrigger]) set by an edit or a dismissal that arrived
/// while the write was still running. Returns the new state plus whether
/// the caller must immediately start another write rather than wait for a
/// timer — old: `_onAutosaveSuccess`/the catch blocks in `_writePending`
/// for the state half, and `_performAutosave`'s trailing `if (_saveQueued)
/// { _saveQueued = false; if (_dirty) unawaited(_performAutosave()); }`
/// for the retrigger half, which ran identically whether [succeeded] or
/// not.
///
/// [state] must be [DaySheetSaving] (the caller just finished writing its
/// [DaySheetSaving.inFlight]); any other state is returned unchanged with
/// no retrigger, defensively, since it should not occur.
(DaySheetSaveState state, bool retrigger) daySheetSettleWrite(
  DaySheetSaveState state, {
  required bool succeeded,
}) {
  if (state is! DaySheetSaving) return (state, false);
  final queuedNext = state.queuedNext;
  final settled = succeeded
      ? (queuedNext == null ? const DaySheetSaved() : DaySheetDirty(queuedNext))
      : DaySheetFailed(queuedNext ?? state.inFlight);
  return (settled, state.retrigger && queuedNext != null);
}

/// What [_DaySheetState.dispose] (`lib/ui/logging/day_sheet.dart`) must do
/// for the current state, computed once as a pure, directly-testable value
/// instead of an inline `switch` in `dispose` itself — issue #601 review:
/// keeping that method's own cyclomatic complexity low (the CRAP gate
/// flagged it) is worth the one extra indirection here.
sealed class DaySheetDisposeAction {
  const DaySheetDisposeAction();
}

/// Nothing to do: [DaySheetIdle], [DaySheetSaved], a [DaySheetSaving] with
/// nothing queued behind it, or either terminal delete state
/// ([DaySheetDeleting]/[DaySheetDeleted] — issue #601's LLA-003 audit
/// finding: deletion, once requested, owns whatever happens next entirely
/// on its own continuation; dispose must never act again on its behalf).
final class DaySheetDisposeNoop extends DaySheetDisposeAction {
  const DaySheetDisposeNoop();
}

/// Flush [pending] directly ([DaySheetDirty]/[DaySheetFailed]): nothing is
/// in flight, so this is the belt-and-braces write
/// `_DaySheetState._flushOnDispose` fires.
final class DaySheetDisposeFlush extends DaySheetDisposeAction {
  const DaySheetDisposeFlush(this.pending);

  final DayEntry pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySheetDisposeFlush && other.pending == pending;

  @override
  int get hashCode => pending.hashCode;
}

/// Mark the in-flight write for retrigger ([daySheetRequestRetrigger]) so
/// its own completion picks up [DaySheetSaving.queuedNext] once it settles
/// (issue #546), rather than starting a second, concurrent write here.
/// [nextState] is the already-computed result — the caller just assigns it.
final class DaySheetDisposeRetrigger extends DaySheetDisposeAction {
  const DaySheetDisposeRetrigger(this.nextState);

  final DaySheetSaveState nextState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySheetDisposeRetrigger && other.nextState == nextState;

  @override
  int get hashCode => nextState.hashCode;
}

/// The pure decision behind `dispose`'s old inline switch — exact same
/// cases, same reasoning (see each [DaySheetDisposeAction] variant's doc
/// for the old comment it carries forward), just returned as data instead
/// of executed as a `switch` statement's side effects.
DaySheetDisposeAction daySheetDisposeAction(DaySheetSaveState state) =>
    switch (state) {
      DaySheetDirty(:final pending) => DaySheetDisposeFlush(pending),
      DaySheetFailed(:final pending) => DaySheetDisposeFlush(pending),
      DaySheetSaving(:final queuedNext) when queuedNext != null =>
        DaySheetDisposeRetrigger(daySheetRequestRetrigger(state)),
      DaySheetSaving() ||
      DaySheetIdle() ||
      DaySheetSaved() ||
      DaySheetDeleting() ||
      DaySheetDeleted() =>
        const DaySheetDisposeNoop(),
    };
